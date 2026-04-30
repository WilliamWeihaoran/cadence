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
        pendingClearWorkItem?.cancel()
        pendingClearWorkItem = nil
        if hoveredTask?.id == task.id, hoveredSource == source { return }
        hoveredTask = task
        hoveredSource = source
    }

    func beginHoveringDate(_ kind: HoveredTaskDateKind, for task: AppTask) {
        guard hoveredTask?.id == task.id else { return }
        if hoveredDateKind == kind { return }
        hoveredDateKind = kind
    }

    func endHoveringDate(for task: AppTask) {
        guard hoveredTask?.id == task.id else { return }
        guard hoveredDateKind != nil else { return }
        hoveredDateKind = nil
    }

    func endHovering(_ task: AppTask) {
        guard hoveredTask?.id == task.id else { return }
        pendingClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.hoveredTask?.id == task.id else { return }
            self.hoveredTask = nil
            self.hoveredSource = nil
            self.hoveredDateKind = nil
            self.pendingClearWorkItem = nil
        }
        pendingClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }
}
#endif
