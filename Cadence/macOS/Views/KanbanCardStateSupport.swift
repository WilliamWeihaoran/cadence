#if os(macOS)
import SwiftUI
import SwiftData

enum KanbanCardStateSupport {
    static func metadataRows(for task: AppTask, doDateMetaItem: KanbanMetaItem, dueDateMetaItem: KanbanMetaItem?) -> [[KanbanMetaItem]] {
        if let dueDateMetaItem {
            return [[doDateMetaItem, dueDateMetaItem]]
        }
        return [[doDateMetaItem]]
    }

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
            hoveredEditableManager.beginHovering(id: "kanban-task-\(task.id.uuidString)") {
                showTaskInspector.wrappedValue = true
            } onDelete: {
                deleteConfirmationManager.present(
                    title: "Delete Task?",
                    message: "This will permanently delete \"\(task.title.isEmpty ? "Untitled" : task.title)\"."
                ) {
                    if hoveredTaskManager.hoveredTask?.id == task.id {
                        hoveredTaskManager.hoveredTask = nil
                    }
                    modelContext.deleteTask(task)
                }
            }
        } else {
            hoveredTaskManager.endHovering(task)
            hoveredEditableManager.endHovering(id: "kanban-task-\(task.id.uuidString)")
        }
    }
}
#endif
