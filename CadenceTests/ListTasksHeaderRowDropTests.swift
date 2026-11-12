import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-16682]] -- a list's Tasks tab heading re-files a dropped row on iOS/iPadOS as it does on
/// the Mac.** iOS's headings are `CadenceTaskDisplayGroup`s built by
/// `ListDetailSortControls.taskGroups` (the groups `iOSListDetailView.sectionStack` draws), and
/// their row drop is `ListTasksGroupDrop.dropOnHeader`, the Mac header's own steps moved to
/// `Shared/`. Driven here against an in-memory store and read back through a second context, on
/// whichever platform runs the suite; the drag gesture itself is a sighting ([[T-16911]]).
@MainActor
struct ListTasksHeaderRowDropTests {
    private struct Refused: Error {}

    private static let todayKey = "2026-11-11"

    private func store() throws -> (ModelContainer, ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (container, ModelContext(container))
    }

    /// A list with sections Documents and Later; `titles` filed in order, `order` = index.
    private func seeded(
        _ titles: [(String, String)],
        sections: [String] = ["Documents", "Later"],
        in modelContext: ModelContext
    ) throws -> [AppTask] {
        let project = Project(name: "Website")
        project.sectionNames = sections
        modelContext.insert(project)
        let tasks = titles.enumerated().map { index, pair -> AppTask in
            let task = AppTask(title: pair.0)
            task.project = project
            task.sectionName = pair.1
            task.order = index
            modelContext.insert(task)
            return task
        }
        try modelContext.save()
        return tasks
    }

    /// The touch page's groups, exactly as `iOSListDetailView.sectionGroups` asks for them.
    private func groups(
        _ tasks: [AppTask],
        grouping: TaskGroupingMode,
        sections: [String] = ["Documents", "Later"]
    ) -> [CadenceTaskDisplayGroup] {
        ListDetailSortControls.taskGroups(
            from: CadenceTaskQuerySupport.openTasks(from: tasks),
            grouping: grouping,
            sectionNames: sections,
            sectionConfigs: [],
            pageIsEmpty: tasks.isEmpty,
            todayKey: Self.todayKey
        )
    }

    private func drop(
        _ task: AppTask,
        on group: CadenceTaskDisplayGroup,
        grouping: TaskGroupingMode,
        among tasks: [AppTask],
        in modelContext: ModelContext,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) -> ListTasksGroupDrop.HeaderDropOutcome {
        ListTasksGroupDrop.dropOnHeader(
            payload: TaskDragPayload.string(for: task.id),
            onto: group,
            groupingMode: grouping,
            listTasks: tasks,
            todayKey: Self.todayKey,
            modelContext: modelContext,
            sortKeyOrder: { _, _ in .tie },
            commit: commit
        )
    }

    private func stored(_ id: UUID, in container: ModelContainer) throws -> AppTask? {
        try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.id == id }
    }

    /// A row from Documents let go over the Later heading is filed under Later AND renumbered to
    /// the top of it -- the Mac's refile-then-reorder through its first row.
    @Test func aRowDroppedOnAnotherSectionsHeadingJoinsItAtItsTop() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Ship", "Later"), ("Launch", "Later"), ("Spec", "Documents")], in: modelContext)
        let later = try #require(groups(tasks, grouping: .byList).first { $0.title == "Later" })
        #expect(ListTasksGroupDrop.takesDroppedRow(later))

        #expect(drop(tasks[2], on: later, grouping: .byList, among: tasks, in: modelContext) == .applied(notice: nil))

        let spec = try #require(try stored(tasks[2].id, in: container))
        let ship = try #require(try stored(tasks[0].id, in: container))
        let launch = try #require(try stored(tasks[1].id, in: container))
        #expect(spec.resolvedSectionName == "Later")
        #expect(spec.order < ship.order && ship.order < launch.order,
                "the row joined Later but not at its top: \([spec.order, ship.order, launch.order])")
    }

    /// An EMPTY section's heading files the row with no renumber ([[T-15821]]'s half).
    @Test func aRowDroppedOnAnEmptySectionsHeadingIsFiledThere() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Spec", "Documents"), ("Ship", "Documents")], in: modelContext)
        let later = try #require(groups(tasks, grouping: .byList).first { $0.title == "Later" })
        #expect(later.tasks.isEmpty)
        #expect(ListTasksGroupDrop.takesDroppedRow(later))

        #expect(drop(tasks[1], on: later, grouping: .byList, among: tasks, in: modelContext) == .applied(notice: nil))
        #expect(try stored(tasks[1].id, in: container)?.resolvedSectionName == "Later")
        #expect(try stored(tasks[1].id, in: container)?.order == 1, "an empty section's heading renumbered")
        #expect(try stored(tasks[0].id, in: container)?.resolvedSectionName == "Documents")
    }

    /// By Priority the heading's priority is written, as on the Mac.
    @Test func aRowDroppedOnAPriorityHeadingTakesThatPriority() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Urgent", "Documents"), ("Loose", "Documents")], in: modelContext)
        tasks[0].priority = .high
        try modelContext.save()
        let high = try #require(groups(tasks, grouping: .byPriority).first { $0.id == "priority-high" })

        #expect(drop(tasks[1], on: high, grouping: .byPriority, among: tasks, in: modelContext) == .applied(notice: nil))
        #expect(try stored(tasks[1].id, in: container)?.priority == .high)
    }

    /// A refused commit is said, and leaves the row where it was.
    @Test func aRefusedRefileIsReportedAndWritesNothing() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Ship", "Later"), ("Spec", "Documents")], in: modelContext)
        let later = try #require(groups(tasks, grouping: .byList).first { $0.title == "Later" })

        #expect(
            drop(tasks[1], on: later, grouping: .byList, among: tasks, in: modelContext, commit: { _ in throw Refused() })
                == .refused(notice: CadencePendingChangePersistence.editFailureNotice)
        )
        #expect(try stored(tasks[1].id, in: container)?.resolvedSectionName == "Documents")
    }

    /// A payload the list does not hold, or a heading's own row, resolves to nothing.
    @Test func aRowTheHeadingCannotTakeWritesNothing() throws {
        let (container, modelContext) = try store()
        let tasks = try seeded([("Ship", "Later"), ("Spec", "Documents")], in: modelContext)
        let later = try #require(groups(tasks, grouping: .byList).first { $0.title == "Later" })
        let stranger = AppTask(title: "Elsewhere")
        modelContext.insert(stranger)
        try modelContext.save()

        #expect(drop(stranger, on: later, grouping: .byList, among: tasks, in: modelContext) == .resolvedNothing)
        #expect(drop(tasks[0], on: later, grouping: .byList, among: tasks, in: modelContext) == .resolvedNothing)
        #expect(try stored(stranger.id, in: container)?.sectionName != "Later")
    }

    /// Which headings register a row destination at all: every section and priority group, the
    /// three date buckets a task can be moved into, and nothing else -- counted across every
    /// grouping, so a predicate that answered for all, or none, is red.
    @Test func aHeadingTakesARowExactlyWhenItNamesAPlacement() throws {
        let (_, modelContext) = try store()
        let tasks = try seeded([("Late", "Documents"), ("Today", "Documents"), ("Loose", "Later")], in: modelContext)
        tasks[0].dueDate = "2026-11-01"
        tasks[1].scheduledDate = Self.todayKey
        tasks[1].priority = .high
        try modelContext.save()

        var taking: [String] = []
        var refusing: [String] = []
        for mode in TaskGroupingMode.allCases {
            for group in groups(tasks, grouping: mode) {
                if ListTasksGroupDrop.takesDroppedRow(group) { taking.append(group.id) } else { refusing.append(group.id) }
            }
        }
        #expect(refusing.contains("all"), "the ungrouped Tasks heading takes a row it files nowhere")
        #expect(refusing.contains("overdue"), "Overdue takes a row, and no assignment makes a task late")
        #expect(taking.contains("do-today"))
        #expect(taking.contains("unscheduled"))
        #expect(taking.contains { $0.hasPrefix("section-") })
        #expect(taking.contains("priority-high"))
    }

    /// The iOS page's call site: every heading in `sectionStack` is handed this drop.
    @Test func theIOSListTasksTabHandsEachHeadingTheSharedDrop() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSListDetailView.swift")
        #expect(source.contains("onDropTaskPayload: headingRowDrop(for: group)"),
                "the list Tasks tab headings take only the new-task +")
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "headingRowDrop", in: source)
        #expect(body.contains("guard ListTasksGroupDrop.takesDroppedRow(group) else { return nil }"))
        #expect(body.contains("ListTasksGroupDrop.dropOnHeader("))
        #expect(body.contains("listTasks: filteredTasks"), "the renumber spans less than the list")
    }
}
