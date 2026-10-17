#if os(iOS)
import UIKit
import Vision
import XCTest

@MainActor
final class CadenceIOSCalendarAndNoteParityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    // T-1483: asserting the screen catches authorization guards in callers as well as the
    // manager. This launch cannot request EventKit access: the fixture requires the disarm flag.
    func testCalendarShowsTimedAndAllDayFixturesWithoutCalendarPermission() throws {
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        launchFixture()
        tap("Calendar")
        tap("Month")
        for title in ["Deep red event", "Pure blue event", "Pale event", "Deep red all-day"] {
            XCTAssertTrue(containing(title).waitForExistence(timeout: 10), app.debugDescription)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Mobile calendar fixtures"
        shot.lifetime = .keepAlways
        add(shot)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(try renderedText(in: app).contains("9:15a"), "the month chip never rendered its compact start time")
        }
    }

    // T-1471/T-1472: edits use the real note UI. OCR reads only the rendered text-view viewport;
    // the accessibility value contains the entire document even when the heading is offscreen.
    func testLongNoteActuallyScrollsToHeadingsAndLinksAnUnlinkedMention() throws {
        launchFixture()
        tap("Notes")
        tap("Pad")
        tap("New note")
        let editor = app.textViews["markdown.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        replaceText(in: editor, with: "# Orchard plans\n\nA separate target note.")
        tap("Done")
        tap("New note")
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let content = "# Navigation start\n\nOrchard plans\n\n"
            + (1...65).map { "Paragraph \($0): the quiet river crosses the valley.\n" }.joined()
            + "\n## Destination Harbor\n\nThe last section.\n"
        replaceText(in: editor, with: content)

        jump(to: "Navigation start")
        let before = try renderedText(in: editor)
        XCTAssertTrue(before.contains("Navigation start"), before)
        XCTAssertFalse(before.contains("Destination Harbor"), "control: the far heading is already visible")
        jump(to: "Destination Harbor")
        let after = try renderedText(in: editor)
        XCTAssertTrue(after.contains("Destination Harbor"), "selection moved but the viewport did not: \(after)")
        XCTAssertFalse(after.contains("Navigation start"), after)

        // A second request for the same heading must work after the user scrolls away.
        editor.swipeDown(velocity: .fast)
        XCTAssertFalse(try renderedText(in: editor).contains("Destination Harbor"))
        jump(to: "Destination Harbor")
        XCTAssertTrue(try renderedText(in: editor).contains("Destination Harbor"))

        tap("Unlinked mentions")
        tap("Link Orchard plans")
        XCTAssertTrue(containing("No unlinked mentions").waitForExistence(timeout: 5))
        tap("Done")
        let linked = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(linked.contains("Orchard plans"))
        XCTAssertTrue(linked.contains("[[note:"), "the plain title was not converted to a reference")
        XCTAssertTrue(linked.contains("Destination Harbor"), "linking lost the rest of the draft")
    }

    // 375pt is the smallest supported phone portrait width. The shipping phone uses the compact
    // grid/agenda, but even a full seven-column grid at that width can hold the compact clock on
    // its own line. Measure UIKit's font, including the widest minute and both hour-cycle forms.
    func testCompactClockFitsTheSmallestPhoneColumn() {
        // Also cover the full grid's smallest 340pt pane after the inspector takes its share.
        let widths = [375.0, 340.0].map { $0 / 7 - 12 - 10 + 4 }
        let font = UIFont.systemFont(ofSize: 8, weight: .medium)
        for width in widths {
            for clock in ["11:59a", "11:59p", "23:59", "to 11:59p", "to 23:59"] {
                let measured = (clock as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(measured * 0.8, width, "\(clock): \(measured)pt, budget \(width)pt")
            }
        }
        let compact = ("9:15a" as NSString).size(withAttributes: [.font: font]).width
        let regular = ("9:15 AM" as NSString).size(withAttributes: [.font: font]).width
        XCTAssertLessThan(compact, regular)
    }

    private func launchFixture() {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_UI_TEST_SCENARIO"] = "calendar-hues"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "ios-parity-\(UUID().uuidString)")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    private func containing(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func tap(_ title: String) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "missing \(title): \(app.debugDescription)")
        button.tap()
    }

    private func replaceText(in editor: XCUIElement, with content: String) {
        editor.tap()
        editor.press(forDuration: 1)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        } else {
            // New notes contain only their initial '# ' line. The hardware shortcut selects
            // that line too, without making the test depend on the edit menu's presentation.
            editor.typeKey("a", modifierFlags: .command)
        }
        editor.typeText(content)
    }

    private func jump(to heading: String) {
        tap("Outline")
        tap(heading)
        XCTAssertTrue(app.navigationBars["Outline"].waitForNonExistence(timeout: 5))
    }

    private func renderedText(in editor: XCUIElement) throws -> String {
        let screenshot = editor.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Heading viewport"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(UIImage(data: screenshot.pngRepresentation)?.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
#endif
