#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-16652]] — a Leftover row dropped on a By Date "Scheduled" header moved nowhere.**
///
/// `CadenceTaskHeaderDrop.apply(.pushToScheduled)` wrote tomorrow only for a task with no do date or a
/// do date of today. A do date already gone by fell through both, so the drop on All Tasks' or a
/// list Tasks tab's Scheduled header answered `.applied`, wrote nothing, and the row stayed under
/// Leftover — the group [[T-12323]] gave those rows, after this guard was written. The fixture is
/// a fixed day rather than the clock, so "tomorrow" is a key the test can name.
@MainActor
struct TasksListScheduledDropTests {

    private static let todayKey = "2026-11-11"

    @Test("Scheduled's drop writes tomorrow for no date, today and a past date, and leaves a later date alone")
    func pushedKeyCoversEveryDoDateThatIsNotAlreadyScheduled() {
        let push = { TasksPanelSupport.pushedToScheduledDateKey(from: $0, todayKey: Self.todayKey) }

        #expect(push("") == "2026-11-12")
        #expect(push(Self.todayKey) == "2026-11-12")
        #expect(push("2026-11-10") == "2026-11-12", "a Leftover do date must move forward, not stay")
        #expect(push("2026-10-01") == "2026-11-12")
        #expect(push("2026-11-12") == nil)
        #expect(push("2026-12-25") == nil)
        // Tomorrow is counted from the page's day, across a month end.
        #expect(TasksPanelSupport.pushedToScheduledDateKey(from: "", todayKey: "2026-11-30") == "2026-12-01")
    }

    @Test("A Leftover row dropped on the Scheduled header leaves Leftover and is drawn under Scheduled")
    func aLeftoverRowDroppedOnScheduledMovesIntoScheduled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let leftover = AppTask(title: "Planned yesterday")
        leftover.scheduledDate = "2026-11-10"
        let later = AppTask(title: "Planned for Christmas")
        later.scheduledDate = "2026-12-25"
        modelContext.insert(leftover)
        modelContext.insert(later)
        try modelContext.save()

        let groupsBefore = CadenceTaskQuerySupport.dateDisplayGroups(from: [leftover, later], todayKey: Self.todayKey)
        #expect(groupsBefore.first { $0.id == "past-do" }?.tasks.map(\.id) == [leftover.id])

        guard let scheduledKey = TasksListView.dateDropKey(forGroupID: "scheduled") else {
            Issue.record("the Scheduled header hands out no drop key")
            return
        }
        for task in [leftover, later] {
            let outcome = TasksPanelSupport.assignTask(
                task,
                for: scheduledKey,
                todayKey: Self.todayKey,
                areas: [],
                projects: [],
                modelContext: modelContext,
                reconciler: .inert
            )
            #expect(outcome == .applied)
        }

        #expect(leftover.scheduledDate == "2026-11-12")
        #expect(later.scheduledDate == "2026-12-25", "a do date already after today is the assignment")

        let groupsAfter = CadenceTaskQuerySupport.dateDisplayGroups(from: [leftover, later], todayKey: Self.todayKey)
        #expect(groupsAfter.contains { $0.id == "past-do" } == false)
        #expect(Set(groupsAfter.first { $0.id == "scheduled" }?.tasks.map(\.id) ?? []) == [leftover.id, later.id])
    }
}
#endif
