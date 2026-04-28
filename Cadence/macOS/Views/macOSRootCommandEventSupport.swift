#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

enum RootCommandEventSupport {
    static func handleModalConfirmations(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
        if context.deleteConfirmationManager.request != nil {
            switch event.keyCode {
            case 36, 76:
                context.deleteConfirmationManager.confirm()
                return nil
            case 53:
                context.deleteConfirmationManager.cancel()
                return nil
            default:
                return event
            }
        }

        if context.hoveredTaskDatePickerManager.request != nil {
            switch event.keyCode {
            case 36, 76:
                context.hoveredTaskDatePickerManager.confirm()
                return nil
            case 53:
                context.hoveredTaskDatePickerManager.cancel()
                return nil
            default:
                return event
            }
        }

        return nil
    }

    static func handlePresentedGlobalSearch(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
        switch event.keyCode {
        case 53:
            context.globalSearchManager.dismiss()
            return nil
        default:
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
               event.keyCode == 40 {
                return nil
            }
            return event
        }
    }

    static func handleCommandKeyEvent(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
        switch event.keyCode {
        case 40:
            context.clearAppEditingFocus()
            context.globalSearchManager.present()
            return nil
        case 51:
            if context.hoveredEditableManager.triggerDelete() { return nil }
            guard let task = context.hoveredTaskManager.hoveredTask else { return event }
            RootCommandActionSupport.handleDeleteShortcut(task: task, context: context)
            return nil
        case 14:
            if context.hoveredEditableManager.triggerEdit() { return nil }
            return event
        case 17:
            guard let task = context.hoveredTaskManager.hoveredTask else { return event }
            if event.modifierFlags.contains(.shift) {
                context.hoveredTaskDatePickerManager.present(for: task, kind: .doDate)
            } else {
                RootCommandActionSupport.toggleTodayDate(for: task, kind: .doDate)
            }
            return nil
        case 2:
            guard let task = context.hoveredTaskManager.hoveredTask else { return event }
            if event.modifierFlags.contains(.shift) {
                context.hoveredTaskDatePickerManager.present(for: task, kind: .dueDate)
            } else {
                RootCommandActionSupport.toggleTodayDate(for: task, kind: .dueDate)
            }
            return nil
        case 35:
            guard let task = context.hoveredTaskManager.hoveredTask,
                  !event.modifierFlags.contains(.shift) else { return event }
            task.priority = task.priority.nextCycled
            return nil
        case 36, 76:
            guard !context.taskCreationManager.isPresented else { return nil }
            if let task = context.hoveredTaskManager.hoveredTask {
                context.taskCompletionAnimationManager.toggleCompletion(for: task)
                return nil
            }
            if context.hoveredSectionManager.triggerToggleComplete() { return nil }
            return event
        case 44:
            guard !context.taskCreationManager.isPresented else { return nil }
            guard context.hoveredTaskManager.hoveredTask != nil else { return event }
            _ = RootCommandActionSupport.handleCancellation(context: context)
            return nil
        case 45:
            if context.hoveredKanbanColumnManager.triggerCreateTask() { return nil }
            return event
        case 6:
            let firstResponder = NSApp.keyWindow?.firstResponder
            if firstResponder is NSTextView || firstResponder is NSTextField {
                return event
            }
            if event.modifierFlags.contains(.shift) {
                context.modelContext.undoManager?.redo()
            } else {
                context.modelContext.undoManager?.undo()
            }
            return nil
        case 42:
            RootCommandActionSupport.handleTimelineShortcut(context: context)
            return nil
        case 1:
            guard let task = context.hoveredTaskManager.hoveredTask else { return event }
            context.taskSubtaskEntryManager.requestFocus(for: task.id)
            _ = context.hoveredEditableManager.triggerEdit()
            return nil
        case 31:
            context.toggleSidebarVisibility()
            return nil
        case 24, 27:
            guard event.modifierFlags.contains(.shift),
                  let task = context.hoveredTaskManager.hoveredTask,
                  let dateKind = context.hoveredTaskManager.hoveredDateKind else { return event }
            let delta = event.keyCode == 27 ? -1 : 1
            RootCommandActionSupport.nudgeDate(for: task, kind: dateKind, delta: delta)
            return nil
        default:
            return event
        }
    }
}
#endif
