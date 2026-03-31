#if os(macOS)
import SwiftUI

enum HoveredTaskSource {
    case list
    case kanban
    case timeline
}

@Observable
final class HoveredTaskManager {
    static let shared = HoveredTaskManager()

    var hoveredTask: AppTask? = nil
    var hoveredSource: HoveredTaskSource? = nil

    private init() {}

    func beginHovering(_ task: AppTask, source: HoveredTaskSource) {
        hoveredTask = task
        hoveredSource = source
    }

    func endHovering(_ task: AppTask) {
        guard hoveredTask?.id == task.id else { return }
        hoveredTask = nil
        hoveredSource = nil
    }
}
#endif
