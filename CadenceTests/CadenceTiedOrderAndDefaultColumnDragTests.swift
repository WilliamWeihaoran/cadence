// Compiled for macOS only, like `CadenceRowReorderSequenceTests`: the column half reaches
// `KanbanBoardSupport`, a macOS-only type, and the source scans read the tree from the Mac host.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-18167]] and [[T-18168]]: what a drop edits is what the screen shows.**
///
/// T-18167: every row and card drop ordered the rows it was about to renumber by `order` alone, so
/// rows tied on `order` kept whatever sequence the caller handed in -- usually the raw relationship
/// -- and that arbitrary sequence was then written. The list draws ties by
/// `TaskOrdering.fallbackPrecedes`, so that is the sequence a drop must edit.
///
/// T-18168: Default is pinned first by every write of a list's columns, so a drag that moved it
/// (or put a column above it) was thrown away silently. iOS now keeps it first in the editor's
/// drafts and offers no move on its row; the Mac offers no drag on its header.
@MainActor
struct CadenceTiedOrderAndDefaultColumnDragTests {

    // MARK: - T-18167

    /// **Behavioural.** A and B tie on `order` (A older, so drawn first), C follows. The caller
    /// hands them in the relationship's sequence B, A, C. Dragging C onto A must give C, A, B --
    /// under the `order`-only sort it gave B, C, A: C not on top and A fallen to the bottom.
    @Test func adropOverTiedOrdersEditsTheDisplayedSequence() throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func task(_ title: String, order: Int, age: TimeInterval) -> AppTask {
            let task = AppTask(title: title)
            task.order = order
            task.createdAt = base.addingTimeInterval(age)
            modelContext.insert(task)
            return task
        }
        let a = task("A", order: 5, age: 0)
        let b = task("B", order: 5, age: 60)
        let c = task("C", order: 6, age: 120)
        try modelContext.save()

        #expect([b, a, c].sorted(by: TaskOrdering.fallbackPrecedes).map(\.title) == ["A", "B", "C"],
                "non-vacuity: the list draws A, B, C")

        let siblings = try #require(
            CadenceRowReorderSpan.ownListSiblings(moving: c.id, before: a.id, in: [b, a, c])
        )
        #expect(siblings.map(\.title) == ["C", "A", "B"])
        #expect(CadenceRowReorderSpan.movesTheSlice(moving: c.id, before: a.id, in: [b, a, c]))
    }

    /// **Source census.** The three kanban card drops order their column the same way; two are
    /// `private` members of SwiftUI views and the third needs a drag payload, so this reads them.
    @Test func everyCardDropOrdersItsColumnByTheFullTieBreak() throws {
        let span = try CadenceCommitSurfaceScan.scanned("Cadence/Shared/CadenceRowReorderSpan.swift")
        let sliceMove = try CadenceCommitSurfaceScan.declarationBody(named: "sliceMove", in: span)
        #expect(sliceMove.contains("scopeTasks.sorted(by: TaskOrdering.fallbackPrecedes)"))

        let sites: [(path: String, function: String, sort: String)] = [
            ("Cadence/Shared/CadenceKanbanCardDrop.swift", "drop", "columnTasks.sorted(by: TaskOrdering.fallbackPrecedes)"),
            ("Cadence/macOS/Views/KanbanSectionColumnView.swift", "moveTask", "tasks.sorted(by: TaskOrdering.fallbackPrecedes)"),
            ("Cadence/macOS/Views/KanbanListColumnView.swift", "moveTask", "unfrozenSortedTasks.sorted(by: TaskOrdering.fallbackPrecedes)"),
        ]
        for site in sites {
            let text = try CadenceCommitSurfaceScan.scanned(site.path)
            #expect(text.contains(site.sort), "\(site.path) no longer orders its column by `fallbackPrecedes`")
            #expect(!text.contains(".sorted { $0.order < $1.order }"), "\(site.path) ordered a drop by `order` alone again")
        }
    }

    // MARK: - T-18168

    private func drafts() -> [CadenceSectionDraft] {
        [
            CadenceSectionDraft.defaultColumnSeed(),
            CadenceSectionDraft(config: TaskSectionConfig(name: "Doing")),
            CadenceSectionDraft(config: TaskSectionConfig(name: "Done")),
        ]
    }

    /// **Behavioural.** A column dropped above Default lands just below it; Default dragged down
    /// stays first; an ordinary move is untouched.
    @Test func adraftsMoveKeepsDefaultFirst() {
        let start = drafts()
        #expect(start.first?.isDefaultColumn == true, "non-vacuity: the seed is the Default column")

        let aboveDefault = CadenceSectionEditingSupport.movingDrafts(start, fromOffsets: [2], toOffset: 0)
        #expect(aboveDefault.map(\.name) == ["Default", "Done", "Doing"])

        let defaultDown = CadenceSectionEditingSupport.movingDrafts(start, fromOffsets: [0], toOffset: 3)
        #expect(defaultDown.map(\.name) == ["Default", "Doing", "Done"])

        let ordinary = CadenceSectionEditingSupport.movingDrafts(start, fromOffsets: [1], toOffset: 3)
        #expect(ordinary.map(\.name) == ["Default", "Done", "Doing"])
    }

    /// **Behavioural.** The Mac board offers a header drag on every column but Default.
    @Test func theMacDefaultColumnOffersNoDrag() {
        #expect(!KanbanBoardSupport.isColumnDraggable(TaskSectionConfig(name: TaskSectionDefaults.defaultName)))
        #expect(KanbanBoardSupport.isColumnDraggable(TaskSectionConfig(name: "Doing")))
    }

    /// **Source census.** The iOS row is `moveDisabled` for Default and its move goes through the
    /// clamp; the Mac's only column `.onDrag` is the one gated on `isColumnDraggable`.
    @Test func bothEditorsWithholdTheDefaultDrag() throws {
        let editor = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSListEditorViews.swift")
        #expect(editor.contains(".moveDisabled(draft.isDefaultColumn)"))
        #expect(editor.contains("CadenceSectionEditingSupport.movingDrafts("))
        #expect(!editor.contains("sectionDrafts.move(fromOffsets:"), "the editor applies an unclamped move again")

        let board = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        #expect(board.contains("isDraggable: KanbanBoardSupport.isColumnDraggable(section)"))
        #expect(board.components(separatedBy: ".onDrag").count - 1 == 1, "a column header drag escaped the Default gate")
    }
}
#endif
