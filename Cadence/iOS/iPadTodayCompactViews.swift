#if os(iOS)
import SwiftUI

struct iOSCompactTodayView: View {
    let todayTasks: [AppTask]
    let completedTodayTasks: [AppTask]
    let compactScheduleTasks: [AppTask]
    let todayTaskGroups: [CadenceTodayTaskGroup]
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool
    @Binding var newTitle: String
    @Binding var saveError: String?
    let captureTodayTask: () -> Void
    #if DEBUG
    let sampleDataStatus: String?
    let seedSampleData: () -> Void
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                header
                stats
                captureCard
                taskSections

                if !compactScheduleTasks.isEmpty {
                    iOSCompactTodaySchedulePreview(tasks: compactScheduleTasks)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 32, height: 32)
                .background(Theme.amber.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.amber.opacity(0.22), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatters.longDate.string(from: Date()))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text("Today")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(todayTasks.count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.blue.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            iOSCompactTodayMetric(
                value: "\(todayTasks.count)",
                label: "Active",
                systemImage: "checklist",
                tint: Theme.blue
            )
            Divider()
                .frame(height: 22)
                .overlay(Theme.borderSubtle.opacity(0.6))
            iOSCompactTodayMetric(
                value: "\(compactScheduleTasks.count)",
                label: "Timed",
                systemImage: "clock.fill",
                tint: Theme.purple
            )
            Divider()
                .frame(height: 22)
                .overlay(Theme.borderSubtle.opacity(0.6))
            iOSCompactTodayMetric(
                value: "\(completedTodayTasks.count)",
                label: "Done",
                systemImage: "checkmark.circle.fill",
                tint: Theme.green
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            iOSTaskCaptureBar(
                placeholder: "Add a task...",
                title: $newTitle,
                action: captureTodayTask
            )

            if let saveError {
                iOSInlineErrorBanner(message: saveError) {
                    self.saveError = nil
                }
            }

            iOSTaskViewOptionsBar(
                sortMode: $sortMode,
                showCompleted: $showCompleted,
                completedCount: completedTodayTasks.count
            )
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var taskSections: some View {
        if todayTasks.isEmpty && (!showCompleted || completedTodayTasks.isEmpty) {
            iOSEmptyPanel(
                systemImage: "checkmark.circle",
                title: "Nothing planned",
                subtitle: "Add a task above or schedule one from Inbox."
            )
            .frame(minHeight: 190)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
            }

            #if DEBUG
            iOSCompactSampleDataCard(
                status: sampleDataStatus,
                action: seedSampleData
            )
            #endif
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(todayTaskGroups, id: \.title) { group in
                    iOSCompactTodayTaskGroup(
                        group: group,
                        color: color(for: group.kind)
                    )
                }

                if showCompleted && !completedTodayTasks.isEmpty {
                    iOSCompactCompletedTasks(tasks: Array(completedTodayTasks.prefix(12)))
                }
            }
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
        }
    }

    private func color(for groupKind: CadenceTodayTaskGroupKind) -> Color {
        switch groupKind {
        case .overdue: return Theme.red
        case .dueToday: return Theme.amber
        case .plannedToday: return Theme.blue
        }
    }
}

#if DEBUG
private struct iOSCompactSampleDataCard: View {
    let status: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 34, height: 34)
                .background(Theme.amber.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(status ?? "Need realistic rows?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                Text("Seed local simulator tasks for Today, Inbox, and Timeline.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityLabel("Seed sample tasks")
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
        }
    }
}
#endif

private struct iOSCompactTodayMetric: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct iOSCompactTodayTaskGroup: View {
    let group: CadenceTodayTaskGroup
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                iOSTaskSectionHeader(title: group.title, color: color)
                Spacer()
                Text("\(group.tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.11))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(group.tasks) { task in
                    iOSTaskRow(task: task)
                }
            }
        }
    }
}

private struct iOSCompactCompletedTasks: View {
    let tasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                iOSTaskSectionHeader(title: "Completed Today", color: Theme.green)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.green.opacity(0.11))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(tasks) { task in
                    iOSTaskRow(task: task)
                        .opacity(0.62)
                }
            }
        }
    }
}

private struct iOSCompactTodaySchedulePreview: View {
    let tasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .textCase(.uppercase)
                        .kerning(0.8)
                    Text("Timeline")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                }

                Spacer()

                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.purple.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    iOSCompactScheduleTaskRow(task: task)
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct iOSCompactScheduleTaskRow: View {
    let task: AppTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(startLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.purple)
                    .monospacedDigit()
                    .lineLimit(1)

                if !endLabel.isEmpty {
                    Text(endLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.purple.opacity(0.72))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Untitled Task" : task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(task.containerName.isEmpty ? "Inbox" : task.containerName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.surfaceElevated.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Theme.purple)
                .frame(width: 3)
        }
    }

    private var startLabel: String {
        TimeFormatters.timeString(from: task.scheduledStartMin)
    }

    private var endLabel: String {
        guard task.scheduledEndMin > task.scheduledStartMin else { return "" }
        return TimeFormatters.timeString(from: task.scheduledEndMin)
    }
}
#endif
