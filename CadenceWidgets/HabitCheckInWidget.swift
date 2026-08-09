import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct HabitCheckInWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CadenceHabitWidgetSnapshot
}

struct HabitCheckInWidgetProvider: TimelineProvider {
    typealias Entry = HabitCheckInWidgetEntry

    func placeholder(in context: TimelineProviderContext) -> HabitCheckInWidgetEntry {
        HabitCheckInWidgetEntry(
            date: Date(),
            snapshot: placeholderSnapshot()
        )
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (HabitCheckInWidgetEntry) -> Void) {
        completion(
            HabitCheckInWidgetEntry(
                date: Date(),
                snapshot: currentSnapshot()
            )
        )
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<HabitCheckInWidgetEntry>) -> Void) {
        let entry = HabitCheckInWidgetEntry(
            date: Date(),
            snapshot: currentSnapshot()
        )
        completion(
            Timeline(
                entries: [entry],
                policy: .after(CadenceHabitWidgetSupport.recommendedReloadDate(for: entry.snapshot))
            )
        )
    }

    private func placeholderSnapshot() -> CadenceHabitWidgetSnapshot {
        let habits = [
            placeholderHabit(title: "Water", icon: "drop.fill", colorHex: "#5DB9FF", streak: 6, isDone: true),
            placeholderHabit(title: "Read", icon: "book.fill", colorHex: "#FFB347", streak: 4, isDone: false),
            placeholderHabit(title: "Walk", icon: "figure.walk", colorHex: "#66D28A", streak: 8, isDone: false),
            placeholderHabit(title: "Stretch", icon: "figure.cooldown", colorHex: "#FF7F7F", streak: 3, isDone: true),
            placeholderHabit(title: "Journal", icon: "square.and.pencil", colorHex: "#B690FF", streak: 2, isDone: false),
            placeholderHabit(title: "Meditate", icon: "sparkles", colorHex: "#8FE1D6", streak: 11, isDone: false),
            placeholderHabit(title: "Protein", icon: "fork.knife", colorHex: "#FF9F68", streak: 5, isDone: true),
            placeholderHabit(title: "Sleep", icon: "moon.stars.fill", colorHex: "#7FA8FF", streak: 9, isDone: false),
        ]

        return CadenceHabitWidgetSnapshot(
            date: Date(),
            dateKey: CadenceWidgetDateSupport.dateKey(from: Date()),
            state: .ready,
            statusMessage: nil,
            totalDueCount: habits.count,
            doneCount: habits.filter(\.isDoneToday).count,
            habits: habits
        )
    }

    private func currentSnapshot() -> CadenceHabitWidgetSnapshot {
        do {
            let container = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let modelContext = ModelContext(container)
            return try CadenceHabitWidgetSupport.snapshot(
                modelContext: modelContext,
                limit: 8
            )
        } catch {
            return CadenceHabitWidgetSupport.unavailableSnapshot()
        }
    }

    private func placeholderHabit(
        title: String,
        icon: String,
        colorHex: String,
        streak: Int,
        isDone: Bool
    ) -> CadenceHabitWidgetHabit {
        CadenceHabitWidgetHabit(
            id: UUID(),
            title: title,
            icon: icon,
            colorHex: colorHex,
            frequencyLabel: "Daily",
            currentStreak: streak,
            isDoneToday: isDone
        )
    }
}

struct CadenceHabitCheckInWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CadenceWidgetRefreshCenter.habitWidgetKind,
            provider: HabitCheckInWidgetProvider()
        ) { entry in
            HabitCheckInWidgetView(entry: entry)
        }
        .configurationDisplayName("Habit Check-In")
        .description("Tap habits to log today's check-ins without opening Cadence.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HabitCheckInWidgetView: View {
    let entry: HabitCheckInWidgetEntry

    @Environment(\.widgetFamily) private var widgetFamily
    private var scale: CadenceWidgetScale { .forFamily(widgetFamily) }

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            default:
                largeLayout
            }
        }
        .cadenceWidgetBackground([Theme.bg, Theme.surface])
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header

            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.state == .empty {
                emptyState
            } else {
                habitGrid(columns: 2, cellCount: 4, compact: true)
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
                HStack(alignment: .top, spacing: scale.sectionSpacing) {
                    habitGrid(columns: 3, cellCount: 6, compact: false)
                    summaryRail
                        .frame(width: 98)
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
                HStack(alignment: .top, spacing: scale.sectionSpacing) {
                    habitGrid(columns: 4, cellCount: 8, compact: false)

                    VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
                        CadenceWidgetMetricCard(title: "Done", value: "\(entry.snapshot.doneCount)")
                        CadenceWidgetMetricCard(title: "Open", value: "\(entry.snapshot.openCount)")
                        CadenceWidgetMetricCard(title: "Due", value: "\(entry.snapshot.totalDueCount)")
                        CadenceWidgetFooterLink(label: "Open Habits", url: entry.snapshot.habitsURL)
                    }
                    .frame(width: 108, alignment: .topLeading)
                }
            }
        }
        .padding(scale.outerPadding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(headerTitle)
                    .font(.system(size: scale.titleSize, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text("\(entry.snapshot.doneCount)")
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

    private var summaryRail: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            CadenceWidgetMetricCard(title: "Checked in", value: "\(entry.snapshot.doneCount)")
            CadenceWidgetMetricCard(title: "Left today", value: "\(entry.snapshot.openCount)")
            CadenceWidgetMetricCard(title: "Due habits", value: "\(entry.snapshot.totalDueCount)")
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func habitGrid(columns: Int, cellCount: Int, compact: Bool) -> some View {
        let items = paddedHabits(count: cellCount)
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: max(columns, 1))

        return LazyVGrid(columns: gridColumns, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                habitCell(items[index], compact: compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func habitCell(_ habit: CadenceHabitWidgetHabit?, compact: Bool) -> some View {
        if let habit {
            Button(intent: ToggleHabitCompletionIntent(habitID: habit.id)) {
                VStack(alignment: .leading, spacing: compact ? 6 : 7) {
                    HStack(alignment: .top) {
                        Image(systemName: habit.icon)
                            .font(.system(size: compact ? scale.bodyFontSize + 2 : scale.bodyFontSize + 3, weight: .semibold))
                            .foregroundStyle(habitTint(for: habit))
                        Spacer(minLength: 8)
                        Image(systemName: habit.isDoneToday ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: compact ? scale.metricValueSize - 1 : scale.metricValueSize, weight: .semibold))
                            .foregroundStyle(habitTint(for: habit))
                    }

                    Spacer(minLength: 0)

                    Text(habit.title)
                        .font(.system(size: compact ? scale.bodyFontSize + 0.5 : scale.bodyFontSize + 1, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !compact {
                        Text(habit.currentStreak > 0 ? "\(habit.currentStreak)d streak" : habit.frequencyLabel)
                            .font(.system(size: scale.captionFontSize, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    } else if habit.currentStreak > 0 {
                        Text("\(habit.currentStreak)d")
                            .font(.system(size: scale.captionFontSize, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .padding(compact ? scale.compactCardPadding : scale.cardPadding)
                .frame(maxWidth: .infinity, minHeight: compact ? 66 : 74, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: scale.cardCornerRadius, style: .continuous)
                        .fill(habitBackground(for: habit))
                )
                .cadenceWidgetElevation(scale)
            }
            .buttonStyle(.plain)
        } else {
            RoundedRectangle(cornerRadius: scale.cardCornerRadius, style: .continuous)
                .fill(Theme.surface)
                .frame(minHeight: compact ? 66 : 74)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: scale.bodyFontSize + 1, weight: .bold))
                        .foregroundStyle(Theme.dim)
                }
        }
    }

    private var emptyState: some View {
        CadenceWidgetStateCard(
            title: "No habits due today",
            message: "Your check-ins are clear. Use Cadence to plan new habits or adjust schedules.",
            actionLabel: "Open Habits",
            actionURL: entry.snapshot.habitsURL
        )
    }

    private var unavailableState: some View {
        CadenceWidgetStateCard(
            title: "Habit widget needs Cadence",
            message: entry.snapshot.statusMessage,
            actionLabel: "Open Cadence",
            actionURL: entry.snapshot.habitsURL
        )
    }

    private func habitBackground(for habit: CadenceHabitWidgetHabit) -> LinearGradient {
        let tint = Color(hex: habit.colorHex)
        if habit.isDoneToday {
            return LinearGradient(
                colors: [tint.opacity(0.42), tint.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Theme.surfaceElevated, tint.opacity(0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func habitTint(for habit: CadenceHabitWidgetHabit) -> Color {
        // A checked-in cell is filled with the habit's own color, so its glyphs are the one place
        // in the widget set that is genuinely drawn on a saturated fill — hence `onColor` rather
        // than the neutral `text` used everywhere else here.
        habit.isDoneToday ? Theme.onColor : Color(hex: habit.colorHex)
    }

    private func paddedHabits(count: Int) -> [CadenceHabitWidgetHabit?] {
        let visible = Array(entry.snapshot.habits.prefix(max(count, 0))).map(Optional.some)
        let remainder = max(0, count - visible.count)
        return visible + Array(repeating: nil, count: remainder)
    }

    private var headerTitle: String {
        widgetFamily == .systemSmall ? "Habits" : "Habit Check-In"
    }

    private var headerBadges: [WidgetHeaderBadge] {
        let doneTint = Theme.green
        let openTint = Theme.amber

        if widgetFamily == .systemSmall {
            if entry.snapshot.openCount == 0 {
                return [WidgetHeaderBadge(text: "all checked", tint: doneTint)]
            }
            return [WidgetHeaderBadge(text: "\(entry.snapshot.openCount) left today", tint: openTint)]
        }

        return [
            WidgetHeaderBadge(text: "\(entry.snapshot.doneCount) done", tint: doneTint),
            WidgetHeaderBadge(text: "\(entry.snapshot.openCount) open", tint: openTint),
        ]
    }
}
