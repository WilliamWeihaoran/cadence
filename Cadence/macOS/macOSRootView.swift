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
    @Environment(ThemeManager.self) private var themeManager
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
        }
        .modelContext(currentModelContext)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
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
            macOSRootStateSupport.syncCalendarLinkedTasks(
                modelContext: activeModelContext ?? modelContext,
                calendarManager: calendarManager
            )
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if hasPendingExternalDataRefresh || mcpRefreshCoordinator.shouldRefreshForCurrentMarker() {
                scheduleAppDataRefreshIfPossible()
            }
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
}

private final class CadenceMCPRefreshCoordinator {
    private var monitor: CadenceMCPRefreshMonitor?
    private var lastMarkerDate: Date?

    func start(onChange: @escaping () -> Void) {
        guard monitor == nil else { return }
        monitor = CadenceMCPRefreshMonitor { [weak self] in
            self?.lastMarkerDate = Self.currentMarkerDate() ?? Date()
            onChange()
        }
        lastMarkerDate = Self.currentMarkerDate()
    }

    func shouldRefreshForCurrentMarker() -> Bool {
        guard let markerDate = Self.currentMarkerDate(),
              markerDate != lastMarkerDate else { return false }
        lastMarkerDate = markerDate
        return true
    }

    private static func currentMarkerDate() -> Date? {
        guard let markerURL = try? CadenceModelContainerFactory.refreshMarkerURL(),
              let values = try? markerURL.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }
}

private final class CadenceMCPRefreshMonitor {
    private let queue = DispatchQueue(label: "com.haoranwei.Cadence.mcp-refresh-monitor")
    private let source: DispatchSourceFileSystemObject
    private var pendingRefresh: DispatchWorkItem?

    init?(onChange: @escaping () -> Void) {
        guard let markerURL = try? CadenceModelContainerFactory.refreshMarkerURL() else { return nil }
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: markerURL.path) {
            FileManager.default.createFile(atPath: markerURL.path, contents: Data())
        }

        let descriptor = open(markerURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleRefresh(onChange)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    private func scheduleRefresh(_ onChange: @escaping () -> Void) {
        pendingRefresh?.cancel()
        let workItem = DispatchWorkItem {
            DispatchQueue.main.async(execute: onChange)
        }
        pendingRefresh = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}

#endif
