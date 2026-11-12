import Foundation
import SwiftData
import Testing
@testable import Cadence

// [[T-16654]]'s iOS half: the grouped headings on All Tasks and Inbox take a dragged ROW, not only
// the new-task `+`, and file it through `CadenceTaskHeaderDrop` -- the Mac's write. What is pinned
// is the wiring `iOSTaskCollectionSections` hands each heading, driven against an in-memory store
// and read back through a second context; the drag itself is a system drop and is a sighting.
#if os(iOS)

@Suite @MainActor
struct iOSTaskHeaderRowDropTests {
    private static let todayKey = "2026-11-11"

    @Test func aGroupedHeadingTakesADraggedRowAndFilesItThroughTheSharedWrite() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Garden")
        let resident = AppTask(title: "In Garden, high")
        resident.project = project
        resident.priority = .high
        let dragged = AppTask(title: "Dragged")
        context.insert(project)
        context.insert(resident)
        context.insert(dragged)
        try context.save()
        let page = [resident, dragged]

        let priorityGroups = CadenceTaskQuerySupport.displayGroups(from: page, mode: .byPriority, todayKey: Self.todayKey, contexts: [])
        let high = try #require(priorityGroups.first { $0.id == "priority-high" })
        let dropOnHigh = try #require(
            iOSTaskCollectionSections.headerTaskDrop(
                for: high,
                among: page,
                todayKey: Self.todayKey,
                modelContext: context,
                reconciler: .inert
            ),
            "the High heading takes no dragged row"
        )
        #expect(dropOnHigh(TaskDragPayload.string(for: dragged.id)) == .applied)

        let listGroups = CadenceTaskQuerySupport.displayGroups(from: page, mode: .byList, todayKey: Self.todayKey, contexts: [])
        let garden = try #require(listGroups.first { $0.tasks.contains { $0.id == resident.id } })
        let dropOnGarden = try #require(
            iOSTaskCollectionSections.headerTaskDrop(
                for: garden,
                among: page,
                todayKey: Self.todayKey,
                modelContext: context,
                reconciler: .inert
            )
        )
        #expect(dropOnGarden(TaskDragPayload.string(for: dragged.id)) == .applied)

        let read = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.id == dragged.id })
        #expect(read.priority == .high)
        #expect(read.project?.id == project.id)
    }

    /// The heading registers a row drop exactly when the shared key says it names something, so an
    /// Overdue or Leftover heading -- or the ungrouped "Tasks" one -- never accepts a row it then
    /// files nowhere. Counted across every grouping, so a wiring that answered for all, or none,
    /// is red.
    @Test func aHeadingTakesARowExactlyWhenItsBucketNamesAPlacement() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let overdue = AppTask(title: "Overdue")
        overdue.dueDate = "2026-11-01"
        let leftover = AppTask(title: "Leftover")
        leftover.scheduledDate = "2026-11-10"
        let loose = AppTask(title: "Loose")
        let page = [overdue, leftover, loose]
        page.forEach(context.insert)

        var taking = 0
        var refusing = 0
        for mode in TaskGroupingMode.allCases {
            for group in CadenceTaskQuerySupport.displayGroups(from: page, mode: mode, todayKey: Self.todayKey, contexts: []) {
                let drop = iOSTaskCollectionSections.headerTaskDrop(
                    for: group,
                    among: page,
                    todayKey: Self.todayKey,
                    modelContext: context,
                    reconciler: .inert
                )
                #expect((drop != nil) == (CadenceTaskHeaderDrop.dropKey(forDisplayGroup: group) != nil), "\(mode) \(group.id)")
                if drop == nil { refusing += 1 } else { taking += 1 }
            }
        }
        // None: Tasks (refuses). Date: Overdue, Leftover refuse; Unscheduled takes. Priority: one
        // None group takes. List: one Inbox group takes.
        #expect(refusing == 3, "expected Tasks, Overdue and Leftover to refuse a row, \(refusing) did")
        #expect(taking == 3, "expected Unscheduled, None and Inbox to take a row, \(taking) did")
    }
}
#endif
