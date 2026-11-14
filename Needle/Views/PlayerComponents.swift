import SwiftUI

/// Title (up to two lines, space always reserved so the record never resizes), artist, album.
@MainActor
struct TrackInfoView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    @ScaledMetric(relativeTo: .title3) private var titleBox: CGFloat = 58
    let animated: Bool

    var body: some View {
        ZStack {
            if let track = playback.track {
                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(Theme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: titleBox, maxHeight: titleBox)
                        .accessibilityIdentifier("trackTitle")
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.footnote)
                            .foregroundColor(Theme.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .id(track.uri)
                .transition(.opacity.combined(with: .offset(x: 0, y: 8)))
            }
        }
        .animation(animated ? .easeInOut(duration: 0.3) : nil, value: playback.track?.uri)
    }
}

/// Reflects Spotify's real position (extrapolated only between real updates). Tap or drag
/// to seek; the seek command is sent once, when the finger lifts.
@MainActor
struct ProgressBarView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    @State private var dragFraction: Double?

    var body: some View {
        let snapshot = playback.snapshot
        let durationMs = snapshot?.track?.durationMs ?? 0
        let enabled = playback.isEnabled(.seek)
        let paused = !playback.isPlaying || dragFraction != nil

        TimelineView(.animation(minimumInterval: 0.25, paused: paused)) { timeline in
            let positionMs = snapshot?.positionMs(at: timeline.date) ?? 0
            let fraction = dragFraction ?? (durationMs > 0 ? Double(positionMs) / Double(durationMs) : 0)
            let shownMs = dragFraction.map { Int($0 * Double(durationMs)) } ?? positionMs
            VStack(spacing: 4) {
                bar(fraction: fraction, enabled: enabled)
                HStack {
                    Text(TimeFormat.string(ms: durationMs > 0 ? shownMs : nil))
                    Spacer()
                    Text(TimeFormat.string(ms: durationMs > 0 ? durationMs : nil))
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(Theme.tertiaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(durationMs > 0
                            ? "\(TimeFormat.string(ms: snapshot?.positionMs(at: Date()))) of \(TimeFormat.string(ms: durationMs))"
                            : "Unavailable")
        .accessibilityAdjustableAction { direction in
            guard enabled, durationMs > 0 else { return }
            let current = Double(snapshot?.positionMs(at: Date()) ?? 0)
            let delta = 10_000.0
            switch direction {
            case .increment: Task { await playback.seek(toFraction: (current + delta) / Double(durationMs)) }
            case .decrement: Task { await playback.seek(toFraction: (current - delta) / Double(durationMs)) }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("progressBar")
    }

    private func bar(fraction: Double, enabled: Bool) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let active = dragFraction != nil
            let thickness: CGFloat = active ? 7 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(height: thickness)
                Capsule().fill(Color.white.opacity(enabled ? 0.92 : 0.45))
                    .frame(width: max(0, width * CGFloat(fraction)), height: thickness)
                if active {
                    Circle().fill(Color.white).frame(width: 14, height: 14)
                        .offset(x: max(0, width * CGFloat(fraction) - 7))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled else { return }
                        dragFraction = min(max(Double(value.location.x / width), 0), 1)
                    }
                    .onEnded { value in
                        guard enabled else { dragFraction = nil; return }
                        let target = min(max(Double(value.location.x / width), 0), 1)
                        dragFraction = target
                        Task {
                            await playback.seek(toFraction: target)
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            dragFraction = nil
                        }
                    }
            )
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(height: 32)
    }
}

@MainActor
struct ControlButton: View {
    let symbol: String
    let label: String
    var value: String? = nil
    var size: CGFloat = 22
    var isActive = false
    let isEnabled: Bool
    let isPending: Bool
    let accent: Color
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .opacity(isPending ? 0 : 1)
                if isPending {
                    ProgressView().tint(.white).scaleEffect(0.8)
                }
                if isActive {
                    // A dot as well as a color change, so state never depends on color alone.
                    Circle().fill(accent).frame(width: 4, height: 4).offset(y: size * 0.95)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .foregroundColor(isActive ? accent : Theme.primaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isPending ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityIdentifier(identifier)
    }
}

/// Shuffle, previous, play/pause, next, repeat. Every state shown is Spotify-confirmed.
@MainActor
struct ControlsView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    @ScaledMetric(relativeTo: .title) private var mainSize: CGFloat = 72

    var body: some View {
        let snapshot = playback.snapshot
        let accent = playback.appearance.palette.accent.color
        let repeatMode = snapshot?.repeatMode ?? .off

        HStack(spacing: 0) {
            ControlButton(symbol: "shuffle", label: "Shuffle",
                          value: (snapshot?.isShuffling ?? false) ? "On" : "Off",
                          isActive: snapshot?.isShuffling ?? false,
                          isEnabled: playback.isEnabled(.shuffle), isPending: playback.pending.contains(.shuffle),
                          accent: accent, identifier: "shuffleButton") { playback.toggleShuffle() }
                .frame(maxWidth: .infinity)

            ControlButton(symbol: "backward.fill", label: "Previous track", size: 26,
                          isEnabled: playback.isEnabled(.previous), isPending: playback.pending.contains(.previous),
                          accent: accent, identifier: "previousButton") { playback.skipPrevious() }
                .frame(maxWidth: .infinity)

            playPause
                .frame(maxWidth: .infinity)

            ControlButton(symbol: "forward.fill", label: "Next track", size: 26,
                          isEnabled: playback.isEnabled(.next), isPending: playback.pending.contains(.next),
                          accent: accent, identifier: "nextButton") { playback.skipNext() }
                .frame(maxWidth: .infinity)

            ControlButton(symbol: repeatMode == .track ? "repeat.1" : "repeat", label: "Repeat",
                          value: Self.repeatDescription(repeatMode),
                          isActive: repeatMode != .off,
                          isEnabled: playback.isEnabled(.repeatMode), isPending: playback.pending.contains(.repeatMode),
                          accent: accent, identifier: "repeatButton") { playback.cycleRepeat() }
                .frame(maxWidth: .infinity)
        }
    }

    private var playPause: some View {
        let playing = playback.isPlaying
        let pending = playback.pending.contains(.playPause)
        let enabled = playback.isEnabled(.playPause)
        return Button(action: {
            Haptics.tap()
            playback.togglePlayPause()
        }) {
            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                if pending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Theme.primaryText)
                        .offset(x: playing ? 0 : 2)
                }
            }
            .frame(width: mainSize, height: mainSize)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || pending ? 1 : 0.4)
        .accessibilityLabel(playing ? "Pause" : "Play")
        .accessibilityIdentifier("playPauseButton")
    }

    private static func repeatDescription(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: return "Off"
        case .context: return "All"
        case .track: return "One"
        }
    }
}

@MainActor
struct EmptyStateView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    var onBrowse: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            Text(playback.isLive ? "Nothing playing right now." : "Live playback status unavailable.")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.primaryText)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("nothingPlayingLabel")
            Text(playback.isLive
                 ? "Start a song in Spotify, or pick something to play from here."
                 : "Reconnect to see what's on.")
                .font(.subheadline)
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Open Spotify") { playback.openSpotify() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .accessibilityIdentifier("emptyOpenSpotifyButton")
                Button("Browse music", action: onBrowse)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .accessibilityIdentifier("browseMusicButton")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
