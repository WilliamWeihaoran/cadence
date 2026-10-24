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

/// T-5800. **Which Cmd-key shortcuts stand down while the user is typing.**
///
/// The root key monitor is an app-wide local monitor, so it sees a key before the first responder
/// does. The hover-scoped shortcuts act on whatever task, row or column the POINTER rests over, and
/// the pointer stays there while the keyboard is busy in a text field — so Cmd+Delete, the system's
/// "delete to start of line", asked to delete the hovered task, and the next Return confirmed it.
/// While an editable text view (a SwiftUI `TextField`'s field editor or a `TextEditor`) is first
/// responder, those keys belong to the text.
///
/// Cmd+K (40), Cmd+\ (42) and Cmd+O (31) name no hovered object and stay global.
nonisolated enum RootCommandTextEditingGate {
    /// The hover-scoped keys: Delete (51), Return / keypad Enter (36, 76), T (17), D (2), P (35),
    /// / (44), S (1), = and - (24, 27), E (14), N (45).
    static let hoverScopedKeyCodes: Set<UInt16> = [51, 36, 76, 17, 2, 35, 44, 1, 24, 27, 14, 45]

    /// `true` when the key must go to the responder chain untouched instead of the shortcut table.
    static func passesThrough(keyCode: UInt16, isEditingText: Bool) -> Bool {
        isEditingText && hoverScopedKeyCodes.contains(keyCode)
    }

    /// An editable `NSTextView` — the field editor behind every `TextField` is one. A selectable
    /// but read-only text view is not editing, so the shortcuts still work over it.
    @MainActor
    static func isEditingText(_ responder: NSResponder?) -> Bool {
        guard let textView = responder as? NSTextView else { return false }
        return textView.isEditable
    }
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

    /// The app's Cmd-key table. A case returns `nil` when it consumed the key and `event` when it
    /// did not, so anything absent from the switch falls through to the responder chain.
    ///
    /// **Cmd+Z (keyCode 6) is deliberately absent (T-367).** It used to be handled here: hand the
    /// key to the responder chain if a text view had focus, otherwise drive
    /// `modelContext.undoManager`. Global model undo is gone — `macOSRootLifecycleSupport` carries
    /// the reasoning — and once it is gone the remaining branch is what `default` already does.
    /// Re-adding a case to "pass Cmd+Z through" would be a no-op that reads like a feature.
    static func handleCommandKeyEvent(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
        let firstResponder = (event.window ?? NSApp.keyWindow)?.firstResponder
        if RootCommandTextEditingGate.passesThrough(
            keyCode: event.keyCode,
            isEditingText: RootCommandTextEditingGate.isEditingText(firstResponder)
        ) {
            return event
        }

        switch event.keyCode {
        case 40:
            // T-5882: unconditional, and that is the decision rather than an oversight. This arm
            // runs before `performKeyEquivalent`, so for as long as it is here the markdown
            // editor's own Cmd+K can never fire. The owner chose one meaning for Cmd+K app-wide —
            // Search — over letting it reach an editable text view, so the editor's insert-link
            // shortcut moved to Cmd+Shift+K (`MarkdownKeyboardShortcutSupport.handle`) and this
            // arm does **not** grow a text-editing exception.
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
            RootCommandActionSupport.cyclePriority(of: task, in: context.modelContext)
            return nil
        case 36, 76:
            // T-5802: pass, do not swallow. The New Task panel's Create button is bound to
            // Cmd+Return and only the responder chain can reach it; returning `nil` here ate the
            // key. Hover is cleared behind the panel, so no background row can take it either way.
            guard !context.taskCreationManager.isPresented else { return event }
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
            // T-5953: the Kanban arm stays first — over a column Cmd+N makes a card *in that
            // column*. Handing the key on no longer reaches SwiftUI's File ▸ New Window: the
            // `.newItem` group is replaced by `macOSRootMenuCommands`, whose New Task item owns
            // Cmd+N, so the fall-through is New Task rather than a second window.
            if context.hoveredKanbanColumnManager.triggerCreateTask() { return nil }
            return event
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
