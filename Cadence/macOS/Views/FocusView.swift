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
                onClose: { focusManager.activeTask = nil }
            )

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
                .frame(minWidth: 520, idealWidth: 720)
                .background(Theme.bg)

                FocusSidebar(
                    task: task,
                    nextTasks: Array(readyTasks.filter { $0.id != task.id }.prefix(4)),
                    onSelectTask: { focusManager.startFocus(task: $0) }
                )
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 430)
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
                help: "Reset session",
                action: { focusManager.reset() }
            )

            FocusIconButton(
                systemName: focusManager.isRunning ? "pause.fill" : "play.fill",
                foreground: .white,
                background: Color(hex: task.containerColor),
                size: 52,
                shadowColor: Color(hex: task.containerColor).opacity(0.45),
                shadowRadius: 11,
                help: focusManager.isRunning ? "Pause session" : "Start session",
                action: { focusManager.isRunning.toggle() }
            )

            FocusIconButton(
                systemName: "checkmark",
                foreground: focusManager.elapsed > 0 ? Theme.green : Theme.muted,
                background: Theme.surfaceElevated,
                size: 38,
                help: "Log session",
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
                        FocusSessionSupport.logSession(
                            hours: hours,
                            minutes: minutes,
                            complete: complete,
                            task: task,
                            modelContext: modelContext,
                            focusManager: focusManager
                        )
                        showLogSheet = false
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
                onClose: { focusManager.activeSession = nil }
            )

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
                .frame(minWidth: 520, idealWidth: 720)
                .background(Theme.bg)

                FocusBundleSidebar(
                    bundle: bundle,
                    nextTasks: Array(readyTasks.filter { !bundle.sortedTasks.map(\.id).contains($0.id) }.prefix(4)),
                    onSelectTask: { focusManager.startFocus(task: $0) }
                )
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 430)
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
                help: "Reset session",
                action: { focusManager.reset() }
            )

            FocusIconButton(
                systemName: focusManager.isRunning ? "pause.fill" : "play.fill",
                foreground: .white,
                background: Theme.amber,
                size: 52,
                shadowColor: Theme.amber.opacity(0.45),
                shadowRadius: 11,
                help: focusManager.isRunning ? "Pause session" : "Start session",
                action: { focusManager.isRunning.toggle() }
            )

            FocusIconButton(
                systemName: "checkmark",
                foreground: focusManager.elapsed > 0 ? Theme.green : Theme.muted,
                background: Theme.surfaceElevated,
                size: 38,
                help: "Log session",
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
                        FocusSessionSupport.logBundleSession(
                            hours: hours,
                            minutes: minutes,
                            tasks: selectedBundleTasks(bundle),
                            focusManager: focusManager
                        )
                        showLogSheet = false
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
        bundle.sortedTasks.filter { focusManager.selectedBundleTaskIDs.contains($0.id) }
    }

    // MARK: - Idle layout

    private var idleLayout: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                FocusIdleHero(
                    clockDisplay: clockDisplay
                )
                .frame(height: 178)

                FocusPickSessionCard(
                    title: "Pick a task",
                    subtitle: "Search tasks and bundles, or start from the best matches.",
                    searchText: $idleSearchText,
                    items: focusPickerItems,
                    onSelectTask: { focusManager.startFocus(task: $0) },
                    onSelectBundle: { focusManager.startFocus(bundle: $0) }
                )
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(18)
            .frame(minWidth: 520, idealWidth: 720)
            .background(Theme.bg)

            VStack(spacing: 0) {
                SchedulePanel(presentation: .compact)
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 430)
            .background(Theme.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // MARK: - Helpers

    private var clockDisplay: String {
        FocusSessionSupport.clockDisplay(elapsedSeconds: focusManager.elapsed)
    }

    private func durationLabel(for task: AppTask) -> String? {
        FocusSessionSupport.durationLabel(for: task)
    }
}
#endif
