#if os(macOS)
import SwiftUI

/// One-line task detail shared by the focus rows and the bundle task rows. Renders as a single
/// `Text` so it still collapses under `lineLimit(1)`, while tinting only the due segment — an
/// overdue task should read red on the deadline, not on the scheduling note next to it.
struct TaskDetailLineLabel: View {
    let parts: CadenceTaskDetailLine
    var fontSize: CGFloat = 10

    init(parts: CadenceTaskDetailLine, fontSize: CGFloat = 10) {
        self.parts = parts
        self.fontSize = fontSize
    }

    init(task: AppTask, fallback: String, fontSize: CGFloat = 10) {
        self.init(
            parts: CadenceFocusSupport.sidebarDetailParts(
                for: task,
                todayKey: DateFormatters.todayKey(),
                fallback: fallback
            ),
            fontSize: fontSize
        )
    }

    var body: some View {
        composed
            .font(.system(size: fontSize))
            .lineLimit(1)
    }

    /// One `Text`, not concatenated ones: `lineLimit(1)` has to collapse the whole line, and only
    /// the due segment is tinted so an overdue task cannot make its scheduling half look urgent too.
    private var composed: Text {
        var line = AttributedString()

        if let lead = parts.lead {
            var segment = AttributedString(lead)
            segment.foregroundColor = Theme.dim
            line += segment
        }

        if let due = parts.due {
            if !line.characters.isEmpty {
                var separator = AttributedString(" / ")
                separator.foregroundColor = Theme.dim
                line += separator
            }
            var segment = AttributedString(due)
            segment.foregroundColor = parts.isOverdue ? Theme.red : Theme.dim
            line += segment
        }

        return Text(line)
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
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(Color(hex: task.containerColor).opacity(0.14))
                    Circle()
                        .fill(Color(hex: task.containerColor))
                        .frame(width: 6, height: 6)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    TaskDetailLineLabel(task: task, fallback: "Ready")
                }

                Spacer(minLength: 8)

                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 22, height: 22)
                    .background(Theme.blue.opacity(isHovered ? 0.15 : 0.08))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.surfaceElevated.opacity(isHovered ? 0.78 : 0.52))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .help("Focus this task")
        .onHover { isHovered = $0 }
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
