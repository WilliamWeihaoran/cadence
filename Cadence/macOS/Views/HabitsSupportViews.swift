#if os(macOS)
import SwiftUI

enum HabitListFilter: CaseIterable {
    case today
    case completed
    case streaking
    case all

    var label: String {
        switch self {
        case .today: return "Due Today"
        case .completed: return "Completed Today"
        case .streaking: return "Streaking"
        case .all: return "All"
        }
    }

    func matches(_ habit: Habit) -> Bool {
        switch self {
        case .today:
            return habit.isDueToday
        case .completed:
            return habit.isDone(on: DateFormatters.todayKey())
        case .streaking:
            return habit.currentStreak >= 3
        case .all:
            return true
        }
    }
}

struct HabitListCard: View {
    let habit: Habit
    let todayKey: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    private var isDoneToday: Bool {
        habit.isDone(on: todayKey)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: habit.colorHex).opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: habit.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: habit.colorHex))
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(habit.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        if let ctx = habit.context {
                            Text(ctx.name)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(hex: ctx.colorHex))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: ctx.colorHex).opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 10) {
                        Label(habit.frequencySummary, systemImage: "repeat")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)

                        Label("\(habit.currentStreak)d", systemImage: "flame.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.amber)

                        if habit.isDueToday {
                            Text(isDoneToday ? "Done today" : "Due today")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isDoneToday ? Theme.green : Theme.blue)
                        }
                    }

                    HabitRecentStrip(habit: habit)
                }

                Spacer(minLength: 8)

                Button(action: onToggle) {
                    Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isDoneToday ? Color(hex: habit.colorHex) : Theme.borderSubtle)
                }
                .buttonStyle(.cadencePlain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Theme.surfaceElevated : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.blue.opacity(0.55) : Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct HabitDetailView: View {
    let habit: Habit
    let todayKey: String
    let onToggle: () -> Void

    private var totalCompletions: Int {
        (habit.completions ?? []).count
    }

    private var isDoneToday: Bool {
        habit.isDone(on: todayKey)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 18) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: habit.colorHex).opacity(0.18))
                                .frame(width: 62, height: 62)
                            Image(systemName: habit.icon)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Color(hex: habit.colorHex))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text(habit.title)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Theme.text)

                                if let ctx = habit.context {
                                    Text(ctx.name)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: ctx.colorHex))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: ctx.colorHex).opacity(0.14))
                                        .clipShape(Capsule())
                                }
                            }

                            Text(habit.frequencySummary)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)

                            HStack(spacing: 8) {
                                DetailMetaChip(label: habit.isDueToday ? "Due today" : "Not due today", color: habit.isDueToday ? Theme.blue : Theme.dim.opacity(0.8))
                                DetailMetaChip(label: isDoneToday ? "Checked in" : "Pending", color: isDoneToday ? Theme.green : Theme.amber)
                            }
                        }
                    }

                    Spacer(minLength: 16)

                    Button(action: onToggle) {
                        HStack(spacing: 8) {
                            Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                            Text(isDoneToday ? "Undo Today" : "Check In Today")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isDoneToday ? Theme.green : Color(hex: habit.colorHex))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.cadencePlain)
                }

                HabitInfoCard(title: "Today") {
                    HStack(spacing: 14) {
                        HabitTodayPlanPill(
                            title: habit.isDueToday ? "Due Today" : "Off Today",
                            detail: habit.frequencyShortLabel,
                            tint: habit.isDueToday ? Theme.blue : Theme.dim.opacity(0.9)
                        )
                        HabitTodayPlanPill(
                            title: isDoneToday ? "Checked In" : "Still Open",
                            detail: isDoneToday ? "Nice work" : "Ready when you are",
                            tint: isDoneToday ? Theme.green : Theme.amber
                        )
                        HabitTodayPlanPill(
                            title: "Last 7 Days",
                            detail: "\(habit.last7DayCount) completions",
                            tint: Color(hex: habit.colorHex)
                        )
                    }
                }

                HStack(spacing: 12) {
                    HabitDetailStatCard(
                        title: "Current Streak",
                        value: "\(habit.currentStreak)",
                        subtitle: "days in a row",
                        color: Theme.amber,
                        icon: "flame.fill"
                    )
                    HabitDetailStatCard(
                        title: "Best Streak",
                        value: "\(habit.bestStreak)",
                        subtitle: "best run so far",
                        color: Theme.purple,
                        icon: "trophy.fill"
                    )
                    HabitDetailStatCard(
                        title: "Last 30 Days",
                        value: "\(habit.last30DayCompletionRate)%",
                        subtitle: "consistency",
                        color: Theme.blue,
                        icon: "chart.line.uptrend.xyaxis"
                    )
                    HabitDetailStatCard(
                        title: "Total Check-ins",
                        value: "\(totalCompletions)",
                        subtitle: "all time",
                        color: Color(hex: habit.colorHex),
                        icon: "checkmark.circle.fill"
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    HabitInfoCard(title: "Recent Activity") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(habit.recentCompletionLabels, id: \.self) { label in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(hex: habit.colorHex))
                                    Text(label)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.text)
                                    Spacer()
                                }
                            }

                            if habit.recentCompletionLabels.isEmpty {
                                Text("No recent check-ins yet.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                    }

                    HabitInfoCard(title: "Cadence") {
                        VStack(alignment: .leading, spacing: 10) {
                            HabitMiniProgress(label: "This week", value: "\(habit.thisWeekCount)", detail: habit.thisWeekSummary, tint: Color(hex: habit.colorHex))
                            HabitMiniProgress(label: "Last 7 days", value: "\(habit.last7DayCount)", detail: habit.last7DaySummary, tint: Theme.blue)
                            HabitMiniProgress(label: "Expected rhythm", value: habit.frequencyShortLabel, detail: habit.frequencySummary, tint: Theme.amber)
                        }
                    }
                }

                HabitInfoCard(title: "Activity Heatmap") {
                    HabitHeatmap(habit: habit)
                }
            }
            .padding(24)
        }
        .background(Theme.bg)
    }
}

struct HabitsEmptyDetail: View {
    var body: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.dim)
                Text("Select a habit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Pick a habit on the left to inspect streaks, recent activity, and consistency.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
    }
}

struct HabitSummaryTile: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct HabitDetailStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct HabitInfoCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct HabitMiniProgress: View {
    let label: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.16))
                .frame(width: 8, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct DetailMetaChip: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct HabitRecentStrip: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 5) {
            ForEach(habit.last7DayStates.indices, id: \.self) { index in
                Circle()
                    .fill(habit.last7DayStates[index] ? Color(hex: habit.colorHex) : Theme.borderSubtle)
                    .frame(width: 6, height: 6)
            }
            Text("\(habit.last7DayCount)/7")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
    }
}

struct HabitTodayPlanPill: View {
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Habit Heatmap

struct HabitHeatmap: View {
    let habit: Habit

    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 2
    private let weeks = 52

    private var completionDates: Set<String> {
        Set((habit.completions ?? []).map { $0.date })
    }

    private var cal: Calendar { Calendar.current }

    private var startDate: Date {
        let today = cal.startOfDay(for: Date())
        let daysBack = weeks * 7
        let rawStart = cal.date(byAdding: .day, value: -daysBack, to: today) ?? today
        let weekday = cal.component(.weekday, from: rawStart)
        let offset = weekday - 1
        return cal.date(byAdding: .day, value: -offset, to: rawStart) ?? rawStart
    }

    private var months: [(label: String, weekCol: Int)] {
        var result: [(String, Int)] = []
        var seenMonths = Set<Int>()
        for weekIdx in 0..<weeks {
            guard let weekStart = cal.date(byAdding: .day, value: weekIdx * 7, to: startDate) else { continue }
            let month = cal.component(.month, from: weekStart)
            if !seenMonths.contains(month) {
                seenMonths.insert(month)
                result.append((DateFormatters.monthAbbrev.string(from: weekStart), weekIdx))
            }
        }
        return result
    }

    var body: some View {
        let fmt = DateFormatters.ymd
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 16)
                ForEach(months, id: \.weekCol) { m in
                    Text(m.label)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                        .offset(x: CGFloat(m.weekCol) * (cellSize + gap))
                }
            }

            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { weekIdx in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { dayOfWeek in
                            let dayOffset = weekIdx * 7 + dayOfWeek
                            let date = cal.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
                            let key = fmt.string(from: date)
                            let isDone = completionDates.contains(key)
                            let isFuture = date > Date()

                            RoundedRectangle(cornerRadius: 2)
                                .fill(isFuture ? Color.clear : (isDone ? Color(hex: habit.colorHex) : Theme.borderSubtle))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }
}

extension Habit {
    var completionDateKeys: Set<String> {
        Set((completions ?? []).map(\.date))
    }

    func isDone(on key: String) -> Bool {
        completionDateKeys.contains(key)
    }

    var isDueToday: Bool {
        isDue(on: Calendar.current.startOfDay(for: Date()))
    }

    func isDue(on date: Date) -> Bool {
        let cal = Calendar.current
        switch frequencyType {
        case .daily:
            return true
        case .daysOfWeek:
            let weekday = cal.component(.weekday, from: date)
            let normalized = weekday == 1 ? 7 : weekday - 1
            return frequencyDays.contains(normalized)
        case .timesPerWeek:
            return true
        case .monthly:
            let day = cal.component(.day, from: date)
            let target = frequencyDays.first ?? 1
            return day == target
        }
    }

    var frequencySummary: String {
        switch frequencyType {
        case .daily:
            return "Every day"
        case .daysOfWeek:
            let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let selected = frequencyDays.sorted().compactMap { idx in
                let mapped = idx - 1
                return names.indices.contains(mapped) ? names[mapped] : nil
            }
            return selected.isEmpty ? "Custom days" : selected.joined(separator: ", ")
        case .timesPerWeek:
            return "\(targetCount)x per week"
        case .monthly:
            let day = frequencyDays.first ?? 1
            return "Day \(day) each month"
        }
    }

    var frequencyShortLabel: String {
        switch frequencyType {
        case .daily: return "Daily"
        case .daysOfWeek: return "\(frequencyDays.count)x/week"
        case .timesPerWeek: return "\(targetCount)x/week"
        case .monthly: return "Monthly"
        }
    }

    var bestStreak: Int {
        let dates = completionDateKeys
        let cal = Calendar.current
        var best = 0
        var current = 0
        let today = cal.startOfDay(for: Date())
        for i in stride(from: 365, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            if dates.contains(DateFormatters.dateKey(from: date)) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    var recentCompletionLabels: [String] {
        let sorted = (completions ?? [])
            .sorted { $0.date > $1.date }
            .prefix(5)
        return sorted.compactMap { completion in
            guard let date = DateFormatters.date(from: completion.date) else { return nil }
            return DateFormatters.longDate.string(from: date)
        }
    }

    var last7DayCount: Int {
        completionCount(daysBack: 7)
    }

    var last7DayStates: [Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let keys = completionDateKeys
        return (0..<7).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return keys.contains(DateFormatters.dateKey(from: date))
        }
    }

    var thisWeekCount: Int {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let keys = completionDateKeys
        var count = 0
        for i in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: i, to: start), date <= Date() else { continue }
            if keys.contains(DateFormatters.dateKey(from: date)) {
                count += 1
            }
        }
        return count
    }

    var last7DaySummary: String {
        "\(last7DayCount) check-ins"
    }

    var thisWeekSummary: String {
        if frequencyType == .timesPerWeek {
            return "Goal \(targetCount) times"
        }
        return "So far this week"
    }

    var last30DayCompletionRate: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let keys = completionDateKeys
        var due = 0
        var done = 0

        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            if isDue(on: date) {
                due += 1
                if keys.contains(DateFormatters.dateKey(from: date)) {
                    done += 1
                }
            }
        }

        if due == 0 {
            return 0
        }
        return Int((Double(done) / Double(due) * 100).rounded())
    }

    private func completionCount(daysBack: Int) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let keys = completionDateKeys
        return (0..<daysBack).reduce(0) { partial, offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return partial }
            return partial + (keys.contains(DateFormatters.dateKey(from: date)) ? 1 : 0)
        }
    }
}
#endif
