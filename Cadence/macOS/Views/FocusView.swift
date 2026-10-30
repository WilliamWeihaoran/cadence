#if os(macOS)
import SwiftUI
import SwiftData
import Combine

struct FocusView: View {
    @Environment(FocusManager.self) private var focusManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    @State private var showLogSheet = false
    @State private var idleSearchText = ""

    /// **T-1103.** The instant the clock face is drawn for, and the whole of what this view's timer
    /// does now. It used to be an accumulator — `focusManager.elapsed += 1` per delivery — which
    /// made a view the accounting authority for a session the manager owns: `RootDetailContent`
    /// builds `FocusView` only for `selection == .focus`, so a walk to Notes and back deleted the
    /// only thing counting, and the minutes spent away never reached `actualMinutes`. Now the
    /// manager derives elapsed time from when the session started, and a missed tick costs a
    /// redraw rather than a minute.
    @State private var displayTick = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch focusManager.activeSession {
            case .task(let task):
                activeLayout(task: task)
            case nil:
                idleLayout
            }
        }
        .background(Theme.bg)
        // Arriving on a session that ran while this screen was gone must show its real reading
        // immediately, not the one it had when the view was last torn down.
        .onAppear { displayTick = Date() }
        .onReceive(timer) { instant in
            guard focusManager.isRunning else { return }
            displayTick = instant
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
            query: idleSearchText,
            todayKey: todayKey
        )
    }

    // MARK: - Active layout

    @ViewBuilder
    private func activeLayout(task: AppTask) -> some View {
        // T-8011: one phase, read by the timer card and the sidebar's Session chip alike.
        let phase = CadenceFocusTimerPhase(
            isRunning: focusManager.isRunning,
            elapsedSeconds: focusManager.elapsedSeconds(at: displayTick)
        )
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
                            phase: phase,
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
                            phase: phase,
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
                foreground: Theme.onColor(for: Color(hex: task.containerColor)),
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
                                focusManager: focusManager,
                                nextReadyTask: { readyTasks.first { $0.id != task.id } }
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

    // MARK: - Idle layout

    private var idleLayout: some View {
        GeometryReader { proxy in
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    FocusPickSessionCard(
                        title: CadenceFocusSupport.pickListTitle,
                        subtitle: "Search your ready tasks, then start the cleanest next session.",
                        clockDisplay: clockDisplay,
                        searchText: $idleSearchText,
                        items: focusPickerItems,
                        onSelectTask: { task in reportingFocusFailure { try focusManager.startFocus(task: task, in: modelContext) } }
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
        FocusSessionSupport.clockDisplay(elapsedSeconds: focusManager.elapsedSeconds(at: displayTick))
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
    /// sheet on top of it — `LogSessionPopover`'s `onLog` — can
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
