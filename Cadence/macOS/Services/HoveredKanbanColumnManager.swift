#if os(macOS)
import SwiftUI

@Observable
final class HoveredKanbanColumnManager {
    static let shared = HoveredKanbanColumnManager()

    private var hoveredID: AnyHashable?
    private var createTaskAction: (() -> Void)?

    private init() {}

    func beginHovering(id: AnyHashable, onCreateTask: @escaping () -> Void) {
        hoveredID = id
        createTaskAction = onCreateTask
    }

    func endHovering(id: AnyHashable) {
        guard hoveredID == id else { return }
        hoveredID = nil
        createTaskAction = nil
    }

    @discardableResult
    func triggerCreateTask() -> Bool {
        guard let createTaskAction else { return false }
        createTaskAction()
        return true
    }
}
#endif
