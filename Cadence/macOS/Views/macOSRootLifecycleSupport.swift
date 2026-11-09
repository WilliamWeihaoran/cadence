#if os(macOS)
import SwiftUI
import SwiftData

enum macOSRootLifecycleSupport {
    /// **No `UndoManager` is installed on the model context, and that is a decision (T-367).**
    ///
    /// The root used to do `modelContext.undoManager = UndoManager()` here and route non-text
    /// Cmd+Z into it. Three things were wrong with that, in this order:
    ///
    /// 1. **It is the same primitive `CadencePendingChangePersistence` already refuses.** That
    ///    file's first reason for not offering `rollback()` to an editor is that this app has a
    ///    *single* `ModelContext`, so a whole-context undo takes work its caller knows nothing
    ///    about with it. A global Cmd+Z is that hazard without even an editor's scope: what it
    ///    reverts is whatever the shared context recorded last, which on any given keystroke may
    ///    be a rollover, a reconcile, an external-write merge or a widget refresh rather than
    ///    anything the user did.
    /// 2. **It can only undo half of anything.** Every destructive path here is a store write
    ///    *plus* effects the undo stack never saw: `deleteHabit` cancels the habit's pending
    ///    notification, `CadenceTaskMutationSupport.deleteTasks` cancels task reminders, repairs
    ///    recurrence links and disposes emptied bundles, and the macOS wrapper tears down focus,
    ///    hover and subtask-entry state. Undo would put the rows back with their reminders gone.
    /// 3. **The app's own copy contradicted it.** `CreateGoalSheet` and `HabitsFormSheets` tell
    ///    the user "This cannot be undone" in as many words.
    ///
    /// The ticket recorded this as "source measured, runtime behaviour not measured", so it was
    /// measured before deciding — against `CadenceSchema` in an in-memory container, one context,
    /// one model type, explicit `beginUndoGrouping`/`endUndoGrouping` around each change:
    /// after `delete` + `save`, `canUndo` was **true** and `undo()` left the row **deleted**; after
    /// a title edit, `undo()` removed the edited row instead of restoring its old title. Read that
    /// as a bound, not as the app's behaviour — a headless test has no run loop, so `UndoManager`'s
    /// automatic per-event grouping does not apply and the app's stack was shaped differently. What
    /// it does rule out is the reading this decision had to exclude: that global model undo was a
    /// working feature somebody would miss. It was never wired to a menu item, never given a
    /// `setActionName`, and its only entry point *swallowed* Cmd+Z for non-text responders.
    ///
    /// Editor undo is untouched: `NSTextView` owns its own `UndoManager` and reaches it through
    /// the responder chain, which is why the Cmd+Z case was removed from
    /// `RootCommandEventSupport.handleCommandKeyEvent` rather than narrowed — with no case, the
    /// key falls through to `return event` for every responder, including the text views.
    static func handleAppear(
        modelContext: ModelContext,
        installKeyMonitorIfNeeded: () -> Void
    ) {
        macOSRootStateSupport.configureMainWindow()
        TaskCompletionAnimationManager.shared.modelContext = modelContext
        installKeyMonitorIfNeeded()
        CalendarManager.shared.refreshAuthorizationState()
        RemindersManager.shared.refreshAuthorizationState()
    }

    static func handleDisappear(removeKeyMonitor: () -> Void) {
        removeKeyMonitor()
    }

    /// **[[T-14432]]: leaving Focus undoes Focus's own hide, and only that.**
    ///
    /// `columnVisibility` is one value that two writers share: a running Focus session hides the
    /// sidebar (`handleFocusRunningChange`, `handleFocusNavigationRequest`) and so does the user
    /// (Cmd+O, the corner toggle, through `toggleSidebar`). This used to restore `.all` on every
    /// change to a page other than Focus, which could not tell the two apart and so brought back a
    /// sidebar the user had hidden on any navigation at all. `focusHidSidebar` records whether the
    /// hide standing now is Focus's; it is set only by a hide that actually changed something, and
    /// cleared by a user toggle, which takes the sidebar back.
    static func handleSelectionChange(
        newValue: SidebarItem?,
        columnVisibility: inout NavigationSplitViewVisibility,
        focusHidSidebar: inout Bool
    ) {
        guard newValue != .focus, focusHidSidebar else { return }
        focusHidSidebar = false
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .all
        }
    }

    static func handleFocusRunningChange(
        isRunning: Bool,
        selection: SidebarItem?,
        columnVisibility: inout NavigationSplitViewVisibility,
        focusHidSidebar: inout Bool
    ) {
        if isRunning && selection == .focus {
            hideSidebarForFocus(columnVisibility: &columnVisibility, focusHidSidebar: &focusHidSidebar)
        }
    }

    static func handleFocusNavigationRequest(
        focusManager: FocusManager,
        selection: inout SidebarItem?,
        columnVisibility: inout NavigationSplitViewVisibility,
        focusHidSidebar: inout Bool
    ) {
        if focusManager.wantsNavToFocus {
            selection = .focus
            hideSidebarForFocus(columnVisibility: &columnVisibility, focusHidSidebar: &focusHidSidebar)
            focusManager.wantsNavToFocus = false
        }
    }

    /// The user's Cmd+O / corner toggle. Whatever was hidden, the user owns the sidebar now, so a
    /// later page change leaves it where they put it.
    static func toggleSidebar(
        columnVisibility: inout NavigationSplitViewVisibility,
        focusHidSidebar: inout Bool
    ) {
        focusHidSidebar = false
        withAnimation(.easeInOut(duration: 0.22)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    /// A sidebar the user had already hidden stays theirs: Focus hiding it again changes nothing,
    /// so leaving Focus must not show it.
    private static func hideSidebarForFocus(
        columnVisibility: inout NavigationSplitViewVisibility,
        focusHidSidebar: inout Bool
    ) {
        guard columnVisibility != .detailOnly else { return }
        focusHidSidebar = true
        withAnimation(.easeInOut(duration: 0.25)) {
            columnVisibility = .detailOnly
        }
    }

    /// [[T-5061]]: a note opened from outside the Notes page (a `[[note]]` link in a task's notes)
    /// sets a `NotesNavigationManager` request and nothing else; this brings the page up to read it.
    /// `NotesView` consumes the request on appear.
    static func handleNotesNavigationRequest(
        request: NotesNavigationManager.Request?,
        selection: inout SidebarItem?
    ) {
        guard request != nil else { return }
        selection = .notes
    }

    static func handleListNavigationRequest(
        request: ListNavigationManager.Request,
        selection: inout SidebarItem?
    ) {
        if let areaID = request.areaID {
            selection = .area(areaID)
        } else if let projectID = request.projectID {
            selection = .project(projectID)
        }
    }
}
#endif
