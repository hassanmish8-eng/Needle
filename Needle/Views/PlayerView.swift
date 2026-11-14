import SwiftUI

/// The main screen: header, turntable, track info, progress and controls.
/// Portrait stacks everything; landscape puts the turntable beside the controls.
@MainActor
struct PlayerView: View {
    enum Sheet: String, Identifiable {
        case settings, connection, search
        var id: String { rawValue }
    }

    @EnvironmentObject private var playback: PlaybackViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var sheet: Sheet?

    var body: some View {
        let settings = settingsVM.settings
        let motion = MotionPolicy(settings: settings, systemReduceMotion: systemReduceMotion)

        ZStack {
            VinylBackground(style: settings.backgroundStyle,
                            blur: settings.backgroundBlur,
                            artwork: playback.artwork,
                            backgroundImage: playback.backgroundImage,
                            palette: playback.appearance.palette,
                            animated: motion.animatesArtwork)
                .ignoresSafeArea()

            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    landscape(motion: motion, settings: settings)
                } else {
                    portrait(motion: motion, settings: settings)
                }
            }
        }
        .overlay(alignment: .top) {
            if let banner = playback.banner {
                BannerView(banner: banner) { playback.dismissBanner() }
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: playback.banner)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
    }

    // MARK: Layouts

    private func portrait(motion: MotionPolicy, settings: AppSettings) -> some View {
        VStack(spacing: 0) {
            header
            StatusStrip()
            turntable(motion: motion, settings: settings)
            infoPanel(motion: motion)
        }
        .padding(.horizontal, 20)
    }

    private func landscape(motion: MotionPolicy, settings: AppSettings) -> some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 24) {
                turntable(motion: motion, settings: settings)
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    StatusStrip()
                    infoPanel(motion: motion)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
    }

    private var header: some View {
        HeaderView(onConnection: { sheet = .connection },
                   onSearch: { sheet = .search },
                   onSettings: { sheet = .settings })
    }

    /// The record takes the width asked for by the "Vinyl size" setting, shrunk only if the
    /// controls below would otherwise lose room. Info text reserves its space, so a long
    /// title never makes the record jump.
    private func turntable(motion: MotionPolicy, settings: AppSettings) -> some View {
        GeometryReader { g in
            let byWidth = g.size.width * settings.vinylSize.widthFraction
            let byHeight = (g.size.height - 8) / TurntableMetrics.plinthRatio
            let diameter = max(100, min(byWidth, byHeight))
            TurntableView(diameter: diameter,
                          appearance: playback.appearance,
                          artwork: playback.artwork,
                          motion: motion,
                          showTonearm: settings.showTonearm,
                          track: playback.track,
                          isPlaying: playback.isPlaying,
                          progress: { playback.progress(at: $0) })
                .frame(width: g.size.width, height: g.size.height)
                .opacity(playback.hasStaleTrack ? 0.6 : 1)
        }
    }

    private func infoPanel(motion: MotionPolicy) -> some View {
        VStack(spacing: 14) {
            if playback.track == nil {
                EmptyStateView(onBrowse: { sheet = .search })
            } else {
                TrackInfoView(animated: motion.animatesArtwork)
                ProgressBarView()
                ControlsView()
                if let note = playback.restrictionNote {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(Theme.tertiaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .opacity(playback.hasStaleTrack ? 0.55 : 1)
        .padding(.bottom, 10)
    }

    @ViewBuilder private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .settings: SettingsView()
        case .connection: ConnectionPanelView()
        case .search: SearchView()
        }
    }
}
