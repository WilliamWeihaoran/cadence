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
    case pursuits
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ThemeManager.self) private var themeManager
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Environment(FocusManager.self) private var focusManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskDatePickerManager.self) private var hoveredTaskDatePickerManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(TodayTimelineFocusManager.self) private var todayTimelineFocusManager
    @Environment(GlobalSearchManager.self) private var globalSearchManager
    @Environment(ListNavigationManager.self) private var listNavigationManager
    @Environment(NotesNavigationManager.self) private var notesNavigationManager
    @Environment(CalendarNavigationManager.self) private var calendarNavigationManager
    @Environment(TaskSubtaskEntryManager.self) private var taskSubtaskEntryManager
    @Environment(\.modelContext) private var modelContext
    @State private var activeModelContext: ModelContext?
    @State private var dataRefreshID = UUID()
    @State private var mcpRefreshCoordinator = CadenceMCPRefreshCoordinator()
    @State private var pendingAppDataRefresh: DispatchWorkItem?
    @State private var hasPendingExternalDataRefresh = false
    @State private var keyMonitor: Any? = nil
    @State private var showTimelineSidebar = false
    private let hoveredTaskManager = HoveredTaskManager.shared
    private let hoveredEditableManager = HoveredEditableManager.shared
    private let hoveredKanbanColumnManager = HoveredKanbanColumnManager.shared
    private let hoveredSectionManager = HoveredSectionManager.shared
    private let taskCompletionAnimationManager = TaskCompletionAnimationManager.shared

    var body: some View {
        let _ = themeManager.selectedTheme
        let currentModelContext = activeModelContext ?? modelContext

        ZStack {
            macOSRootMainShell(
                columnVisibility: columnVisibility,
                selection: $selection,
                showTimelineSidebar: showTimelineSidebar,
                timelineSidebarOverlay: AnyView(timelineSidebarOverlay)
            ) {
                detailView
            }
            .id(dataRefreshID)
            .overlay(alignment: .topLeading) {
                RootSidebarToggleButton(
                    isSidebarHidden: columnVisibility == .detailOnly,
                    action: toggleSidebarVisibility
                )
                .padding(.leading, 10)
                .padding(.top, 10)
            }

            macOSRootOverlayStack(handleSearchSelection: handleSearchSelection)
                .id(dataRefreshID)

            if let startupIssue = PersistenceController.startupIssue {
                RootStartupIssueBanner(message: startupIssue)
                    .padding(.top, 14)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .modelContext(currentModelContext)
        .ignoresSafeArea(.container, edges: .top)
        .onOpenURL { url in
            CadenceDeepLinkManager.shared.handle(url)
        }
        .onAppear {
            CadenceUITestSupport.prepareAppState(modelContext: activeModelContext ?? modelContext)
            mcpRefreshCoordinator.start {
                hasPendingExternalDataRefresh = true
                scheduleAppDataRefreshIfPossible()
            }
            macOSRootLifecycleSupport.handleAppear(
                modelContext: activeModelContext ?? modelContext,
                installKeyMonitorIfNeeded: installKeyMonitorIfNeeded
            )
        }
        .onDisappear {
            pendingAppDataRefresh?.cancel()
            pendingAppDataRefresh = nil
            macOSRootLifecycleSupport.handleDisappear(removeKeyMonitor: removeKeyMonitor)
        }
        .onChange(of: calendarManager.storeVersion) {
            macOSRootStateSupport.clearCalendarLinkedTasks(modelContext: activeModelContext ?? modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                CadenceWidgetRefreshCenter.reloadTodayWidgets()
                return
            }
            if hasPendingExternalDataRefresh || mcpRefreshCoordinator.shouldRefreshForCurrentMarker() {
                scheduleAppDataRefreshIfPossible()
            }
        }
        .onChange(of: deepLinkManager.route?.token) { _, _ in
            handleDeepLinkRoute()
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
            modelContext: activeModelContext ?? modelContext,
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
            modelContext: activeModelContext ?? modelContext,
            calendarManager: calendarManager,
            globalSearchManager: globalSearchManager,
            listNavigationManager: listNavigationManager,
            notesNavigationManager: notesNavigationManager,
            calendarNavigationManager: calendarNavigationManager,
            clearAppEditingFocus: clearAppEditingFocus,
            setSelection: { selection = $0 },
            presentTaskCreation: { taskCreationManager.present() }
        )
    }

    private func refreshAppData() {
        let currentContext = activeModelContext ?? modelContext
        if currentContext.hasChanges {
            try? currentContext.save()
        }
        currentContext.processPendingChanges()
        activeModelContext = ModelContext(modelContext.container)
        dataRefreshID = UUID()
        hasPendingExternalDataRefresh = false
    }

    private func scheduleAppDataRefreshIfPossible() {
        pendingAppDataRefresh?.cancel()
        let workItem = DispatchWorkItem {
            guard NSApp.isActive else { return }
            refreshAppData()
            pendingAppDataRefresh = nil
        }
        pendingAppDataRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func handleDeepLinkRoute() {
        guard let route = deepLinkManager.route?.deepLink else { return }
        switch route {
        case .today, .task:
            selection = .today
        }
    }
}

private struct RootStartupIssueBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("Recovery Store Active")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 620)
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.amber.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

#endif
