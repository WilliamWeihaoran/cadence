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
    @Environment(\.scenePhase) private var scenePhase
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

    /// The context every read and write in this view must go through.
    ///
    /// `refreshAppData()` replaces `activeModelContext` wholesale so the UI picks up writes made
    /// by another process (the MCP server), which leaves the environment's context as nothing but
    /// the fallback for the frames before the first refresh. This used to be spelled
    /// `activeModelContext ?? modelContext` at each of seven call sites, and a site that forgot
    /// the `??` would read or write through the *discarded* context — SwiftData raises nothing for
    /// that, it just serves stale rows or drops the write.
    private var currentModelContext: ModelContext {
        activeModelContext ?? modelContext
    }

    var body: some View {
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
            .allowsHitTesting(!taskCreationManager.isPresented)
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
        }
        // Shared with both iOS shells since T-153. The banner used to be a `private` view in this
        // file, so the identical silent failure was visible here and invisible on iPhone and iPad.
        .cadenceStartupIssueBanner(PersistenceController.startupIssue)
        .modelContext(currentModelContext)
        // Attached *after* `.modelContext(...)` on purpose: like the `@Query`s it replaces, the
        // observer must resolve against the inherited context, not `currentModelContext`.
        .background { NotificationReconcileObserver() }
        .ignoresSafeArea(.container, edges: .top)
        .onOpenURL { url in
            CadenceDeepLinkManager.shared.handle(url)
        }
        .onAppear {
            CadenceUITestSupport.prepareAppState(modelContext: currentModelContext)
            mcpRefreshCoordinator.start {
                hasPendingExternalDataRefresh = true
                scheduleAppDataRefreshIfPossible()
            }
            macOSRootLifecycleSupport.handleAppear(
                modelContext: currentModelContext,
                installKeyMonitorIfNeeded: installKeyMonitorIfNeeded
            )
        }
        .onDisappear {
            pendingAppDataRefresh?.cancel()
            pendingAppDataRefresh = nil
            macOSRootLifecycleSupport.handleDisappear(removeKeyMonitor: removeKeyMonitor)
        }
        .onChange(of: calendarManager.storeVersion) {
            macOSRootStateSupport.clearMissingCalendarLinkedTasks(
                modelContext: currentModelContext,
                calendarManager: calendarManager
            )
        }
        .onChange(of: scenePhase) { _, phase in
            // The leaving-active half of this (widget reload + notification reconcile) lives in
            // `NotificationReconcileObserver` so its two unbounded `@Query`s stay off the root.
            guard phase == .active else { return }
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
        .onChange(of: taskCreationManager.isPresented) { _, isPresented in
            if isPresented {
                clearBackgroundHoverState()
            }
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

    private func clearBackgroundHoverState() {
        hoveredTaskManager.clear()
        hoveredEditableManager.clear()
        hoveredKanbanColumnManager.clear()
        hoveredSectionManager.clear()
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
            modelContext: currentModelContext,
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
            modelContext: currentModelContext,
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
        // Saving before the swap is the whole contract — see `CadenceModelContextRefresh`.
        activeModelContext = CadenceModelContextRefresh.replacement(for: currentModelContext)
        dataRefreshID = UUID()
        hasPendingExternalDataRefresh = false
        // Adopting an out-of-process write means adopting its *schedule*, not only its rows. A
        // task an MCP agent completed keeps its pending "due today" reminder, and one it just
        // scheduled has none, until some unrelated scene-phase checkpoint happens to sweep — so a
        // reminder can fire for work that is already done. This is the app side of the contract
        // the writers keep with `CadenceStoreSupport.postExternalWrite`: they post, and the one
        // process that can read `notificationsEnabled` reconciles. `docs/TODO.md` T-306, T-312.
        //
        // After the swap, over `currentModelContext`, because the outgoing context predates the
        // write and would diff against rows the other process never touched.
        HabitNotificationReconcileSupport.scheduleReconcile(in: currentModelContext)
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

    /// A `.task` link no longer routes blind. `resolvedDestination(for:modelContext:)` fetches the
    /// row, disarms `pendingTaskID` when Today will not show it, and answers with a page that
    /// will — see `CadenceDeepLinkResolutionSupport`.
    private func handleDeepLinkRoute() {
        guard let route = deepLinkManager.route?.deepLink else { return }
        let destination = deepLinkManager.resolvedDestination(
            for: route,
            modelContext: currentModelContext
        )
        // Mapped through `SidebarStaticDestination` rather than a second switch, so the sidebar's
        // feature-to-item table stays the only one. Every destination a deep link can produce is
        // in it; `.today` is the safety net, not a route.
        selection = SidebarStaticDestination.allCases.first { $0.feature == destination }?.item ?? .today
    }
}

/// Owns the two unbounded `@Query`s the notification reconcile needs, so they sit on a leaf view
/// rendered in `.background { }` instead of on `macOSRootView` itself — the same shape as
/// `HoverFreezeObserver`. Nothing else changes: the reconcile still runs on exactly the same
/// scene-phase transitions with exactly the same task/habit sets.
private struct NotificationReconcileObserver: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allTasks: [AppTask]
    @Query private var allHabits: [Habit]

    var body: some View {
        Color.clear
            // SwiftUI's `Color.clear` is hit-testable, unlike UIKit's. This one is a full-window
            // background, so without this it would sit in front of the shell for pointer events.
            .allowsHitTesting(false)
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                CadenceWidgetRefreshCenter.reloadAllWidgets()
                let tasks = allTasks
                let habits = allHabits
                Task { await NotificationManager.shared.reconcile(tasks: tasks, habits: habits) }
            }
    }
}

#endif
