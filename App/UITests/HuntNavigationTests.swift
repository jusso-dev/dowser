import XCTest

/// The list-to-hunt path, which has no unit-testable seam: it is navigation,
/// and the failure it is here to catch — opening the hunt and bouncing back to
/// the list a moment later — only happens on a real view hierarchy.
final class HuntNavigationTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        return app
    }

    func testTappingADeviceOpensTheHuntAndStaysThere() {
        let app = launch()

        let device = app.staticTexts["AirPods Max"]
        XCTAssertTrue(device.waitForExistence(timeout: 10), "the survey list never appeared")
        device.tap()

        let reading = app.staticTexts["dBm"]
        XCTAssertTrue(reading.waitForExistence(timeout: 5), "tapping a device did not open a hunt")

        // The bug this guards: the hunt opened and unwound itself, which read
        // as a screen that jumped straight back.
        XCTAssertFalse(reading.waitForNonExistence(timeout: 3),
                       "the hunt screen bounced back to the list")
    }

    func testStopReturnsToTheList() {
        let app = launch()

        let device = app.staticTexts["AirPods Max"]
        XCTAssertTrue(device.waitForExistence(timeout: 10))
        device.tap()
        XCTAssertTrue(app.staticTexts["dBm"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.staticTexts["Pick a device"].waitForExistence(timeout: 5)
                      || app.navigationBars["Nearby"].waitForExistence(timeout: 5),
                      "Stop did not return to the list")
    }
}
