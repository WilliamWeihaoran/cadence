#if os(macOS)
import SwiftUI
import SwiftData
import Combine

struct FocusView: View {
    @Environment(FocusManager.self) private var focusManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    @State private var showTaskPicker = false
    @State private var showLogSheet = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let task = focusManager.activeTask {
                activeLayout(task: task)
            } else {
                idleLayout
            }
        }
        .background(Theme.bg)
        .onAppear { } // timer only starts via startFocus(task:) from the hover ▶ button
        .onReceive(timer) { _ in
            guard focusManager.isRunning else { return }
            focusManager.elapsed += 1
        }
        .popover(isPresented: $showTaskPicker) {
            FocusTaskPicker(tasks: allTasks.filter { !$0.isDone && !$0.isCancelled }) { task in
                focusManager.startFocus(task: task)
                showTaskPicker = false
            }
        }
    }

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var readyTasks: [AppTask] {
        FocusSessionSupport.readyTasks(from: allTasks, todayKey: todayKey)
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

    // MARK: - Idle layout

    private var idleLayout: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                FocusIdleHero(
                    clockDisplay: clockDisplay,
                    onPickTask: { showTaskPicker = true }
                )
                .frame(height: 220)

                FocusTaskBucketCard(
                    title: "Up next",
                    subtitle: "Best next tasks",
                    accent: Theme.blue,
                    tasks: Array(readyTasks.prefix(8)),
                    onSelect: { focusManager.startFocus(task: $0) }
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

// MARK: - Active Focus Surface

private struct FocusSessionHeader: View {
    let task: AppTask
    let estimateLabel: String?
    let onClose: () -> Void

    var body: some View {
        let hasContainer = !task.containerName.isEmpty
        let hasPriority = task.priority != .none
        let hasDueDate = !task.dueDate.isEmpty
        let hasEstimate = estimateLabel != nil

        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Focus Session")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)

                Text(task.title.isEmpty ? "Untitled Task" : task.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 7) {
                    if hasContainer {
                        Label {
                            Text(task.containerName)
                        } icon: {
                            Circle()
                                .fill(Color(hex: task.containerColor))
                                .frame(width: 6, height: 6)
                        }
                        if hasPriority || hasDueDate || hasEstimate { metaSeparator }
                    }

                    if hasPriority {
                        Label {
                            Text(task.priority.label)
                        } icon: {
                            Circle()
                                .fill(Theme.priorityColor(task.priority))
                                .frame(width: 6, height: 6)
                        }
                        if hasDueDate || hasEstimate { metaSeparator }
                    }

                    if hasDueDate {
                        Text("Due \(DateFormatters.relativeDate(from: task.dueDate))")
                        if hasEstimate { metaSeparator }
                    }

                    if let estimateLabel {
                        Text(estimateLabel)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            }

            Spacer(minLength: 16)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.cadencePlain)
            .help("Close focus session")
        }
        .padding(.leading, 28)
        .padding(.trailing, 18)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
    }

    private var metaSeparator: some View {
        Text("/")
            .foregroundStyle(Theme.dim.opacity(0.42))
    }
}

private struct FocusTimerPanel<Controls: View>: View {
    let clockDisplay: String
    let isRunning: Bool
    let accent: Color
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(isRunning ? "Running" : "Paused", systemImage: isRunning ? "timer" : "pause.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isRunning ? accent : Theme.dim)
                Spacer()
            }

            Spacer(minLength: 0)

            Text(clockDisplay)
                .font(.system(size: 82, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(isRunning ? Theme.text : Theme.muted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())
                .shadow(color: accent.opacity(isRunning ? 0.34 : 0), radius: 24)

            controls()

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(isRunning ? 0.72 : 0.24))
                .frame(height: 2)
        }
    }
}

private struct FocusIconButton: View {
    let systemName: String
    let foreground: Color
    let background: Color
    let size: CGFloat
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size > 44 ? 18 : 14, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
                .shadow(color: shadowColor, radius: shadowRadius)
        }
        .buttonStyle(.cadencePlain)
        .help(help)
    }
}

private struct FocusNotesPanel: View {
    let task: AppTask

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Task notes")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Capture the details you need while working.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider().background(Theme.borderSubtle)

            MarkdownEditor(text: Binding(
                get: { task.notes },
                set: { task.notes = $0 }
            ))
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
    }
}

private struct FocusSidebar: View {
    let task: AppTask
    let nextTasks: [AppTask]
    let onSelectTask: (AppTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    sidebarLabel("Session")
                    HStack(spacing: 8) {
                        statusChip(title: "Ready", color: Theme.green, icon: "checkmark.circle.fill")
                        if task.isRecurring {
                            statusChip(title: task.recurrenceRule.shortLabel, color: Theme.blue, icon: "arrow.clockwise")
                        }
                    }
                }

                Divider().background(Theme.borderSubtle)

                VStack(alignment: .leading, spacing: 9) {
                    sidebarLabel("Next up")
                    if nextTasks.isEmpty {
                        Text("No other ready tasks")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 7) {
                            ForEach(nextTasks) { nextTask in
                                FocusSidebarTaskRow(task: nextTask) {
                                    onSelectTask(nextTask)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)

            Divider().background(Theme.borderSubtle)

            SchedulePanel(presentation: .compact)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)
        }
    }

    private func sidebarLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .textCase(.uppercase)
    }

    private func statusChip(title: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct FocusSidebarTaskRow: View {
    let task: AppTask
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(Color(hex: task.containerColor))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 24, height: 24)
                    .background(Theme.blue.opacity(0.11))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.surfaceElevated.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .help("Focus this task")
    }

    private var detail: String {
        FocusSessionSupport.sidebarDetail(for: task, todayKey: DateFormatters.todayKey(), fallback: "Ready")
    }
}

// MARK: - Idle Focus Surface

private struct FocusIdleHero: View {
    let clockDisplay: String
    let onPickTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to focus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Choose a task and start a clean session.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }

            Spacer(minLength: 0)

            Text(clockDisplay)
                .font(.system(size: 78, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Button(action: onPickTask) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Pick a task")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)
            .help("Pick a task to focus on")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
    }
}

// MARK: - Log Session Popover

private struct LogSessionPopover: View {
    let task: AppTask
    let onLog: (Int, Int, Bool) -> Void
    let onDiscard: () -> Void

    @State private var logHours: Int
    @State private var logMinutes: Int
    @State private var markComplete: Bool = false

    init(task: AppTask, elapsedSeconds: Int, onLog: @escaping (Int, Int, Bool) -> Void, onDiscard: @escaping () -> Void) {
        self.task = task
        self.onLog = onLog
        self.onDiscard = onDiscard
        let totalMins = (elapsedSeconds + 59) / 60
        _logHours = State(initialValue: totalMins / 60)
        _logMinutes = State(initialValue: totalMins % 60)
    }

    private var totalMinutes: Int { logHours * 60 + logMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Log Session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: task.containerColor))
                        .frame(width: 6, height: 6)
                    Text(task.title)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 14) {
                // Time fields
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time to log")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    HStack(spacing: 10) {
                        timeField(label: "h", value: $logHours)
                        timeField(label: "min", value: $logMinutes)
                        Spacer()
                    }
                }

                Divider().background(Theme.borderSubtle)

                // Complete toggle
                HStack {
                    Toggle(isOn: $markComplete) {
                        Text("Mark task as complete")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(Theme.borderSubtle)

            // Footer buttons
            HStack(spacing: 8) {
                Button("Discard") { onDiscard() }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Spacer()

                Button {
                    onLog(logHours, max(0, logMinutes), markComplete)
                } label: {
                    Text(totalMinutes > 0 ? "Log \(formatTotal())" : "Log")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.cadencePlain)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 260)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func timeField(label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            TextField("0", value: value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
    }

    private func formatTotal() -> String {
        if logHours > 0 && logMinutes > 0 { return "\(logHours)h \(logMinutes)m" }
        if logHours > 0 { return "\(logHours)h" }
        return "\(logMinutes)m"
    }
}

// MARK: - Task Picker Popover

private struct FocusTaskPicker: View {
    let tasks: [AppTask]
    let onSelect: (AppTask) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Pick a Task")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(12)
            Divider().background(Theme.borderSubtle)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tasks) { task in
                        Button { onSelect(task) } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: task.containerColor))
                                    .frame(width: 6, height: 6)
                                Text(task.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
                                if label != "-/-" {
                                    Text(label)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.dim)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 260, height: 320)
        .background(Theme.surface)
    }
}

private struct FocusTaskBucketCard: View {
    let title: String
    let subtitle: String
    let accent: Color
    let tasks: [AppTask]
    let onSelect: (AppTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }

            ScrollView {
                VStack(spacing: 8) {
                    if tasks.isEmpty {
                        Text("Nothing here right now")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(tasks) { task in
                            Button {
                                onSelect(task)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: task.containerColor))
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title.isEmpty ? "Untitled" : task.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.text)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(1)
                                        Text(detail(for: task))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.dim)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(1)
                                    }

                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.blue)
                                        .frame(width: 28, height: 28)
                                        .background(Theme.blue.opacity(0.11))
                                        .clipShape(Circle())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(Theme.surfaceElevated.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.cadencePlain)
                            .help("Focus this task")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func detail(for task: AppTask) -> String {
        FocusSessionSupport.sidebarDetail(for: task, todayKey: DateFormatters.todayKey(), fallback: "Ready to focus")
    }
}
#endif
