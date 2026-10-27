import SwiftData
import SwiftUI
import WidgetKit

struct CalendarSnapshotWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CadenceCalendarWidgetSnapshot
}

struct CalendarSnapshotWidgetProvider: TimelineProvider {
    typealias Entry = CalendarSnapshotWidgetEntry

    func placeholder(in context: TimelineProviderContext) -> CalendarSnapshotWidgetEntry {
        CalendarSnapshotWidgetEntry(
            date: Date(),
            snapshot: placeholderSnapshot()
        )
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (CalendarSnapshotWidgetEntry) -> Void) {
        // The widget gallery asks for a snapshot with `isPreview` set, and `placeholder(in:)` is
        // only the redacted loading frame. Answering the gallery from the live store meant a new
        // install advertised this widget as empty and the sample content below was shown to no
        // one (T-7125); the gallery gets the sample, the home screen still gets the store.
        completion(
            CalendarSnapshotWidgetEntry(
                date: Date(),
                snapshot: context.isPreview ? placeholderSnapshot() : currentSnapshot(for: context.family)
            )
        )
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<CalendarSnapshotWidgetEntry>) -> Void) {
        let entry = CalendarSnapshotWidgetEntry(
            date: Date(),
            snapshot: currentSnapshot(for: context.family)
        )
        completion(
            Timeline(
                entries: [entry],
                policy: .after(CadenceCalendarWidgetSupport.recommendedReloadDate(for: entry.snapshot))
            )
        )
    }

    private func placeholderSnapshot() -> CadenceCalendarWidgetSnapshot {
        let today = Calendar.current.startOfDay(for: Date())
        let dayCount = 14

        let days = (0..<dayCount).compactMap { offset -> CadenceCalendarWidgetDay? in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: today) else { return nil }
            let scheduledCount = offset % 3 == 0 ? 2 : (offset % 2 == 0 ? 1 : 0)
            let dueCount = offset == 0 || offset == 2 ? 1 : 0
            return CadenceCalendarWidgetDay(
                dateKey: CadenceWidgetDateSupport.dateKey(from: date),
                weekdayLabel: CadenceWidgetDateSupport.weekdayLabel(from: date),
                dayNumberLabel: CadenceWidgetDateSupport.dayNumberLabel(from: date),
                dueCount: dueCount,
                scheduledCount: scheduledCount,
                totalCount: dueCount + scheduledCount,
                isToday: offset == 0
            )
        }

        return CadenceCalendarWidgetSnapshot(
            date: today,
            state: .ready,
            statusMessage: nil,
            days: days,
            overdueCount: 2,
            upcomingTitle: "Finish weekly planning review",
            upcomingDueDate: CadenceWidgetDateSupport.dateKey(from: today)
        )
    }

    /// Instrumented for [[T-1366]]; see `TodayTasksWidgetProvider` for what the probe records and
    /// why it is off until the app group says otherwise. `renderedCount` is the family-sized day
    /// strip, not the full 14-day snapshot. `rowsFetched` is
    /// where the cost was: this fetch carried no predicate until [[T-1366]]'s sweep measured what
    /// the rows it could not use were costing, and it now materialises the dated open population
    /// alone. `CadenceCalendarWidgetSupport.snapshot(modelContext:dayCount:probe:)` carries the
    /// numbers and the equivalence argument.
    private func currentSnapshot(for family: WidgetFamily) -> CadenceCalendarWidgetSnapshot {
        let probe = CadenceWidgetGenerationProbe(kind: CadenceWidgetRefreshCenter.calendarWidgetKind)
        do {
            let container = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none
            )
            probe.finished(.containerOpen)
            let modelContext = ModelContext(container)
            let snapshot = try CadenceCalendarWidgetSupport.snapshot(
                modelContext: modelContext,
                dayCount: 14,
                probe: probe
            )
            probe.recordGeneration(
                outcome: snapshot.state == .empty ? .empty : .ready,
                renderedCount: snapshot.state == .ready
                    ? min(snapshot.days.count, family.cadenceLayout.calendarDayLimit) : 0,
                sourceSnapshotAt: snapshot.date
            )
            return snapshot
        } catch {
            probe.recordRefusal(error)
            return CadenceCalendarWidgetSupport.unavailableSnapshot()
        }
    }
}

struct CadenceCalendarSnapshotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CadenceWidgetRefreshCenter.calendarWidgetKind,
            provider: CalendarSnapshotWidgetProvider()
        ) { entry in
            CalendarSnapshotWidgetView(entry: entry)
        }
        .configurationDisplayName("Calendar Snapshot")
        .description("See your next stretch of due and scheduled work at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        // WidgetKit insets widget content by ~16pt a side unless a configuration opts out, and
        // `CalendarSnapshotWidgetView` already draws `scale.outerPadding` inside that. Both
        // together spent 56pt of a 158pt `systemSmall` tile on chrome before the first day cell
        // was laid out, which left each of the three cells ~31pt wide -- less glyph room than two
        // black rounded digits need even at `.minimumScaleFactor(0.6)`, so SwiftUI truncated every
        // two-digit day to an ellipsis (T-7120) -- and took 32pt off the height of the 158pt
        // `systemMedium` tile, which is what sheared the title off the top and cut the summary row
        // off the bottom (T-7122). The padding the view already carries IS the margin.
        .contentMarginsDisabled()
    }
}

struct CalendarSnapshotWidgetView: View {
    let entry: CalendarSnapshotWidgetEntry

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
            default:
                extraLargeLayout
            }
        }
        .cadenceWidgetBackground(accent: Theme.blue, anchor: .bottomTrailing)
        .widgetURL(entry.snapshot.calendarURL)
    }

    /// `systemSmall` gives this view 134pt of height on an iPhone 15 (158pt less the 12pt it pads
    /// itself), and the ready layout used to want ~184pt of it: header, badge line, a day cell
    /// with its `d`/`p` chips stacked, and a two-line next-up title. WidgetKit does not scroll, so
    /// the next-up title was drawn off the bottom of the tile and, on the iPad where it wraps,
    /// `Calendar` was sheared at the top too (T-7163). Three levers, all of them at this family
    /// only: no badge line (`N next up` restated the count beside the title and the section under
    /// it), the chips side by side in the cell, and one next-up title line; the compact section
    /// spacing and a 7pt cell inset buy the few points of slack the three leave over.
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                dayStrip(days: visibleSpan.days, compact: true)
                nextUpSection(titleLineLimit: 1)
            }
        }
        .padding(scale.outerPadding)
    }

    /// `systemMedium` is a 158pt tile, so with WidgetKit's own margins off (see the configuration)
    /// this view has 134pt of height to spend. A two-line header plus a 74pt day strip plus a row
    /// of `CadenceWidgetMetricCard`s wants about 200pt of it, and WidgetKit does not scroll: the
    /// overflow came off both ends at once, shearing `Calendar` through the middle at the top and
    /// cutting the Overdue/Scheduled/Due values mid-digit at the bottom (T-7122).
    ///
    /// The three numbers are not dropped, they are re-sited. `headerBadges` carries them at this
    /// family, which costs one badge line rather than the ~54pt a padded card row costs, and the
    /// strip drops to the compact cell. 134pt now holds the whole layout with room to spare
    /// instead of 200pt of content hanging out of both edges.
    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                dayStrip(days: visibleSpan.days, compact: true)
            }
        }
        .padding(scale.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                twoWeekGrid(days: visibleSpan.days)
                HStack(spacing: scale.compactSectionSpacing) {
                    CadenceWidgetMetricCard(title: "Overdue", value: "\(entry.snapshot.overdueCount)")
                    CadenceWidgetMetricCard(title: "Scheduled", value: "\(scheduledCount)")
                    CadenceWidgetMetricCard(title: "Due", value: "\(dueCount)")
                }
                footerLink
            }
        }
        .padding(scale.outerPadding)
    }

    private var extraLargeLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                // `Open Calendar` sits under the grid, not under the agenda column. The agenda
                // column is the tall one -- three metric cards and a next-up card -- and with the
                // button at its foot it was the column that ran off the bottom of the iPad tile,
                // slicing the button's lower third away; the grid's two rows leave room (T-7126).
                HStack(alignment: .top, spacing: scale.sectionSpacing) {
                    VStack(alignment: .leading, spacing: scale.sectionSpacing) {
                        twoWeekGrid(days: visibleSpan.days)
                        footerLink
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    agendaPanel
                        .frame(width: 190, alignment: .topLeading)
                }
            }
        }
        .padding(scale.outerPadding)
    }

    /// At `systemMedium` the badges ride the title line and the count drops to title size. A
    /// second header line plus a 21pt count costs ~23pt of a 134pt budget, and that family has no
    /// 23pt to spare — see `mediumLayout` (T-7122).
    private var usesInlineHeaderBadges: Bool { widgetFamily == .systemMedium }

    private var header: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Calendar")
                    .font(.system(size: scale.titleSize, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if usesInlineHeaderBadges {
                    badgeRow
                }
                Spacer(minLength: 8)
                Text("\(visibleSpan.totalCount)")
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

            if !usesInlineHeaderBadges && !headerBadges.isEmpty {
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

    private func dayStrip(days: [CadenceCalendarWidgetDay], compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(days) { day in
                dayCell(day, compact: compact)
            }
        }
    }

    private func twoWeekGrid(days: [CadenceCalendarWidgetDay]) -> some View {
        // 4pt between columns, not 6: seven columns pay the gap six times, and the 12pt this
        // returns goes straight back into the day number's glyph width (T-7120).
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days) { day in
                dayCell(day, compact: false)
            }
        }
    }

    private func dayCell(_ day: CadenceCalendarWidgetDay, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 5) {
            Text(day.weekdayLabel)
                .font(.system(size: scale.captionFontSize, weight: .semibold))
                .foregroundStyle(day.isToday ? Theme.blueLight : Theme.subdued)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // No `+ 1` for the grid families any more. The grid is where the cell is NARROWEST --
            // seven columns across a 338pt `systemLarge` tile -- so the one place the number was
            // drawn a point larger was the one place it had the least room to be drawn in
            // (T-7120).
            Text(day.dayNumberLabel)
                .font(.system(size: scale.metricValueSize, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.6)
                .monospacedDigit()

            if day.totalCount == 0 {
                Text("clear")
                    .font(.system(size: scale.captionFontSize, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if widgetFamily == .systemSmall {
                // Side by side rather than stacked: one caption line instead of two, which is
                // ~14pt of the small tile's height (T-7163). `1d 2p` is ~24pt of glyphs against
                // the ~30pt the narrowest (iPhone) cell leaves inside its inset.
                HStack(spacing: 4) {
                    dayCountChips(day, labelSpacing: 1)
                }
            } else {
                VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                    dayCountChips(day, labelSpacing: 3)
                }
            }
        }
        .padding(.horizontal, dayCellHorizontalInset)
        .padding(.vertical, dayCellVerticalInset(compact: compact))
        .frame(maxWidth: .infinity, minHeight: dayCellMinHeight(compact: compact), alignment: .topLeading)
        .background(dayBackground(for: day))
        .clipShape(RoundedRectangle(cornerRadius: scale.cardCornerRadius, style: .continuous))
        .cadenceWidgetElevation(scale)
    }

    /// The due label rides the caption row rather than sitting on its own line: these families are
    /// already vertically tight, and `fixedSize` keeps the date from being scaled or clipped away.
    private func nextUpSection(titleLineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Next up")
                    .font(.system(size: scale.captionFontSize, weight: .semibold))
                    .foregroundStyle(Theme.subdued)
                Spacer(minLength: 4)
                if let dueLabel = upcomingDueLabel {
                    Text(dueLabel)
                        .font(.system(size: scale.captionFontSize, weight: .semibold))
                        .foregroundStyle(upcomingDueTint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(entry.snapshot.upcomingTitle ?? "Nothing urgent right now")
                .font(.system(size: scale.bodyFontSize + 1, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(titleLineLimit)
                .minimumScaleFactor(0.85)
        }
    }

    private var upcomingDueLabel: String? {
        guard entry.snapshot.upcomingTitle != nil else { return nil }
        return CadenceWidgetDateSupport.dueLabel(
            for: entry.snapshot.upcomingDueDate,
            todayKey: todayKey
        )
    }

    private var upcomingDueTint: Color {
        let dueDate = entry.snapshot.upcomingDueDate
        if dueDate < todayKey { return Theme.red }
        if dueDate == todayKey { return Theme.amber }
        return Theme.blueLight
    }

    private var todayKey: String {
        CadenceWidgetDateSupport.dateKey(from: entry.snapshot.date)
    }

    private var agendaPanel: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            CadenceWidgetMetricCard(title: "Overdue", value: "\(entry.snapshot.overdueCount)")
            CadenceWidgetMetricCard(title: "Scheduled", value: "\(scheduledCount)")
            CadenceWidgetMetricCard(title: "Due", value: "\(dueCount)")

            // Two title lines, not three: this column is the tallest thing in the tile, and the
            // third line was ~14pt it could not spend (T-7126).
            nextUpSection(titleLineLimit: 2)
                .padding(scale.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: scale.panelCornerRadius, style: .continuous))
        }
    }

    private var footerLink: some View {
        CadenceWidgetFooterLink(label: "Open Calendar", url: entry.snapshot.calendarURL)
    }

    private var emptyState: some View {
        CadenceWidgetStateCard(
            title: "Schedule is clear",
            message: "There is no due or scheduled work in this stretch.",
            actionLabel: "Open Calendar",
            actionURL: entry.snapshot.calendarURL,
            alignment: stateCardAlignment
        )
    }

    private var unavailableState: some View {
        CadenceWidgetStateCard(
            title: "Calendar widget needs Cadence",
            message: entry.snapshot.statusMessage,
            actionLabel: "Open Calendar",
            actionURL: entry.snapshot.calendarURL,
            alignment: stateCardAlignment
        )
    }

    /// Leading only at `systemSmall`, centered everywhere else -- the same split
    /// `TodayTasksWidgetView` makes. A leading card is pinned `.topLeading`, which on the 4x4
    /// `systemLarge` tile left the bottom ~60% of it a blank rectangle under a band of text, and
    /// the two shipped widgets disagreed with each other on one screen (T-7124).
    private var stateCardAlignment: HorizontalAlignment {
        widgetFamily == .systemSmall ? .leading : .center
    }

    private func dayBackground(for day: CadenceCalendarWidgetDay) -> some ShapeStyle {
        if day.isToday {
            return AnyShapeStyle(
                LinearGradient(
                    // Today's cell keeps a blue wash rather than resolving to a neutral surface:
                    // the weekday label above it is already `blueLight`, and a neutral cell would
                    // leave that lone blue word doing all the work of marking today.
                    colors: [
                        Theme.blue.opacity(0.32),
                        Theme.blue.opacity(0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Theme.surfaceElevated)
    }

    /// The days this family draws; every count beside them reads the same span (T-5881).
    private var visibleSpan: CadenceCalendarWidgetVisibleSpan {
        CadenceCalendarWidgetVisibleSpan(days: Array(entry.snapshot.days.prefix(widgetFamily.cadenceLayout.calendarDayLimit)))
    }

    private var scheduledCount: Int {
        visibleSpan.scheduledCount
    }

    private var dueCount: Int {
        visibleSpan.dueCount
    }

    /// The side inset is what a two-digit day number is taken out of, and the families do not
    /// share a cell width. `systemLarge` lays SEVEN columns across a 338pt tile — about 39pt a
    /// cell — while `systemExtraLarge` lays the same seven across roughly 495pt. One inset sized
    /// for the roomy case left `26` with less width than even the minimum scale factor needed, so
    /// SwiftUI truncated instead of shrinking further (T-7120); this cuts it where the columns are
    /// narrow and leaves it alone where they are not.
    private var dayCellHorizontalInset: CGFloat {
        switch widgetFamily {
        case .systemExtraLarge: scale.compactCardPadding
        case .systemLarge: 5
        default: 6
        }
    }

    /// `systemSmall` alone runs tighter than the other compact strip (medium): its single chip
    /// line makes the cell ~14pt shorter, and the small tile has no height to spare (T-7163).
    private func dayCellVerticalInset(compact: Bool) -> CGFloat {
        if widgetFamily == .systemSmall { return 7 }
        return compact ? max(scale.compactCardPadding - 1, 7) : scale.compactCardPadding
    }

    private func dayCellMinHeight(compact: Bool) -> CGFloat {
        if widgetFamily == .systemSmall { return 0 }
        return compact ? 68 : 74
    }

    private var headerBadges: [WidgetHeaderBadge] {
        let overdueTint = Theme.red
        let upcomingTint = Theme.blueLight
        let upcomingCount = visibleSpan.totalCount

        // No badge line at `systemSmall`: the tile has no 23pt for it (see `smallLayout`, T-7163).
        if widgetFamily == .systemSmall {
            return []
        }

        if widgetFamily == .systemMedium {
            // The three numbers the metric-card row used to carry at this family, in the one line
            // the tile can actually afford. `mediumLayout` says why the cards went (T-7122); the
            // total they sat under is still the count in the header's trailing corner.
            return [
                WidgetHeaderBadge(text: "\(entry.snapshot.overdueCount) overdue", tint: overdueTint),
                WidgetHeaderBadge(text: "\(dueCount) due", tint: Theme.amber),
                WidgetHeaderBadge(text: "\(scheduledCount) planned", tint: upcomingTint),
            ]
        }

        return [
            WidgetHeaderBadge(text: "\(entry.snapshot.overdueCount) overdue", tint: overdueTint),
            WidgetHeaderBadge(text: "\(upcomingCount) upcoming", tint: upcomingTint),
        ]
    }

    /// `d` and `p`, at every family rather than only the two narrow ones. `2 planned` needs ~49pt
    /// of glyph width, and no family's day cell has that: the widest is `systemExtraLarge`'s, at
    /// ~67pt before its own inset. The long labels were truncating on the iPad's `systemLarge` and
    /// `systemExtraLarge` tiles (`1 du`, `3 pl`) exactly as they did on the small ones, so the
    /// strip speaks one vocabulary across families instead of spelling a word it cannot fit.
    @ViewBuilder
    private func dayCountChips(_ day: CadenceCalendarWidgetDay, labelSpacing: CGFloat) -> some View {
        if day.dueCount > 0 {
            countChip(value: "\(day.dueCount)", label: "d", tint: Theme.amber, spacing: labelSpacing)
        }
        if day.scheduledCount > 0 {
            countChip(value: "\(day.scheduledCount)", label: "p", tint: Theme.blueLight, spacing: labelSpacing)
        }
    }

    private func countChip(value: String, label: String, tint: Color, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Text(value)
                .font(.system(size: scale.captionFontSize, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: scale.captionFontSize, weight: .semibold))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.9)
    }
}
