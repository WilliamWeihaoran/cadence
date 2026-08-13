#if os(iOS)
import SwiftData
import SwiftUI

struct iOSFocusView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]
    @State private var selectedTaskID: UUID?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
    @State private var timerState = CadenceFocusTimerState()

    private var todayKey: String { DateFormatters.todayKey() }

    private var readyTasks: [AppTask] {
        CadenceFocusSupport.readyTasks(from: allTasks, todayKey: todayKey)
    }

    private var selectedTask: AppTask? {
        if let selectedTaskID {
            return readyTasks.first { $0.id == selectedTaskID } ?? allTasks.first { $0.id == selectedTaskID }
        }
        return readyTasks.first
    }

    private var elapsedSeconds: Int {
        timerState.elapsedSeconds()
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .iOSHidesCompactNavigationBar()
        .onAppear {
            selectedTaskID = selectedTaskID ?? readyTasks.first?.id
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
    }

    private var horizontalLayout: some View {
        HStack(spacing: 0) {
            taskListPane
                .frame(minWidth: 300, idealWidth: 360)

            Divider().background(Theme.borderSubtle)

            focusDetailPane
        }
    }

    /// The eyebrow carries the session's state, because the title already says "Focus" and a
    /// header that describes the screen you are on twice tells the reader nothing.
    private var statusEyebrow: String {
        if timerState.isRunning { return "Session running" }
        if elapsedSeconds > 0 { return "Session paused" }
        return readyTasks.isEmpty ? "Nothing ready" : "\(readyTasks.count) ready"
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                iOSCompactPageHeader(
                    eyebrow: statusEyebrow,
                    title: "Focus",
                    systemImage: "timer",
                    color: Theme.red,
                    onBack: { dismiss() }
                )

                if readyTasks.isEmpty {
                    // A single consolidated empty state avoids showing two
                    // near-duplicate "nothing here" messages stacked on top
                    // of each other (task list pane + focus detail pane).
                    iOSEmptyPanel(
                        systemImage: "timer",
                        title: "No focus tasks",
                        subtitle: "Schedule a task for today and it will appear here, ready to focus on."
                    )
                    .frame(minHeight: 360)
                    .background(Theme.surface)
                    .iOSCompactPanelCard()
                } else {
                    focusDetailPane
                        .iOSCompactPanelCard()

                    taskListPane
                        .frame(minHeight: 280, maxHeight: 380)
                        .iOSCompactPanelCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Picker

    private var taskListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "Ready to focus", title: "Pick a task", count: readyTasks.count)
            Divider().background(Theme.borderSubtle)

            if readyTasks.isEmpty {
                iOSEmptyPanel(
                    systemImage: "timer",
                    title: "No focus tasks",
                    subtitle: "Schedule a task for today to focus it here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(readyTasks) { task in
                            iOSFocusPickRow(
                                task: task,
                                detail: CadenceFocusSupport.sidebarDetail(for: task, todayKey: todayKey),
                                isSelected: selectedTask?.id == task.id
                            ) {
                                select(task)
                            }
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Theme.surface)
    }

    // MARK: - Session

    private var focusDetailPane: some View {
        VStack(spacing: isCompact ? 16 : 20) {
            if let task = selectedTask {
                selectedTaskHeader(task)
                timerPanel(for: task)
                taskNotes(task)
                Spacer(minLength: 0)
            } else {
                iOSEmptyPanel(
                    systemImage: "timer",
                    title: "Ready when you are",
                    subtitle: "Today tasks will appear here."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(isCompact ? 16 : 22)
        .background(Theme.bg)
    }

    private func selectedTaskHeader(_ task: AppTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title.isEmpty ? "Untitled Task" : task.title)
                .font(.system(size: isCompact ? 22 : 25, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(3)

            HStack(spacing: 8) {
                if !task.containerName.isEmpty {
                    iOSMetaChip(label: task.containerName, color: Color(hex: task.containerColor))
                }
                if task.priority != .none {
                    iOSMetaChip(label: task.priority.label, color: Theme.priorityColor(task.priority))
                }
                if let estimate = estimateLabel(for: task) {
                    iOSMetaChip(label: estimate, color: Theme.dim)
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timerPanel(for task: AppTask) -> some View {
        iOSFocusTimerPanel(
            accent: Color(hex: task.containerColor),
            isRunning: timerState.isRunning,
            isCompact: isCompact,
            clock: {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let seconds = elapsedSeconds
                    VStack(spacing: 6) {
                        Text(CadenceFocusSupport.clockDisplay(elapsedSeconds: seconds))
                            .font(.system(size: isCompact ? 56 : 66, weight: .ultraLight, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(timerState.isRunning ? Theme.text : Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .contentTransition(.numericText())

                        // The stopwatch silently rounds to whole minutes when it is logged, so
                        // the amount that will actually land on the task is spelled out rather
                        // than left to be discovered after the fact.
                        Text(logHint(elapsedSeconds: seconds))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.subdued)
                    }
                }
            },
            controls: {
                focusControls(for: task)
            }
        )
    }

    /// Same "actual/estimate" pill macOS's focus header shows, minus the empty `-/-` case.
    private func estimateLabel(for task: AppTask) -> String? {
        let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
        return label == "-/-" ? nil : label
    }

    private func logHint(elapsedSeconds seconds: Int) -> String {
        let minutes = CadenceFocusSupport.minutes(fromElapsedSeconds: seconds)
        guard minutes > 0 else { return "Nothing to log yet" }
        return "Logs \(minutes)m when you finish"
    }

    private func focusControls(for task: AppTask) -> some View {
        HStack(spacing: 16) {
            iOSFocusControlButton(
                systemImage: "arrow.counterclockwise",
                accessibilityLabel: "Reset session",
                foreground: Theme.muted,
                background: Theme.surfaceElevated,
                diameter: 48,
                action: resetTimer
            )

            iOSFocusControlButton(
                systemImage: timerState.isRunning ? "pause.fill" : "play.fill",
                accessibilityLabel: timerState.isRunning ? "Pause session" : "Start session",
                foreground: Theme.onColor,
                background: Color(hex: task.containerColor),
                diameter: 64,
                glowColor: Color(hex: task.containerColor).opacity(0.45),
                action: toggleTimer
            )

            iOSFocusControlButton(
                systemImage: "checkmark",
                accessibilityLabel: "Log session and mark done",
                // Always green: the button works at zero elapsed (it completes the task), so
                // greying it promised a disabled control that was not disabled.
                foreground: Theme.green,
                background: Theme.surfaceElevated,
                diameter: 48
            ) {
                complete(task)
            }
        }
    }

    @ViewBuilder
    private func taskNotes(_ task: AppTask) -> some View {
        if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            iOSMarkdownPreview(
                markdown: task.notes,
                imageAssets: imageAssets,
                taskEmbeds: taskEmbedInfos,
                onOpenReference: openMarkdownReference
            )
            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: isCompact ? 260 : 320, alignment: .topLeading)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
        }
    }

    private var taskEmbedInfos: [UUID: MarkdownTaskEmbedRenderInfo] {
        Dictionary(uniqueKeysWithValues: allTasks.map { task in
            (task.id, MarkdownTaskEmbedRenderInfo.task(task))
        })
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }

    private func select(_ task: AppTask) {
        selectedTaskID = task.id
        resetTimer()
    }

    private func toggleTimer() {
        timerState.toggle()
    }

    private func resetTimer() {
        timerState.reset()
    }

    private func complete(_ task: AppTask) {
        CadenceFocusSupport.complete(task, elapsedSeconds: elapsedSeconds, modelContext: modelContext)
        resetTimer()
        selectedTaskID = readyTasks.first { $0.id != task.id }?.id
    }
}

// MARK: - Focus chrome

/// iOS counterpart of macOS's `FocusTimerPanel`: a `Theme.surface` panel with an accent rule
/// across its top that brightens while the session runs, the running/paused state named in words,
/// and the clock as the one large thing on the screen.
private struct iOSFocusTimerPanel<Clock: View, Controls: View>: View {
    let accent: Color
    let isRunning: Bool
    let isCompact: Bool
    @ViewBuilder let clock: () -> Clock
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: isRunning ? "timer" : "pause.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(isRunning ? "Running" : "Paused")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isRunning ? accent : Theme.dim)

            clock()
                // The glow is the only cue that survives being glanced at from across a desk.
                .shadow(color: accent.opacity(isRunning ? 0.34 : 0), radius: 24)

            controls()
        }
        .padding(isCompact ? 18 : 22)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(isRunning ? 0.72 : 0.24))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 16, x: 0, y: 6)
    }
}

/// iOS counterpart of macOS's `FocusIconButton`. Circular, tinted, and never smaller than the
/// 44pt touch floor even when the plate itself is drawn smaller.
private struct iOSFocusControlButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let foreground: Color
    let background: Color
    var diameter: CGFloat = 48
    var glowColor: Color = .clear
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: diameter > 56 ? 22 : 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(background))
                .shadow(color: glowColor, radius: 12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// iOS counterpart of macOS's `FocusPickItemRow`: the task's list colour as a dot in a ring, the
/// title, one detail line, and a play affordance that says what tapping the row will do.
private struct iOSFocusPickRow: View {
    let task: AppTask
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color {
        Color(hex: task.containerColor)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.16))
                    Circle().fill(tint).frame(width: 9, height: 9)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title.isEmpty ? "Untitled Task" : task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.onColor : Theme.blue)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isSelected ? Theme.blue : Theme.blue.opacity(0.12)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            // One selection layer, at the row's own radius: the card fill lifts and a hairline
            // in the list colour marks the selected row. No second background underneath.
            .cadenceCard(
                background: isSelected ? Theme.surfaceElevated : Theme.surface,
                cornerRadius: Theme.radiusCard,
                shadowRadius: 10,
                shadowY: 4
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(tint.opacity(0.7), lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Focus \(task.title.isEmpty ? "Untitled Task" : task.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
