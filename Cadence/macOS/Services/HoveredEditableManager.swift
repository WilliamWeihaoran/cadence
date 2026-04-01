#if os(macOS)
import SwiftUI

@Observable
final class HoveredEditableManager {
    static let shared = HoveredEditableManager()

    private var hoveredID: AnyHashable?
    private var editAction: (() -> Void)?
    private var deleteAction: (() -> Void)?

    private init() {}

    func beginHovering(id: AnyHashable, onEdit: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        if hoveredID == id { return }
        hoveredID = id
        editAction = onEdit
        deleteAction = onDelete
    }

    func endHovering(id: AnyHashable) {
        guard hoveredID == id else { return }
        hoveredID = nil
        editAction = nil
        deleteAction = nil
    }

    @discardableResult
    func triggerEdit() -> Bool {
        guard let editAction else { return false }
        editAction()
        return true
    }

    @discardableResult
    func triggerDelete() -> Bool {
        guard let deleteAction else { return false }
        deleteAction()
        return true
    }
}
#endif
