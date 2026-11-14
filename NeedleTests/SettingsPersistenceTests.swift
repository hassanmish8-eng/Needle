import XCTest
@testable import Needle

@MainActor
final class SettingsPersistenceTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let name = "needle.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testPreferencesPersistAcrossRelaunch() {
        let defaults = makeDefaults()
        let first = SettingsViewModel(persistence: PersistenceService(defaults: defaults))
        first.settings.vinylSize = .small
        first.settings.backgroundStyle = .solidDark
        first.settings.manualColorEnabled = true
        first.settings.manualColor = RGBColor(0.1, 0.4, 0.9)
        first.settings.showTonearm = false
        first.setStyle(.twoTone, forAlbum: "spotify:album:1")

        let second = SettingsViewModel(persistence: PersistenceService(defaults: defaults))
        XCTAssertEqual(second.settings, first.settings)
        XCTAssertEqual(second.settings.vinylSize, .small)
        XCTAssertEqual(second.settings.style(forAlbum: "spotify:album:1"), .twoTone)
        XCTAssertEqual(second.settings.manualColor, RGBColor(0.1, 0.4, 0.9))
    }

    func testUnknownAlbumUsesDefaultStyle() {
        let vm = SettingsViewModel(persistence: PersistenceService(defaults: makeDefaults()))
        vm.setStyle(.classic, forAlbum: nil)
        XCTAssertEqual(vm.settings.style(forAlbum: "never-seen"), .classic)
        vm.setStyle(.multicolor, forAlbum: "a")
        XCTAssertEqual(vm.settings.style(forAlbum: "a"), .multicolor)
        vm.clearStyleOverride(forAlbum: "a")
        XCTAssertEqual(vm.settings.style(forAlbum: "a"), .classic)
    }

    func testResetRestoresDefaultsAndPersistsThem() {
        let defaults = makeDefaults()
        let vm = SettingsViewModel(persistence: PersistenceService(defaults: defaults))
        vm.settings.vinylSize = .small
        vm.resetAppearance()
        XCTAssertEqual(vm.settings, AppSettings())
        XCTAssertEqual(SettingsViewModel(persistence: PersistenceService(defaults: defaults)).settings, AppSettings())
    }

    func testOlderSavedSettingsStillDecode() throws {
        let json = #"{"vinylSize":"small","showTonearm":false}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.vinylSize, .small)
        XCTAssertFalse(decoded.showTonearm)
        XCTAssertEqual(decoded.backgroundStyle, AppSettings().backgroundStyle)
        XCTAssertTrue(decoded.surfaceReflections)
    }

    func testAlbumOverridesAreCapped() {
        let vm = SettingsViewModel(persistence: PersistenceService(defaults: makeDefaults()))
        for i in 0..<320 { vm.setStyle(.solid, forAlbum: "album-\(i)") }
        XCTAssertLessThanOrEqual(vm.settings.albumStyles.count, 300)
    }

    func testMotionPolicyHonorsSystemAndUserSettings() {
        var s = AppSettings()
        XCTAssertTrue(MotionPolicy(settings: s, systemReduceMotion: false).spinsRecord)
        XCTAssertFalse(MotionPolicy(settings: s, systemReduceMotion: true).spinsRecord)
        XCTAssertFalse(MotionPolicy(settings: s, systemReduceMotion: true).animatesTonearm)
        s.alwaysReduceMotion = true
        XCTAssertTrue(MotionPolicy(settings: s, systemReduceMotion: false).reduceMotion)
        s = AppSettings()
        s.continuousRotation = false
        XCTAssertFalse(MotionPolicy(settings: s, systemReduceMotion: false).spinsRecord)
    }
}
