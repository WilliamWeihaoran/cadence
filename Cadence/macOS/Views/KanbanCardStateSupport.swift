#if os(macOS)
import SwiftUI
import SwiftData

enum KanbanCardStateSupport {
    static func openDatePicker(
        dateKey: String,
        setSelection: (Date) -> Void,
        setViewMonth: (Date) -> Void,
        setPresented: (Bool) -> Void
    ) {
        let resolved = dateKey.isEmpty ? Date() : (DateFormatters.date(from: dateKey) ?? Date())
        setSelection(resolved)
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        setViewMonth(Calendar.current.date(from: comps) ?? resolved)
        setPresented(true)
    }

    static func syncInteractiveHoverState(
        task: AppTask,
        isPointerOverCard: Bool,
        isPresentingInlinePopover: Bool,
        setHovered: (Bool) -> Void,
        hoveredTaskManager: HoveredTaskManager,
        hoveredEditableManager: HoveredEditableManager,
        deleteConfirmationManager: DeleteConfirmationManager,
        modelContext: ModelContext,
        showTaskInspector: Binding<Bool>
    ) {
        let isActive = isPointerOverCard || isPresentingInlinePopover
        setHovered(isActive)
        if isActive {
            hoveredTaskManager.beginHovering(task, source: .kanban)
            hoveredEditableManager.beginHovering(id: editableID(for: task)) {
                showTaskInspector.wrappedValue = true
            } onDelete: {
                deleteConfirmationManager.presentTaskDelete(task, in: modelContext) {
                    if hoveredTaskManager.hoveredTask?.id == task.id {
                        hoveredTaskManager.hoveredTask = nil
                    }
                    hoveredEditableManager.endHovering(id: editableID(for: task))
                }
            }
        } else {
            endHoverRegistration(
                task: task,
                hoveredTaskManager: hoveredTaskManager,
                hoveredEditableManager: hoveredEditableManager
            )
        }
    }

    /// Namespaced per surface so a task visible on two surfaces at once can't unregister
    /// the other's entry.
    static func editableID(for task: AppTask) -> String {
        "kanban-task-\(task.id.uuidString)"
    }

    /// Drops the card's hovered-task/hovered-editable entries. Both managers' `endHovering`
    /// are identity-guarded, so calling this after the hover has already moved to another
    /// card is a no-op rather than a stomp.
    static func endHoverRegistration(
        task: AppTask,
        hoveredTaskManager: HoveredTaskManager,
        hoveredEditableManager: HoveredEditableManager
    ) {
        hoveredTaskManager.endHovering(task)
        hoveredEditableManager.endHovering(id: editableID(for: task))
    }
}
#endif
