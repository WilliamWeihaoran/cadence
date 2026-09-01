#if os(macOS)
import SwiftUI

// `TaskDetailLineLabel` moved to `Shared/Components/CadenceTaskDetailLineLabel.swift`, unchanged,
// as `CadenceTaskDetailLineLabel`. It contained no AppKit and never had; sitting inside this file's
// `#if os(macOS)` is the whole reason iOS's bundle member row wrote its own secondary line, and
// that copy had no due date in it.

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
        SectionEyebrowLabel(text: title)
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
                    Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    CadenceTaskDetailLineLabel(task: task, fallback: "Ready")
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
        .cadenceControlLabel("Focus this task")
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
