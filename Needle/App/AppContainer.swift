import Foundation

/// Builds the object graph once. Debug builds can swap in a scripted Spotify double
/// (launch argument `-ui-test-scenario <name>`) so UI tests never need a real account.
@MainActor
final class AppContainer: ObservableObject {
    let spotify: SpotifyServicing
    let settings: SettingsViewModel
    let playback: PlaybackViewModel
    let search: SearchViewModel

    init() {
        let service: SpotifyServicing
        let persistence: PersistenceService

        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "ui-test-scenario"),
           let scenario = ScriptedSpotifyService.Scenario(rawValue: name) {
            let suite = "needle.uitests"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            service = ScriptedSpotifyService(scenario: scenario)
            persistence = PersistenceService(defaults: defaults)
        } else {
            service = SpotifyService()
            persistence = PersistenceService()
        }
        #else
        service = SpotifyService()
        persistence = PersistenceService()
        #endif

        let settings = SettingsViewModel(persistence: persistence)
        let webAPI = SpotifyWebAPI(tokenProvider: { [weak service] in service?.accessToken })

        self.spotify = service
        self.settings = settings
        self.search = SearchViewModel(api: webAPI)
        self.playback = PlaybackViewModel(spotify: service,
                                          settings: settings,
                                          artwork: ArtworkService(),
                                          palettes: ColorPaletteService(),
                                          webAPI: webAPI,
                                          network: NetworkMonitor())
    }
}
