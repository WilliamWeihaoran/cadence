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
            upcomingTitle: "Finish weekly planning review"
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

private struct CalendarSnapshotWidgetView: View {
    let entry: CalendarSnapshotWidgetEntry

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
        VStack(alignment: .leading, spacing: 12) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                dayStrip(days: Array(entry.snapshot.days.prefix(7)), compact: true)
                agendaLabel
            }
        }
        .padding(14)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                dayStrip(days: Array(entry.snapshot.days.prefix(7)), compact: false)
                HStack(spacing: 10) {
                    CadenceWidgetMetricCard(title: "Overdue", value: "\(entry.snapshot.overdueCount)")
                    CadenceWidgetMetricCard(title: "Scheduled", value: "\(scheduledCount)")
                    CadenceWidgetMetricCard(title: "Due", value: "\(dueCount)")
                }
            }
        }
        .padding(14)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 12) {
                    twoWeekGrid(days: Array(entry.snapshot.days.prefix(14)))
                    VStack(alignment: .leading, spacing: 10) {
                        CadenceWidgetMetricCard(title: "Overdue", value: "\(entry.snapshot.overdueCount)")
                        CadenceWidgetMetricCard(title: "Scheduled", value: "\(scheduledCount)")
                        CadenceWidgetMetricCard(title: "Due", value: "\(dueCount)")
                        footerLink
                    }
                    .frame(width: 126)
                }
            }
        }
        .padding(16)
    }

    private var extraLargeLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 14) {
                    twoWeekGrid(days: Array(entry.snapshot.days.prefix(14)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        agendaPanel
                        footerLink
                    }
                    .frame(width: 220, alignment: .topLeading)
                }
            }
        }
        .padding(18)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calendar")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("\(scheduledCount + dueCount)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                CadenceWidgetBadge(
                    text: "\(entry.snapshot.overdueCount) overdue",
                    tint: Color(red: 1.0, green: 0.52, blue: 0.44)
                )
                CadenceWidgetBadge(
                    text: "\(Array(entry.snapshot.days.prefix(7)).reduce(0) { $0 + $1.totalCount }) upcoming",
                    tint: Color(red: 0.48, green: 0.77, blue: 1.0)
                )
            }
        }
    }

    private func dayStrip(days: [CadenceCalendarWidgetDay], compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            ForEach(days) { day in
                dayCell(day, compact: compact)
            }
        }
    }

    private func twoWeekGrid(days: [CadenceCalendarWidgetDay]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(days) { day in
                dayCell(day, compact: false)
            }
        }
    }

    private func dayCell(_ day: CadenceCalendarWidgetDay, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 7) {
            Text(day.weekdayLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(day.isToday ? Color(red: 0.48, green: 0.77, blue: 1.0) : .white.opacity(0.58))

            Text(day.dayNumberLabel)
                .font(.system(size: compact ? 16 : 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            if day.totalCount == 0 {
                Text("clear")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if day.dueCount > 0 {
                        Text("\(day.dueCount) due")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.28))
                    }
                    if day.scheduledCount > 0 {
                        Text("\(day.scheduledCount) planned")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(red: 0.48, green: 0.77, blue: 1.0))
                    }
                }
            }
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 78 : 84, alignment: .topLeading)
        .background(dayBackground(for: day))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var agendaLabel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            Text(entry.snapshot.upcomingTitle ?? "Nothing urgent right now")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
    }

    private var agendaPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceWidgetMetricCard(title: "Overdue", value: "\(entry.snapshot.overdueCount)")
            CadenceWidgetMetricCard(title: "Scheduled", value: "\(scheduledCount)")
            CadenceWidgetMetricCard(title: "Due", value: "\(dueCount)")

            VStack(alignment: .leading, spacing: 6) {
                Text("Next up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Text(entry.snapshot.upcomingTitle ?? "Nothing urgent right now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        return AnyShapeStyle(Color.white.opacity(0.06))
    }

    private var scheduledCount: Int {
        entry.snapshot.days.reduce(0) { $0 + $1.scheduledCount }
    }

    private var dueCount: Int {
        entry.snapshot.days.reduce(0) { $0 + $1.dueCount }
    }
}
