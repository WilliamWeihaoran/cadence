import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-16341]] — a checklist reads in one order on every surface, even where two subtasks share
/// an `order`.**
///
/// Ties are in real stores. From 2026-03-30 to `aaa0064d` (2026-08-29) both inspectors numbered a
/// new subtask `order = (task.subtasks ?? []).count`, so deleting any row and adding one gave the
/// new row the number the old last row still held; the duplicate-merge repair re-points a copy's
/// subtasks onto the survivor with the orders they had; and two devices appending offline both
/// take `max + 1`. `task.subtasks` is an unordered to-many, so the array's arrangement is whatever
/// the store hands back.
///
/// The task rows, the Mac inspector and the iOS task sheet sorted on `order` alone and so listed a
/// tied pair in that arbitrary arrangement, while the note task-embed card broke the tie on title
/// and MCP on title then id. These pin the one shared comparator, `TaskOrdering.subtaskPrecedes`.
@MainActor
struct CadenceSubtaskOrderTieTests {
    private func makeTask(arrangement: [(String, Int)]) throws -> (ModelContainer, AppTask) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let task = AppTask(title: "Pack")
        context.insert(task)
        var rows: [Subtask] = []
        for (title, order) in arrangement {
            let subtask = Subtask(title: title)
            subtask.order = order
            subtask.parentTask = task
            context.insert(subtask)
            rows.append(subtask)
        }
        // Assigned whole, in the given arrangement: this array is the one the store's fetch order
        // decides in production.
        task.subtasks = rows
        return (container, task)
    }

    /// The row list (both platforms' rows and boards read `listedSubtasks`) does not depend on
    /// the arrangement the relationship comes back in.
    @Test func aTiedPairListsInTheSameOrderWhateverTheArrayArrangement() throws {
        let (c1, zFirst) = try makeTask(arrangement: [("Zip bag", 1), ("Adapter", 1), ("Passport", 0)])
        let (c2, aFirst) = try makeTask(arrangement: [("Adapter", 1), ("Passport", 0), ("Zip bag", 1)])
        _ = (c1, c2)

        let one = CadenceTaskPresentationSupport.allUnfinishedSubtasks(for: zFirst).map(\.title)
        let two = CadenceTaskPresentationSupport.allUnfinishedSubtasks(for: aFirst).map(\.title)
        #expect(one == ["Passport", "Adapter", "Zip bag"], "order first, then title on a tie")
        #expect(one == two, "the arrangement of `task.subtasks` must not decide the listed order")
    }

    /// The row and the note embed card of the same task agree on a tie.
    @Test func theRowAndTheNoteEmbedCardAgreeOnATiedPair() throws {
        let (container, task) = try makeTask(arrangement: [("Zip bag", 0), ("Adapter", 0)])
        _ = container

        let row = CadenceTaskPresentationSupport.allUnfinishedSubtasks(for: task).map(\.title)
        let embed = MarkdownTaskEmbedRenderInfo.task(task).subtasks.map(\.title)
        #expect(row == ["Adapter", "Zip bag"])
        #expect(embed == row)
    }

    /// Total: a pair tied on order and title still has one answer, the id's, in both directions.
    @Test func theComparatorIsTotalOnATiedOrderAndTitle() throws {
        let (container, task) = try makeTask(arrangement: [("Adapter", 0), ("adapter", 0)])
        _ = container
        let rows = task.subtasks ?? []
        #expect(rows.count == 2)
        let (a, b) = (rows[0], rows[1])
        #expect(TaskOrdering.subtaskPrecedes(a, b) != TaskOrdering.subtaskPrecedes(b, a))
        #expect(!TaskOrdering.subtaskPrecedes(a, a))
        let byID = a.id.uuidString < b.id.uuidString
        #expect(TaskOrdering.subtaskPrecedes(a, b) == byID)
        #expect(rows.subtaskSorted().map(\.id) == rows.reversed().subtaskSorted().map(\.id))
    }

    /// Wiring: the two inspectors and the copy paths sort through the shared comparator, and the
    /// order-only closure is gone from each.
    @Test func everySubtaskListSortsThroughTheSharedComparator() throws {
        let sites: [(path: String, declaration: String)] = [
            ("Cadence/iOS/iOSTaskDetailSheet.swift", "private var sortedSubtasks: [Subtask]"),
            ("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift", "struct TaskDetailSubtasksSection: View"),
            ("Cadence/Shared/CadenceTaskPresentationSupport.swift", "static func allUnfinishedSubtasks(for task: AppTask) -> [Subtask]"),
            ("Cadence/Services/MarkdownTaskEmbedSupport.swift", "static func task(_ task: AppTask) -> MarkdownTaskEmbedRenderInfo")
        ]
        for site in sites {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(site.path))
            let body = try #require(
                CadenceSourceScan.declarationBody(site.declaration, in: source),
                "\(site.path): declaration not found"
            )
            #expect(body.contains("subtaskSorted()"), "\(site.path) sorts through the shared comparator")
            #expect(!body.contains("$0.order < $1.order"), "\(site.path) still sorts on order alone")
        }

        for path in ["Cadence/Shared/CadenceTaskRecurrenceWorkflowSupport.swift", "Cadence/Shared/CadenceTaskMutationSupport.swift"] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("subtaskSorted()"), "\(path) copies the checklist in the shared order")
            #expect(!source.contains(".sorted { $0.order < $1.order }"), "\(path) still sorts subtasks on order alone")
        }
    }
}
