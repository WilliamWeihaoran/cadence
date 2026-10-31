#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-9255 and T-9256**, two Mac copy/state defects found reading the source (agent
/// `hunt0938mac`).
@MainActor
struct CadenceMacHunt0938CopyTests {
    // MARK: T-9255 -- the inspector's "After N times" end count

    /// The word after the count field was a literal "times", so a series ending after one
    /// occurrence read "After 1 times".
    @Test func theEndCountUnitIsSingularAtOne() {
        #expect(TaskInspectorRecurrenceControl.endCountUnit(forCountText: "1") == "time")
        #expect(TaskInspectorRecurrenceControl.endCountUnit(forCountText: "2") == "times")
        #expect(TaskInspectorRecurrenceControl.endCountUnit(forCountText: "10") == "times")
        // Read off the digits the commit parses, so a stray character does not flip the word.
        #expect(TaskInspectorRecurrenceControl.endCountUnit(forCountText: " 1") == "time")
        // A field mid-edit (empty) keeps the plural, the form that reads next to no number.
        #expect(TaskInspectorRecurrenceControl.endCountUnit(forCountText: "") == "times")
        #expect(TaskInspectorRecurrenceControl.endCountUnit(forCountText: "11") == "times")
    }

    // MARK: T-9256 -- the hover-shortcut date panel's Clear

    /// The panel the Do/Due date shortcut raises over a hovered task drew a red Clear on a field
    /// with no date, clearing nothing.
    @Test func clearIsDrawnOnlyOverAFieldWithADate() {
        let undated = AppTask(title: "Undated")
        for kind in [HoveredTaskDatePickerManager.DateKind.doDate, .dueDate] {
            let request = HoveredTaskDatePickerManager.request(for: undated, kind: kind)
            #expect(!request.fieldHasDate)
            #expect(!request.showsClear)
        }

        let dated = AppTask(title: "Dated")
        dated.scheduledDate = "2026-11-02"
        dated.dueDate = "2026-11-05"
        let doRequest = HoveredTaskDatePickerManager.request(for: dated, kind: .doDate)
        #expect(doRequest.fieldHasDate)
        #expect(doRequest.showsClear)
        #expect(DateFormatters.dateKey(from: doRequest.selectedDate) == "2026-11-02")
        let dueRequest = HoveredTaskDatePickerManager.request(for: dated, kind: .dueDate)
        #expect(dueRequest.showsClear)
        #expect(DateFormatters.dateKey(from: dueRequest.selectedDate) == "2026-11-05")
    }

    /// The kinds read their own field: a task with only a due date offers Clear on Due, not Do.
    @Test func eachKindReadsItsOwnField() {
        let dueOnly = AppTask(title: "Due only")
        dueOnly.dueDate = "2026-11-05"
        #expect(!HoveredTaskDatePickerManager.request(for: dueOnly, kind: .doDate).showsClear)
        #expect(HoveredTaskDatePickerManager.request(for: dueOnly, kind: .dueDate).showsClear)
    }

    /// The undated seed is still today -- what Apply writes -- so the grid keeps showing it.
    @Test func anUndatedFieldStillOpensOnNow() throws {
        let now = try #require(DateFormatters.date(from: "2026-10-31"))
        let request = HoveredTaskDatePickerManager.request(for: AppTask(title: "x"), kind: .dueDate, now: now)
        #expect(DateFormatters.dateKey(from: request.selectedDate) == "2026-10-31")
    }
}
#endif
