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

private struct HabitCheckInWidgetView: View {
    let entry: HabitCheckInWidgetEntry

    @Environment(\.widgetFamily) private var widgetFamily

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
        .cadenceWidgetBackground([
            Color(red: 0.09, green: 0.12, blue: 0.09),
            Color(red: 0.13, green: 0.19, blue: 0.13),
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
                habitGrid(columns: 2, cellCount: 4, compact: true)
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
                HStack(alignment: .top, spacing: 12) {
                    habitGrid(columns: 3, cellCount: 6, compact: false)
                    summaryRail
                        .frame(width: 110)
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
                HStack(alignment: .top, spacing: 14) {
                    habitGrid(columns: 4, cellCount: 8, compact: false)

                    VStack(alignment: .leading, spacing: 10) {
                        CadenceWidgetMetricCard(title: "Done", value: "\(entry.snapshot.doneCount)")
                        CadenceWidgetMetricCard(title: "Open", value: "\(entry.snapshot.openCount)")
                        CadenceWidgetMetricCard(title: "Due", value: "\(entry.snapshot.totalDueCount)")
                        CadenceWidgetFooterLink(label: "Open Habits", url: entry.snapshot.habitsURL)
                    }
                    .frame(width: 120, alignment: .topLeading)
                }
            }
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Habit Check-In")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("\(entry.snapshot.doneCount)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                CadenceWidgetBadge(
                    text: "\(entry.snapshot.doneCount) done",
                    tint: Color(red: 0.38, green: 0.90, blue: 0.55)
                )
                CadenceWidgetBadge(
                    text: "\(entry.snapshot.openCount) open",
                    tint: Color(red: 1.0, green: 0.74, blue: 0.30)
                )
            }
        }
    }

    private var summaryRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            CadenceWidgetMetricCard(title: "Checked in", value: "\(entry.snapshot.doneCount)")
            CadenceWidgetMetricCard(title: "Left today", value: "\(entry.snapshot.openCount)")
            CadenceWidgetMetricCard(title: "Due habits", value: "\(entry.snapshot.totalDueCount)")
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func habitGrid(columns: Int, cellCount: Int, compact: Bool) -> some View {
        let items = paddedHabits(count: cellCount)
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(columns, 1))

        return LazyVGrid(columns: gridColumns, spacing: 8) {
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
                VStack(alignment: .leading, spacing: compact ? 7 : 8) {
                    HStack(alignment: .top) {
                        Image(systemName: habit.icon)
                            .font(.system(size: compact ? 13 : 14, weight: .semibold))
                            .foregroundStyle(habitTint(for: habit))
                        Spacer(minLength: 8)
                        Image(systemName: habit.isDoneToday ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: compact ? 15 : 16, weight: .semibold))
                            .foregroundStyle(habitTint(for: habit))
                    }

                    Spacer(minLength: 0)

                    Text(habit.title)
                        .font(.system(size: compact ? 11 : 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(compact ? 2 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(habit.currentStreak > 0 ? "\(habit.currentStreak)d streak" : habit.frequencyLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                }
                .padding(compact ? 10 : 11)
                .frame(maxWidth: .infinity, minHeight: compact ? 74 : 82, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(habitBackground(for: habit))
                )
            }
            .buttonStyle(.plain)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(minHeight: compact ? 74 : 82)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.28))
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
            colors: [Color.white.opacity(0.08), tint.opacity(0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func habitTint(for habit: CadenceHabitWidgetHabit) -> Color {
        habit.isDoneToday ? .white : Color(hex: habit.colorHex)
    }

    private func paddedHabits(count: Int) -> [CadenceHabitWidgetHabit?] {
        let visible = Array(entry.snapshot.habits.prefix(max(count, 0))).map(Optional.some)
        let remainder = max(0, count - visible.count)
        return visible + Array(repeating: nil, count: remainder)
    }
}
