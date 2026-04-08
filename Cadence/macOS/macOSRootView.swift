#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

enum SidebarItem: Hashable {
    case today
    case allTasks
    case inbox
    case area(UUID)
    case project(UUID)
    case goals
    case habits
    case notes
    case calendar
    case focus
    case settings
}

struct macOSRootView: View {
    @State private var selection: SidebarItem? = .today
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(ThemeManager.self) private var themeManager
    @Environment(FocusManager.self) private var focusManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskDatePickerManager.self) private var hoveredTaskDatePickerManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(TodayTimelineFocusManager.self) private var todayTimelineFocusManager
    @Environment(GlobalSearchManager.self) private var globalSearchManager
    @Environment(ListNavigationManager.self) private var listNavigationManager
    @Environment(CalendarNavigationManager.self) private var calendarNavigationManager
    @Environment(TaskSubtaskEntryManager.self) private var taskSubtaskEntryManager
    @Environment(\.modelContext) private var modelContext
    @State private var keyMonitor: Any? = nil
    @State private var showTimelineSidebar = false
    private let hoveredTaskManager = HoveredTaskManager.shared
    private let hoveredEditableManager = HoveredEditableManager.shared
    private let hoveredKanbanColumnManager = HoveredKanbanColumnManager.shared
    private let hoveredSectionManager = HoveredSectionManager.shared
    private let taskCompletionAnimationManager = TaskCompletionAnimationManager.shared

    var body: some View {
        let _ = themeManager.selectedTheme

        ZStack {
            macOSRootMainShell(
                columnVisibility: columnVisibility,
                selection: $selection,
                showTimelineSidebar: showTimelineSidebar,
                timelineSidebarOverlay: AnyView(timelineSidebarOverlay)
            ) {
                detailView
            }

            VStack {
                HStack {
                    RootSidebarToggleButton(
                        isSidebarHidden: columnVisibility == .detailOnly,
                        action: toggleSidebarVisibility
                    )

                    Spacer()
                }
                .padding(.leading, 10)
                .padding(.top, 10)

                Spacer()
            }
            .zIndex(5)

            macOSRootOverlayStack(handleSearchSelection: handleSearchSelection)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            macOSRootLifecycleSupport.handleAppear(
                modelContext: modelContext,
                installKeyMonitorIfNeeded: installKeyMonitorIfNeeded
            )
        }
        .onDisappear {
            macOSRootLifecycleSupport.handleDisappear(removeKeyMonitor: removeKeyMonitor)
        }
        .onChange(of: calendarManager.storeVersion) {
            macOSRootStateSupport.syncCalendarLinkedTasks(
                modelContext: modelContext,
                calendarManager: calendarManager
            )
        }
        .onChange(of: selection) { _, newValue in
            macOSRootLifecycleSupport.handleSelectionChange(
                newValue: newValue,
                columnVisibility: &columnVisibility
            )
        }
        .onChange(of: focusManager.isRunning) { _, isRunning in
            macOSRootLifecycleSupport.handleFocusRunningChange(
                isRunning: isRunning,
                selection: selection,
                columnVisibility: &columnVisibility
            )
        }
        .onChange(of: focusManager.wantsNavToFocus) {
            macOSRootLifecycleSupport.handleFocusNavigationRequest(
                focusManager: focusManager,
                selection: &selection,
                columnVisibility: &columnVisibility
            )
        }
        .onChange(of: listNavigationManager.request?.token) { _, _ in
            guard let request = listNavigationManager.request else { return }
            macOSRootLifecycleSupport.handleListNavigationRequest(
                request: request,
                selection: &selection
            )
        }
    }

    @ViewBuilder
    private var detailView: some View {
        macOSRootStateSupport.detailContent(for: selection)
    }

    private var timelineSidebarOverlay: some View {
        RootTimelineSidebarPane {
            withAnimation(.easeInOut(duration: 0.2)) {
                showTimelineSidebar = false
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            RootCommandHandler.handle(event, context: makeCommandContext())
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func toggleSidebarVisibility() {
        withAnimation(.easeInOut(duration: 0.22)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    private func handleSearchSelection(_ result: GlobalSearchResult) {
        RootCommandHandler.handleSearchSelection(result, context: makeSearchSelectionContext())
    }

    private func makeCommandContext() -> RootCommandContext {
        macOSRootStateSupport.makeCommandContext(
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
            setShowTimelineSidebar: { showTimelineSidebar = $0 },
            toggleSidebarVisibility: toggleSidebarVisibility
        )
    }

    private func makeSearchSelectionContext() -> RootSearchSelectionContext {
        macOSRootStateSupport.makeSearchSelectionContext(
            modelContext: modelContext,
            calendarManager: calendarManager,
            globalSearchManager: globalSearchManager,
            listNavigationManager: listNavigationManager,
            calendarNavigationManager: calendarNavigationManager,
            clearAppEditingFocus: clearAppEditingFocus,
            setSelection: { selection = $0 },
            presentTaskCreation: { taskCreationManager.present() }
        )
    }
}

#endif
