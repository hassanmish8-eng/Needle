import Foundation
import Combine
import UIKit

/// Everything the rest of the app needs from Spotify. The live implementation wraps the
/// official iOS SDK; tests and UI tests use a scripted double.
@MainActor
protocol SpotifyServicing: AnyObject {
    var connectionStatus: ConnectionStatus { get }
    var snapshot: PlaybackSnapshot? { get }
    /// Non-nil only while the stored token is still valid.
    var accessToken: String? { get }

    var connectionStatusPublisher: AnyPublisher<ConnectionStatus, Never> { get }
    var snapshotPublisher: AnyPublisher<PlaybackSnapshot?, Never> { get }

    // Lifecycle
    func authorize()
    func connect()
    func reconnect()
    func disconnect(forgetSession: Bool)
    func refreshPlayerState()
    func handleBecameActive()
    func handleEnteredBackground()
    func handle(url: URL)
    func openSpotify()

    // Data
    func fetchArtwork(for track: TrackInfo, size: CGSize) async throws -> UIImage

    // Commands (each throws if Spotify rejects it)
    func resume() async throws
    func pause() async throws
    func skipNext() async throws
    func skipPrevious() async throws
    func seek(toMs ms: Int) async throws
    func setShuffle(_ enabled: Bool) async throws
    func setRepeat(_ mode: RepeatMode) async throws
    func play(uri: String) async throws
}
