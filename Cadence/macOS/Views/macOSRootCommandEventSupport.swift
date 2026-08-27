#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// What a modal overlay wants done with a key, when one is up.
///
/// This exists because the answer has three cases and the code had two. `handleModalConfirmations`
/// used to return `NSEvent?`, where `nil` meant *both* "the modal consumed this" and "no modal is
/// open" — and the caller's `if let` could only read `nil` as "not handled, keep going". So every
/// consume-path fell through into the app's global shortcut table. Concretely: with the delete
/// confirmation up, **Cmd+Return confirmed the delete and then toggled completion on the hovered
/// task** — two irreversible actions, on two different tasks, from one keystroke.
nonisolated enum RootModalKeyAction: Equatable {
    case confirmDelete
    case cancelDelete
    case confirmDatePicker
    case cancelDatePicker
}

nonisolated enum RootModalKeyDisposition: Equatable {
    /// A modal handled this key. Swallow the event; nothing else may see it.
    case act(RootModalKeyAction)
    /// A modal is up but does not handle this key. Hand it to the responder chain so the overlay's
    /// own `.defaultAction` / `.cancelAction` buttons can take it — but keep it away from the app's
    /// global shortcuts, which must not fire behind an open modal.
    case passToOverlay
    /// Nothing is up. Carry on with normal shortcut handling.
    case noModal
}

enum RootCommandEventSupport {
    /// Return (36), keypad Enter (76) and Escape (53) are the only keys a confirmation overlay
    /// claims.
    ///
    /// Pure and `NSEvent`-free so `CadenceTests` can enumerate it — the previous shape could only
    /// have been caught by pressing Cmd+Return over a task with the delete dialog open, which is
    /// exactly the kind of thing nobody does on purpose.
    static func modalKeyDisposition(
        keyCode: UInt16,
        hasDeleteRequest: Bool,
        hasDatePickerRequest: Bool
    ) -> RootModalKeyDisposition {
        if hasDeleteRequest {
            switch keyCode {
            case 36, 76: return .act(.confirmDelete)
            case 53: return .act(.cancelDelete)
            default: return .passToOverlay
            }
        }

        if hasDatePickerRequest {
            switch keyCode {
            case 36, 76: return .act(.confirmDatePicker)
            case 53: return .act(.cancelDatePicker)
            default: return .passToOverlay
            }
        }

        return .noModal
    }

    static func handleModalConfirmations(
        _ event: NSEvent,
        context: RootCommandContext
    ) -> RootModalKeyDisposition {
        let disposition = modalKeyDisposition(
            keyCode: event.keyCode,
            hasDeleteRequest: context.deleteConfirmationManager.request != nil,
            hasDatePickerRequest: context.hoveredTaskDatePickerManager.request != nil
        )

        switch disposition {
        case .act(.confirmDelete):
            context.deleteConfirmationManager.confirm()
        case .act(.cancelDelete):
            context.deleteConfirmationManager.cancel()
        case .act(.confirmDatePicker):
            context.hoveredTaskDatePickerManager.confirm(in: context.modelContext)
        case .act(.cancelDatePicker):
            context.hoveredTaskDatePickerManager.cancel()
        case .passToOverlay, .noModal:
            break
        }

        return disposition
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
                RootCommandActionSupport.toggleTodayDate(for: task, kind: .doDate, in: context.modelContext)
            }
            return nil
        case 2:
            guard let task = context.hoveredTaskManager.hoveredTask else { return event }
            if event.modifierFlags.contains(.shift) {
                context.hoveredTaskDatePickerManager.present(for: task, kind: .dueDate)
            } else {
                RootCommandActionSupport.toggleTodayDate(for: task, kind: .dueDate, in: context.modelContext)
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
            RootCommandActionSupport.nudgeDate(for: task, kind: dateKind, delta: delta, in: context.modelContext)
            return nil
        default:
            return event
        }
    }
}
#endif
