import SwiftData
import SwiftUI

/// **The row renumber, on both platforms ([[T-16682]]).** This was the body of the Mac's
/// `TasksPanelSupport.reorderTask`, `#if os(macOS)`, which still answers for every Mac caller and
/// keeps the whole argument for what a drag under a non-`order` sort rewrites (T-884), why the
/// renumber spans the list and not the slice (T-1175) and why it writes only the dragged row's own
/// list (T-1119). It moved here verbatim so iOS's list Tasks tab renumbers a row dropped on a
/// heading through the same rule rather than a copy of it (`ListTasksGroupDrop.dropOnHeader`).
///
/// - Returns: Whether the new order is in the store. `false` means every row is back where it
///   was, and the surface must show `CadenceOrderCommit.failureNotice`. A drop with nothing to
///   write answers `true`, because nothing failed.
enum CadenceTaskRowReorder {
    static func reorderTask(
        droppedID: UUID,
        targetID: UUID,
        scopeTasks: [AppTask],
        spanTasks: [AppTask],
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        guard let siblings = CadenceRowReorderSpan.ownListSiblings(
            moving: droppedID,
            before: targetID,
            in: scopeTasks
        ), let dropped = siblings.first(where: { $0.id == droppedID }) else { return true }
        let sequence = CadenceRowReorderSpan.wholeSequence(
            resequencing: siblings,
            within: spanTasks,
            ofList: CadenceTaskQuerySupport.listGroupKey(for: dropped)
        )
        return withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            CadenceOrderCommit.commit(
                sequence,
                readOrder: { $0.order },
                writeOrder: { $0.order = $1 },
                in: modelContext,
                commit: commit
            )
        }
    }
}
