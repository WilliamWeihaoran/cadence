#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-5351. **A Month day cell takes a dropped task, and a bad payload writes nothing.**
///
/// The first half of this entry gave `MonthTaskChip` the all-day lane's click and drag, and
/// deliberately left the day cell inert pending the owner's decision — so a Month chip could be
/// picked up with nowhere on the grid to put it down. The owner chose option (a); this is the drop
/// half of it. The click half is `CadenceCalendarMonthDayOpenTests`.
///
/// `CalendarMonthDayDropSupport.drop` resolves the payload and then hands off to the Calendar
/// Board's own `schedule`, so what this suite owns is the resolution and the hand-off, not the
/// write — `CalendarBoardDayDropCommitTests` owns that, and duplicating its commit counting here
/// would be a second opinion rather than a second check.
@MainActor
struct CadenceCalendarMonthDayDropTests {
    private struct Refused: Error {}

    private func fixture() throws -> (context: ModelContext, task: AppTask) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let task = AppTask(title: "Dragged across the month grid")
        task.scheduledDate = "2026-06-01"
        context.insert(task)
        try context.save()
        return (context, task)
    }

    @Test func aTaskDroppedOnADayIsRescheduledOntoThatDay() throws {
        let fixture = try fixture()

        let outcome = CalendarMonthDayDropSupport.drop(
            [fixture.task.id.uuidString],
            on: "2026-07-04",
            in: [fixture.task],
            modelContext: fixture.context
        )

        #expect(outcome == .applied)
        #expect(fixture.task.scheduledDate == "2026-07-04")
    }

    /// The Month chip drags its bare `id.uuidString`; a task dragged from a list carries the
    /// `listTask:` prefix. Both have to land on a day, or the grid takes one of the app's two
    /// task drags and refuses the other.
    @Test func aPrefixedListPayloadLandsOnTheDayToo() throws {
        let fixture = try fixture()

        let outcome = CalendarMonthDayDropSupport.drop(
            [TaskDragPayload.string(for: fixture.task.id)],
            on: "2026-07-04",
            in: [fixture.task],
            modelContext: fixture.context
        )

        #expect(outcome == .applied)
        #expect(fixture.task.scheduledDate == "2026-07-04")
    }

    /// Resolution before any write: a payload the grid cannot place must not reach `commit`, or a
    /// drop that moved no field would commit whatever unrelated pending work the app's single
    /// `ModelContext` happens to be holding.
    @Test func anUnresolvablePayloadWritesNothingAndCommitsNothing() throws {
        let fixture = try fixture()
        var commits = 0

        let outcome = CalendarMonthDayDropSupport.drop(
            [TaskDragPayload.bundleString(for: UUID())],
            on: "2026-07-04",
            in: [fixture.task],
            modelContext: fixture.context,
            commit: { _ in commits += 1 }
        )

        #expect(outcome == .resolvedNothing)
        #expect(commits == 0)
        #expect(fixture.task.scheduledDate == "2026-06-01")
    }

    @Test func anEmptyDropResolvesNothing() throws {
        let fixture = try fixture()

        let outcome = CalendarMonthDayDropSupport.drop(
            [],
            on: "2026-07-04",
            in: [fixture.task],
            modelContext: fixture.context
        )

        #expect(outcome == .resolvedNothing)
        #expect(fixture.task.scheduledDate == "2026-06-01")
    }

    /// A refused store answers `.refused`, which the cell reports to `.dropDestination` as `false`
    /// so the card springs back rather than being drawn on a day the store never took.
    @Test func aRefusedCommitIsReportedRatherThanSwallowed() throws {
        let fixture = try fixture()

        let outcome = CalendarMonthDayDropSupport.drop(
            [fixture.task.id.uuidString],
            on: "2026-07-04",
            in: [fixture.task],
            modelContext: fixture.context,
            commit: { _ in throw Refused() }
        )

        #expect(outcome == .refused)
        #expect(fixture.task.scheduledDate == "2026-06-01", "undone, not left on the refused day")
    }

    /// [[T-6211]]. The refusal above sprang the card back with no sentence; the grid now answers it
    /// with the board's. Each outcome against the others, so a mapping that always (or never)
    /// spoke fails here.
    @Test func aRefusedDropIsExplainedAndAnyOtherOutcomeClearsTheNotice() throws {
        let fixture = try fixture()
        let refused = CalendarMonthDayDropSupport.drop(
            [fixture.task.id.uuidString],
            on: "2026-07-04",
            in: [fixture.task],
            modelContext: fixture.context,
            commit: { _ in throw Refused() }
        )
        #expect(
            CalendarMonthDayDropSupport.failureNotice(after: refused)
                == CadencePendingChangePersistence.editFailureNotice
        )
        #expect(CalendarMonthDayDropSupport.failureNotice(after: .applied) == nil)
        #expect(CalendarMonthDayDropSupport.failureNotice(after: .resolvedNothing) == nil)
    }

    /// [[T-6211]], the wiring: the cell writes the mapped notice into the grid's slot, and the grid
    /// draws it with the board's component, so a refused month drop is no longer silent.
    @Test func theMonthGridDrawsTheNoticeItsCellsReport() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let month = try read("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        let cell = try #require(CadenceSourceScan.declarationBody("struct MonthDayCell", in: month))
        #expect(cell.contains("@Binding var dropFailureNotice: String?"))
        let drop = try #require(CadenceSourceScan.declarationBody("private func handleTaskDrop(", in: cell))
        #expect(drop.contains("dropFailureNotice = CalendarMonthDayDropSupport.failureNotice(after: outcome)"))
        #expect(drop.contains("return outcome == .applied"))

        let components = try read("Cadence/macOS/Views/CalendarPageComponents.swift")
        let grid = try #require(CadenceSourceScan.declarationBody("struct MonthGridView", in: components))
        #expect(grid.contains("@State private var dropFailureNotice: String?"))
        #expect(grid.contains("CadenceInlineFailureNotice(text: dropFailureNotice)"))
        #expect(grid.contains("dropFailureNotice: $dropFailureNotice"))
        let weeks = try #require(CadenceSourceScan.declarationBody("struct MonthWeeksView", in: components))
        #expect(weeks.contains("dropFailureNotice: $dropFailureNotice"))
    }
}

/// T-5351, the click half. A day cell and its "+N more" row open that day, and the Mac has no Day
/// *mode* to switch to — `CadenceCalendarViewMode` is week / twoWeeks / month and the toolbar
/// picker offers only Week and Month — so "opens that day in Day view" is the jump the whole app
/// already means by opening a day: out of the grid, into the timeline, on that day's column.
@MainActor
struct CadenceCalendarMonthDayOpenTests {
    @Test func theDayCellAndItsOverflowRowBothOpenTheDay() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        let body = try #require(CadenceSourceScan.functionBody(named: "openDay", in: source))
        #expect(body.contains("calendarNavigationManager.open(dateKey: dateKey)"))

        // Two call sites: the cell itself, and the overflow strip that exists *because* the day
        // holds more than it can show.
        #expect(source.components(separatedBy: "onTapGesture { openDay() }").count - 1 == 2)
        #expect(source.contains(".dropDestination(for: String.self)"))
    }

    /// The jump must not pass the cell's own `date`, which is a start of day: that would hand the
    /// jump hour 0 and land every click on the top of the column rather than on the row the user
    /// is already looking at.
    @Test func theJumpDoesNotPassAStartOfDayAsItsHour() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        let body = try #require(CadenceSourceScan.functionBody(named: "openDay", in: source))
        #expect(!body.contains("open(date:"))
    }
}
#endif
