import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

/// **T-16201** — the iOS calendar day inspector's **Timed** section listed its tasks in priority
/// order, so a high-priority 3 PM task sat above a 9 AM one under a heading named for the time of
/// day.
///
/// The inspector is `#if os(iOS)` and invisible to this macOS-built bundle, so the behaviour is
/// pinned in two halves: the shared query the section now reads puts the inspector's own input back
/// in start order, and the inspector's `timedTasks` is that query and nothing else.
@MainActor
@Suite struct CadenceCalendarDayInspectorTimedOrderTests {
    private static let dayKey = "2026-06-11"

    private func dayTasks(in context: ModelContext) -> [AppTask] {
        func add(_ title: String, startMin: Int, priority: TaskPriority) -> AppTask {
            let task = AppTask(title: title)
            task.scheduledDate = Self.dayKey
            task.scheduledStartMin = startMin
            task.estimatedMinutes = 30
            task.priority = priority
            context.insert(task)
            return task
        }
        let afternoon = add("Afternoon", startMin: 15 * 60, priority: .high)
        let morning = add("Morning", startMin: 9 * 60, priority: .none)
        let untimed = add("Untimed", startMin: -1, priority: .medium)
        let finished = add("Finished", startMin: 12 * 60, priority: .low)
        finished.status = .done
        return [afternoon, morning, untimed, finished]
    }

    @Test func theTimedSectionReadsInStartOrderWhatTheInspectorIsHandedInPriorityOrder() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let all = dayTasks(in: context)

        // What `iOSCalendarView` hands the inspector as `tasks`: priority order, so the premise of
        // the defect holds — the 3 PM task is ahead of the 9 AM one on the way in.
        let handed = CadenceScheduleSupport.calendarDayTasks(on: Self.dayKey, from: all)
        let handedTitles = handed.map(\.title)
        let afternoonIndex = try #require(handedTitles.firstIndex(of: "Afternoon"))
        let morningIndex = try #require(handedTitles.firstIndex(of: "Morning"))
        #expect(afternoonIndex < morningIndex, "non-vacuity: the input is no longer priority-ordered")

        // What the section draws: timed only, the done task kept, in start-minute order.
        let timed = CadenceScheduleSupport.scheduledTasks(on: Self.dayKey, from: handed, includeCompleted: true)
        #expect(timed.map(\.title) == ["Morning", "Finished", "Afternoon"])
    }

    @Test func theInspectorsTimedSectionIsTheSharedStartOrderedQuery() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarInspectorView.swift"))
        #expect(source.contains("struct iOSCalendarDayInspector: View"), "non-vacuity: wrong file read")
        let body = try #require(CadenceSourceScan.declarationBody("private var timedTasks: [AppTask]", in: source))
        #expect(body.contains("CadenceScheduleSupport.scheduledTasks(on: dayKey, from: tasks, includeCompleted: true)"))
        #expect(!body.contains(".filter"), "the Timed section went back to filtering the priority-ordered input")
    }
    // MARK: - [[T-16821]]: a Timed row states its slot

    /// The Timed rows drew only a ring, a title and a list chip -- the day pill is suppressed
    /// because the pane names the day -- so a section ordered by start time never said the time.
    /// The slot reads in the event rows' range shape; an untimed task has none to state.
    @Test func aTimedTaskStatesItsSlotAndAnUntimedOneStatesNothing() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let tasks = dayTasks(in: context)
        let morning = try #require(tasks.first { $0.title == "Morning" })
        let untimed = try #require(tasks.first { $0.title == "Untimed" })

        #expect(
            CadenceTaskPresentationSupport.scheduledTimeRangeLabel(for: morning)
                == TimeFormatters.timeRange(startMin: 9 * 60, endMin: 9 * 60 + 30)
        )
        #expect(CadenceTaskPresentationSupport.scheduledTimeRangeLabel(for: untimed) == nil)
    }

    @Test func theTimedSectionAndTheAgendaAskTheRowToStateTheSlot() throws {
        let inspector = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarInspectorView.swift"))
        #expect(inspector.contains("struct iOSCalendarDayInspector: View"), "non-vacuity: wrong file read")
        #expect(inspector.contains(
            "iOSTaskRow(task: task, dayAlreadyStatedBySurface: dayKey, statesScheduledTime: true, todayKey: todayKey)"
        ), "the Timed section's rows no longer state their slot")
        // Only the Timed section: the Do Date and Due rows are untimed or there for a deadline.
        #expect(inspector.components(separatedBy: "statesScheduledTime: true").count - 1 == 1)

        let agenda = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthAgendaViews.swift"))
        #expect(agenda.contains("statesScheduledTime: true"), "the compact agenda's task rows no longer state their slot")

        let row = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        let badges = try #require(CadenceSourceScan.declarationBody("private var taskBadgeContent: some View", in: row))
        #expect(badges.contains(
            "if statesScheduledTime, let slot = CadenceTaskPresentationSupport.scheduledTimeRangeLabel(for: task)"
        ), "the row no longer draws the slot it is asked for")
        #expect(row.contains("var statesScheduledTime: Bool = false"), "the slot is no longer opt-in")
    }

    // MARK: - [[T-18051]]: the Due heading's colour

    /// The Due section lists the deadlines of whatever day is inspected, so its eyebrow is red only
    /// for a past day that still holds open work; a today or later day, or a past day whose
    /// deadlines are all settled, reads in the resting due amber. *Failing-first:* the constant
    /// `Theme.red` the section shipped with fails the today, future and all-settled legs.
    @Test func theDueHeadingIsRedOnlyForAPastDayStillHoldingOpenWork() throws {
        let context = ModelContext(try CadenceTestStore.container())
        func task(_ status: TaskStatus) -> AppTask {
            let task = AppTask(title: "Due")
            task.dueDate = "2026-06-10"
            task.status = status
            context.insert(task)
            return task
        }
        let open = task(.todo)
        let done = task(.done)
        let cancelled = task(.cancelled)
        let today = Self.dayKey
        func tint(_ day: String, _ tasks: [AppTask]) -> Color {
            CadenceDueUrgency.dueSectionTint(dayKey: day, tasks: tasks, todayKey: today)
        }

        #expect(tint("2026-06-10", [done, open]) == Theme.red, "a past day with open work is not red")
        #expect(tint(today, [open]) == Theme.amber, "today's Due heading is not amber")
        #expect(tint("2026-06-18", [open]) == Theme.amber, "a later day's Due heading is not amber")
        #expect(tint("2026-06-10", [done, cancelled]) == Theme.amber, "a past day whose deadlines are settled is still red")
    }

    @Test func theInspectorsDueSectionAsksTheSharedTint() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarInspectorView.swift"))
        #expect(source.contains("struct iOSCalendarDayInspector: View"), "non-vacuity: wrong file read")
        #expect(source.contains("CadenceDueUrgency.dueSectionTint(dayKey: dayKey, tasks: dueOnlyTasks, todayKey: todayKey)"))
        #expect(!source.contains("title: \"Due\", color: Theme.red"), "the Due heading went back to a fixed red")
    }
}
