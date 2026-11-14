import SwiftUI

@MainActor
struct RootView: View {
    @EnvironmentObject private var playback: PlaybackViewModel

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            if playback.connectionStatus.needsOnboarding {
                OnboardingView().transition(.opacity)
            } else {
                PlayerView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: playback.connectionStatus.needsOnboarding)
    }
}
