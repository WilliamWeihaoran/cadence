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
        completion(
            CalendarSnapshotWidgetEntry(
                date: Date(),
                snapshot: currentSnapshot()
            )
        )
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<CalendarSnapshotWidgetEntry>) -> Void) {
        let entry = CalendarSnapshotWidgetEntry(
            date: Date(),
            snapshot: currentSnapshot()
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

    private func currentSnapshot() -> CadenceCalendarWidgetSnapshot {
        do {
            let container = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let modelContext = ModelContext(container)
            return try CadenceCalendarWidgetSupport.snapshot(
                modelContext: modelContext,
                dayCount: 14
            )
        } catch {
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
        .cadenceWidgetBackground([
            Color(red: 0.07, green: 0.11, blue: 0.17),
            Color(red: 0.10, green: 0.15, blue: 0.23),
        ])
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                dayStrip(days: Array(entry.snapshot.days.prefix(3)), compact: true)
                agendaLabel
            }
        }
        .padding(scale.outerPadding)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                dayStrip(days: Array(entry.snapshot.days.prefix(6)), compact: false)
                HStack(spacing: scale.compactSectionSpacing) {
                    CadenceWidgetMetricCard(title: "Overdue", value: "\(entry.snapshot.overdueCount)")
                    CadenceWidgetMetricCard(title: "Scheduled", value: "\(scheduledCount)")
                    CadenceWidgetMetricCard(title: "Due", value: "\(dueCount)")
                }
            }
        }
        .padding(scale.outerPadding)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                twoWeekGrid(days: Array(entry.snapshot.days.prefix(14)))
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
                HStack(alignment: .top, spacing: scale.sectionSpacing) {
                    twoWeekGrid(days: Array(entry.snapshot.days.prefix(14)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
                        agendaPanel
                        footerLink
                    }
                    .frame(width: 190, alignment: .topLeading)
                }
            }
        }
        .padding(scale.outerPadding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calendar")
                    .font(.system(size: scale.titleSize, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("\(scheduledCount + dueCount)")
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

    private func dayStrip(days: [CadenceCalendarWidgetDay], compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(days) { day in
                dayCell(day, compact: compact)
            }
        }
    }

    private func twoWeekGrid(days: [CadenceCalendarWidgetDay]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
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
                .foregroundStyle(day.isToday ? Color(red: 0.48, green: 0.77, blue: 1.0) : .white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(day.dayNumberLabel)
                .font(.system(size: compact ? scale.metricValueSize : scale.metricValueSize + 1, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()

            if day.totalCount == 0 {
                Text("clear")
                    .font(.system(size: scale.captionFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                    if day.dueCount > 0 {
                        countChip(
                            value: "\(day.dueCount)",
                            label: usesShortCountLabels ? "d" : "due",
                            tint: Color(red: 1.0, green: 0.72, blue: 0.28)
                        )
                    }
                    if day.scheduledCount > 0 {
                        countChip(
                            value: "\(day.scheduledCount)",
                            label: usesShortCountLabels ? "p" : "planned",
                            tint: Color(red: 0.48, green: 0.77, blue: 1.0)
                        )
                    }
                }
            }
        }
        .padding(compact ? max(scale.compactCardPadding - 1, 7) : scale.compactCardPadding)
        .frame(maxWidth: .infinity, minHeight: compact ? 68 : 74, alignment: .topLeading)
        .background(dayBackground(for: day))
        .clipShape(RoundedRectangle(cornerRadius: scale.cardCornerRadius, style: .continuous))
        .cadenceWidgetElevation(scale)
    }

    private var agendaLabel: some View {
        nextUpSection(titleLineLimit: 2)
    }

    /// The due label rides the caption row rather than sitting on its own line: these families are
    /// already vertically tight, and `fixedSize` keeps the date from being scaled or clipped away.
    private func nextUpSection(titleLineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Next up")
                    .font(.system(size: scale.captionFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
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
                .foregroundStyle(.white)
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
        if dueDate < todayKey { return Color(red: 1.0, green: 0.52, blue: 0.44) }
        if dueDate == todayKey { return Color(red: 1.0, green: 0.72, blue: 0.28) }
        return Color(red: 0.48, green: 0.77, blue: 1.0)
    }

    private var todayKey: String {
        CadenceWidgetDateSupport.dateKey(from: entry.snapshot.date)
    }

    private var agendaPanel: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            CadenceWidgetMetricCard(title: "Overdue", value: "\(entry.snapshot.overdueCount)")
            CadenceWidgetMetricCard(title: "Scheduled", value: "\(scheduledCount)")
            CadenceWidgetMetricCard(title: "Due", value: "\(dueCount)")

            nextUpSection(titleLineLimit: 3)
                .padding(scale.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.07))
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
            actionURL: entry.snapshot.calendarURL
        )
    }

    private var unavailableState: some View {
        CadenceWidgetStateCard(
            title: "Calendar widget needs Cadence",
            message: entry.snapshot.statusMessage,
            actionLabel: "Open Calendar",
            actionURL: entry.snapshot.calendarURL
        )
    }

    private func dayBackground(for day: CadenceCalendarWidgetDay) -> some ShapeStyle {
        if day.isToday {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.21, green: 0.34, blue: 0.52).opacity(0.65),
                        Color(red: 0.12, green: 0.18, blue: 0.28).opacity(0.95),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.08))
    }

    private var scheduledCount: Int {
        entry.snapshot.days.reduce(0) { $0 + $1.scheduledCount }
    }

    private var dueCount: Int {
        entry.snapshot.days.reduce(0) { $0 + $1.dueCount }
    }

    private var usesShortCountLabels: Bool {
        widgetFamily == .systemSmall || widgetFamily == .systemMedium
    }

    private var headerBadges: [WidgetHeaderBadge] {
        let overdueTint = Color(red: 1.0, green: 0.52, blue: 0.44)
        let upcomingTint = Color(red: 0.48, green: 0.77, blue: 1.0)
        let leadingDayCount = widgetFamily == .systemSmall ? 5 : 7
        let upcomingCount = Array(entry.snapshot.days.prefix(leadingDayCount)).reduce(0) { $0 + $1.totalCount }

        if widgetFamily == .systemSmall {
            return [WidgetHeaderBadge(text: "\(upcomingCount) next up", tint: upcomingTint)]
        }

        return [
            WidgetHeaderBadge(text: "\(entry.snapshot.overdueCount) overdue", tint: overdueTint),
            WidgetHeaderBadge(text: "\(upcomingCount) upcoming", tint: upcomingTint),
        ]
    }

    private func countChip(value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 3) {
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
