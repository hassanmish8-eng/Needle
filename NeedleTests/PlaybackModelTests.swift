import XCTest
@testable import Needle

final class PlaybackModelTests: XCTestCase {

    private let track = TrackInfo(uri: "spotify:track:1", title: "T", artist: "A", album: "Al",
                                  albumURI: "spotify:album:1", imageIdentifier: "spotify:image:1", durationMs: 200_000)

    private func snapshot(paused: Bool, position: Int, receivedAgo: TimeInterval, now: Date) -> PlaybackSnapshot {
        PlaybackSnapshot(track: track, isPaused: paused, positionMs: position, isShuffling: false,
                         repeatMode: .off, receivedAt: now.addingTimeInterval(-receivedAgo))
    }

    func testPositionAdvancesFromRealReportWhilePlaying() {
        let now = Date()
        XCTAssertEqual(snapshot(paused: false, position: 10_000, receivedAgo: 5, now: now).positionMs(at: now), 15_000, accuracy: 50)
    }

    func testPositionDoesNotAdvanceWhilePaused() {
        let now = Date()
        XCTAssertEqual(snapshot(paused: true, position: 10_000, receivedAgo: 30, now: now).positionMs(at: now), 10_000)
    }

    func testPositionIsClampedToDuration() {
        let now = Date()
        XCTAssertEqual(snapshot(paused: false, position: 199_000, receivedAgo: 60, now: now).positionMs(at: now), 200_000)
    }

    func testProgressIsNilWithoutDuration() {
        var s = snapshot(paused: false, position: 0, receivedAgo: 0, now: Date())
        s.track = TrackInfo(uri: "u", title: "t", artist: "a", album: "", albumURI: "", imageIdentifier: "", durationMs: 0)
        XCTAssertNil(s.progress(at: Date()))
    }

    func testTimeFormatting() {
        XCTAssertEqual(TimeFormat.string(ms: 0), "0:00")
        XCTAssertEqual(TimeFormat.string(ms: 187_000), "3:07")
        XCTAssertEqual(TimeFormat.string(ms: 3_723_000), "1:02:03")
        XCTAssertEqual(TimeFormat.string(ms: nil), "–:––")
    }

    func testTracksOnOneAlbumShareAnArtworkKey() {
        let other = TrackInfo(uri: "spotify:track:2", title: "T2", artist: "A", album: "Al",
                              albumURI: "spotify:album:1", imageIdentifier: "spotify:image:1", durationMs: 1)
        XCTAssertEqual(track.artworkKey, other.artworkKey)
        XCTAssertNotEqual(track.artworkKey, TrackInfo(uri: "x", title: "", artist: "", album: "", albumURI: "spotify:album:9",
                                                       imageIdentifier: "spotify:image:9", durationMs: 1).artworkKey)
    }

    func testRepeatCycleRespectsRestrictions() {
        let all = PlaybackRestrictions()
        XCTAssertEqual(PlaybackViewModel.nextRepeat(after: .off, restrictions: all), .context)
        XCTAssertEqual(PlaybackViewModel.nextRepeat(after: .context, restrictions: all), .track)
        XCTAssertEqual(PlaybackViewModel.nextRepeat(after: .track, restrictions: all), .off)
        var noContext = PlaybackRestrictions()
        noContext.canRepeatContext = false
        XCTAssertEqual(PlaybackViewModel.nextRepeat(after: .off, restrictions: noContext), .track)
    }

    func testSpinDriverRunsAtOneTurnPer1Point8SecondsAndCoastsToAStop() {
        XCTAssertEqual(SpinDriver.fullSpeed * 1.8, 360, accuracy: 0.0001)

        let driver = SpinDriver()
        driver.targetVelocity = SpinDriver.fullSpeed
        for _ in 0..<200 { driver.step(dt: 0.02) }            // spin up
        XCTAssertEqual(driver.velocity, SpinDriver.fullSpeed, accuracy: 0.001)

        driver.targetVelocity = 0
        var previous = driver.angle
        for _ in 0..<400 {
            driver.step(dt: 0.01)
            // Angle only ever moves forward (clockwise), and in small steps: no jumps.
            let delta = (driver.angle - previous + 360).truncatingRemainder(dividingBy: 360)
            XCTAssertLessThan(delta, 3.0)
            previous = driver.angle
        }
        XCTAssertEqual(driver.velocity, 0)
        let resting = driver.angle
        driver.step(dt: 1)
        XCTAssertEqual(driver.angle, resting)                  // stopped means stopped

        driver.targetVelocity = SpinDriver.fullSpeed
        driver.step(dt: 0.01)
        XCTAssertGreaterThanOrEqual(driver.angle, resting)     // resumes from the same angle
    }
}
