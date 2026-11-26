import XCTest

@MainActor final class RoamJournalUITests: XCTestCase {
    private func launch(corrupt: Bool = false, largeText: Bool = false, dark: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.michelle.roamjornal")
        app.launchArguments = ["-roam-ui-test-session", UUID().uuidString]
        if corrupt { app.launchArguments += ["-roam-ui-test-corrupt"] }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", dark ? "-roam-ui-test-dark" : "-roam-ui-test-light"] }
        app.launch(); return app
    }
    func testLaunchAndSettingsPrivacy() throws {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Roam Journal"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Privacy policy"].tap()
        XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 5))
    }
    func testStartupRecoveryIsReachableWithoutOpeningJournal() throws {
        let app = launch(corrupt: true)
        let recovery = app.buttons["Recover from encrypted backup"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 15)); recovery.tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["Backup recovery code"].exists)
        XCTAssertFalse(app.buttons["Prepare encrypted backup"].isEnabled)
    }
    func testNewTripRequiresFaceIDAndCancelKeepsItLocked() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["New trip"].waitForExistence(timeout: 15)); app.buttons["New trip"].tap()
        let field = app.textFields["Trip destination"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("UI test holiday")
        app.buttons["Save"].tap()
        let locked = app.staticTexts["Your trip is locked"]
        XCTAssertTrue(locked.waitForExistence(timeout: 10))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if system.buttons["Cancel"].exists { system.buttons["Cancel"].tap() }
        XCTAssertFalse(app.buttons["Flights, documents & packing"].exists)
    }
    func testHomeAccessibilityAtLargeTextInLightMode() throws {
        let app = launch(largeText: true, dark: false)
        XCTAssertTrue(app.navigationBars["Roam Journal"].waitForExistence(timeout: 15))
        if #available(iOS 17, *) { try app.performAccessibilityAudit() }
    }
    func testHomeAccessibilityAtLargeTextInDarkMode() throws {
        let app = launch(largeText: true)
        XCTAssertTrue(app.navigationBars["Roam Journal"].waitForExistence(timeout: 15))
        if #available(iOS 17, *) { try app.performAccessibilityAudit() }
    }
}
