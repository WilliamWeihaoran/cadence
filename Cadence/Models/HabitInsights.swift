import Foundation

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
            return frequencyDays.contains(Self.weekdayIndex(for: date, calendar: cal))
        case .timesPerWeek:
            return true
        case .monthly:
            let day = cal.component(.day, from: date)
            let target = frequencyDays.first ?? 1
            let range = cal.range(of: .day, in: .month, for: date)
            let lastDay = range?.upperBound.advanced(by: -1) ?? 31
            return day == min(max(1, target), lastDay)
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
