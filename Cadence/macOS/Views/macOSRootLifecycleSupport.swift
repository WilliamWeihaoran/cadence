#if os(macOS)
import SwiftUI
import SwiftData

enum macOSRootLifecycleSupport {
    static func handleAppear(
        modelContext: ModelContext,
        installKeyMonitorIfNeeded: () -> Void
    ) {
        macOSRootStateSupport.configureMainWindow()
        if modelContext.undoManager == nil {
            modelContext.undoManager = UndoManager()
        }
        TaskCompletionAnimationManager.shared.modelContext = modelContext
        installKeyMonitorIfNeeded()
        GlobalHotKeyManager.shared.registerIfNeeded()
        CalendarManager.shared.refreshAuthorizationState()
    }

    static func handleDisappear(removeKeyMonitor: () -> Void) {
        removeKeyMonitor()
        GlobalHotKeyManager.shared.unregister()
    }

    static func handleSelectionChange(
        newValue: SidebarItem?,
        columnVisibility: inout NavigationSplitViewVisibility
    ) {
        if newValue != .focus {
            withAnimation(.easeInOut(duration: 0.25)) {
                columnVisibility = .all
            }
        }
    }

    static func handleFocusRunningChange(
        isRunning: Bool,
        selection: SidebarItem?,
        columnVisibility: inout NavigationSplitViewVisibility
    ) {
        if isRunning && selection == .focus {
            withAnimation(.easeInOut(duration: 0.25)) {
                columnVisibility = .detailOnly
            }
        }
    }

    static func handleFocusNavigationRequest(
        focusManager: FocusManager,
        selection: inout SidebarItem?,
        columnVisibility: inout NavigationSplitViewVisibility
    ) {
        if focusManager.wantsNavToFocus {
            selection = .focus
            withAnimation(.easeInOut(duration: 0.25)) {
                columnVisibility = .detailOnly
            }
            focusManager.wantsNavToFocus = false
        }
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
