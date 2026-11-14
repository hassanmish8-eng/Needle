import XCTest
@testable import Needle

@MainActor
final class PlaybackViewModelTests: XCTestCase {

    private struct Rig {
        let vm: PlaybackViewModel
        let spotify: ScriptedSpotifyService
        let settings: SettingsViewModel
    }

    private func makeRig(_ scenario: ScriptedSpotifyService.Scenario) -> Rig {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("needle-vm-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "needle.tests.\(UUID().uuidString)")!
        let settings = SettingsViewModel(persistence: PersistenceService(defaults: defaults))
        let spotify = ScriptedSpotifyService(scenario: scenario)
        let vm = PlaybackViewModel(spotify: spotify,
                                   settings: settings,
                                   artwork: ArtworkService(directory: dir.appendingPathComponent("art")),
                                   palettes: ColorPaletteService(cache: PaletteCache(directory: dir.appendingPathComponent("pal"))),
                                   debounce: 0)
        return Rig(vm: vm, spotify: spotify, settings: settings)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private func track(_ n: Int, album: Int) -> TrackInfo {
        TrackInfo(uri: "spotify:track:\(n)", title: "Track \(n)", artist: "Artist", album: "Album \(album)",
                  albumURI: "spotify:album:\(album)", imageIdentifier: "spotify:image:\(album)", durationMs: 200_000)
    }

    func testMirrorsWhatSpotifyReports() {
        let rig = makeRig(.playing)
        XCTAssertEqual(rig.vm.track?.title, "Test Track")
        XCTAssertTrue(rig.vm.isPlaying)
        rig.spotify.push(snapshot: ScriptedSpotifyService.makeSnapshot(paused: true))
        XCTAssertFalse(rig.vm.isPlaying)
        XCTAssertNotNil(rig.vm.track)
    }

    func testNothingPlayingShowsNeutralClassicRecord() {
        let rig = makeRig(.empty)
        XCTAssertNil(rig.vm.track)
        XCTAssertFalse(rig.vm.isPlaying)
        XCTAssertEqual(rig.vm.appearance.style, .classic)
        XCTAssertEqual(rig.vm.appearance.palette, .neutral)
    }

    func testPauseSendsARealCommandAndFollowsSpotifysAnswer() async {
        let rig = makeRig(.playing)
        rig.vm.togglePlayPause()
        let paused = await waitUntil { !rig.vm.isPlaying }
        XCTAssertTrue(paused)
        XCTAssertTrue(rig.spotify.commandLog.contains("pause"))
        XCTAssertFalse(rig.vm.pending.contains(.playPause))
    }

    func testRejectedCommandShowsMessageAndDoesNotChangeState() async {
        let rig = makeRig(.playing)
        rig.spotify.rejectNextCommand = "Premium required"
        let before = rig.vm.snapshot
        rig.vm.skipNext()
        let shown = await waitUntil { rig.vm.banner != nil }
        XCTAssertTrue(shown)
        XCTAssertTrue(rig.vm.banner?.message.lowercased().contains("premium") ?? false)
        XCTAssertEqual(rig.vm.snapshot, before)          // no fake success
        XCTAssertFalse(rig.vm.pending.contains(.next))   // no endless spinner
    }

    func testShuffleOnlyShowsActiveAfterSpotifyConfirms() async {
        let rig = makeRig(.playing)
        XCTAssertEqual(rig.vm.snapshot?.isShuffling, false)
        rig.spotify.rejectNextCommand = "no"
        rig.vm.toggleShuffle()
        _ = await waitUntil { rig.vm.banner != nil }
        XCTAssertEqual(rig.vm.snapshot?.isShuffling, false)
        rig.vm.dismissBanner()
        rig.vm.toggleShuffle()
        let on = await waitUntil { rig.vm.snapshot?.isShuffling == true }
        XCTAssertTrue(on)
    }

    func testControlsAreDisabledWhenDisconnectedAndTrackIsMarkedStale() {
        let rig = makeRig(.playing)
        XCTAssertTrue(rig.vm.isEnabled(.playPause))
        rig.spotify.push(status: .disconnected("lost"))
        XCTAssertTrue(rig.vm.hasStaleTrack)
        XCTAssertFalse(rig.vm.isPlaying)                  // never claims to be playing when it can't know
        XCTAssertFalse(rig.vm.isEnabled(.playPause))
        XCTAssertFalse(rig.vm.isEnabled(.next))
    }

    func testRestrictionsDisableControlsAndExplainWhy() {
        let rig = makeRig(.playing)
        var snap = ScriptedSpotifyService.makeSnapshot(paused: false)
        snap.restrictions.canSkipNext = false
        rig.spotify.push(snapshot: snap)
        XCTAssertFalse(rig.vm.isEnabled(.next))
        XCTAssertTrue(rig.vm.isEnabled(.previous))
        XCTAssertNotNil(rig.vm.restrictionNote)
    }

    func testArtworkAndPaletteAreLoadedForTheCurrentTrack() async {
        let rig = makeRig(.playing)
        let ready = await waitUntil { rig.vm.artworkState == .ready }
        XCTAssertTrue(ready)
        XCTAssertNotNil(rig.vm.artwork.image)
        XCTAssertNotEqual(rig.vm.appearance.palette, .neutral)
        let hue = rig.vm.appearance.palette.primary.hsl.h
        XCTAssertTrue(hue > 0.45 && hue < 0.72, "hue \(hue)")   // cyan-to-blue cover
    }

    func testSameAlbumDoesNotRegenerateTheVinyl() async {
        let rig = makeRig(.playing)
        _ = await waitUntil { rig.vm.artworkState == .ready }
        let paletteBefore = rig.vm.appearance.palette
        rig.spotify.push(snapshot: ScriptedSpotifyService.makeSnapshot(track: ScriptedSpotifyService.sampleTrack, paused: false))
        var sameAlbumNextTrack = ScriptedSpotifyService.sampleTrack
        sameAlbumNextTrack = TrackInfo(uri: "spotify:track:other", title: "Next", artist: sameAlbumNextTrack.artist,
                                       album: sameAlbumNextTrack.album, albumURI: sameAlbumNextTrack.albumURI,
                                       imageIdentifier: sameAlbumNextTrack.imageIdentifier, durationMs: 100_000)
        rig.spotify.push(snapshot: ScriptedSpotifyService.makeSnapshot(track: sameAlbumNextTrack, paused: false))
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(rig.spotify.artworkRequests.count, 1)
        XCTAssertEqual(rig.vm.appearance.palette, paletteBefore)
        XCTAssertEqual(rig.vm.track?.title, "Next")
    }

    func testNewAlbumFetchesNewArtwork() async {
        let rig = makeRig(.playing)
        _ = await waitUntil { rig.vm.artworkState == .ready }
        let oldKey = rig.vm.artwork.key
        rig.spotify.push(snapshot: ScriptedSpotifyService.makeSnapshot(track: track(9, album: 9), paused: false))
        let changed = await waitUntil { rig.vm.artwork.key != oldKey && rig.vm.artworkState == .ready }
        XCTAssertTrue(changed)
        XCTAssertEqual(rig.spotify.artworkRequests.count, 2)
    }

    func testOnlyTheLatestTrackArtworkIsApplied() async {
        let rig = makeRig(.empty)
        rig.spotify.artworkHandler = { requested in
            if requested.imageIdentifier == "spotify:image:1" { try? await Task.sleep(nanoseconds: 400_000_000) }
            return ScriptedSpotifyService.syntheticArtwork()
        }
        rig.spotify.push(snapshot: ScriptedSpotifyService.makeSnapshot(track: track(1, album: 1), paused: false))
        rig.spotify.push(snapshot: ScriptedSpotifyService.makeSnapshot(track: track(2, album: 2), paused: false))
        let latest = track(2, album: 2).artworkKey
        let applied = await waitUntil { rig.vm.artwork.key == latest }
        XCTAssertTrue(applied)
        try? await Task.sleep(nanoseconds: 600_000_000)       // the slow, stale request finishes
        XCTAssertEqual(rig.vm.artwork.key, latest)            // and must not overwrite the newer one
    }

    func testArtworkFailureFallsBackToADistinctPlaceholder() async {
        let rig = makeRig(.empty)
        rig.spotify.artworkHandler = { _ in throw SpotifyError.artworkUnavailable }
        rig.spotify.push(snapshot: ScriptedSpotifyService.makeSnapshot(paused: false))
        let failed = await waitUntil { rig.vm.artworkState == .failed }
        XCTAssertTrue(failed)
        XCTAssertNil(rig.vm.artwork.image)
        XCTAssertEqual(rig.vm.artwork, .placeholder)
        XCTAssertNotNil(rig.vm.track)                          // metadata still shown
    }

    func testManualColorOverridesTheExtractedPalette() async {
        let rig = makeRig(.playing)
        _ = await waitUntil { rig.vm.artworkState == .ready }
        rig.settings.settings.manualColorEnabled = true
        rig.settings.settings.manualColor = RGBColor(0.85, 0.10, 0.12)
        let red = await waitUntil { isRedHue(rig.vm.appearance.palette.primary.hsl.h) }
        XCTAssertTrue(red)
    }

    func testChangingStyleUpdatesTheRecordWithoutTouchingPlayback() async {
        let rig = makeRig(.playing)
        rig.settings.setStyle(.multicolor, forAlbum: ScriptedSpotifyService.sampleTrack.albumKey)
        let updated = await waitUntil { rig.vm.appearance.style == .multicolor }
        XCTAssertTrue(updated)
        XCTAssertTrue(rig.vm.isPlaying)
        XCTAssertTrue(rig.spotify.commandLog.isEmpty)
    }

    func testSeekSendsTheRequestedPosition() async {
        let rig = makeRig(.playing)
        await rig.vm.seek(toFraction: 0.5)
        XCTAssertTrue(rig.spotify.commandLog.contains("seek:107500"))
    }
}
