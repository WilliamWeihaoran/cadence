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
    private var scale: CadenceWidgetScale { .forFamily(widgetFamily) }

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
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .leading)
            } else if let task = entry.snapshot.tasks.first {
                primaryTaskCard(task: task, compact: true)
            } else {
                emptyState(alignment: .leading)
            }
        }
        .padding(scale.outerPadding)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .center)
            } else if entry.snapshot.tasks.isEmpty {
                emptyState(alignment: .center)
            } else {
                VStack(spacing: scale.compactSectionSpacing) {
                    ForEach(entry.snapshot.tasks.prefix(3)) { task in
                        taskRow(task, dense: false)
                    }
                }
            }
        }
        .padding(scale.outerPadding)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .center)
            } else if entry.snapshot.tasks.isEmpty {
                emptyState(alignment: .center)
            } else {
                HStack(alignment: .top, spacing: scale.sectionSpacing) {
                    if let task = entry.snapshot.tasks.first {
                        primaryTaskCard(task: task, compact: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    summaryPanel
                        .frame(width: 132)
                }

                taskStackCard(
                    title: "Actionable queue",
                    subtitle: queueSubtitle,
                    tasks: Array(entry.snapshot.tasks.prefix(6))
                )

                footerBar(label: "Open Today")
            }
        }
        .padding(scale.outerPadding)
    }

    private var extraLargeLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .center)
            } else if entry.snapshot.tasks.isEmpty {
                emptyState(alignment: .center)
            } else {
                HStack(alignment: .top, spacing: scale.sectionSpacing) {
                    VStack(alignment: .leading, spacing: scale.sectionSpacing) {
                        if let task = entry.snapshot.tasks.first {
                            primaryTaskCard(task: task, compact: false)
                        }

                        focusStrip
                        footerBar(label: "Open Today")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .top, spacing: scale.sectionSpacing) {
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
        .padding(scale.outerPadding)
    }

    private var summaryPanel: some View {
        CadenceWidgetPanel {
            VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
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
        HStack(spacing: scale.compactSectionSpacing) {
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
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: scale.titleSize, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 10)
                Text("\(entry.snapshot.totalCount)")
                    .font(.system(size: scale.countSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 5) {
                ForEach(headerBadges) { badge in
                    CadenceWidgetBadge(text: badge.text, tint: badge.tint)
                }
            }
        }
    }

    private func primaryTaskCard(task: CadenceTodayWidgetTask, compact: Bool) -> some View {
        let status = task.widgetStatus(for: entry.snapshot.dateKey)

        return VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            HStack(alignment: .top, spacing: scale.compactSectionSpacing) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(compact ? "Top task" : "Priority now")
                        .font(.system(size: scale.captionFontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    Link(destination: task.deepLinkURL) {
                        Text(task.title)
                            .font(.system(size: compact ? scale.bodyFontSize + 2 : scale.titleSize, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(compact ? 3 : 3)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !compact {
                    completeButton(taskID: task.id, size: scale.countSize - 2)
                }
            }

            HStack(spacing: 6) {
                statusPill(status)
                if !task.containerName.isEmpty {
                    containerPill(task.containerName)
                }
                Spacer(minLength: 8)
                if compact {
                    completeButton(taskID: task.id, size: scale.metricValueSize)
                }
            }
        }
        .padding(compact ? scale.compactCardPadding : scale.cardPadding)
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
        .clipShape(RoundedRectangle(cornerRadius: compact ? scale.cardCornerRadius : scale.cardCornerRadius + 1, style: .continuous))
    }

    private func taskStackCard(
        title: String,
        subtitle: String,
        tasks: [CadenceTodayWidgetTask]
    ) -> some View {
        CadenceWidgetPanel {
            VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: scale.bodyFontSize + 1, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: scale.bodyFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                VStack(spacing: scale.compactSectionSpacing) {
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
            VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
                Text(title)
                    .font(.system(size: scale.bodyFontSize + 1, weight: .bold))
                    .foregroundStyle(.white)

                if tasks.isEmpty {
                    Text("No more tasks in this lane.")
                        .font(.system(size: scale.bodyFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: scale.compactSectionSpacing) {
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

        return HStack(spacing: dense ? 7 : 8) {
            Link(destination: task.deepLinkURL) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: dense ? scale.bodyFontSize + 0.5 : scale.bodyFontSize + 1, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(dense ? 2 : 2)
                        .minimumScaleFactor(0.9)

                    HStack(spacing: 5) {
                        statusPill(status)
                        if !task.containerName.isEmpty {
                            Text(task.containerName)
                                .font(.system(size: scale.captionFontSize, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            completeButton(taskID: task.id, size: dense ? scale.metricValueSize - 1 : scale.metricValueSize)
        }
        .padding(.horizontal, scale.panelPadding)
        .padding(.vertical, dense ? max(scale.panelPadding - 2, 6) : max(scale.panelPadding - 1, 7))
        .background(Color.white.opacity(dense ? 0.05 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: scale.cardCornerRadius, style: .continuous))
    }

    private func footerBar(label: String) -> some View {
        HStack(spacing: scale.compactSectionSpacing) {
            Text("\(entry.snapshot.totalCount) tasks in view")
                .font(.system(size: scale.bodyFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
            Spacer(minLength: 8)
            CadenceWidgetFooterLink(label: label, url: entry.snapshot.todayURL)
        }
    }

    private func metricTile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: scale.captionFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            Text("\(value)")
                .font(.system(size: scale.metricValueSize + 1, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func focusTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: scale.captionFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: scale.bodyFontSize + 2, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(scale.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: scale.panelCornerRadius, style: .continuous))
    }

    private func emptyState(alignment: HorizontalAlignment) -> some View {
        CadenceWidgetStateCard(
            title: "Nothing planned today",
            message: alignment == .leading ? "Your hot path is clear right now." : nil,
            actionLabel: "Open Today",
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
            .font(.system(size: scale.captionFontSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.76))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, scale.badgeHorizontalPadding)
            .padding(.vertical, scale.badgeVerticalPadding)
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

    private var headerBadges: [WidgetHeaderBadge] {
        if entry.snapshot.isUnavailable {
            return [
                WidgetHeaderBadge(
                    text: "unavailable",
                    tint: Color(red: 1.0, green: 0.72, blue: 0.28)
                )
            ]
        }

        let overdueTint = Color(red: 1.0, green: 0.45, blue: 0.41)
        let dueTint = Color(red: 1.0, green: 0.72, blue: 0.28)
        let scheduledTint = Color(red: 0.39, green: 0.71, blue: 1.0)

        switch widgetFamily {
        case .systemSmall:
            if entry.snapshot.overdueCount > 0 {
                return [WidgetHeaderBadge(text: "\(entry.snapshot.overdueCount) overdue", tint: overdueTint)]
            }
            if entry.snapshot.dueTodayCount > 0 {
                return [WidgetHeaderBadge(text: "\(entry.snapshot.dueTodayCount) due now", tint: dueTint)]
            }
            return [WidgetHeaderBadge(text: "\(entry.snapshot.scheduledTodayCount) planned", tint: scheduledTint)]
        case .systemMedium:
            return [
                WidgetHeaderBadge(text: "\(entry.snapshot.overdueCount) overdue", tint: overdueTint),
                WidgetHeaderBadge(text: "\(entry.snapshot.dueTodayCount) due", tint: dueTint),
            ]
        default:
            return [
                WidgetHeaderBadge(text: "\(entry.snapshot.overdueCount) overdue", tint: overdueTint),
                WidgetHeaderBadge(text: "\(entry.snapshot.dueTodayCount) due", tint: dueTint),
                WidgetHeaderBadge(text: "\(entry.snapshot.scheduledTodayCount) scheduled", tint: scheduledTint),
            ]
        }
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
