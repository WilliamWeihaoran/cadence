// **macOS only — T-2074/T-2075.** Until this target was asked to build for an iOS Simulator it
// had no platform guards at all, because it had never been built for anything but macOS: it reaches
// AppKit, `XCUIElement.rightClick()`, `CGSessionCopyCurrentDictionary` and identifiers only the
// desktop surface publishes. The guard is here rather than around the individual call sites because
// nothing in this file is about iOS; the iOS half of the target is `CadenceIOSSeededStoreUITests`.
#if os(macOS)
//
//  CadenceUITestsLaunchTests.swift
//  CadenceUITests
//
//  Created by William Wei on 3/26/26.
//

import XCTest

final class CadenceUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "launch-\(UUID().uuidString)")
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground),
            "app did not reach the foreground; state is \(app.state.rawValue)"
        )
        XCTAssertTrue(app.buttons["sidebar.destination.today"].waitForExistence(timeout: CadenceUITestBounds.firstPaint))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
