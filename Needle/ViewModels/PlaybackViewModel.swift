import Foundation
import Combine
import SwiftUI
import UIKit

struct Banner: Identifiable, Equatable {
    enum Kind { case error, info }
    let id = UUID()
    var message: String
    var kind: Kind = .error
}

/// Single source of UI truth for playback. It renders only what Spotify reports: commands
/// never optimistically change state, they show a pending indicator until Spotify confirms.
@MainActor
final class PlaybackViewModel: ObservableObject {
    enum ArtworkState: Equatable { case none, loading, ready, failed }

    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var snapshot: PlaybackSnapshot?
    @Published private(set) var artwork: ArtworkImage = .placeholder
    @Published private(set) var backgroundImage: UIImage?
    @Published private(set) var appearance: VinylAppearance
    @Published private(set) var artworkState: ArtworkState = .none
    @Published private(set) var pending: Set<PlaybackControl> = []
    @Published private(set) var banner: Banner?
    @Published private(set) var accountName: String?
    @Published private(set) var isOffline = false

    let spotify: SpotifyServicing
    private let artworkService: ArtworkService
    private let palettes: ColorPaletteService
    private let webAPI: SpotifyWebAPI?
    private let debounce: TimeInterval

    private var currentSettings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var appliedArtworkKey: String?
    private var loadingKey: String?
    private var extractedPalette: AlbumPalette?
    private var currentImage: UIImage?

    init(spotify: SpotifyServicing,
         settings: SettingsViewModel,
         artwork: ArtworkService,
         palettes: ColorPaletteService,
         webAPI: SpotifyWebAPI? = nil,
         network: NetworkMonitor? = nil,
         debounce: TimeInterval = 0.25) {
        self.spotify = spotify
        self.artworkService = artwork
        self.palettes = palettes
        self.webAPI = webAPI
        self.debounce = debounce
        self.currentSettings = settings.settings
        self.connectionStatus = spotify.connectionStatus
        self.appearance = VinylAppearance(style: .classic,
                                          palette: .neutral,
                                          grooves: settings.settings.grooveVisibility,
                                          reflections: settings.settings.surfaceReflections)

        spotify.connectionStatusPublisher
            .sink { [weak self] in self?.connectionStatusChanged($0) }
            .store(in: &cancellables)
        spotify.snapshotPublisher
            .sink { [weak self] in self?.apply(snapshot: $0) }
            .store(in: &cancellables)
        // Published emits before the property changes, so use the delivered value, not a re-read.
        settings.$settings
            .dropFirst()
            .sink { [weak self] in self?.settingsChanged($0) }
            .store(in: &cancellables)
        network?.$isOnline
            .sink { [weak self] online in self?.isOffline = !online }
            .store(in: &cancellables)
    }

    // MARK: Derived state for views

    var track: TrackInfo? { snapshot?.track }
    var isLive: Bool { connectionStatus.isConnected }
    var isPlaying: Bool { isLive && (snapshot?.isPlaying ?? false) }
    /// A track we remember but can no longer confirm (disconnected / offline).
    var hasStaleTrack: Bool { track != nil && !isLive }

    func progress(at date: Date) -> Double {
        snapshot?.progress(at: date) ?? 0
    }

    func isEnabled(_ control: PlaybackControl) -> Bool {
        guard isLive, let snap = snapshot, snap.track != nil else { return false }
        if pending.contains(control) { return false }
        switch control {
        case .playPause: return true
        case .next: return snap.restrictions.canSkipNext
        case .previous: return snap.restrictions.canSkipPrevious
        case .shuffle: return snap.restrictions.canToggleShuffle
        case .repeatMode: return snap.restrictions.canRepeatContext || snap.restrictions.canRepeatTrack
        case .seek: return snap.restrictions.canSeek && (snap.track?.durationMs ?? 0) > 0
        }
    }

    /// Explains disabled controls instead of leaving them silently dead.
    var restrictionNote: String? {
        guard isLive, let r = snapshot?.restrictions else { return nil }
        if r.canSkipNext && r.canSkipPrevious && r.canSeek && r.canToggleShuffle { return nil }
        return "Spotify is limiting some controls right now (for example during an ad, or on a free account)."
    }

    // MARK: Incoming state

    private func connectionStatusChanged(_ status: ConnectionStatus) {
        connectionStatus = status
        if status == .connected { fetchAccountName() }
        if case .notAuthorized = status { accountName = nil }
    }

    private func fetchAccountName() {
        guard accountName == nil, let webAPI else { return }
        Task { [weak self] in
            let name = await webAPI.currentUserName()
            self?.accountName = name
        }
    }

    private func apply(snapshot new: PlaybackSnapshot?) {
        let previousURI = snapshot?.track?.uri
        snapshot = new
        if new?.track?.uri != previousURI {
            recomputeAppearance()
            scheduleArtwork(for: new?.track)
        }
    }

    private func settingsChanged(_ new: AppSettings) {
        let extractionTurnedOn = new.autoExtractColors && !currentSettings.autoExtractColors
        currentSettings = new
        recomputeAppearance()
        if extractionTurnedOn, extractedPalette == nil, let image = currentImage, let key = appliedArtworkKey {
            Task { [weak self] in
                guard let self else { return }
                let palette = await self.palettes.palette(for: image, key: key)
                guard self.appliedArtworkKey == key else { return }
                self.extractedPalette = palette
                self.recomputeAppearance()
            }
        }
    }

    // MARK: Appearance

    private func recomputeAppearance() {
        let s = currentSettings
        let palette: AlbumPalette
        if track == nil {
            palette = .neutral
        } else if s.manualColorEnabled {
            palette = .manual(s.manualColor)
        } else if s.autoExtractColors, let extracted = extractedPalette {
            palette = extracted
        } else {
            palette = .neutral
        }
        let style: VinylStyle = track == nil ? .classic : s.style(forAlbum: track?.albumKey)
        let next = VinylAppearance(style: style, palette: palette, grooves: s.grooveVisibility, reflections: s.surfaceReflections)
        if next != appearance { appearance = next }
    }

    // MARK: Artwork pipeline (debounced, latest-track-wins, cached)

    private func scheduleArtwork(for track: TrackInfo?) {
        guard let track else {
            artworkTask?.cancel()
            resetArtwork()
            return
        }
        let key = track.artworkKey
        if key == appliedArtworkKey && artworkState == .ready { return }   // same album: keep the vinyl
        if key == loadingKey { return }
        artworkTask?.cancel()
        loadingKey = key
        artworkState = .loading
        artworkTask = Task { [weak self] in
            guard let self else { return }
            if self.debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(self.debounce * 1_000_000_000))
            }
            if Task.isCancelled { return }
            await self.loadArtwork(for: track)
        }
    }

    private func isCurrent(_ key: String) -> Bool {
        !Task.isCancelled && track?.artworkKey == key
    }

    private func loadArtwork(for track: TrackInfo) async {
        let key = track.artworkKey
        do {
            let spotify = self.spotify
            let image = try await artworkService.loadImage(for: track) { requested in
                try await spotify.fetchArtwork(for: requested, size: ArtworkService.requestSize)
            }
            guard isCurrent(key) else { return }
            var palette: AlbumPalette?
            if currentSettings.autoExtractColors {
                palette = await palettes.palette(for: image, key: key)
                guard isCurrent(key) else { return }
            }
            applyArtwork(image: image, key: key, palette: palette)
        } catch {
            guard isCurrent(key) else { return }
            applyArtworkFailure()
        }
    }

    private func applyArtwork(image: UIImage, key: String, palette: AlbumPalette?) {
        appliedArtworkKey = key
        loadingKey = nil
        currentImage = image
        extractedPalette = palette
        backgroundImage = image.downscaled(maxDimension: 200)
        artwork = ArtworkImage(key: key, image: image)
        artworkState = .ready
        recomputeAppearance()
    }

    private func applyArtworkFailure() {
        // A visibly different placeholder label, never a stale cover from another album.
        appliedArtworkKey = nil
        loadingKey = nil
        currentImage = nil
        extractedPalette = nil
        backgroundImage = nil
        artwork = .placeholder
        artworkState = .failed
        recomputeAppearance()
    }

    private func resetArtwork() {
        appliedArtworkKey = nil
        loadingKey = nil
        currentImage = nil
        extractedPalette = nil
        backgroundImage = nil
        artwork = .placeholder
        artworkState = .none
        recomputeAppearance()
    }

    private func retryArtworkIfNeeded() {
        guard artworkState == .failed, let track else { return }
        scheduleArtwork(for: track)
    }

    // MARK: Commands

    func togglePlayPause() {
        guard let snap = snapshot, snap.track != nil else { return }
        let playing = snap.isPlaying
        perform(.playPause) { service in
            if playing { try await service.pause() } else { try await service.resume() }
        }
    }

    func skipNext() { perform(.next) { try await $0.skipNext() } }
    func skipPrevious() { perform(.previous) { try await $0.skipPrevious() } }

    func toggleShuffle() {
        guard let snap = snapshot else { return }
        let target = !snap.isShuffling
        perform(.shuffle) { try await $0.setShuffle(target) }
    }

    func cycleRepeat() {
        guard let snap = snapshot else { return }
        let next = Self.nextRepeat(after: snap.repeatMode, restrictions: snap.restrictions)
        perform(.repeatMode) { try await $0.setRepeat(next) }
    }

    nonisolated static func nextRepeat(after current: RepeatMode, restrictions: PlaybackRestrictions) -> RepeatMode {
        let order: [RepeatMode] = [.off, .context, .track]
        let start = order.firstIndex(of: current) ?? 0
        for step in 1...order.count {
            let candidate = order[(start + step) % order.count]
            switch candidate {
            case .off: return .off
            case .context where restrictions.canRepeatContext: return candidate
            case .track where restrictions.canRepeatTrack: return candidate
            default: continue
            }
        }
        return .off
    }

    func seek(toFraction fraction: Double) async {
        guard let snap = snapshot, let duration = snap.track?.durationMs, duration > 0, isLive else { return }
        let ms = Int(min(max(fraction, 0), 1) * Double(duration))
        pending.insert(.seek)
        do {
            try await spotify.seek(toMs: ms)
        } catch {
            showBanner(SpotifyError.from(error).localizedDescription)
        }
        pending.remove(.seek)
        spotify.refreshPlayerState()
    }

    /// Starts playback of a Spotify URI chosen by the user in search.
    func play(uri: String) async -> Bool {
        guard isLive else {
            showBanner(SpotifyError.notConnected.localizedDescription)
            return false
        }
        do {
            try await spotify.play(uri: uri)
            spotify.refreshPlayerState()
            return true
        } catch {
            let mapped = SpotifyError.from(error)
            var text = mapped.localizedDescription
            if mapped != .premiumRequired { text += " Playing a specific item needs Spotify Premium." }
            showBanner(text)
            return false
        }
    }

    private func perform(_ control: PlaybackControl, _ operation: @escaping (SpotifyServicing) async throws -> Void) {
        guard !pending.contains(control) else { return }
        guard isLive else {
            showBanner(SpotifyError.notConnected.localizedDescription)
            return
        }
        pending.insert(control)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await operation(self.spotify)
            } catch {
                self.showBanner(SpotifyError.from(error).localizedDescription)
            }
            self.pending.remove(control)
            self.spotify.refreshPlayerState()     // always re-sync with what Spotify really did
        }
    }

    // MARK: Banner

    func showBanner(_ message: String, kind: Banner.Kind = .error) {
        let new = Banner(message: message, kind: kind)
        banner = new
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.banner?.id == new.id { self?.banner = nil }
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    // MARK: Connection actions

    func reconnect() { spotify.reconnect() }
    func reauthorize() { spotify.authorize() }
    func disconnect() { spotify.disconnect(forgetSession: true) }
    func openSpotify() { spotify.openSpotify() }

    // MARK: Scene lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            spotify.handleBecameActive()
            retryArtworkIfNeeded()
            startPeriodicSync()
        case .inactive:
            stopPeriodicSync()
        case .background:
            stopPeriodicSync()
            spotify.handleEnteredBackground()
        @unknown default:
            break
        }
    }

    /// Spotify pushes changes; this low-rate re-sync only corrects clock drift while playing.
    private func startPeriodicSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.isPlaying { self.spotify.refreshPlayerState() }
            }
        }
    }

    private func stopPeriodicSync() {
        syncTask?.cancel()
        syncTask = nil
    }
}
