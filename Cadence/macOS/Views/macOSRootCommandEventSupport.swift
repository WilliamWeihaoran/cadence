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

/// [[T-10054]]: what the root monitor does with a key while the global search palette is up.
nonisolated enum RootPresentedSearchKeyDisposition: Equatable {
    /// Escape or a second Cmd+K: close the palette and consume the key.
    case dismiss
    /// Anything else belongs to the palette's field and list.
    case passToPalette
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

    /// **[[T-10054]] — what a key does while the search palette is up.**
    ///
    /// Escape closes it, and so does a second Cmd+K: the doc comment on `handleCommandKeyEvent`
    /// groups Cmd+K with Cmd+\ and Cmd+O as the root's three global overlay keys, and the other two
    /// already toggle their overlays (the Today Timeline pane, the sidebar). The arm used to swallow
    /// Cmd+K and do nothing, which left the one key that opens the palette inert against it --
    /// keeper decided, the consistent option. Every other key, a bare `k` included, goes on to the
    /// palette's own text field.
    ///
    /// Pure and `NSEvent`-free, the `modalKeyDisposition` shape, so the whole space is testable.
    static func presentedGlobalSearchKeyDisposition(keyCode: UInt16, hasCommand: Bool) -> RootPresentedSearchKeyDisposition {
        switch keyCode {
        case 53: return .dismiss
        case 40 where hasCommand: return .dismiss
        default: return .passToPalette
        }
    }

    static func handlePresentedGlobalSearch(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
        let disposition = presentedGlobalSearchKeyDisposition(
            keyCode: event.keyCode,
            hasCommand: event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        )
        switch disposition {
        case .dismiss:
            // Consumed either way, so Cmd+K never also reaches View > Search's key equivalent.
            context.globalSearchManager.dismiss()
            return nil
        case .passToPalette:
            return event
        }
    }

    /// **[[T-17171]] — Cmd+/ toggles cancellation; Cmd+Shift+/ is not Cmd+/.**
    ///
    /// Shift+/ is `?`, and Cmd+? is the system's Help ▸ Search, which every Mac app answers. The
    /// `case 44` arm checked no modifier but Command, so with the pointer resting on a task Cmd+?
    /// cancelled that task and the Help menu never opened -- and with the New Task panel up it was
    /// swallowed outright. The Cmd+P arm already stands down on Shift for the same reason.
    static func cancellationArmClaims(modifierFlags: NSEvent.ModifierFlags) -> Bool {
        !modifierFlags.contains(.shift)
    }

    /// **[[T-7203]] — the one body behind Cmd+K, Cmd+O and Cmd+\ and their View-menu items.**
    ///
    /// The `case 40` / `case 31` / `case 42` arms below call this and return `nil`, so the key is
    /// consumed before `performKeyEquivalent` and the menu item's own key equivalent never fires
    /// from the keyboard while the monitor runs: one press, one action. A click on the item comes
    /// through `RootCommandHandler.handleViewMenuCommand`, which lands here too.
    static func performViewCommand(_ command: CadenceViewMenuCommand, context: RootCommandContext) {
        switch command {
        case .search:
            context.clearAppEditingFocus()
            context.globalSearchManager.present()
        case .toggleSidebar:
            context.toggleSidebarVisibility()
        case .toggleTimeline:
            RootCommandActionSupport.handleTimelineShortcut(context: context)
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
            // [[T-7203]]: View ▸ Search names this key; both run `performViewCommand`.
            performViewCommand(.search, context: context)
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
            // [[T-17171]]: Cmd+Shift+/ is Cmd+? — Help ▸ Search — and is not this arm's key.
            guard cancellationArmClaims(modifierFlags: event.modifierFlags) else { return event }
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
            performViewCommand(.toggleTimeline, context: context)
            return nil
        case 1:
            guard let task = context.hoveredTaskManager.hoveredTask else { return event }
            context.taskSubtaskEntryManager.requestFocus(for: task.id)
            _ = context.hoveredEditableManager.triggerEdit()
            return nil
        case 31:
            performViewCommand(.toggleSidebar, context: context)
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
