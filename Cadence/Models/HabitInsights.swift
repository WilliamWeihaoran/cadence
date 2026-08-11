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

    /// Kept as a property because that is how the iOS detail view reads it
    /// (`iOSFeatureDetailViews.swift`); the implementation lives on `Habit.bestStreak(asOf:calendar:)`
    /// so it shares `currentStreak`'s definition of a streak instead of inventing a second,
    /// incompatible one. Not dead — a dead-code pass removed it once and broke the build.
    var bestStreak: Int {
        bestStreak()
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
