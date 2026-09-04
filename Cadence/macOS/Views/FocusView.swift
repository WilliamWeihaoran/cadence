#if os(macOS)
import SwiftUI
import SwiftData
import Combine

struct FocusView: View {
    @Environment(FocusManager.self) private var focusManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]

    @State private var showLogSheet = false
    @State private var idleSearchText = ""

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch focusManager.activeSession {
            case .task(let task):
                activeLayout(task: task)
            case .bundle(let bundle):
                activeBundleLayout(bundle: bundle)
            case nil:
                idleLayout
            }
        }
        .background(Theme.bg)
        .onAppear { } // timer only starts via startFocus(task:) from the hover ▶ button
        .onReceive(timer) { _ in
            guard focusManager.isRunning else { return }
            focusManager.elapsed += 1
        }
    }

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var readyTasks: [AppTask] {
        FocusSessionSupport.readyTasks(from: allTasks, todayKey: todayKey)
    }

    private var focusPickerItems: [FocusPickItem] {
        FocusPickItem.filtered(
            tasks: readyTasks,
            bundles: allBundles,
            query: idleSearchText,
            todayKey: todayKey
        )
    }

    // MARK: - Active layout

    @ViewBuilder
    private func activeLayout(task: AppTask) -> some View {
        VStack(spacing: 0) {
            FocusSessionHeader(
                task: task,
                estimateLabel: durationLabel(for: task),
                onClose: { reportingFocusFailure { try focusManager.endSession(in: modelContext) } }
            )

            GeometryReader { proxy in
                HSplitView {
                    VStack(spacing: 14) {
                        FocusTimerPanel(
                            clockDisplay: clockDisplay,
                            isRunning: focusManager.isRunning,
                            accent: Color(hex: task.containerColor),
                            controls: { timerControls(task: task) }
                        )
                        .frame(height: 218)

                        FocusNotesPanel(task: task)
                            .frame(minHeight: 280)
                    }
                    .padding(18)
                    .frame(
                        minWidth: CadenceDesktopSplitLayout.focusSessionPaneMinWidth,
                        idealWidth: 720
                    )
                    .background(Theme.bg)

                    if CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: proxy.size.width) {
                        FocusSidebar(
                            task: task,
                            nextTasks: Array(readyTasks.filter { $0.id != task.id }.prefix(4)),
                            onSelectTask: { task in reportingFocusFailure { try focusManager.startFocus(task: task, in: modelContext) } }
                        )
                        .frame(
                            minWidth: CadenceDesktopSplitLayout.focusSidebarPaneMinWidth,
                            idealWidth: 360,
                            maxWidth: 430
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 34)
        .background(Theme.bg)
    }

    @ViewBuilder
    private func timerControls(task: AppTask) -> some View {
        HStack(spacing: 12) {
            FocusIconButton(
                systemName: "arrow.counterclockwise",
                foreground: Theme.muted,
                background: Theme.surfaceElevated,
                size: 38,
                accessibilityLabel: "Reset session",
                action: { focusManager.reset() }
            )

            FocusIconButton(
                systemName: focusManager.isRunning ? "pause.fill" : "play.fill",
                foreground: Theme.onColor,
                background: Color(hex: task.containerColor),
                size: 52,
                shadowColor: Color(hex: task.containerColor).opacity(0.45),
                shadowRadius: 11,
                accessibilityLabel: focusManager.isRunning ? "Pause session" : "Start session",
                action: { focusManager.isRunning.toggle() }
            )

            FocusIconButton(
                systemName: "checkmark",
                foreground: focusManager.elapsed > 0 ? Theme.green : Theme.muted,
                background: Theme.surfaceElevated,
                size: 38,
                accessibilityLabel: "Log session",
                action: {
                    focusManager.isRunning = false
                    showLogSheet = true
                }
            )
            .popover(isPresented: $showLogSheet, arrowEdge: .bottom) {
                LogSessionPopover(
                    task: task,
                    elapsedSeconds: focusManager.elapsed,
                    onLog: { hours, minutes, complete in
                        let committed = reportingFocusFailure {
                            try FocusSessionSupport.logSession(
                                hours: hours,
                                minutes: minutes,
                                complete: complete,
                                task: task,
                                modelContext: modelContext,
                                focusManager: focusManager
                            )
                        }
                        // T-566: dismissing over a refused commit reports a save that did not
                        // happen. The popover stays open so the entered hours/minutes are not lost.
                        if committed {
                            showLogSheet = false
                        }
                    },
                    onDiscard: {
                        focusManager.reset()
                        showLogSheet = false
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func activeBundleLayout(bundle: TaskBundle) -> some View {
        VStack(spacing: 0) {
            FocusBundleHeader(
                bundle: bundle,
                selectedCount: selectedBundleTasks(bundle).count,
                onClose: { reportingFocusFailure { try focusManager.endSession(in: modelContext) } }
            )

            GeometryReader { proxy in
                HSplitView {
                    VStack(spacing: 14) {
                        FocusTimerPanel(
                            clockDisplay: clockDisplay,
                            isRunning: focusManager.isRunning,
                            accent: Theme.amber,
                            controls: { bundleTimerControls(bundle: bundle) }
                        )
                        .frame(height: 218)

                        FocusBundleTasksPanel(
                            bundle: bundle,
                            selectedTaskIDs: Binding(
                                get: { focusManager.selectedBundleTaskIDs },
                                set: { focusManager.selectedBundleTaskIDs = $0 }
                            )
                        )
                        .frame(minHeight: 280)
                    }
                    .padding(18)
                    .frame(
                        minWidth: CadenceDesktopSplitLayout.focusSessionPaneMinWidth,
                        idealWidth: 720
                    )
                    .background(Theme.bg)

                    if CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: proxy.size.width) {
                        FocusBundleSidebar(
                            bundle: bundle,
                            nextTasks: Array(readyTasks.filter { !bundle.sortedTasks.map(\.id).contains($0.id) }.prefix(4)),
                            onSelectTask: { task in reportingFocusFailure { try focusManager.startFocus(task: task, in: modelContext) } }
                        )
                        .frame(
                            minWidth: CadenceDesktopSplitLayout.focusSidebarPaneMinWidth,
                            idealWidth: 360,
                            maxWidth: 430
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 34)
        .background(Theme.bg)
    }

    @ViewBuilder
    private func bundleTimerControls(bundle: TaskBundle) -> some View {
        HStack(spacing: 12) {
            FocusIconButton(
                systemName: "arrow.counterclockwise",
                foreground: Theme.muted,
                background: Theme.surfaceElevated,
                size: 38,
                accessibilityLabel: "Reset session",
                action: { focusManager.reset() }
            )

            FocusIconButton(
                systemName: focusManager.isRunning ? "pause.fill" : "play.fill",
                foreground: Theme.onColor,
                background: Theme.amber,
                size: 52,
                shadowColor: Theme.amber.opacity(0.45),
                shadowRadius: 11,
                accessibilityLabel: focusManager.isRunning ? "Pause session" : "Start session",
                action: { focusManager.isRunning.toggle() }
            )

            FocusIconButton(
                systemName: "checkmark",
                foreground: focusManager.elapsed > 0 ? Theme.green : Theme.muted,
                background: Theme.surfaceElevated,
                size: 38,
                accessibilityLabel: "Log session",
                action: {
                    focusManager.isRunning = false
                    showLogSheet = true
                }
            )
            .popover(isPresented: $showLogSheet, arrowEdge: .bottom) {
                BundleLogSessionPopover(
                    bundle: bundle,
                    elapsedSeconds: focusManager.elapsed,
                    selectedTasks: selectedBundleTasks(bundle),
                    onLog: { hours, minutes in
                        let committed = reportingFocusFailure {
                            try FocusSessionSupport.logBundleSession(
                                hours: hours,
                                minutes: minutes,
                                tasks: selectedBundleTasks(bundle),
                                modelContext: modelContext,
                                focusManager: focusManager
                            )
                        }
                        // T-566: see the sibling task popover's identical guard above.
                        if committed {
                            showLogSheet = false
                        }
                    },
                    onDiscard: {
                        focusManager.reset()
                        showLogSheet = false
                    }
                )
            }
        }
    }

    private func selectedBundleTasks(_ bundle: TaskBundle) -> [AppTask] {
        CadenceFocusSupport.selectedTasks(in: bundle, selectedTaskIDs: focusManager.selectedBundleTaskIDs)
    }

    // MARK: - Idle layout

    private var idleLayout: some View {
        GeometryReader { proxy in
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    FocusPickSessionCard(
                        title: "Pick a task",
                        subtitle: "Search across tasks and bundles, then start the cleanest next session.",
                        clockDisplay: clockDisplay,
                        searchText: $idleSearchText,
                        items: focusPickerItems,
                        onSelectTask: { task in reportingFocusFailure { try focusManager.startFocus(task: task, in: modelContext) } },
                        onSelectBundle: { bundle in reportingFocusFailure { try focusManager.startFocus(bundle: bundle, in: modelContext) } }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(18)
                .frame(
                    minWidth: CadenceDesktopSplitLayout.focusSessionPaneMinWidth,
                    idealWidth: 720
                )
                .background(Theme.bg)

                if CadenceDesktopSplitLayout.focusShowsSidebar(paneWidth: proxy.size.width) {
                    VStack(spacing: 0) {
                        SchedulePanel(presentation: .compact)
                    }
                    .frame(
                        minWidth: CadenceDesktopSplitLayout.focusSidebarPaneMinWidth,
                        idealWidth: 360,
                        maxWidth: 430
                    )
                    .background(Theme.surface)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    // MARK: - Helpers

    private var clockDisplay: String {
        FocusSessionSupport.clockDisplay(elapsedSeconds: focusManager.elapsed)
    }

    private func durationLabel(for task: AppTask) -> String? {
        FocusSessionSupport.durationLabel(for: task)
    }

    /// **T-654.** Every close/switch on this screen now commits a pending bank through
    /// `FocusManager`, and a refusal has to be named somewhere: this is macOS's one place for it,
    /// reusing the alert `macOSRootView` already shows for a refused settle
    /// (`TaskCompletionAnimationManager.settleFailed`) rather than adding a second notice for what
    /// is, from the user's side, the same event — a task mutation the store did not take.
    ///
    /// Returns whether `body` committed, so a caller that would otherwise dismiss a popover or
    /// sheet on top of it — `LogSessionPopover`'s and `BundleLogSessionPopover`'s `onLog` — can
    /// leave it open on a refusal instead of reporting success over one (T-566's rule).
    @discardableResult
    private func reportingFocusFailure(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            return true
        } catch {
            TaskCompletionAnimationManager.shared.recordSettleFailure()
            return false
        }
    }
}
#endif
