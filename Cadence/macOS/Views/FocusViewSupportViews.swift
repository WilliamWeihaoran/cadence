#if os(macOS)
import SwiftUI

private struct FocusSurfaceHeader<Metadata: View>: View {
    let eyebrow: String
    let title: String
    let onClose: () -> Void
    @ViewBuilder let metadata: () -> Metadata

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)

                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                metadata()
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
}

private struct FocusMetaSeparator: View {
    var body: some View {
        Text("/")
            .foregroundStyle(Theme.dim.opacity(0.42))
    }
}

struct FocusSessionHeader: View {
    let task: AppTask
    let estimateLabel: String?
    let onClose: () -> Void

    var body: some View {
        let hasContainer = !task.containerName.isEmpty
        let hasPriority = task.priority != .none
        let hasDueDate = !task.dueDate.isEmpty
        let hasEstimate = estimateLabel != nil

        FocusSurfaceHeader(
            eyebrow: "Focus Session",
            title: task.title.isEmpty ? "Untitled Task" : task.title,
            onClose: onClose
        ) {
            HStack(spacing: 7) {
                if hasContainer {
                    Label {
                        Text(task.containerName)
                    } icon: {
                        Circle()
                            .fill(Color(hex: task.containerColor))
                            .frame(width: 6, height: 6)
                    }
                    if hasPriority || hasDueDate || hasEstimate { FocusMetaSeparator() }
                }

                if hasPriority {
                    Label {
                        Text(task.priority.label)
                    } icon: {
                        Circle()
                            .fill(Theme.priorityColor(task.priority))
                            .frame(width: 6, height: 6)
                    }
                    if hasDueDate || hasEstimate { FocusMetaSeparator() }
                }

                if hasDueDate {
                    Text("Due \(DateFormatters.relativeDate(from: task.dueDate))")
                    if hasEstimate { FocusMetaSeparator() }
                }

                if let estimateLabel {
                    Text(estimateLabel)
                }
            }
        }
    }
}

struct FocusBundleHeader: View {
    let bundle: TaskBundle
    let selectedCount: Int
    let onClose: () -> Void

    var body: some View {
        FocusSurfaceHeader(
            eyebrow: "Bundle Focus",
            title: bundle.displayTitle,
            onClose: onClose
        ) {
            HStack(spacing: 7) {
                Label {
                    Text(TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin))
                } icon: {
                    Image(systemName: "tray.full")
                        .font(.system(size: 10, weight: .semibold))
                }
                FocusMetaSeparator()
                Text("\(selectedCount) selected")
                FocusMetaSeparator()
                Text("\(bundle.sortedTasks.count) total")
                if bundle.totalEstimatedMinutes > 0 {
                    FocusMetaSeparator()
                    Text("\(bundle.totalEstimatedMinutes)m estimated")
                }
            }
        }
    }
}

struct FocusTimerPanel<Controls: View>: View {
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

struct FocusIconButton: View {
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

struct FocusNotesPanel: View {
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

private struct FocusStatusChip: View {
    let title: String
    let color: Color
    let icon: String

    var body: some View {
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

private struct FocusSidebarShell<SessionSummary: View>: View {
    let nextTasks: [AppTask]
    let onSelectTask: (AppTask) -> Void
    @ViewBuilder let sessionSummary: () -> SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    sidebarLabel("Session")
                    sessionSummary()
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
}

struct FocusSidebar: View {
    let task: AppTask
    let nextTasks: [AppTask]
    let onSelectTask: (AppTask) -> Void

    var body: some View {
        FocusSidebarShell(nextTasks: nextTasks, onSelectTask: onSelectTask) {
            HStack(spacing: 8) {
                FocusStatusChip(title: "Ready", color: Theme.green, icon: "checkmark.circle.fill")
                if task.isRecurring {
                    FocusStatusChip(title: task.recurrenceRule.shortLabel, color: Theme.blue, icon: "arrow.clockwise")
                }
            }
        }
    }
}

struct FocusSidebarTaskRow: View {
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

struct FocusBundleTasksPanel: View {
    let bundle: TaskBundle
    @Binding var selectedTaskIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bundle tasks")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Selected tasks receive logged time from this session.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(spacing: 8) {
                    if bundle.sortedTasks.isEmpty {
                        Text("This bundle is empty.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    } else {
                        ForEach(Array(bundle.sortedTasks.enumerated()), id: \.element.id) { index, task in
                            FocusBundleTaskRow(
                                task: task,
                                isSelected: selectedTaskIDs.contains(task.id),
                                canMoveUp: index > 0,
                                canMoveDown: index < bundle.sortedTasks.count - 1,
                                onToggle: { toggle(task) },
                                onMove: { SchedulingActions.moveTaskInBundle(task, direction: $0) },
                                onRemove: {
                                    selectedTaskIDs.remove(task.id)
                                    SchedulingActions.removeTaskFromBundle(task)
                                }
                            )
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
    }

    private func toggle(_ task: AppTask) {
        if selectedTaskIDs.contains(task.id) {
            selectedTaskIDs.remove(task.id)
        } else {
            selectedTaskIDs.insert(task.id)
        }
    }
}

struct FocusBundleTaskRow: View {
    let task: AppTask
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: () -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Theme.green : Theme.dim)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .help(isSelected ? "Exclude from time log" : "Include in time log")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .lineLimit(1)
                Text(TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if task.isDone {
                Text("Done")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.green)
            }

            focusRowIconButton("chevron.up", isDisabled: !canMoveUp) { onMove(-1) }
            focusRowIconButton("chevron.down", isDisabled: !canMoveDown) { onMove(1) }
            focusRowIconButton("xmark", isDisabled: false, action: onRemove)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surfaceElevated.opacity(isSelected ? 0.95 : 0.66))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Theme.amber.opacity(0.18) : Color.clear, lineWidth: 1)
        }
    }

    private func focusRowIconButton(_ systemName: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isDisabled ? Theme.dim.opacity(0.35) : Theme.dim)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .disabled(isDisabled)
    }
}

struct FocusBundleSidebar: View {
    let bundle: TaskBundle
    let nextTasks: [AppTask]
    let onSelectTask: (AppTask) -> Void

    var body: some View {
        FocusSidebarShell(nextTasks: nextTasks, onSelectTask: onSelectTask) {
            HStack(spacing: 8) {
                FocusStatusChip(title: "Bundle", color: Theme.amber, icon: "tray.full")
                FocusStatusChip(title: "\(bundle.sortedTasks.count) tasks", color: Theme.blue, icon: "checklist")
            }
        }
    }
}

struct FocusIdleHero: View {
    let clockDisplay: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to focus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Search below and start a clean session.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }

            Spacer(minLength: 0)

            Text(clockDisplay)
                .font(.system(size: 64, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
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

struct LogSessionPopover: View {
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

struct BundleLogSessionPopover: View {
    let bundle: TaskBundle
    let selectedTasks: [AppTask]
    let onLog: (Int, Int) -> Void
    let onDiscard: () -> Void

    @State private var logHours: Int
    @State private var logMinutes: Int

    init(
        bundle: TaskBundle,
        elapsedSeconds: Int,
        selectedTasks: [AppTask],
        onLog: @escaping (Int, Int) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.bundle = bundle
        self.selectedTasks = selectedTasks
        self.onLog = onLog
        self.onDiscard = onDiscard
        let totalMins = (elapsedSeconds + 59) / 60
        _logHours = State(initialValue: totalMins / 60)
        _logMinutes = State(initialValue: totalMins % 60)
    }

    private var totalMinutes: Int { logHours * 60 + logMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Log Bundle Session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(selectedTasks.count) selected tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 14) {
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

                Text("Time is distributed by each task's estimate.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            .padding(16)

            Divider().background(Theme.borderSubtle)

            HStack {
                Button("Discard", action: onDiscard)
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                Spacer()
                Button {
                    onLog(logHours, logMinutes)
                } label: {
                    Text(totalMinutes > 0 ? "Log \(formatTotal())" : "Log")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.cadencePlain)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selectedTasks.isEmpty ? Theme.dim.opacity(0.35) : Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .disabled(selectedTasks.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 270)
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

enum FocusPickItem: Identifiable {
    case task(AppTask)
    case bundle(TaskBundle)

    var id: String {
        switch self {
        case .task(let task): return "task-\(task.id.uuidString)"
        case .bundle(let bundle): return "bundle-\(bundle.id.uuidString)"
        }
    }

    static func filtered(tasks: [AppTask], bundles: [TaskBundle], query: String, todayKey: String) -> [FocusPickItem] {
        let activeBundles = bundles
            .filter { !$0.sortedTasks.isEmpty && !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.dateKey != rhs.dateKey {
                    return bundleDateRank(lhs.dateKey, todayKey: todayKey) < bundleDateRank(rhs.dateKey, todayKey: todayKey)
                }
                if lhs.startMin != rhs.startMin {
                    return lhs.startMin < rhs.startMin
                }
                return lhs.createdAt > rhs.createdAt
            }

        let items = tasks.map(FocusPickItem.task) + activeBundles.map(FocusPickItem.bundle)
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            return Array(items.prefix(18))
        }

        return items.filter { $0.matches(cleanedQuery) }
    }

    private static func bundleDateRank(_ dateKey: String, todayKey: String) -> Int {
        if dateKey == todayKey { return 0 }
        if dateKey.isEmpty { return 2 }
        return dateKey > todayKey ? 1 : 3
    }

    private func matches(_ query: String) -> Bool {
        let needle = query.lowercased()
        return searchText.lowercased().contains(needle)
    }

    private var searchText: String {
        switch self {
        case .task(let task):
            return [
                task.title,
                task.containerName,
                task.priority.label,
                task.dueDate,
                task.scheduledDate
            ].joined(separator: " ")
        case .bundle(let bundle):
            return ([bundle.displayTitle, bundle.dateKey] + bundle.sortedTasks.map(\.title)).joined(separator: " ")
        }
    }
}

struct FocusPickSessionCard: View {
    let title: String
    let subtitle: String
    @Binding var searchText: String
    let items: [FocusPickItem]
    let onSelectTask: (AppTask) -> Void
    let onSelectBundle: (TaskBundle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            searchBar

            ScrollView {
                VStack(spacing: 8) {
                    if items.isEmpty {
                        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nothing ready right now" : "No matching tasks or bundles")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(items) { item in
                            FocusPickItemRow(item: item) {
                                switch item {
                                case .task(let task):
                                    onSelectTask(task)
                                case .bundle(let bundle):
                                    onSelectBundle(bundle)
                                }
                            }
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
                .stroke(Theme.blue.opacity(0.18), lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
            TextField("Search tasks and bundles", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.cadencePlain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.85), lineWidth: 1)
        }
    }
}

private struct FocusPickItemRow: View {
    let item: FocusPickItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leadingIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }

                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceElevated.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .help(helpText)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch item {
        case .task(let task):
            Circle()
                .fill(Color(hex: task.containerColor))
                .frame(width: 8, height: 8)
        case .bundle:
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 18, height: 18)
        }
    }

    private var title: String {
        switch item {
        case .task(let task):
            return task.title.isEmpty ? "Untitled Task" : task.title
        case .bundle(let bundle):
            return bundle.displayTitle
        }
    }

    private var detail: String {
        switch item {
        case .task(let task):
            return FocusSessionSupport.sidebarDetail(for: task, todayKey: DateFormatters.todayKey(), fallback: "Ready to focus")
        case .bundle(let bundle):
            var parts = ["Bundle", "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")"]
            if !bundle.dateKey.isEmpty {
                parts.append(bundle.dateKey == DateFormatters.todayKey() ? "Today" : DateFormatters.relativeDate(from: bundle.dateKey))
            }
            parts.append(TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin))
            if bundle.totalEstimatedMinutes > 0 {
                parts.append("\(bundle.totalEstimatedMinutes)m tasks")
            }
            return parts.joined(separator: " / ")
        }
    }

    private var tint: Color {
        switch item {
        case .task:
            return Theme.blue
        case .bundle:
            return Theme.amber
        }
    }

    private var helpText: String {
        switch item {
        case .task:
            return "Focus this task"
        case .bundle:
            return "Focus this bundle"
        }
    }
}
#endif
