#if os(macOS)
import Foundation
import Observation

/// **[[T-5300]] — the one-slot inbox for "open this task's inspector", for a caller with no row.**
///
/// Every other macOS surface that opens `TaskDetailPopover` owns the row the popover points at —
/// a task row, a Kanban card, a timeline block, a `[[task:…]]` link. Cmd+K has no row: the result
/// it picked may be in a list that is not on screen, and with "include completed" on it may be
/// inside a Completed group that is collapsed on appear. So the request travels as an id and
/// `TaskInspectorLayerView` presents it from a fixed anchor over the shell.
///
/// Same shape as `GlobalSearchManager` and `CadenceDeepLinkManager`: a distant surface drops one
/// request in, the shell takes it out. Not merged into `ListNavigationManager.Request`, which is
/// about which *page* is shown — the owner's decision was explicitly that Cmd+K opens the task
/// rather than revealing it in its list, so the inspector does not depend on the page arriving.
@Observable
final class TaskInspectorPresentationManager {
    static let shared = TaskInspectorPresentationManager()

    /// The task whose inspector should be up, or `nil`.
    private(set) var requestedTaskID: UUID?

    private init() {}

    func present(taskID: UUID) {
        requestedTaskID = taskID
    }

    func dismiss() {
        requestedTaskID = nil
    }
}
#endif
