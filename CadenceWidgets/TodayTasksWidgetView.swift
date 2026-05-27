import AppIntents
import SwiftUI
import WidgetKit

private struct CadenceTodayTaskStatusPresentation {
    let label: String
    let tint: Color
}

private extension CadenceTodayWidgetTask {
    func widgetStatus(for todayKey: String) -> CadenceTodayTaskStatusPresentation {
        if !dueDate.isEmpty && dueDate < todayKey {
            return CadenceTodayTaskStatusPresentation(
                label: "Overdue",
                tint: Color(red: 1.0, green: 0.45, blue: 0.41)
            )
        }
        if dueDate == todayKey {
            return CadenceTodayTaskStatusPresentation(
                label: "Due today",
                tint: Color(red: 1.0, green: 0.72, blue: 0.28)
            )
        }
        return CadenceTodayTaskStatusPresentation(
            label: "Scheduled",
            tint: Color(red: 0.39, green: 0.71, blue: 1.0)
        )
    }
}

struct TodayTasksWidgetView: View {
    let entry: TodayTasksWidgetEntry

    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            case .systemLarge:
                largeLayout
            case .systemExtraLarge:
                extraLargeLayout
            default:
                mediumLayout
            }
        }
        .cadenceWidgetBackground([
            Color(red: 0.08, green: 0.10, blue: 0.15),
            Color(red: 0.12, green: 0.14, blue: 0.21),
        ])
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .leading)
            } else if let task = entry.snapshot.tasks.first {
                primaryTaskCard(task: task, compact: true)
            } else {
                emptyState(alignment: .leading)
            }
        }
        .padding(14)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .center)
            } else if entry.snapshot.tasks.isEmpty {
                emptyState(alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.snapshot.tasks.prefix(3)) { task in
                        taskRow(task, dense: false)
                    }
                }
            }
        }
        .padding(14)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .center)
            } else if entry.snapshot.tasks.isEmpty {
                emptyState(alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    if let task = entry.snapshot.tasks.first {
                        primaryTaskCard(task: task, compact: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    summaryPanel
                        .frame(width: 146)
                }

                taskStackCard(
                    title: "Actionable queue",
                    subtitle: queueSubtitle,
                    tasks: Array(entry.snapshot.tasks.prefix(6))
                )

                footerBar(label: "Open full Today view")
            }
        }
        .padding(16)
    }

    private var extraLargeLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .center)
            } else if entry.snapshot.tasks.isEmpty {
                emptyState(alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let task = entry.snapshot.tasks.first {
                            primaryTaskCard(task: task, compact: false)
                        }

                        focusStrip
                        footerBar(label: "Open Today in Cadence")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .top, spacing: 12) {
                        taskColumnCard(
                            title: "On deck",
                            tasks: leadingColumnTasks
                        )
                        taskColumnCard(
                            title: "Then",
                            tasks: trailingColumnTasks
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
    }

    private var summaryPanel: some View {
        CadenceWidgetPanel {
            VStack(alignment: .leading, spacing: 10) {
                metricTile(
                    title: "Overdue",
                    value: entry.snapshot.overdueCount,
                    tint: Color(red: 1.0, green: 0.45, blue: 0.41)
                )
                metricTile(
                    title: "Due today",
                    value: entry.snapshot.dueTodayCount,
                    tint: Color(red: 1.0, green: 0.72, blue: 0.28)
                )
                metricTile(
                    title: "Scheduled",
                    value: entry.snapshot.scheduledTodayCount,
                    tint: Color(red: 0.39, green: 0.71, blue: 1.0)
                )
            }
        }
    }

    private var focusStrip: some View {
        HStack(spacing: 10) {
            focusTile(
                title: "Now",
                value: topStatus.label,
                tint: topStatus.tint
            )
            focusTile(
                title: "Visible",
                value: "\(entry.snapshot.tasks.count)",
                tint: .white
            )
            focusTile(
                title: "Total",
                value: "\(entry.snapshot.totalCount)",
                tint: Color(red: 0.72, green: 0.86, blue: 1.0)
            )
        }
    }

    private var widgetHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 10)
                Text("\(entry.snapshot.totalCount)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                if entry.snapshot.isUnavailable {
                    CadenceWidgetBadge(
                        text: "unavailable",
                        tint: Color(red: 1.0, green: 0.72, blue: 0.28)
                    )
                } else {
                    CadenceWidgetBadge(
                        text: "\(entry.snapshot.overdueCount) overdue",
                        tint: Color(red: 1.0, green: 0.45, blue: 0.41)
                    )
                    CadenceWidgetBadge(
                        text: "\(entry.snapshot.dueTodayCount) due",
                        tint: Color(red: 1.0, green: 0.72, blue: 0.28)
                    )
                    CadenceWidgetBadge(
                        text: "\(entry.snapshot.scheduledTodayCount) scheduled",
                        tint: Color(red: 0.39, green: 0.71, blue: 1.0)
                    )
                }
            }
        }
    }

    private func primaryTaskCard(task: CadenceTodayWidgetTask, compact: Bool) -> some View {
        let status = task.widgetStatus(for: entry.snapshot.dateKey)

        return VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(compact ? "Top task" : "Priority now")
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    Link(destination: task.deepLinkURL) {
                        Text(task.title)
                            .font(.system(size: compact ? 14 : 18, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(compact ? 3 : 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !compact {
                    completeButton(taskID: task.id, size: 21)
                }
            }

            HStack(spacing: 8) {
                statusPill(status)
                if !task.containerName.isEmpty {
                    containerPill(task.containerName)
                }
                Spacer(minLength: 8)
                if compact {
                    completeButton(taskID: task.id, size: 18)
                }
            }
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color(red: 0.21, green: 0.31, blue: 0.42).opacity(0.26),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 20, style: .continuous))
    }

    private func taskStackCard(
        title: String,
        subtitle: String,
        tasks: [CadenceTodayWidgetTask]
    ) -> some View {
        CadenceWidgetPanel {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        taskRow(task, dense: true)
                    }
                }
            }
        }
    }

    private func taskColumnCard(
        title: String,
        tasks: [CadenceTodayWidgetTask]
    ) -> some View {
        CadenceWidgetPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                if tasks.isEmpty {
                    Text("No more tasks in this lane.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 8) {
                        ForEach(tasks) { task in
                            taskRow(task, dense: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func taskRow(_ task: CadenceTodayWidgetTask, dense: Bool) -> some View {
        let status = task.widgetStatus(for: entry.snapshot.dateKey)

        return HStack(spacing: dense ? 8 : 10) {
            Link(destination: task.deepLinkURL) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: dense ? 12 : 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(dense ? 2 : 3)

                    HStack(spacing: 6) {
                        statusPill(status)
                        if !task.containerName.isEmpty {
                            Text(task.containerName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            completeButton(taskID: task.id, size: dense ? 16 : 17)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, dense ? 9 : 10)
        .background(Color.white.opacity(dense ? 0.05 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func footerBar(label: String) -> some View {
        HStack(spacing: 10) {
            Text("\(entry.snapshot.totalCount) tasks in view")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
            Spacer(minLength: 8)
            CadenceWidgetFooterLink(label: label, url: entry.snapshot.todayURL)
        }
    }

    private func metricTile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            Text("\(value)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func focusTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyState(alignment: HorizontalAlignment) -> some View {
        CadenceWidgetStateCard(
            title: "Nothing planned today",
            message: alignment == .leading ? "Your hot path is clear right now." : nil,
            actionLabel: "Open Today in Cadence",
            actionURL: entry.snapshot.todayURL,
            alignment: alignment
        )
        .padding(.vertical, 10)
    }

    private func unavailableState(alignment: HorizontalAlignment) -> some View {
        CadenceWidgetStateCard(
            title: "Widget needs Cadence",
            message: entry.snapshot.statusMessage,
            actionLabel: "Open Cadence",
            actionURL: entry.snapshot.todayURL,
            alignment: alignment
        )
        .padding(.vertical, 10)
    }

    private func completeButton(taskID: UUID, size: CGFloat) -> some View {
        Button(intent: CompleteTaskIntent(taskID: taskID)) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color(red: 0.35, green: 0.89, blue: 0.56))
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ status: CadenceTodayTaskStatusPresentation) -> some View {
        CadenceWidgetBadge(text: status.label, tint: status.tint)
    }

    private func containerPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.76))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private var queueSubtitle: String {
        if entry.snapshot.overdueCount > 0 {
            return "Start with the overdue work, then clear what is due today."
        }
        if entry.snapshot.dueTodayCount > 0 {
            return "You are on the clock for today. Keep the hot path moving."
        }
        return "Planned work is lined up. Finish the top item, then keep momentum."
    }

    private var topStatus: CadenceTodayTaskStatusPresentation {
        guard let task = entry.snapshot.tasks.first else {
            return CadenceTodayTaskStatusPresentation(
                label: "Scheduled",
                tint: Color(red: 0.39, green: 0.71, blue: 1.0)
            )
        }
        return task.widgetStatus(for: entry.snapshot.dateKey)
    }

    private var extraLargeQueueTasks: [CadenceTodayWidgetTask] {
        Array(entry.snapshot.tasks.dropFirst())
    }

    private var leadingColumnTasks: [CadenceTodayWidgetTask] {
        let queue = extraLargeQueueTasks
        let midpoint = (queue.count + 1) / 2
        return Array(queue.prefix(midpoint))
    }

    private var trailingColumnTasks: [CadenceTodayWidgetTask] {
        let queue = extraLargeQueueTasks
        let midpoint = (queue.count + 1) / 2
        return Array(queue.dropFirst(midpoint))
    }
}
