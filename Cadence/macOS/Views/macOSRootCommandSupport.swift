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
    let calendarNavigationManager: CalendarNavigationManager
    let clearAppEditingFocus: () -> Void
    let setSelection: (SidebarItem) -> Void
    let presentTaskCreation: () -> Void
}

enum RootCommandHandler {
    static func handle(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
        if let modalResult = RootCommandEventSupport.handleModalConfirmations(event, context: context) {
            return modalResult
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

    static func handleSearchSelection(_ result: GlobalSearchResult, context: RootSearchSelectionContext) {
        RootCommandActionSupport.handleSearchSelection(result, context: context)
    }
}
#endif
