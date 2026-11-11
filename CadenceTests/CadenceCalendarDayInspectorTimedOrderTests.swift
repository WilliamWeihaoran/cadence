import Foundation
import SwiftData
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
}
