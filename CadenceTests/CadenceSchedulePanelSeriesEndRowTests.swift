import Foundation
import Testing
@testable import Cadence

/// **The standard schedule panel has an Ends row under Repeat** ([[T-6901]]).
///
/// `CadenceSchedulePanel.standardPanel` — the Mac drag-create popover, the Mac event editor, the
/// inline task panel and the iPad timeline's draft editor — drew Repeat with no end condition, so
/// a series made there was always endless and an existing series' end rode through the editor
/// unseen. The row's writes are draft methods, tested here as values; the panel's wiring to them is
/// source-scanned, because a SwiftUI body is not reachable from a unit test. Shared code, so it runs on both legs; the
/// drag-create value types are macOS-only and are asserted there. No
/// `EKEventStore` and no `ModelContext` are involved.
@MainActor
struct CadenceSchedulePanelSeriesEndRowTests {
    private static let calendar = Calendar.current

    private static func day(_ key: String) throws -> Date {
        try #require(DateFormatters.date(from: key, in: calendar))
    }

    private static func weekly(_ kind: CadenceScheduleDraftKind, on key: String = "2026-10-21") -> CadenceScheduleDraft {
        var draft = CadenceScheduleDraft(dateKey: key, startMin: 600, kind: kind)
        draft.repeatRule = .weekly
        return draft
    }

    // MARK: Visibility

    @Test func theEndsRowsAreDrawnOnlyUnderARepeatThatRepeats() {
        var draft = Self.weekly(.event)
        #expect(draft.showsSeriesEndRows)
        draft.repeatRule = .none
        #expect(!draft.showsSeriesEndRows)
    }

    // MARK: Choosing a mode reaches the create writes

    @Test func choosingAfterOnANewEventSeedsTenAndTheDragCreateEventDraftCarriesIt() {
        var draft = Self.weekly(.event)
        draft.selectSeriesEnd(.afterCount)

        #expect(draft.seriesEndCount == CadenceTaskRecurrenceEndPresentation.seededEndCount)
        #expect(draft.seriesEndCount > 1, "a fresh series ending on its first occurrence")
        #expect(draft.effectiveSeriesEndMode == .afterCount)
        #if os(macOS)
        let event = QuickCreateEventDraft(scheduleDraft: draft)
        #expect(event.seriesEndMode == .afterCount)
        #expect(event.seriesEndCount == 10)
        #endif
    }

    @Test func choosingOnDateOnANewTaskSeedsADayAndTheDragCreateTaskDraftCarriesIt() throws {
        let today = try Self.day("2026-10-21")
        var draft = Self.weekly(.task)
        draft.selectSeriesEnd(.onDate, reference: today, calendar: Self.calendar)

        #expect(draft.seriesEndDateKey == "2026-11-21")
        #expect(draft.effectiveSeriesEndMode == .onDate)
        #if os(macOS)
        let task = QuickCreateTaskDraft(scheduleDraft: draft)
        #expect(task.seriesEndMode == .onDate)
        #expect(task.seriesEndDateKey == "2026-11-21")
        #endif
    }

    @Test func choosingNeverWritesAnEndlessSeriesButKeepsTheCountForAReturnToAfter() {
        var draft = Self.weekly(.event)
        draft.setSeriesEndCount(4)
        draft.selectSeriesEnd(.never)

        #expect(draft.effectiveSeriesEndMode == .never)
        #if os(macOS)
        #expect(QuickCreateEventDraft(scheduleDraft: draft).seriesEndMode == .never)
        #endif
        draft.selectSeriesEnd(.afterCount)
        #expect(draft.seriesEndCount == 4)
    }

    // MARK: Values

    @Test func theAfterCountIsFlooredAtOneAndAtTheOccurrenceAnExistingTaskReached() {
        var draft = Self.weekly(.task)
        draft.setSeriesEndCount(0)
        #expect(draft.seriesEndCount == 1)

        draft.seriesOccurrenceNumber = 15
        draft.selectSeriesEnd(.afterCount)
        #expect(draft.seriesEndCount == 15, "a task on its 15th occurrence would read 15 of 1")
        draft.setSeriesEndCount(3)
        #expect(draft.seriesEndCount == 15)
        #expect(draft.seriesEndCountRange.lowerBound == 15)
    }

    @Test func theAfterStepperNeverCapsACountAlreadyPastItsCeiling() {
        var draft = Self.weekly(.task)
        draft.seriesEndCount = 1500
        #expect(draft.seriesEndCountRange.contains(1500))
        #expect(draft.seriesEndCountRange.lowerBound == 1)
    }

    @Test func pickingAnEndDayWritesItsKeyAndTheMode() throws {
        var draft = Self.weekly(.event)
        draft.setSeriesEndDate(try Self.day("2027-01-05"))
        #expect(draft.seriesEndMode == .onDate)
        #expect(draft.seriesEndDateKey == "2027-01-05")
    }

    // MARK: The existing-event editor

    @Test func changingAnExistingSeriesEndInThePanelIsWhatTheEventEditorSaves() throws {
        var opened = Self.weekly(.event)
        CadenceEventRepeatSetting(rule: .weekly, endMode: .afterCount, endDateKey: "", endCount: 10).seed(&opened)
        var draft = opened
        #expect(CadenceEventRepeatSetting.edit(draft: draft, opened: opened) == nil)

        draft.setSeriesEndDate(try Self.day("2027-02-01"))
        let saved = try #require(CadenceEventRepeatSetting.edit(draft: draft, opened: opened))
        #expect(saved.endMode == .onDate)
        #expect(saved.endDateKey == "2027-02-01")
        #expect(saved.endCount == 0)
    }

    // MARK: Wiring

    @Test func bothArmsOfTheStandardPanelDrawTheEndsRowsUnderRepeat() throws {
        let panel = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        )
        for arm in ["private var taskSchedule: some View", "private var eventSchedule: some View"] {
            let body = try #require(CadenceSourceScan.declarationBody(arm, in: panel), "\(arm) not found")
            let compact = body.filter { !$0.isWhitespace }
            #expect(compact.contains("repeatRowseriesEndRows"), "\(arm) draws Repeat without Ends")
        }
        let rows = try #require(CadenceSourceScan.declarationBody("private var seriesEndRows: some View", in: panel))
        #expect(rows.contains("draft.showsSeriesEndRows"))
        #expect(rows.contains("seriesEndModeBinding"))
        #expect(rows.contains("seriesEndDateBinding"))
        #expect(rows.contains("seriesEndCountBinding"))
        #expect(panel.contains("set: { draft.selectSeriesEnd($0) }"))
        #expect(panel.contains("set: { draft.setSeriesEndDate($0) }"))
        #expect(panel.contains("set: { draft.setSeriesEndCount($0) }"))
    }
}
