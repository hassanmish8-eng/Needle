#if DEBUG
import Foundation
import Combine
import UIKit

/// Debug-only test double. Used by unit tests and by UI tests (launch argument
/// `-ui-test-scenario <name>`). It is compiled out of Release builds, so the shipped
/// app can never show scripted data.
@MainActor
final class ScriptedSpotifyService: ObservableObject, SpotifyServicing {
    enum Scenario: String { case onboarding, empty, playing, disconnected }

    static let sampleTrack = TrackInfo(uri: "spotify:track:scripted1", title: "Test Track", artist: "Test Artist",
                                       album: "Test Album", albumURI: "spotify:album:scripted",
                                       imageIdentifier: "spotify:image:scripted", durationMs: 215_000)

    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var snapshot: PlaybackSnapshot?
    var accessToken: String? = "scripted-token"

    var connectionStatusPublisher: AnyPublisher<ConnectionStatus, Never> { $connectionStatus.eraseToAnyPublisher() }
    var snapshotPublisher: AnyPublisher<PlaybackSnapshot?, Never> { $snapshot.eraseToAnyPublisher() }

    /// Set to make the next command fail the way Spotify would.
    var rejectNextCommand: String?
    private(set) var commandLog: [String] = []
    private(set) var artworkRequests: [TrackInfo] = []
    var artworkHandler: (TrackInfo) async throws -> UIImage = { _ in ScriptedSpotifyService.syntheticArtwork() }

    init(scenario: Scenario) {
        switch scenario {
        case .onboarding:
            connectionStatus = .notAuthorized(nil)
        case .empty:
            connectionStatus = .connected
        case .playing:
            connectionStatus = .connected
            snapshot = Self.makeSnapshot(paused: false)
        case .disconnected:
            connectionStatus = .disconnected("NEEDLE lost its connection to Spotify.")
            snapshot = Self.makeSnapshot(paused: false)
        }
    }

    static func makeSnapshot(track: TrackInfo = sampleTrack, paused: Bool, positionMs: Int = 42_000,
                             shuffling: Bool = false, repeatMode: RepeatMode = .off) -> PlaybackSnapshot {
        PlaybackSnapshot(track: track, isPaused: paused, positionMs: positionMs, isShuffling: shuffling,
                         repeatMode: repeatMode, receivedAt: Date())
    }

    // Test drivers
    func push(snapshot new: PlaybackSnapshot?) { snapshot = new }
    func push(status: ConnectionStatus) { connectionStatus = status }

    // Lifecycle
    func authorize() { connectionStatus = .connected; snapshot = Self.makeSnapshot(paused: false) }
    func connect() { connectionStatus = .connected }
    func reconnect() { connectionStatus = .connected; if snapshot == nil { snapshot = Self.makeSnapshot(paused: false) } }
    func disconnect(forgetSession: Bool) {
        connectionStatus = forgetSession ? .notAuthorized(nil) : .disconnected(nil)
        if forgetSession { snapshot = nil }
    }
    func refreshPlayerState() {}
    func handleBecameActive() {}
    func handleEnteredBackground() {}
    func handle(url: URL) {}
    func openSpotify() { commandLog.append("openSpotify") }

    func fetchArtwork(for track: TrackInfo, size: CGSize) async throws -> UIImage {
        artworkRequests.append(track)
        return try await artworkHandler(track)
    }

    // Commands
    private func run(_ name: String, _ change: (inout PlaybackSnapshot) -> Void) async throws {
        commandLog.append(name)
        if let message = rejectNextCommand {
            rejectNextCommand = nil
            throw SpotifyError.rejected(message)
        }
        guard var current = snapshot else { throw SpotifyError.notConnected }
        change(&current)
        current.receivedAt = Date()
        snapshot = current
    }

    func resume() async throws { try await run("resume") { $0.isPaused = false } }
    func pause() async throws { try await run("pause") { $0.positionMs = $0.positionMs(at: Date()); $0.isPaused = true } }
    func skipNext() async throws { try await run("next") { $0.positionMs = 0 } }
    func skipPrevious() async throws { try await run("previous") { $0.positionMs = 0 } }
    func seek(toMs ms: Int) async throws { try await run("seek:\(ms)") { $0.positionMs = ms } }
    func setShuffle(_ enabled: Bool) async throws { try await run("shuffle:\(enabled)") { $0.isShuffling = enabled } }
    func setRepeat(_ mode: RepeatMode) async throws { try await run("repeat:\(mode.rawValue)") { $0.repeatMode = mode } }
    func play(uri: String) async throws { try await run("play:\(uri)") { $0.isPaused = false } }

    /// A recognizably synthetic cover (diagonal blue-to-teal with a disc), never mistaken for real art.
    static func syntheticArtwork(size: CGFloat = 320) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            let colors = [UIColor(red: 0.10, green: 0.22, blue: 0.62, alpha: 1).cgColor,
                          UIColor(red: 0.05, green: 0.55, blue: 0.60, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
            }
            UIColor(white: 1, alpha: 0.85).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: size * 0.3, y: size * 0.3, width: size * 0.4, height: size * 0.4))
        }
    }
}
#endif
