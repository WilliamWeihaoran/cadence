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
        .cadenceTracksDayChanges($observedDay)
    }

    /// [[T-14351]]: the Focus page's own observed day. Nothing it is handed changes at midnight --
    /// the idle picker's ticker runs only while a session does -- so a Mac left on Focus overnight
    /// kept offering yesterday's "ready" list, scored against yesterday's key, until something
    /// else redrew it. Every other page host observes its day the same way.
    @State private var observedDay = CadenceObservedDay()

    private var todayKey: String { observedDay.todayKey }

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
                todayKey: todayKey,
                onClose: { reportingFocusFailure { try focusManager.endSession(in: modelContext) } }
            )

            GeometryReader { proxy in
                HSplitView {
                    VStack(spacing: 14) {
                        FocusTimerPanel(
                            clockDisplay: clockDisplay,
                            logHint: CadenceFocusSupport.logHint(elapsedSeconds: focusManager.elapsedSeconds(at: displayTick)),
                            phase: phase,
                            accent: Color(hex: task.containerColor),
                            controls: { timerControls(task: task) }
                        )
                        // 218 + the hint line and its gap ([[T-11209]]), so the clock keeps its size.
                        .frame(height: 236)

                        // [[T-17043]]: one panel per task, as Notes' editor pane is one per note.
                        // Reused across a switch (a Next up row, Log Session's "Mark task as
                        // complete", the task finished elsewhere), its `.onChange(of: task.id)`
                        // cancelled the pending debounced commit and reloaded the buffer, so up to
                        // `fallbackContentCommitDelay` of typing was dropped: a click on a SwiftUI
                        // button never ends the text view's editing, so no focus-loss flush ran.
                        // Torn down instead, the outgoing panel's `.onDisappear` flushes it while
                        // its `task` is still the one the text belongs to.
                        FocusNotesPanel(task: task)
                            .id(task.id)
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
                            todayKey: todayKey,
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
                // [[T-8732]]: one label on both platforms' Log Session controls.
                accessibilityLabel: CadenceFocusSupport.logFormControlLabel,
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
                        clockDisplay: clockDisplay,
                        searchText: $idleSearchText,
                        items: focusPickerItems,
                        readyCount: readyTasks.count,
                        todayKey: todayKey,
                        // [[T-17048]]: a started session takes the card off screen, and the query
                        // used to outlive it -- the card came back after the session filtered to
                        // the old search ("1 match"), hiding most ready tasks. Cleared only when
                        // the start committed, so a refused start leaves the search as typed.
                        onSelectTask: { task in
                            if reportingFocusFailure({ try focusManager.startFocus(task: task, in: modelContext) }) {
                                idleSearchText = ""
                            }
                        }
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
