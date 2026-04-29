#if os(macOS)
import SwiftUI
import SwiftData
import Combine

struct FocusView: View {
    @Environment(FocusManager.self) private var focusManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    @State private var noteContent = ""
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
        allTasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted(by: focusRanking)
    }

    // MARK: - Active layout

    @ViewBuilder
    private func activeLayout(task: AppTask) -> some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────────
            VStack(spacing: 0) {
                // Meta row
                HStack(spacing: 6) {
                    if !task.containerName.isEmpty {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: task.containerColor))
                                .frame(width: 6, height: 6)
                            Text(task.containerName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.dim)
                        }
                        metaDot
                    }
                    if task.priority != .none {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Theme.priorityColor(task.priority))
                                .frame(width: 5, height: 5)
                            Text(task.priority.label)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }
                        metaDot
                    }
                    if !task.dueDate.isEmpty {
                        Text("Due \(DateFormatters.relativeDate(from: task.dueDate))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                        metaDot
                    }
                    let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
                    if label != "-/-" {
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Button { focusManager.activeTask = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 24, height: 24)
                            .background(Theme.surfaceElevated)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.cadencePlain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Title + clock (centered) with controls on the right
                HStack(alignment: .center, spacing: 0) {
                    // Invisible mirror of the controls column keeps the clock truly centered
                    controlsColumn(task: task)
                        .opacity(0)
                        .allowsHitTesting(false)

                    // Center: title + clock
                    VStack(spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 8)

                        Text(clockDisplay)
                            .font(.system(size: 84, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(focusManager.isRunning ? Theme.text : Theme.muted)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .shadow(
                                color: Color(hex: task.containerColor).opacity(focusManager.isRunning ? 0.4 : 0),
                                radius: 28
                            )
                    }
                    .frame(maxWidth: .infinity)

                    // Right: controls
                    controlsColumn(task: task)
                        .padding(.trailing, 28)
                }
                .padding(.vertical, 20)
            }
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            FocusContextStrip(
                task: task,
                nextTasks: Array(readyTasks.filter { $0.id != task.id }.prefix(3))
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider().background(Theme.borderSubtle)

            // ── Notes + Schedule ──────────────────────────────────────────
            HSplitView {
                MarkdownEditorView(text: $noteContent)
                    .frame(minWidth: 280)

                SchedulePanel()
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            }
        }
    }

    @ViewBuilder
    private func controlsColumn(task: AppTask) -> some View {
        VStack(spacing: 16) {
            Button { focusManager.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 38, height: 38)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.cadencePlain)

            Button { focusManager.isRunning.toggle() } label: {
                Image(systemName: focusManager.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color(hex: task.containerColor))
                    .clipShape(Circle())
                    .shadow(color: Color(hex: task.containerColor).opacity(0.5), radius: 10)
            }
            .buttonStyle(.cadencePlain)

            Button {
                focusManager.isRunning = false
                showLogSheet = true
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14))
                    .foregroundStyle(focusManager.elapsed > 0 ? Theme.green : Theme.muted)
                    .frame(width: 38, height: 38)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.cadencePlain)
            .help("Log session")
            .popover(isPresented: $showLogSheet, arrowEdge: .leading) {
                LogSessionPopover(
                    task: task,
                    elapsedSeconds: focusManager.elapsed,
                    onLog: { hours, minutes, complete in
                        logSession(hours: hours, minutes: minutes, complete: complete, task: task)
                    },
                    onDiscard: {
                        focusManager.reset()
                        showLogSheet = false
                    }
                )
            }
        }
        .frame(width: 72)
    }

    // MARK: - Idle layout

    private var idleLayout: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            Text(clockDisplay)
                .font(.system(size: 84, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()

            Button { showTaskPicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                    Text("Pick a task to focus on")
                        .font(.system(size: 14))
                }
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle))
            }
            .buttonStyle(.cadencePlain)

            FocusTaskBucketCard(
                title: "Ready",
                subtitle: "Best next tasks",
                accent: Theme.blue,
                tasks: Array(readyTasks.prefix(6)),
                onSelect: { focusManager.startFocus(task: $0) }
            )
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Log session action

    private func logSession(hours: Int, minutes: Int, complete: Bool, task: AppTask) {
        let totalMinutes = hours * 60 + minutes
        if totalMinutes > 0 {
            task.actualMinutes += totalMinutes
            // Propagate to goal logged hours
            if let goal = task.goal, goal.progressType == .hours {
                goal.loggedHours += Double(totalMinutes) / 60.0
            }
            // Propagate to project or area
            if let project = task.project {
                project.loggedMinutes += totalMinutes
            } else if let area = task.area {
                area.loggedMinutes += totalMinutes
            }
        }
        if complete {
            TaskWorkflowService.markDone(task, in: modelContext)
        }
        focusManager.reset()
        showLogSheet = false
    }

    // MARK: - Helpers

    private var metaDot: some View {
        Text("·")
            .font(.system(size: 11))
            .foregroundStyle(Theme.dim.opacity(0.45))
    }

    private var clockDisplay: String {
        let secs = focusManager.elapsed
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func focusRanking(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let lhsScore = focusScore(for: lhs)
        let rhsScore = focusScore(for: rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.createdAt > rhs.createdAt
    }

    private func focusScore(for task: AppTask) -> Int {
        var score = 0
        if task.scheduledDate == todayKey { score += 4 }
        if task.dueDate == todayKey { score += 3 }
        if !task.dueDate.isEmpty && task.dueDate < todayKey { score += 5 }
        switch task.priority {
        case .high: score += 3
        case .medium: score += 2
        case .low: score += 1
        case .none: break
        }
        if task.actualMinutes == 0 { score += 1 }
        return score
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

private struct FocusContextStrip: View {
    let task: AppTask
    let nextTasks: [AppTask]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session context")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                HStack(spacing: 8) {
                    if task.isRecurring {
                        statusChip(title: task.recurrenceRule.shortLabel, color: Theme.blue, icon: "arrow.clockwise")
                    }
                    statusChip(title: "Ready", color: Theme.green, icon: "checkmark.circle.fill")
                }
            }

            Divider().frame(height: 42)

            VStack(alignment: .leading, spacing: 8) {
                Text("Next up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                if nextTasks.isEmpty {
                    Text("No other ready tasks")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                } else {
                    HStack(spacing: 8) {
                        ForEach(nextTasks) { task in
                            Text(task.title.isEmpty ? "Untitled" : task.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Theme.surfaceElevated)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private func statusChip(title: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
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
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

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
                                    Text(detail(for: task))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.dim)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Theme.surfaceElevated.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func detail(for task: AppTask) -> String {
        if task.scheduledDate == DateFormatters.todayKey() {
            return "Scheduled today"
        }
        if task.dueDate == DateFormatters.todayKey() {
            return "Due today"
        }
        if !task.containerName.isEmpty {
            return task.containerName
        }
        return "Ready to focus"
    }
}
#endif
