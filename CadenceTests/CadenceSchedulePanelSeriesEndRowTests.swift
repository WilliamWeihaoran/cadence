import Foundation
import SwiftData
import SwiftUI
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

    // MARK: The existing-task editor ([[T-8593]])

    /// The iOS task sheet's Ends rows write through these same draft methods, which keep the
    /// off-mode value in the draft (so a return to After finds the count). That is only safe because
    /// the commit drops it: an opened counted series switched to On Date must reach the store as a
    /// date and no count, on this task and on the later occurrence the scope reaches.
    @Test func anExistingCountedSeriesSwitchedToOnDateSavesTheDateAndDropsTheCount() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seriesID = UUID()
        let tasks = (0..<2).map { index -> AppTask in
            let task = AppTask(title: "Water the plants")
            task.recurrenceRule = .weekly
            task.recurrenceSeriesIDRaw = seriesID.uuidString
            task.recurrenceOccurrenceIndex = index + 2
            task.scheduledDate = "2026-10-2\(index + 1)"
            context.insert(task)
            return task
        }
        tasks[0].recurrenceSpawnedTaskID = tasks[1].id
        for task in tasks {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
                mode: .afterCount, endCount: 5, to: task, allTasks: [task], scope: .thisTask
            )
        }
        try context.save()

        let opened = CadenceScheduleDraft(editing: tasks[0])
        #expect(opened.effectiveSeriesEndMode == .afterCount)
        var draft = opened
        draft.selectSeriesEnd(.onDate, reference: try Self.day("2026-10-21"), calendar: Self.calendar)
        #expect(draft.seriesEndCount == 5, "the draft keeps the count for a return to After")
        #expect(draft.changesRecurrence(from: opened))

        let landed = CadenceTaskEditDraftCommit.save(
            draft, opened: opened, to: tasks[0], area: nil, project: nil,
            allTasks: tasks, scope: .thisAndFuture, in: context, reconciler: .inert
        )
        #expect(landed)

        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(stored.count == 2)
        for task in stored {
            #expect(task.recurrenceEndMode == .onDate)
            #expect(task.recurrenceEndDate == "2026-11-21")
            #expect(task.recurrenceEndCount == 0, "the off-mode count reached the store")
        }
    }

    /// The sheet's rows are the panel's: the same draft writes and stepper bounds, no seeding or
    /// normalizing of their own, and no field of the series end assigned by the view.
    @Test func theIOSTaskSheetSeriesRowsBindTheSameDraftWritesAsThePanel() throws {
        let sheet = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailSheetSections.swift")
        )
        #expect(sheet.contains("set: { draft.selectSeriesEnd($0) }"))
        #expect(sheet.contains("set: { draft.setSeriesEndDate($0) }"))
        #expect(sheet.contains("set: { draft.setSeriesEndCount($0) }"))
        #expect(sheet.contains("in: draft.seriesEndCountRange"))
        #expect(sheet.contains("draft.showsSeriesEndRows"))
        for copy in ["defaultEndDateKey", "resolvedEndCount", "normalizedEndCount", "seedSeriesEnd", "endCountChoices"] {
            #expect(!sheet.contains(copy), "the iOS task sheet keeps its own \(copy)")
        }
        for field in ["seriesEndMode", "seriesEndDateKey", "seriesEndCount"] {
            #expect(
                sheet.range(of: "draft\\.\(field)\\s*=[^=]", options: .regularExpression) == nil,
                "the iOS task sheet assigns draft.\(field) itself"
            )
        }
        // One look: the series rows take the panel's purple, not the sheet's old grey. Five here
        // and one in `CadenceSeriesEndCountRow`, which the After row draws since [[T-8901]].
        #expect(CadenceSourceScan.matchCount(#"color: Theme\.purple"#, in: sheet) == 5)
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

/// **The After stepper row is on the Ends row's rhythm** ([[T-8901]]).
///
/// The row was a bare `Stepper` floored by hand with `.frame(minHeight:)` -- 36 in the Mac panel,
/// beside 34 pt field rows, and 44 on the iOS sheet. It is a `CadenceFieldRow` now. The first test
/// measures the RELATION -- the After row and an Ends-shaped field row resolve to the same height
/// on this platform -- by hosting both, never a point figure (T-1279). On the Mac it kills the old
/// 36 pt floor; on iOS the old 44 pt shape measured the same as the field row, so there the second
/// test, which pins that both sheets draw the one row, is what holds the line.
@MainActor
struct CadenceSeriesEndCountRowRhythmTests {
    /// The width a phone's sheet gives its rows; wide enough that no label wraps.
    private static let width: CGFloat = 345

    private static func fittedHeight<V: View>(_ view: V) -> CGFloat {
        let root = view.frame(width: width).fixedSize(horizontal: false, vertical: true)
        let proposal = CGSize(width: width, height: 1_000)
        #if os(iOS)
        return UIHostingController(rootView: root).sizeThatFits(in: proposal).height
        #else
        return NSHostingController(rootView: root).sizeThatFits(in: proposal).height
        #endif
    }

    @Test func theAfterStepperRowIsAsTallAsTheEndsRowAboveIt() {
        var count = 10
        let countBinding = Binding(get: { count }, set: { count = $0 })
        let after = Self.fittedHeight(CadenceSeriesEndCountRow(count: countBinding, in: 1...999))
        let ends = Self.fittedHeight(
            CadenceFieldRow(label: "Ends", systemImage: "number", color: Theme.purple) {
                CadenceChoiceValueButton(title: "After 10 times") {}
            }
        )
        // Non-vacuous: a host that measured nothing would make the two equal at zero.
        #expect(ends >= CadenceSettingsRowMetrics.rowHeight, "the Ends-shaped row measured \(ends)")
        #expect(after == ends, "the After stepper row is \(after) pt where the Ends row is \(ends) pt")
    }

    @Test func bothSheetsDrawTheOneAfterRowAndNoHandFlooredStepper() throws {
        let panel = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        )
        let sheet = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailSheetSections.swift")
        )
        let rows = try #require(CadenceSourceScan.declarationBody("private var seriesEndRows: some View", in: panel))
        #expect(rows.contains("CadenceSeriesEndCountRow(count: seriesEndCountBinding, in: draft.seriesEndCountRange)"))
        let endCount = try #require(CadenceSourceScan.declarationBody("private var endCountRow: some View", in: sheet))
        #expect(endCount.contains("CadenceSeriesEndCountRow(count: endCountSelection, in: draft.seriesEndCountRange)"))
        for (name, source) in [("the panel's Ends rows", rows), ("the iOS sheet", sheet)] {
            #expect(!source.contains("Stepper("), "\(name) draws its own Stepper again")
        }

        let row = try #require(CadenceSourceScan.declarationBody("struct CadenceSeriesEndCountRow: View", in: panel))
        #expect(row.contains("CadenceFieldRow(label: label"), "the After row is not a CadenceFieldRow")
        #expect(row.contains(".labelsHidden()"), "the stepper draws a second label beside the row's")
        #expect(!row.contains("minHeight"), "the After row floors its own height again")
    }
}
