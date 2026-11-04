import Foundation
import Testing
@testable import Cadence

/// [[T-11209]]: a Mac/iOS parity pass on Focus under [[T-8201]]. Three small differences with no
/// hardware or input sentence, each now one shared value both platforms read.
///
/// Read as source where the view is the claim: the iOS files never compile in this target and the
/// Mac views take no store-free snapshot, so what is asserted is that each surface reads the shared
/// value and neither types its own copy beside it.
struct CadenceFocusSurfaceParityTests {

    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    private static func body(_ declaration: String, in path: String) throws -> String {
        let source = try code(path)
        return try #require(
            CadenceSourceScan.declarationBody(declaration, in: source),
            "\(path): `\(declaration)` is gone"
        )
    }

    private static let macChrome = "Cadence/macOS/Views/FocusChromeSupportViews.swift"
    private static let macPage = "Cadence/macOS/Views/FocusView.swift"
    private static let macPicker = "Cadence/macOS/Views/FocusPickerSupportViews.swift"
    private static let ios = "Cadence/iOS/iOSFocusView.swift"

    // MARK: - The line under the clock

    /// iOS's timer card says what finishing will bank under the clock ("Logs 25m when you
    /// finish"); the Mac's card, over the same stopwatch, said nothing there.
    @Test func bothTimerCardsDrawTheLogHintUnderTheClock() throws {
        #expect(CadenceFocusSupport.logHint(elapsedSeconds: 0) == "Nothing to log yet")

        let panel = try Self.body("struct FocusTimerPanel<Controls: View>: View", in: Self.macChrome)
        #expect(panel.contains("let logHint: String"), "the Mac timer card takes no hint")
        let clock = try #require(panel.range(of: "Text(clockDisplay)"), "non-vacuity: the Mac card's clock moved")
        let hint = try #require(panel.range(of: "Text(logHint)"), "the Mac timer card does not draw the hint")
        let controls = try #require(panel.range(of: "controls()"))
        #expect(clock.lowerBound < hint.lowerBound && hint.lowerBound < controls.lowerBound,
                "the hint is not between the clock and the controls, where iOS draws it")

        let layout = try Self.body("private func activeLayout(task: AppTask) -> some View", in: Self.macPage)
        #expect(CadenceSourceScan.matchCount(
            #"FocusTimerPanel\(\s*clockDisplay:\s*clockDisplay,\s*logHint:\s*CadenceFocusSupport\.logHint\(elapsedSeconds:"#,
            in: layout
        ) == 1, "the Mac page spells its own hint rather than the shared one")

        let iosClock = try #require(
            CadenceSourceScan.functionBody(named: "sessionClock", in: try Self.code(Self.ios)),
            "non-vacuity: iOS's clock moved"
        )
        #expect(iosClock.contains("CadenceFocusSupport.logHint(elapsedSeconds: seconds)"))
    }

    // MARK: - The overdue due date in the session header

    /// iOS's header tints the due chip red when the date is past; the Mac's header drew the same
    /// "Due ..." words in the dim metadata colour whatever the date.
    @Test func bothSessionHeadersTintAnOverdueDueDateThroughOnePredicate() throws {
        #expect(CadenceFocusSupport.isOverdue(dueDateKey: "2099-06-09", todayKey: "2099-06-10"))
        #expect(!CadenceFocusSupport.isOverdue(dueDateKey: "2099-06-10", todayKey: "2099-06-10"))

        let predicate = #"CadenceFocusSupport\.isOverdue\(dueDateKey:\s*task\.dueDate,\s*todayKey:[^?]*\?\s*Theme\.red\s*:\s*Theme\.dim"#
        let mac = try Self.body("struct FocusSessionHeader: View", in: Self.macChrome)
        #expect(mac.contains("Text(dueLabel)"), "non-vacuity: the Mac header's due label moved")
        #expect(CadenceSourceScan.matchCount(predicate, in: mac) == 1, "the Mac due label is not tinted when overdue")

        let iosHeader = try #require(
            CadenceSourceScan.functionBody(named: "selectedTaskHeader", in: try Self.code(Self.ios))
        )
        #expect(CadenceSourceScan.matchCount(predicate, in: iosHeader) == 1, "non-vacuity: iOS's tint moved")
    }

    // MARK: - The empty picker's glyph

    /// iOS drew `timer` over "No open tasks"; the Mac drew a green `checkmark.circle`. Both read
    /// one constant now, and the Mac's glyph is dim in both states as iOS's is. The searching
    /// glyph stays the app-wide `magnifyingglass` literal on both (see the constant's comment).
    @Test func bothEmptyPickersDrawTheOneGlyph() throws {
        #expect(CadenceEmptyStateCopy.focusSystemImage == "timer")

        let card = try Self.body("struct FocusPickSessionCard: View", in: Self.macPicker)
        let empty = try #require(card.range(of: "private var emptyState: some View"), "non-vacuity: the empty state moved")
        let emptyState = String(card[empty.lowerBound...])
        #expect(emptyState.contains(
            #"Image(systemName: isSearching ? "magnifyingglass" : CadenceEmptyStateCopy.focusSystemImage)"#
        ), "the Mac empty state spells its own glyphs")
        #expect(!emptyState.contains("checkmark.circle"), "the Mac empty state reads all-done again")
        #expect(!emptyState.contains("Theme.green"))

        let iosCode = try Self.code(Self.ios)
        #expect(CadenceSourceScan.matchCount(
            #"systemImage:\s*CadenceEmptyStateCopy\.focusSystemImage,\s*title:\s*CadenceEmptyStateCopy\.focusTitle"#,
            in: iosCode
        ) == 3, "an iOS Focus empty panel spells its own glyph")
        #expect(CadenceSourceScan.matchCount(
            #"systemImage:\s*"magnifyingglass",\s*title:\s*CadenceEmptyStateCopy\.focusSearchTitle"#,
            in: iosCode
        ) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"systemImage:\s*"[^"]+",\s*title:\s*CadenceEmptyStateCopy\.focusTitle"#,
            in: iosCode
        ) == 0, "an iOS Focus empty panel types a glyph literal beside the shared words")
    }
}
