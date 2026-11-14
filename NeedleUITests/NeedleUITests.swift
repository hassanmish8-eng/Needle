import XCTest

/// These run against the debug-only scripted Spotify double (`-ui-test-scenario`), so no
/// Spotify account is needed. They check what is on screen, not Spotify itself.
final class NeedleUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", scenario]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    func testOnboardingShowsWelcomeAndConnectButton() {
        let app = launch("onboarding")
        XCTAssertTrue(element(app, "connectSpotifyButton").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your music, pressed into vinyl."].exists)
        XCTAssertTrue(app.staticTexts["NEEDLE"].exists)
    }

    func testConnectingMovesToThePlayer() {
        let app = launch("onboarding")
        element(app, "connectSpotifyButton").tap()
        XCTAssertTrue(element(app, "playPauseButton").waitForExistence(timeout: 5))
    }

    func testEmptyPlaybackStateIsExplained() {
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["Nothing playing right now."].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "emptyOpenSpotifyButton").exists)
        XCTAssertTrue(element(app, "browseMusicButton").exists)
        XCTAssertTrue(element(app, "vinylRecord").exists)
    }

    func testPlayerRendersTrackAndControls() {
        let app = launch("playing")
        XCTAssertTrue(element(app, "vinylRecord").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test Track"].exists)
        XCTAssertTrue(app.staticTexts["Test Artist"].exists)
        for id in ["playPauseButton", "previousButton", "nextButton", "shuffleButton", "repeatButton", "progressBar", "settingsButton", "connectionPill"] {
            XCTAssertTrue(element(app, id).exists, "missing \(id)")
        }
        XCTAssertEqual(element(app, "connectionPill").label, "Spotify: Connected")
    }

    func testPlayPauseFollowsTheReportedState() {
        let app = launch("playing")
        let button = element(app, "playPauseButton")
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.label, "Pause")
        button.tap()
        let paused = NSPredicate(format: "label == %@", "Play")
        expectation(for: paused, evaluatedWith: button)
        waitForExpectations(timeout: 5)
    }

    func testSettingsOpensAndCloses() {
        let app = launch("playing")
        element(app, "settingsButton").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        element(app, "settingsDoneButton").tap()
        XCTAssertTrue(element(app, "playPauseButton").waitForExistence(timeout: 5))
    }

    func testConnectionLossIsShownAndReconnectRecovers() {
        let app = launch("disconnected")
        XCTAssertTrue(element(app, "reconnectButton").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "connectionPill").label, "Spotify: Not connected")
        element(app, "reconnectButton").tap()
        let connected = NSPredicate(format: "label == %@", "Spotify: Connected")
        expectation(for: connected, evaluatedWith: element(app, "connectionPill"))
        waitForExpectations(timeout: 5)
        XCTAssertFalse(element(app, "reconnectButton").exists)
    }
}
