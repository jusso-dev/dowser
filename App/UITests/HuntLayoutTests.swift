import XCTest

/// The hunt has to fit whatever window it is given. An iPhone Duo shows it on
/// a 466 x 678 pt display, and the app can be moved between displays at any
/// time, so the size is never a given. The largest accessibility text is the
/// cheapest way to make the hunt outgrow that window in a test.
final class HuntLayoutTests: XCTestCase {
    func testTheHuntScrollsWhenItOutgrowsTheWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        // The first row: at this size on a 6.3" phone the second one shows
        // only the top of its name, in the home indicator's strip, and a tap
        // there was dropped on a cold CI simulator.
        let device = app.staticTexts["Justin iPhone 17 Pro Max"]
        XCTAssertTrue(device.waitForExistence(timeout: 30), "the survey list never appeared")
        attach(app, "survey at accessibility text size")
        device.tap()

        // The last thing on the screen: if it can be brought into view, so
        // can everything above it.
        let footnote = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Signal strength is'")).firstMatch
        // One look at this hunt takes the CI simulator about four seconds.
        XCTAssertTrue(footnote.waitForExistence(timeout: 30), "tapping a device did not open a hunt")
        attach(app, "hunt at accessibility text size")

        let before = footnote.frame.minY
        app.windows.firstMatch.swipeUp()
        attach(app, "hunt at accessibility text size, scrolled")

        XCTAssertLessThan(footnote.frame.minY, before, "the hunt did not scroll")
        XCTAssertLessThanOrEqual(footnote.frame.maxY, app.windows.firstMatch.frame.maxY,
                                 "the bottom of the hunt cannot be scrolled into view")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
