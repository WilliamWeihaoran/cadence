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

#endif
