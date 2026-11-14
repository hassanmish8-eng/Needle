import Foundation
import Combine
import UIKit
import SpotifyiOS

struct SpotifyConfig: Equatable {
    let clientID: String
    let redirectScheme: String

    var redirectURL: URL? { URL(string: "\(redirectScheme)://spotify-login-callback") }

    /// False for the empty default or an unexpanded "$(SPOTIFY_CLIENT_ID)" placeholder.
    var isConfigured: Bool {
        !clientID.isEmpty && !clientID.hasPrefix("$(") && !clientID.hasPrefix("paste_") && redirectURL != nil
    }

    static func fromBundle(_ bundle: Bundle = .main) -> SpotifyConfig {
        func string(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let scheme = string("SpotifyRedirectScheme")
        return SpotifyConfig(clientID: string("SpotifyClientID"),
                             redirectScheme: scheme.isEmpty || scheme.hasPrefix("$(") ? "needle-spotify" : scheme)
    }
}

/// Live Spotify integration: official OAuth (SPTSessionManager) + App Remote.
/// Spotify's own app keeps doing all audio; NEEDLE only reads state and sends commands.
@MainActor
final class SpotifyService: NSObject, ObservableObject, SpotifyServicing {

    static let appStoreURL = URL(string: "https://apps.apple.com/app/spotify-music-and-podcasts/id324684580")!
    static let notRunningMessage =
        "Couldn't reach the Spotify app. Start playing something in Spotify first, then come back and reconnect."

    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var snapshot: PlaybackSnapshot?

    var connectionStatusPublisher: AnyPublisher<ConnectionStatus, Never> { $connectionStatus.eraseToAnyPublisher() }
    var snapshotPublisher: AnyPublisher<PlaybackSnapshot?, Never> { $snapshot.eraseToAnyPublisher() }
    var accessToken: String? { (storedSession?.isValid == true) ? storedSession?.accessToken : nil }

    private let config: SpotifyConfig
    private let keychain: KeychainStore
    private var sessionManager: SPTSessionManager?
    private var appRemote: SPTAppRemote?
    private var storedSession: StoredSession?
    private var watchdog: Task<Void, Never>?
    private var expectedDisconnect = false
    private var authCallbackReceived = false

    private var isSpotifyInstalled: Bool {
        guard let url = URL(string: "spotify:") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    init(config: SpotifyConfig = .fromBundle(), keychain: KeychainStore = KeychainStore()) {
        self.config = config
        self.keychain = keychain
        self.connectionStatus = config.isConfigured ? .notAuthorized(nil) : .notConfigured
        super.init()

        guard config.isConfigured, let redirect = config.redirectURL else { return }
        // No playURI is set on purpose: signing in must never start playback.
        let configuration = SPTConfiguration(clientID: config.clientID, redirectURL: redirect)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .error)
        remote.delegate = self
        appRemote = remote
        sessionManager = SPTSessionManager(configuration: configuration, delegate: self)
        restoreSession()
    }

    // MARK: Session

    private func restoreSession() {
        guard let session = keychain.loadSession() else { return }
        if session.isValid {
            storedSession = session
            connectionStatus = .disconnected(nil)       // connects when the app becomes active
        } else {
            keychain.deleteSession()
            connectionStatus = .sessionExpired
        }
    }

    func authorize() {
        guard config.isConfigured, let manager = sessionManager else { setStatus(.notConfigured); return }
        guard isSpotifyInstalled else { setStatus(.spotifyNotInstalled); return }
        authCallbackReceived = false
        setStatus(.authorizing)
        startWatchdog(seconds: 90) { [weak self] in
            self?.authorizationFailed("Authorization timed out. Try again.")
        }
        // Least privilege: App Remote control is the only scope the features need.
        manager.initiateSession(with: [.appRemoteControl], options: .clientOnly, campaign: nil)
    }

    func handle(url: URL) {
        guard let manager = sessionManager else { return }
        authCallbackReceived = true
        _ = manager.application(UIApplication.shared, open: url, options: [:])
    }

    private func didAuthorize(token: String, expiry: Date) {
        cancelWatchdog()
        let session = StoredSession(accessToken: token, expiry: expiry)
        storedSession = session
        keychain.saveSession(session)
        connect()
    }

    private func authorizationFailed(_ message: String) {
        cancelWatchdog()
        if storedSession?.isValid == true {
            setStatus(.disconnected(message))
        } else {
            setStatus(.notAuthorized(message))
        }
    }

    // MARK: Connection

    func connect() {
        guard let appRemote else { setStatus(.notConfigured); return }
        guard let session = storedSession else { setStatus(.notAuthorized(nil)); return }
        guard session.isValid else { setStatus(.sessionExpired); return }
        guard isSpotifyInstalled else { setStatus(.spotifyNotInstalled); return }
        if appRemote.isConnected { remoteDidConnect(); return }

        appRemote.connectionParameters.accessToken = session.accessToken
        setStatus(.connecting)
        startWatchdog(seconds: 12) { [weak self] in
            self?.appRemote?.disconnect()
            self?.setStatus(.failed(SpotifyService.notRunningMessage))
        }
        appRemote.connect()
    }

    func reconnect() {
        if storedSession?.isValid == true { connect() } else { authorize() }
    }

    func disconnect(forgetSession: Bool) {
        cancelWatchdog()
        expectedDisconnect = true
        if appRemote?.isConnected == true { appRemote?.disconnect() }
        if forgetSession {
            keychain.deleteSession()
            storedSession = nil
            appRemote?.connectionParameters.accessToken = nil
            snapshot = nil
            setStatus(.notAuthorized(nil))
        } else {
            setStatus(.disconnected(nil))
        }
    }

    func handleBecameActive() {
        if connectionStatus == .authorizing {
            // Back from Spotify without a redirect callback => the user cancelled.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self, self.connectionStatus == .authorizing, !self.authCallbackReceived else { return }
                self.authorizationFailed("Authorization was cancelled.")
            }
            return
        }
        guard storedSession != nil else { return }
        if let appRemote, appRemote.isConnected {
            refreshPlayerState()
        } else if connectionStatus != .connecting {
            connect()
        }
    }

    func handleEnteredBackground() {
        guard let appRemote, appRemote.isConnected else { return }
        // iOS suspends NEEDLE shortly after this; Spotify's docs advise closing the connection.
        expectedDisconnect = true
        appRemote.disconnect()
        setStatus(.disconnected(nil))
    }

    func openSpotify() {
        let url = isSpotifyInstalled ? (URL(string: "spotify:") ?? Self.appStoreURL) : Self.appStoreURL
        UIApplication.shared.open(url)
    }

    private func remoteDidConnect() {
        cancelWatchdog()
        expectedDisconnect = false
        setStatus(.connected)
        appRemote?.playerAPI?.delegate = self
        appRemote?.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                self?.setStatus(.failed("Couldn't subscribe to Spotify's player: \(message)"))
            }
        })
        refreshPlayerState()
    }

    private func remoteDidDisconnect(message: String?) {
        cancelWatchdog()
        if expectedDisconnect { setStatus(.disconnected(nil)); return }
        if let session = storedSession, !session.isValid {
            setStatus(.sessionExpired)
        } else {
            setStatus(.disconnected(message ?? "NEEDLE lost its connection to Spotify. Make sure music is playing in Spotify, then reconnect."))
        }
    }

    private func remoteConnectionFailed(message: String?) {
        cancelWatchdog()
        if let session = storedSession, !session.isValid {
            setStatus(.sessionExpired)
        } else {
            setStatus(.failed(SpotifyService.notRunningMessage + (message.map { " (\($0))" } ?? "")))
        }
    }

    private func setStatus(_ status: ConnectionStatus) {
        if connectionStatus != status { connectionStatus = status }
    }

    // MARK: Watchdog (no indefinite spinners)

    private func startWatchdog(seconds: Double, onTimeout: @escaping @MainActor () -> Void) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, self != nil else { return }
            onTimeout()
        }
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    // MARK: Player state

    func refreshPlayerState() {
        guard let appRemote, appRemote.isConnected else { return }
        appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
            guard let self, let state = result as? SPTAppRemotePlayerState else { return }
            self.snapshot = SpotifyService.makeSnapshot(from: state)
        }
    }

    nonisolated static func makeSnapshot(from state: SPTAppRemotePlayerState, now: Date = Date()) -> PlaybackSnapshot? {
        let track = state.track
        if track.uri.isEmpty && track.name.isEmpty { return nil }
        let restrictions = state.playbackRestrictions
        let speed = Double(state.playbackSpeed)
        return PlaybackSnapshot(
            track: TrackInfo(uri: track.uri,
                             title: track.name,
                             artist: track.artist.name,
                             album: track.album.name,
                             albumURI: track.album.uri,
                             imageIdentifier: track.imageIdentifier,
                             durationMs: Int(track.duration)),
            isPaused: state.isPaused,
            positionMs: state.playbackPosition,
            playbackSpeed: speed > 0 ? speed : 1,
            isShuffling: state.playbackOptions.isShuffling,
            repeatMode: RepeatMode(sdk: state.playbackOptions.repeatMode),
            restrictions: PlaybackRestrictions(canSkipNext: restrictions.canSkipNext,
                                               canSkipPrevious: restrictions.canSkipPrevious,
                                               canSeek: restrictions.canSeek,
                                               canToggleShuffle: restrictions.canToggleShuffle,
                                               canRepeatTrack: restrictions.canRepeatTrack,
                                               canRepeatContext: restrictions.canRepeatContext),
            receivedAt: now)
    }

    // MARK: Artwork

    func fetchArtwork(for track: TrackInfo, size: CGSize) async throws -> UIImage {
        guard let appRemote, appRemote.isConnected, let api = appRemote.imageAPI else { throw SpotifyError.notConnected }
        guard !track.imageIdentifier.isEmpty else { throw SpotifyError.artworkUnavailable }
        let reference = SpotifyImageReference(identifier: track.imageIdentifier)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            api.fetchImage(forItem: reference, with: size) { result, error in
                if let image = result as? UIImage {
                    continuation.resume(returning: image)
                } else if let error {
                    continuation.resume(throwing: SpotifyError.from(error))
                } else {
                    continuation.resume(throwing: SpotifyError.artworkUnavailable)
                }
            }
        }
    }

    // MARK: Commands

    private func send(_ command: (SPTAppRemotePlayerAPI, @escaping SPTAppRemoteCallback) -> Void) async throws {
        guard let appRemote, appRemote.isConnected, let api = appRemote.playerAPI else { throw SpotifyError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            command(api) { _, error in
                if let error {
                    continuation.resume(throwing: SpotifyError.from(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func resume() async throws { try await send { api, callback in api.resume(callback) } }
    func pause() async throws { try await send { api, callback in api.pause(callback) } }
    func skipNext() async throws { try await send { api, callback in api.skip(toNext: callback) } }
    func skipPrevious() async throws { try await send { api, callback in api.skip(toPrevious: callback) } }
    func seek(toMs ms: Int) async throws { try await send { api, callback in api.seek(toPosition: ms, callback: callback) } }
    func setShuffle(_ enabled: Bool) async throws { try await send { api, callback in api.setShuffle(enabled, callback: callback) } }
    func setRepeat(_ mode: RepeatMode) async throws { try await send { api, callback in api.setRepeatMode(mode.sdkValue, callback: callback) } }
    func play(uri: String) async throws { try await send { api, callback in api.play(uri, callback: callback) } }
}

// MARK: - SDK delegates (callbacks hop to the main actor)

extension SpotifyService: SPTSessionManagerDelegate {
    nonisolated func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        let token = session.accessToken
        let expiry = session.expirationDate
        Task { @MainActor in self.didAuthorize(token: token, expiry: expiry) }
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.authorizationFailed("Spotify sign-in failed: \(message)") }
    }

    nonisolated func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        let token = session.accessToken
        let expiry = session.expirationDate
        Task { @MainActor in self.didAuthorize(token: token, expiry: expiry) }
    }
}

extension SpotifyService: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in self.remoteDidConnect() }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in self.remoteConnectionFailed(message: message) }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let message = error?.localizedDescription
        Task { @MainActor in self.remoteDidDisconnect(message: message) }
    }
}

extension SpotifyService: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let new = SpotifyService.makeSnapshot(from: playerState)
        Task { @MainActor in self.snapshot = new }
    }
}

// MARK: - Helpers

private final class SpotifyImageReference: NSObject, SPTAppRemoteImageRepresentable {
    let imageIdentifier: String
    init(identifier: String) {
        imageIdentifier = identifier
        super.init()
    }
}

private extension RepeatMode {
    init(sdk: SPTAppRemotePlaybackOptionsRepeatMode) {
        switch sdk {
        case .track: self = .track
        case .context: self = .context
        default: self = .off
        }
    }

    var sdkValue: SPTAppRemotePlaybackOptionsRepeatMode {
        switch self {
        case .off: return .off
        case .track: return .track
        case .context: return .context
        }
    }
}
