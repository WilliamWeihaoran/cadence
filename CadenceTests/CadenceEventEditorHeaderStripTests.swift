import Foundation
import Testing
@testable import Cadence

/// One of the three owner-decided [[T-8201]] calendar parity fixes, which landed as three
/// commits off one verified tree. They share a premise — a macOS/iOS difference with no hardware
/// or input constraint behind it is drift, and the fix is one shared owner rather than a second
/// copy nudged closer by hand — and each has its own suite so each could land on its own.
///
/// Source scans where the claim is about a SwiftUI body, values where the claim is a value. Both
/// kinds, rather than only the first: a scan that said "the view is drawn" and nothing about what
/// it says would pass over a strip that printed the wrong number.

// MARK: - [[T-8573]] the event editor's header strip

/// **The repeat marker and the length capsule are one view, drawn by both event editors.**
///
/// The Mac's `CalendarEventEditPopover` drew a strip above the shared `CadenceSchedulePanel` —
/// the calendar's dot and name, a `repeat` glyph with "Repeats" on a series member, and a capsule
/// with the event's length — and `iOSCalendarEventEditSheet` drew the panel alone. The calendar
/// name is in the panel's Calendar row on both, so the drift was the other two facts, and the
/// "Repeats" one has a consequence: a series whose rules Cadence cannot spell gets no Repeat row,
/// so on iOS nothing said the event repeated until Save raised the scope question.
@Suite("The event editor's header strip is one view on both platforms")
@MainActor
struct CadenceEventEditorHeaderStripTests {

    private func timedDraft(start: Int, end: Int, dateKey: String = "2026-03-04") -> CadenceScheduleDraft {
        var draft = CadenceScheduleDraft(dateKey: dateKey, startMin: start, kind: .event, durationMinutes: end - start)
        draft.startMin = start
        draft.endMin = end
        return draft
    }

    /// The capsule's number is the draft's own length, and an all-day event has none — the panel's
    /// schedule row already says "All day", and a capsule reading "24h" beside it would be the
    /// same fact said twice and wrong.
    ///
    /// **Failing-first:** dropping the `!draft.isAllDay` guard answers a label for the all-day
    /// case; reading `endMin - startMin` instead of the instants answers 45 for the two-day draft.
    @Test func theLengthCapsuleReadsTheDraftsOwnInstantsAndIsAbsentOnAnAllDayEvent() {
        let shortDraft = timedDraft(start: 9 * 60, end: 9 * 60 + 45)
        let label = CadenceEventEditorHeaderFacts.durationLabel(for: shortDraft)
        #expect(label == CadenceTaskPresentationSupport.estimateLabel(minutes: 45, emptyPlaceholder: "–"),
                "the capsule does not print the shared estimate label for a 45-minute event")

        var allDay = shortDraft
        allDay.isAllDay = true
        #expect(CadenceEventEditorHeaderFacts.durationLabel(for: allDay) == nil,
                "an all-day event is given a length capsule as well as an All day row")

        // A block drawn on one day may be a segment of something longer: the capsule reads the
        // whole event, which is the half a per-segment reading would get wrong.
        var multiDay = timedDraft(start: 9 * 60, end: 9 * 60 + 45)
        multiDay.endDateKey = "2026-03-05"
        let longLabel = CadenceEventEditorHeaderFacts.durationLabel(for: multiDay)
        #expect(longLabel != nil && longLabel != label,
                "a two-day event prints the same length as the 45 minutes drawn on its first day")
    }

    /// The strip draws nothing when it has nothing to say, so an untimed one-off event on iOS
    /// keeps the sheet it had rather than gaining an empty band above the panel.
    @Test func theHeaderStripIsEmptyOnlyWhenItHasNoFactToState() {
        let bare = CadenceEventEditorHeaderStrip(repeatsInSeries: false, durationLabel: nil)
        #expect(bare.isEmpty, "a strip with no calendar, no series and no length still draws")

        #expect(!CadenceEventEditorHeaderStrip(repeatsInSeries: true, durationLabel: nil).isEmpty,
                "a series member's strip is treated as empty")
        #expect(!CadenceEventEditorHeaderStrip(repeatsInSeries: false, durationLabel: "45m").isEmpty,
                "a strip carrying a length is treated as empty")
        #expect(!CadenceEventEditorHeaderStrip(calendarName: "Work", repeatsInSeries: false, durationLabel: nil).isEmpty,
                "the Mac's calendar label alone is treated as empty")
    }

    /// Both editors draw the same view above the same panel, and neither computes the length a
    /// second way.
    ///
    /// **Failing-first:** restoring the Mac's own `guard !draft.isAllDay, let range = ...`
    /// arithmetic fails the single-owner count; putting the strip below the panel on iOS fails
    /// the order expectation.
    @Test func bothEventEditorsDrawTheSharedStripAboveTheSharedPanel() throws {
        let macPath = "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift"
        let mac = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(macPath))
        let popover = try #require(
            CadenceSourceScan.declarationBody("struct CalendarEventEditPopover: View", in: mac),
            "CalendarEventEditPopover was not found in \(macPath)"
        )
        #expect(popover.contains("CadenceSchedulePanel("), "non-vacuity: the body read is not the popover")
        #expect(popover.contains("CadenceEventEditorHeaderFacts.durationLabel(for: draft)"),
                "the Mac popover computes the event's length instead of asking the shared owner")
        #expect(CadenceSourceScan.matchCount(#"estimateLabel\(minutes:"#, in: popover) == 0,
                "the Mac popover still spells the length arithmetic out for itself")
        let macHeader = try #require(
            CadenceSourceScan.declarationBody("private var header: some View", in: popover),
            "the Mac popover has no header strip"
        )
        #expect(macHeader.contains("CadenceEventEditorHeaderStrip("),
                "the Mac popover draws a header of its own rather than the shared strip")
        let macBody = try #require(CadenceSourceScan.declarationBody("var body: some View", in: popover))
        let macStrip = try #require(macBody.range(of: "header"),
                                    "the Mac popover's body no longer draws its header")
        let macPanel = try #require(macBody.range(of: "CadenceSchedulePanel("))
        #expect(macStrip.lowerBound < macPanel.lowerBound, "the Mac strip is no longer above the panel")

        let iosPath = "Cadence/iOS/iOSCalendarEventEditSheet.swift"
        let ios = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(iosPath))
        let sheet = try #require(
            CadenceSourceScan.declarationBody("struct iOSCalendarEventEditSheet: View", in: ios),
            "iOSCalendarEventEditSheet was not found in \(iosPath)"
        )
        #expect(sheet.contains("CadenceSchedulePanel("), "non-vacuity: the body read is not the sheet")
        let iosHeader = try #require(
            CadenceSourceScan.declarationBody("private var headerStrip: CadenceEventEditorHeaderStrip", in: sheet),
            "the iOS event editor still draws the panel alone ([[T-8573]])"
        )
        #expect(iosHeader.contains("repeatsInSeries: isRecurringEvent"),
                "the iOS strip is not told whether the event repeats")
        #expect(iosHeader.contains("CadenceEventEditorHeaderFacts.durationLabel(for: draft)"),
                "the iOS strip reads the length from somewhere other than the shared owner")
        let iosBody = try #require(CadenceSourceScan.declarationBody("var body: some View", in: sheet))
        let iosStrip = try #require(iosBody.range(of: "headerStrip"),
                                    "the iOS sheet's body never draws the strip")
        let iosPanel = try #require(iosBody.range(of: "CadenceSchedulePanel("))
        #expect(iosStrip.lowerBound < iosPanel.lowerBound, "the iOS strip is drawn below the panel")

        // The calendar dot and name stay the Mac's: the panel's Calendar row names the calendar on
        // both, so adding it to iOS would be that row said twice.
        #expect(macHeader.contains("calendarName: item.calendarTitle"),
                "the Mac popover dropped the calendar label the owner's decision kept")
        #expect(!iosHeader.contains("calendarName"),
                "the iOS sheet now repeats the calendar name the panel's Calendar row already gives")
    }

    /// The strip's two facts are one owner's words, and the length format is the shared one.
    @Test func theStripsWordsAndGlyphComeFromOnePlace() throws {
        #expect(CadenceEventEditorHeaderFacts.repeatsLabel == "Repeats")
        #expect(CadenceEventEditorHeaderFacts.repeatSymbolName == "repeat")

        let path = "Cadence/Shared/Components/CadenceEventEditorHeaderStrip.swift"
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        let strip = try #require(
            CadenceSourceScan.declarationBody("struct CadenceEventEditorHeaderStrip: View", in: code)
        )
        #expect(strip.count > 400, "non-vacuity: the strip read as \(strip.count) characters")
        #expect(strip.contains("CadenceEventEditorHeaderFacts.repeatsLabel"),
                "the strip types the word \"Repeats\" out rather than reading the one owner")
        #expect(strip.contains("CadenceEventEditorHeaderFacts.repeatSymbolName"),
                "the strip types the repeat glyph's name out rather than reading the one owner")
    }
}
