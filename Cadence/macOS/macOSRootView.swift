#if os(macOS)
import Combine
import SwiftUI
import SwiftData
import AppKit

enum SidebarItem: Hashable {
    case today
    case allTasks
    case inbox
    case area(UUID)
    case project(UUID)
    case notes
    case calendar
    case focus
    case settings
}

extension SidebarItem {
    /// The root page a launch opens on: Today, unless a UI-test launch named another with
    /// `CADENCE_UI_TEST_PAGE` ([[T-3200]]). Outside UI-test mode the variable is ignored, so a
    /// shipping launch always lands on Today exactly as before.
    static func launchSelection(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SidebarItem {
        switch CadenceUITestLaunchPage.requested(in: environment) {
        case .none, .today: return .today
        case .allTasks: return .allTasks
        case .inbox: return .inbox
        case .notes: return .notes
        case .calendar: return .calendar
        case .focus: return .focus
        case .settings: return .settings
        }
    }
}

struct macOSRootView: View {
    @State private var selection: SidebarItem? = SidebarItem.launchSelection()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// [[T-14432]]: whether the standing hide is Focus's own, so leaving Focus undoes only that.
    @State private var focusHidSidebar = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Environment(FocusManager.self) private var focusManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskDatePickerManager.self) private var hoveredTaskDatePickerManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(TaskInspectorPresentationManager.self) private var taskInspectorPresentationManager
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
    private let menuCommandRoute = CadenceMenuCommandRoute.shared
    private let viewMenuRoute = CadenceViewMenuRoute.shared

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
        // T-628. The completion control is reached from four surfaces and owned by none of them,
        // so the refusal is named once here rather than four times badly.
        .alert(
            CadenceTaskMutationSupport.settleFailureAlertTitle,
            isPresented: Binding(
                get: { taskCompletionAnimationManager.settleFailed },
                set: { if !$0 { taskCompletionAnimationManager.clearSettleFailure() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(CadencePendingChangePersistence.editFailureNotice)
        }
        .modelContext(currentModelContext)
        // [[T-15461]]: handed `currentModelContext`, the context this window actually reads and
        // writes. It used to resolve a `@Query` against the inherited original context, which
        // `refreshAppData()` exists to replace, so leaving active re-armed a reminder an MCP write
        // had withdrawn.
        .background { NotificationReconcileObserver(sceneContext: currentModelContext) }
        // T-345, attached here for the same reason and after the same `.modelContext(...)`: the
        // root selection can name an area or project that has since been deleted, and nothing else
        // in this view watches for that.
        .background { SidebarSelectionNormalizer(selection: $selection) }
        .ignoresSafeArea(.container, edges: .top)
        .onOpenURL { url in
            CadenceDeepLinkManager.shared.handle(url)
        }
        // T-6111. With no preference declared, SwiftUI answers every external `cadence://` URL — a
        // Today or Calendar widget tap, a link from another app — by opening a SECOND window of
        // the one `WindowGroup`, and the app is built for one (the quick-capture panel, Cmd+K and
        // the hover managers are singletons, T-5953). Claiming every URL here sends it to the
        // window already open, whose `.onOpenURL` above routes it. With no window open SwiftUI
        // still makes one, as it must. Reminder taps never come this way: `NotificationManager`
        // hands them to the same `handle(_:)` in-process, so nothing is routed twice.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
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
            // T-3049: the `.onChange` below never sees a route that was already standing when this
            // view first rendered, which is the shape of a reminder tap that cold-launches the app.
            // `takeUnappliedRoute()` is what keeps this from re-routing on a re-opened window.
            handleDeepLinkRoute()
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
            // `NotificationReconcileObserver`, which fetches on demand rather than observing.
            guard phase == .active else { return }
            if hasPendingExternalDataRefresh || mcpRefreshCoordinator.shouldRefreshForCurrentMarker() {
                scheduleAppDataRefreshIfPossible()
            }
        }
        .onChange(of: deepLinkManager.route?.token) { _, _ in
            handleDeepLinkRoute()
        }
        // T-7232. Cadence ▸ Settings… (Cmd+,) and, since [[T-17170]], File ▸ New Task (Cmd+N) — a
        // menu item has no handle on `selection`. Neither runs behind a modal (T-17170).
        .onChange(of: menuCommandRoute.request?.token) { _, _ in
            guard let request = menuCommandRoute.request else { return }
            RootCommandHandler.handleMenuCommand(
                request.command,
                context: makeSearchSelectionContext(),
                hasModal: deleteConfirmationManager.request != nil || hoveredTaskDatePickerManager.request != nil
            )
        }
        // T-7203. View ▸ Search / Toggle Sidebar / Toggle Timeline — the key monitor's own actions.
        .onChange(of: viewMenuRoute.request?.token) { _, _ in
            guard let request = viewMenuRoute.request else { return }
            RootCommandHandler.handleViewMenuCommand(request.command, context: makeCommandContext())
        }
        .onChange(of: selection) { _, newValue in
            macOSRootLifecycleSupport.handleSelectionChange(
                newValue: newValue,
                columnVisibility: &columnVisibility,
                focusHidSidebar: &focusHidSidebar
            )
        }
        .onChange(of: focusManager.isRunning) { _, isRunning in
            macOSRootLifecycleSupport.handleFocusRunningChange(
                isRunning: isRunning,
                selection: selection,
                columnVisibility: &columnVisibility,
                focusHidSidebar: &focusHidSidebar
            )
        }
        .onChange(of: focusManager.wantsNavToFocus) {
            macOSRootLifecycleSupport.handleFocusNavigationRequest(
                focusManager: focusManager,
                selection: &selection,
                columnVisibility: &columnVisibility,
                focusHidSidebar: &focusHidSidebar
            )
        }
        .onChange(of: listNavigationManager.request?.token) { _, _ in
            guard let request = listNavigationManager.request else { return }
            macOSRootLifecycleSupport.handleListNavigationRequest(
                request: request,
                selection: &selection
            )
        }
        .onChange(of: notesNavigationManager.request?.token) { _, _ in
            macOSRootLifecycleSupport.handleNotesNavigationRequest(
                request: notesNavigationManager.request,
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
        macOSRootLifecycleSupport.toggleSidebar(
            columnVisibility: &columnVisibility,
            focusHidSidebar: &focusHidSidebar
        )
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
            presentTaskCreation: { taskCreationManager.present() },
            presentTaskInspector: { taskInspectorPresentationManager.present(taskID: $0) }
        )
    }

    private func refreshAppData() {
        // Saving before the swap is the whole contract — see `CadenceModelContextRefresh`.
        activeModelContext = CadenceModelContextRefresh.replacement(for: currentModelContext)
        dataRefreshID = UUID()
        hasPendingExternalDataRefresh = false
        // T-3098. `dataRefreshID` is applied to the two subtrees above and to nothing else, so the
        // `.onAppear` on this view — which seeds the app-wide singletons — does not re-run and the
        // singletons are left holding model objects from the context just retired.
        // `macOSRootDataRefreshSupport` says which holder gets re-resolved, which gets cleared, and
        // which is deliberately left alone.
        macOSRootDataRefreshSupport.adoptReplacementContext(
            currentModelContext,
            focusManager: focusManager,
            hoveredTaskManager: hoveredTaskManager
        )
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
        // `takeUnappliedRoute()`, not `route?.deepLink`: this is reached from `.onAppear` as well
        // as from `.onChange`, and exactly one of them should win for any one route (T-3049).
        guard let route = deepLinkManager.takeUnappliedRoute() else { return }
        let destination = deepLinkManager.resolvedDestination(
            for: route,
            modelContext: currentModelContext
        )
        // Selecting the Calendar page is not the whole of opening the calendar: the timeline
        // restores wherever it was last scrolled, so without this the link lands on a remembered
        // date. `openCalendarLink` returns false for every other route and is a no-op for them.
        calendarNavigationManager.openCalendarLink(route)
        // Mapped through the sidebar's own feature-to-page table rather than a second switch, so
        // it stays the only one. It used to be `SidebarStaticDestination.allCases`, which is the
        // *Settings customisation* table and holds six of the eleven destinations — see
        // `deepLinkSidebarItem` for what that quietly did to `.notes` and `.inbox`.
        selection = destination.deepLinkSidebarItem
    }
}

/// The scene-phase checkpoint for the notification reconcile, on a leaf view rendered in
/// `.background { }` instead of on `macOSRootView` itself — the same shape as
/// `HoverFreezeObserver`.
///
/// **No `@Query` ([[T-15461]]).** It owned one, resolved against the window's original context;
/// after `refreshAppData()` swapped in a replacement, that context's registered rows predated
/// every out-of-process write, and the leaving-active reconcile re-added what the fresh pass had
/// withdrawn. Both arms now read a fresh context over the store, as iOS does: becoming active
/// through `CadenceForegroundNotificationSnapshot`, leaving through
/// `CadenceLeavingActiveNotificationInput`, which keeps `sceneContext`'s unsaved edits in the diff.
///
/// **The `@Query private var allHabits: [Habit]` beside it is gone ([[T-2081]]).** It existed only
/// to feed `reconcile(tasks:habits:)`, which no longer takes habits; leaving the query would have
/// kept this view re-rendering on every habit change to compute nothing.
private struct NotificationReconcileObserver: View {
    @Environment(\.scenePhase) private var scenePhase
    let sceneContext: ModelContext
    /// [[T-17311]]: the desktop and Notification Center widgets are on screen beside this window,
    /// so a save is the Mac's checkpoint too, not only leaving active. One per observer, so its
    /// pending trailing reload survives re-renders.
    @State private var widgetReloader = CadenceWidgetStoreChangeReloader()

    var body: some View {
        Color.clear
            // SwiftUI's `Color.clear` is hit-testable, unlike UIKit's. This one is a full-window
            // background, so without this it would sit in front of the shell for pointer events.
            .allowsHitTesting(false)
            // Any save in this process, not only `sceneContext`'s: `refreshAppData()` swaps the
            // context, and every in-process write is one the widgets have not read. Never in a
            // test host, whose saves are fixtures and whose reload would stamp the real app group.
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                guard !NotificationManager.isTestEnvironment else { return }
                widgetReloader.storeDidSave()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    CadenceWidgetRefreshCenter.reloadAllWidgets()
                }
                // **Both directions reconcile, as on iOS ([[T-3046]]).** This used to be
                // `guard phase != .active else { return }` over the whole closure, so only
                // *leaving* active was a checkpoint — and a Mac left open and frontmost all day
                // never converged at all, which is strictly worse than the iOS shape this now
                // matches (`iOSRootView`'s own `.onChange(of: scenePhase)`, [[T-312]]).
                // Leaving active sweeps what this process just changed; *becoming* active is the
                // checkpoint for a write this process did not make — the MCP server's or the
                // widget extension's ([[T-306]]), and the one that matters most, a CloudKit import
                // that landed a delete or a completion from another device while this app was away.
                // The widget reload stays on the leaving arm: it is about what this process wrote.
                // Either read failing reconciles nothing: an empty list cancels every request.
                if phase == .active {
                    let container = sceneContext.container
                    Task {
                        guard let snapshot = try? CadenceForegroundNotificationSnapshot(container: container) else {
                            return
                        }
                        await NotificationManager.shared.reconcile(tasks: snapshot.tasks, completeStore: snapshot.completeStore)
                        withExtendedLifetime(snapshot) {}
                    }
                    return
                }
                guard let input = try? CadenceLeavingActiveNotificationInput(sceneContext: sceneContext) else {
                    return
                }
                Task {
                    await NotificationManager.shared.reconcile(tasks: input.tasks, completeStore: input.completeStore)
                    withExtendedLifetime(input) {}
                }
            }
    }
}

#endif
