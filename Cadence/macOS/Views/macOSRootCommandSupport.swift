#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import EventKit

struct RootCommandContext {
    var selection: SidebarItem?
    var showTimelineSidebar: Bool
    let modelContext: ModelContext
    let deleteConfirmationManager: DeleteConfirmationManager
    let hoveredTaskDatePickerManager: HoveredTaskDatePickerManager
    let taskCreationManager: TaskCreationManager
    let todayTimelineFocusManager: TodayTimelineFocusManager
    let globalSearchManager: GlobalSearchManager
    let hoveredTaskManager: HoveredTaskManager
    let hoveredEditableManager: HoveredEditableManager
    let hoveredKanbanColumnManager: HoveredKanbanColumnManager
    let hoveredSectionManager: HoveredSectionManager
    let taskCompletionAnimationManager: TaskCompletionAnimationManager
    let taskSubtaskEntryManager: TaskSubtaskEntryManager
    let clearAppEditingFocus: () -> Void
    let setShowTimelineSidebar: (Bool) -> Void
    let toggleSidebarVisibility: () -> Void
}

struct RootSearchSelectionContext {
    let modelContext: ModelContext
    let calendarManager: CalendarManager
    let globalSearchManager: GlobalSearchManager
    let listNavigationManager: ListNavigationManager
    let notesNavigationManager: NotesNavigationManager
    let calendarNavigationManager: CalendarNavigationManager
    let clearAppEditingFocus: () -> Void
    let setSelection: (SidebarItem) -> Void
    let presentTaskCreation: () -> Void
    /// [[T-5300]] — raises `TaskDetailPopover` for a task picked in Cmd+K, which has no row on
    /// screen to attach a popover to.
    let presentTaskInspector: (UUID) -> Void
}

/// [[T-7203]] — when a View-menu item may act: exactly the states in which
/// `RootCommandHandler.handle` reaches `handleCommandKeyEvent` for its key.
nonisolated enum RootViewMenuGate {
    static func runs(hasModal: Bool, isSearchPresented: Bool, isQuickTaskPanelVisible: Bool) -> Bool {
        !hasModal && !isSearchPresented && !isQuickTaskPanelVisible
    }
}

enum RootCommandHandler {
    static func handle(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
        switch RootCommandEventSupport.handleModalConfirmations(event, context: context) {
        case .act:
            return nil
        case .passToOverlay:
            return event
        case .noModal:
            break
        }

        if context.globalSearchManager.isPresented {
            return RootCommandEventSupport.handlePresentedGlobalSearch(event, context: context)
        }

        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return event
        }

        if QuickTaskPanelController.shared.isVisible {
            return event
        }

        return RootCommandEventSupport.handleCommandKeyEvent(event, context: context)
    }

    /// **[[T-7203]] — a View-menu item, as `CadenceViewMenuRoute` hands it over.**
    ///
    /// The item runs only where `handle(_:context:)` would have run its key: the monitor hands
    /// Cmd+K / Cmd+O / Cmd+\ on to the responder chain behind a modal, with Cmd+K open and over
    /// the quick-task panel, and from there the key reaches the menu item's key equivalent. The
    /// gate keeps that from opening Search behind a delete confirmation, which the key alone never
    /// could.
    static func handleViewMenuCommand(_ command: CadenceViewMenuCommand, context: RootCommandContext) {
        guard RootViewMenuGate.runs(
            hasModal: context.deleteConfirmationManager.request != nil
                || context.hoveredTaskDatePickerManager.request != nil,
            isSearchPresented: context.globalSearchManager.isPresented,
            isQuickTaskPanelVisible: QuickTaskPanelController.shared.isVisible
        ) else { return }
        RootCommandEventSupport.performViewCommand(command, context: context)
    }

    static func handleSearchSelection(_ result: GlobalSearchResult, context: RootSearchSelectionContext) {
        RootCommandActionSupport.handleSearchSelection(result, context: context)
    }

    static func handleMenuCommand(_ command: GlobalSearchCommand, context: RootSearchSelectionContext) {
        RootCommandActionSupport.handleMenuCommand(command, context: context)
    }
}
#endif
