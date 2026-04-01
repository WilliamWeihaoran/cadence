#if os(macOS)
import SwiftUI

enum HoveredTaskSource: Equatable {
    case list
    case kanban
    case timeline
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

    private init() {}

    func beginHovering(_ task: AppTask, source: HoveredTaskSource) {
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
        hoveredTask = nil
        hoveredSource = nil
        hoveredDateKind = nil
    }
}
#endif
