#if os(macOS)
import SwiftUI

enum HoveredTaskSource: Equatable {
    case list
    case kanban
    case timeline
    case note
}

enum HoveredTaskDateKind: Equatable {
    case doDate
    case dueDate
}

@Observable
final class HoveredTaskManager {
    static let shared = HoveredTaskManager()

    var hoveredTask: AppTask? = nil
    var hoveredSource: HoveredTaskSource? = nil
    var hoveredDateKind: HoveredTaskDateKind? = nil
    private var pendingClearWorkItem: DispatchWorkItem? = nil

    private init() {}

    func beginHovering(_ task: AppTask, source: HoveredTaskSource) {
        guard !TaskCreationManager.shared.isPresented else {
            clear()
            return
        }
        pendingClearWorkItem?.cancel()
        pendingClearWorkItem = nil
        if hoveredTask?.id == task.id, hoveredSource == source { return }
        hoveredTask = task
        hoveredSource = source
    }

    func beginHoveringDate(_ kind: HoveredTaskDateKind, for task: AppTask) {
        guard !TaskCreationManager.shared.isPresented else {
            clear()
            return
        }
        guard hoveredTask?.id == task.id else { return }
        if hoveredDateKind == kind { return }
        hoveredDateKind = kind
    }

    func endHoveringDate(for task: AppTask) {
        guard hoveredTask?.id == task.id else { return }
        guard hoveredDateKind != nil else { return }
        hoveredDateKind = nil
    }

    /// Schedules the debounced clear for `task`, but only while `task` is the hovered one.
    ///
    /// The identity check is deliberately *here* and nowhere else. It used to be in both places —
    /// once as this guard and again inside the work item — and the inner copy made this one
    /// unobservable: with the work item re-checking identity, deleting this line changed no
    /// behaviour any test could see, so the guard was free to be removed by a tidy-up. One guard,
    /// checked before any state is touched, is the whole rule. The work item does not need to
    /// re-check, because every path that replaces `hoveredTask` (`beginHovering`) or nils it
    /// (`clear()`) cancels the pending item itself.
    func endHovering(_ task: AppTask) {
        guard hoveredTask?.id == task.id else { return }
        pendingClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoveredTask = nil
            self.hoveredSource = nil
            self.hoveredDateKind = nil
            self.pendingClearWorkItem = nil
        }
        pendingClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    func clear() {
        pendingClearWorkItem?.cancel()
        pendingClearWorkItem = nil
        hoveredTask = nil
        hoveredSource = nil
        hoveredDateKind = nil
    }
}
#endif
