import Foundation
import Combine

/// Owns every persisted preference. Changes apply immediately (views observe `settings`)
/// and are saved on every change, so nothing needs a restart or a "Save" button.
@MainActor
final class SettingsViewModel: ObservableObject {
    static let storageKey = "needle.settings.v1"
    private static let maxAlbumOverrides = 300

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persistence.save(settings, forKey: Self.storageKey)
        }
    }

    private let persistence: PersistenceService

    init(persistence: PersistenceService = PersistenceService()) {
        self.persistence = persistence
        self.settings = persistence.load(AppSettings.self, forKey: Self.storageKey) ?? AppSettings()
    }

    /// Picks the style for one album; with no album it edits the default for new albums.
    func setStyle(_ style: VinylStyle, forAlbum key: String?) {
        guard let key else {
            settings.defaultStyle = style
            return
        }
        settings.albumStyles[key] = style
        if settings.albumStyles.count > Self.maxAlbumOverrides,
           let oldest = settings.albumStyles.keys.sorted().first(where: { $0 != key }) {
            settings.albumStyles.removeValue(forKey: oldest)
        }
    }

    func clearStyleOverride(forAlbum key: String?) {
        guard let key else { return }
        settings.albumStyles.removeValue(forKey: key)
    }

    func resetAppearance() {
        settings = AppSettings()
    }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
