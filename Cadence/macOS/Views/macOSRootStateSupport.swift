#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct RootDetailContent: View {
    let selection: SidebarItem?

    var body: some View {
        switch selection {
        case .today, .none:
            TodayView()
        case .allTasks:
            AllTasksPageView()
        case .inbox:
            InboxView()
        case .area(let id):
            AreaDetailLoader(id: id)
        case .project(let id):
            ProjectDetailLoader(id: id)
        case .goals:
            GoalsView()
        case .habits:
            HabitsView()
        case .notes:
            NotesView()
        case .calendar:
            CalendarPageView()
        case .focus:
            FocusView()
        case .settings:
            SettingsView()
        }
    }
}

enum macOSRootStateSupport {
    @ViewBuilder
    static func detailContent(for selection: SidebarItem?) -> some View {
        RootDetailContent(selection: selection)
    }

    static func configureMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.contentViewController != nil }) else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbar = nil
            window.isMovableByWindowBackground = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    static func syncCalendarLinkedTasks(modelContext: ModelContext, calendarManager: CalendarManager) {
        let descriptor = FetchDescriptor<AppTask>()
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        for task in tasks where !task.calendarEventID.isEmpty {
            calendarManager.syncTaskFromLinkedEvent(task)
        }
        try? modelContext.save()
    }

    static func makeCommandContext(
        selection: SidebarItem?,
        showTimelineSidebar: Bool,
        modelContext: ModelContext,
        deleteConfirmationManager: DeleteConfirmationManager,
        hoveredTaskDatePickerManager: HoveredTaskDatePickerManager,
        taskCreationManager: TaskCreationManager,
        todayTimelineFocusManager: TodayTimelineFocusManager,
        globalSearchManager: GlobalSearchManager,
        hoveredTaskManager: HoveredTaskManager,
        hoveredEditableManager: HoveredEditableManager,
        hoveredKanbanColumnManager: HoveredKanbanColumnManager,
        hoveredSectionManager: HoveredSectionManager,
        taskCompletionAnimationManager: TaskCompletionAnimationManager,
        taskSubtaskEntryManager: TaskSubtaskEntryManager,
        clearAppEditingFocus: @escaping () -> Void,
        setShowTimelineSidebar: @escaping (Bool) -> Void,
        toggleSidebarVisibility: @escaping () -> Void
    ) -> RootCommandContext {
        RootCommandContext(
            selection: selection,
            showTimelineSidebar: showTimelineSidebar,
            modelContext: modelContext,
            deleteConfirmationManager: deleteConfirmationManager,
            hoveredTaskDatePickerManager: hoveredTaskDatePickerManager,
            taskCreationManager: taskCreationManager,
            todayTimelineFocusManager: todayTimelineFocusManager,
            globalSearchManager: globalSearchManager,
            hoveredTaskManager: hoveredTaskManager,
            hoveredEditableManager: hoveredEditableManager,
            hoveredKanbanColumnManager: hoveredKanbanColumnManager,
            hoveredSectionManager: hoveredSectionManager,
            taskCompletionAnimationManager: taskCompletionAnimationManager,
            taskSubtaskEntryManager: taskSubtaskEntryManager,
            clearAppEditingFocus: clearAppEditingFocus,
            setShowTimelineSidebar: setShowTimelineSidebar,
            toggleSidebarVisibility: toggleSidebarVisibility
        )
    }

    static func makeSearchSelectionContext(
        modelContext: ModelContext,
        calendarManager: CalendarManager,
        globalSearchManager: GlobalSearchManager,
        listNavigationManager: ListNavigationManager,
        calendarNavigationManager: CalendarNavigationManager,
        clearAppEditingFocus: @escaping () -> Void,
        setSelection: @escaping (SidebarItem) -> Void,
        presentTaskCreation: @escaping () -> Void
    ) -> RootSearchSelectionContext {
        RootSearchSelectionContext(
            modelContext: modelContext,
            calendarManager: calendarManager,
            globalSearchManager: globalSearchManager,
            listNavigationManager: listNavigationManager,
            calendarNavigationManager: calendarNavigationManager,
            clearAppEditingFocus: clearAppEditingFocus,
            setSelection: setSelection,
            presentTaskCreation: presentTaskCreation
        )
    }
}
#endif
