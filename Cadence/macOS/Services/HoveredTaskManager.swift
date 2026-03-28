#if os(macOS)
import SwiftUI

@Observable
final class HoveredTaskManager {
    static let shared = HoveredTaskManager()

    var hoveredTask: AppTask? = nil

    private init() {}

    func beginHovering(_ task: AppTask) {
        hoveredTask = task
    }

    func endHovering(_ task: AppTask) {
        guard hoveredTask?.id == task.id else { return }
        hoveredTask = nil
    }
}
#endif
