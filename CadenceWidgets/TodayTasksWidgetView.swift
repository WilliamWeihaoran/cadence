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
        .cadenceWidgetBackground(accent: Theme.blue, anchor: .topLeading)
        .widgetURL(backgroundURL)
    }

    /// T-5801. Where a tap that lands on no `Link` goes. WidgetKit does not deliver `Link` on a
    /// small widget at all, so there this is the ONLY tap target: the task the small layout shows,
    /// else Today. Larger families route to Today; their per-row `Link`s still win where drawn.
    private var backgroundURL: URL {
        if widgetFamily == .systemSmall,
           !entry.snapshot.isUnavailable,
           let task = entry.snapshot.tasks.first {
            return task.deepLinkURL
        }
        return entry.snapshot.todayURL
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

    /// `systemMedium` is a 158pt tile, so with WidgetKit's own margins off (see the configuration)
    /// this view has 134pt of height. A two-line header plus three ~50pt rows wanted about 215pt
    /// of it, and WidgetKit does not scroll: the overflow came off both ends, so the title and the
    /// count were gone off the top and the third row was cut in half by the bottom edge (T-7121).
    ///
    /// Three changes. The badges ride the title line, the rows are the dense single-line variant,
    /// and `todayTaskLimit` for `.medium` drops 3 -> 2. Header plus two dense rows measures ~130pt
    /// against the 134pt an iPhone 15 gives this family and the 146pt an 11-inch iPad gives it,
    /// and both were checked on screen in the widget gallery rather than computed and trusted.
    ///
    /// **`ViewThatFits(in: .vertical)` was tried here first and is deliberately not used.** Asked
    /// to choose between a two-row and a one-row stack it answered differently on the two devices
    /// from one build — two rows on `Cadence-iPhone15` and ONE on `Cadence-iPadPro11`, which has
    /// the taller tile of the pair. A chooser that drops a row on the roomier device is reading
    /// something other than the tile (a `VStack` does not hand a flexible child the full height to
    /// measure against), so what is drawn here is the budget, which is at least the same on both.
    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .center)
            } else if entry.snapshot.tasks.isEmpty {
                emptyState(alignment: .center)
            } else {
                VStack(spacing: scale.compactSectionSpacing) {
                    ForEach(entry.snapshot.tasks.prefix(widgetFamily.cadenceLayout.todayTaskLimit)) { task in
                        taskRow(task, dense: true, titleLines: 1)
                    }
                }
            }
        }
        .padding(scale.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                // The row's own height, not the stack's share. The outer `VStack` proposes this
                // row an even split of the tile (~100pt on the iPhone), the `HStack` passes that
                // to the card, and a two-line title then no longer fits, so it drew one truncated
                // line (`Finish widg...`) — while the 132pt panel, which ignores the proposal,
                // made the row 132pt tall anyway. Asked for its ideal height the card wraps to
                // three lines (~125pt) inside the panel's height, so the tile is no taller (T-7285).
                .fixedSize(horizontal: false, vertical: true)

                let queueTasks = Array(entry.snapshot.tasks.dropFirst().prefix(widgetFamily.cadenceLayout.todayTaskLimit - 1))
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

    /// The panel, not the `Priority now` card beside it, sets the height of the large layout's
    /// middle row, so its spacing is the large tile's height budget. At 8pt between tiles, 4pt
    /// inside each and 2pt above and below, the populated layout wanted ~387pt against the 354pt
    /// an iPhone 15 gives `systemLarge`, and SwiftUI took the difference out of the flexible text
    /// and the outer padding (T-7195). 4 / 2 / 0 here and a one-line queue subtitle bring it to
    /// ~348pt; the iPad's 382pt tile had 8pt spare and now has ~34pt.
    private var summaryPanel: some View {
        CadenceWidgetPanel {
            VStack(alignment: .leading, spacing: 4) {
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
        // `Visible` and `Total` are one- or two-digit counts and take only the width they draw;
        // `Now` takes the rest. Three equal thirds left `Overdue Oct 23` a third of the row and
        // it drew as `Overdue Oc...` on the iPad's extra-large tile (T-7126).
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
            .fixedSize(horizontal: true, vertical: false)
            focusTile(
                title: "Total",
                value: "\(entry.snapshot.totalCount)",
                tint: Theme.blueLight
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// At `systemMedium` the badges ride the title line and the count drops to title size. A
    /// second header line plus a 21pt count costs ~23pt of a 134pt budget, and that family has no
    /// 23pt to spare — see `mediumLayout` (T-7121).
    private var usesInlineHeaderBadges: Bool { widgetFamily == .systemMedium }

    private var widgetHeader: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today")
                    .font(.system(size: scale.titleSize, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if usesInlineHeaderBadges {
                    badgeRow
                }
                Spacer(minLength: 10)
                Text("\(entry.snapshot.totalCount)")
                    .font(
                        .system(
                            size: usesInlineHeaderBadges ? scale.titleSize : scale.countSize,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.8)
            }

            if !usesInlineHeaderBadges {
                badgeRow
            }
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 5) {
            ForEach(headerBadges) { badge in
                CadenceWidgetBadge(text: badge.text, tint: badge.tint)
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

            if compact {
                HStack(spacing: 6) {
                    statusPill(status)
                    if !task.containerName.isEmpty {
                        containerPill(task.containerName)
                    }
                    Spacer(minLength: 8)
                    completeButton(taskID: task.id, size: scale.metricValueSize)
                }
            } else {
                // Beside a dated status pill the container pill was left ~40pt on the iPhone's
                // large tile and drew `[Sa...`, so here it rides only when it fits WHOLE, as the
                // extra-large rows do (T-7126, T-7315). No `Spacer` in this row: an `HStack`
                // would hand the choice only part of the width and drop names that fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        statusPill(status)
                        if !task.containerName.isEmpty {
                            containerPill(task.containerName)
                                .fixedSize()
                        }
                    }
                    statusPill(status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    // One line: at the iPhone's 338pt width it wrapped to two and cost the 13pt
                    // the large tile did not have (T-7195); the iPad already drew it on one.
                    Text(subtitle)
                        .font(.system(size: scale.bodyFontSize, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(1)
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
                        .foregroundStyle(Theme.subdued)
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

    /// `titleLines` is separate from `dense` because the two are not the same question. `dense`
    /// sets the metrics; the line limit is a height budget, and `systemMedium` is the one caller
    /// that cannot afford a second title line (T-7121) while the large queue card and the
    /// extra-large columns can.
    private func taskRow(_ task: CadenceTodayWidgetTask, dense: Bool, titleLines: Int = 2) -> some View {
        let status = task.widgetStatus(for: entry.snapshot.dateKey)

        return HStack(spacing: dense ? 7 : 8) {
            Link(destination: task.deepLinkURL) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: dense ? scale.bodyFontSize + 0.5 : scale.bodyFontSize + 1, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(titleLines)
                        .minimumScaleFactor(0.9)

                    // At extra-large the container name rides beside the status pill only when it
                    // fits WHOLE: the pill is `fixedSize`, so the narrow iPad columns left the name
                    // a two-character stub, `[S`, which is noise rather than information (T-7126).
                    // Every other family truncates it, as before (T-7211 (b)).
                    if widgetFamily.cadenceLayout.todayRowDropsContainerNameThatDoesNotFit {
                        ViewThatFits(in: .horizontal) {
                            statusLine(status, containerName: task.containerName, truncates: false)
                            statusPill(status)
                        }
                    } else {
                        statusLine(status, containerName: task.containerName, truncates: true)
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

    private func statusLine(
        _ status: CadenceTodayTaskStatusPresentation,
        containerName: String,
        truncates: Bool
    ) -> some View {
        HStack(spacing: 5) {
            statusPill(status)
            if !containerName.isEmpty {
                Text(containerName)
                    .font(.system(size: scale.captionFontSize, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
                    .fixedSize(horizontal: !truncates, vertical: false)
            }
        }
    }

    private func footerBar(label: String) -> some View {
        HStack(spacing: scale.compactSectionSpacing) {
            Text(entry.snapshot.tasksInViewLabel)
                .font(.system(size: scale.bodyFontSize, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            CadenceWidgetFooterLink(label: label, url: entry.snapshot.todayURL)
        }
    }

    private func metricTile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: scale.captionFontSize, weight: .semibold))
                .foregroundStyle(Theme.subdued)
            Text("\(value)")
                .font(.system(size: scale.metricValueSize + 1, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func focusTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: scale.captionFontSize, weight: .semibold))
                .foregroundStyle(Theme.subdued)
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
        .padding(.vertical, stateCardVerticalInset)
    }

    private func unavailableState(alignment: HorizontalAlignment) -> some View {
        CadenceWidgetStateCard(
            title: "Widget needs Cadence",
            message: entry.snapshot.statusMessage,
            actionLabel: "Open Cadence",
            actionURL: entry.snapshot.todayURL,
            alignment: alignment
        )
        .padding(.vertical, stateCardVerticalInset)
    }

    /// None at `systemSmall`: the 20pt this inset spends is the height the state card's two-line
    /// title and its message need on that tile (T-7123). The larger families keep it.
    private var stateCardVerticalInset: CGFloat {
        widgetFamily == .systemSmall ? 0 : 10
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
        Array(entry.snapshot.tasks.prefix(widgetFamily.cadenceLayout.todayTaskLimit).dropFirst())
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
