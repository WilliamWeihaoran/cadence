#if os(macOS)
import SwiftUI

@Observable
final class HoveredEditableManager {
    static let shared = HoveredEditableManager()

    private var hoveredID: AnyHashable?
    private var editAction: (() -> Void)?

    private init() {}

    func beginHovering(id: AnyHashable, onEdit: @escaping () -> Void) {
        hoveredID = id
        editAction = onEdit
    }

    func endHovering(id: AnyHashable) {
        guard hoveredID == id else { return }
        hoveredID = nil
        editAction = nil
    }

    @discardableResult
    func triggerEdit() -> Bool {
        guard let editAction else { return false }
        editAction()
        return true
    }
}
#endif
