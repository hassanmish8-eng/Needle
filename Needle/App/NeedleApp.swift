import SwiftUI

@main
struct NeedleApp: App {
    @StateObject private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container.playback)
                .environmentObject(container.settings)
                .environmentObject(container.search)
                // NEEDLE's identity is a dark, low-light turntable, so it always renders dark.
                .preferredColorScheme(.dark)
                .onOpenURL { url in container.spotify.handle(url: url) }
        }
        .onChange(of: scenePhase) { phase in
            container.playback.scenePhaseChanged(phase)
        }
    }
}
