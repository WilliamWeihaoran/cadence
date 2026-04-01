#if os(macOS)
import SwiftUI
import Observation

@MainActor
@Observable
final class HoveredSectionManager {
    struct Target {
        let id: UUID
        let onToggleComplete: () -> Void
    }

    static let shared = HoveredSectionManager()

    private(set) var target: Target?

    private init() {}

    func beginHovering(id: UUID, onToggleComplete: @escaping () -> Void) {
        if target?.id == id { return }
        target = Target(id: id, onToggleComplete: onToggleComplete)
    }

    func endHovering(id: UUID) {
        guard target?.id == id else { return }
        target = nil
    }

    @discardableResult
    func triggerToggleComplete() -> Bool {
        guard let target else { return false }
        target.onToggleComplete()
        return true
    }
}
#endif
