import AppIntents
import SwiftUI
import WidgetKit

private struct CadenceTodayTaskStatusPresentation {
    let label: String
    let tint: Color
}

private extension CadenceTodayWidgetTask {
    /// "Scheduled" is reserved for tasks with no due date at all — a future due date keeps its
    /// own dated label so the two are never collapsed into the same pill.
    func widgetStatus(for todayKey: String) -> CadenceTodayTaskStatusPresentation {
        guard let dueLabel = CadenceWidgetDateSupport.dueLabel(for: dueDate, todayKey: todayKey) else {
            return CadenceTodayTaskStatusPresentation(
                label: "Scheduled",
                tint: Theme.blueLight
            )
        }
        if dueDate < todayKey {
            return CadenceTodayTaskStatusPresentation(
                label: dueLabel,
                tint: Theme.red
            )
        }
        if dueDate == todayKey {
            return CadenceTodayTaskStatusPresentation(
                label: dueLabel,
                tint: Theme.amber
            )
        }
        return CadenceTodayTaskStatusPresentation(
            label: dueLabel,
            tint: Theme.blueLight
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
        .cadenceWidgetBackground([Theme.bg, Theme.surface])
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

                let queueTasks = Array(entry.snapshot.tasks.dropFirst().prefix(1))
                if !queueTasks.isEmpty {
                    taskStackCard(
                        title: "Actionable queue",
                        subtitle: queueSubtitle,
                        tasks: queueTasks
                    )
                }
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
                    tint: Theme.red
                )
                metricTile(
                    title: "Due today",
                    value: entry.snapshot.dueTodayCount,
                    tint: Theme.amber
                )
                metricTile(
                    title: "Scheduled",
                    value: entry.snapshot.scheduledTodayCount,
                    tint: Theme.blueLight
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
                tint: Theme.text
            )
            focusTile(
                title: "Total",
                value: "\(entry.snapshot.totalCount)",
                tint: Theme.blueLight
            )
        }
    }

    private var widgetHeader: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: scale.titleSize, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 10)
                Text("\(entry.snapshot.totalCount)")
                    .font(.system(size: scale.countSize, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.text)
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
                        .foregroundStyle(Theme.muted)

                    Link(destination: task.deepLinkURL) {
                        Text(task.title)
                            .font(.system(size: compact ? scale.bodyFontSize + 2 : scale.titleSize, weight: .bold))
                            .foregroundStyle(Theme.text)
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
                    Theme.surfaceHighlight,
                    // Was a one-off slate blue; the same accent every other tint in this widget
                    // now uses, at the badge-fill alpha, lands in the same place.
                    Theme.blue.opacity(0.20),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? scale.cardCornerRadius : scale.cardCornerRadius + 1, style: .continuous))
        .cadenceWidgetElevation(scale)
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
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: scale.bodyFontSize, weight: .medium))
                        .foregroundStyle(Theme.muted)
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
                    .foregroundStyle(Theme.text)

                if tasks.isEmpty {
                    Text("No more tasks in this lane.")
                        .font(.system(size: scale.bodyFontSize, weight: .medium))
                        .foregroundStyle(Theme.muted)
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
                        .foregroundStyle(Theme.text)
                        .lineLimit(dense ? 2 : 2)
                        .minimumScaleFactor(0.9)

                    HStack(spacing: 5) {
                        statusPill(status)
                        if !task.containerName.isEmpty {
                            Text(task.containerName)
                                .font(.system(size: scale.captionFontSize, weight: .medium))
                                .foregroundStyle(Theme.muted)
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
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: scale.cardCornerRadius, style: .continuous))
        .cadenceWidgetElevation(scale)
    }

    private func footerBar(label: String) -> some View {
        HStack(spacing: scale.compactSectionSpacing) {
            Text("\(entry.snapshot.totalCount) tasks in view")
                .font(.system(size: scale.bodyFontSize, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            CadenceWidgetFooterLink(label: label, url: entry.snapshot.todayURL)
        }
    }

    private func metricTile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: scale.captionFontSize, weight: .semibold))
                .foregroundStyle(Theme.muted)
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
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: scale.bodyFontSize + 2, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(scale.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated)
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
                .foregroundStyle(Theme.green)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `fixedSize` keeps the dated labels intact when a long container name shares the row —
    /// the container pill truncates instead of the due date scaling itself away.
    private func statusPill(_ status: CadenceTodayTaskStatusPresentation) -> some View {
        CadenceWidgetBadge(text: status.label, tint: status.tint)
            .fixedSize()
    }

    private func containerPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: scale.captionFontSize, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, scale.badgeHorizontalPadding)
            .padding(.vertical, scale.badgeVerticalPadding)
            .background(Theme.surfaceHighlight)
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
                tint: Theme.blueLight
            )
        }
        return task.widgetStatus(for: entry.snapshot.dateKey)
    }

    private var headerBadges: [WidgetHeaderBadge] {
        if entry.snapshot.isUnavailable {
            return [
                WidgetHeaderBadge(
                    text: "unavailable",
                    tint: Theme.amber
                )
            ]
        }

        let overdueTint = Theme.red
        let dueTint = Theme.amber
        let scheduledTint = Theme.blueLight

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
