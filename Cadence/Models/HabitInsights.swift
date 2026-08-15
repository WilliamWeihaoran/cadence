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
        last7DayStates(asOf: Date(), calendar: .current)
    }

    /// Reference-date and calendar injectable variant of `last7DayStates`, for the same reason
    /// `currentStreak(asOf:calendar:)` has one: the walk uses `date(byAdding: .day,)`, which
    /// preserves wall-clock time and therefore drifts across a midnight DST transition.
    ///
    /// Returns exactly seven states, oldest first, with today last. It used to `compactMap` the
    /// day walk, which silently *shortened* the array when a date could not be formed — the iOS
    /// dot strip would then draw six dots and every dot after the gap would label the wrong day.
    /// A day that cannot be built is `false` (not completed), never a missing element.
    func last7DayStates(asOf referenceDate: Date, calendar: Calendar = .current) -> [Bool] {
        let today = calendar.startOfDay(for: referenceDate)
        let keys = completionDateKeys
        return (0..<7).reversed().map { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return keys.contains(DateFormatters.dateKey(from: date, calendar: calendar))
        }
    }

    var last30DayCompletionRate: Int {
        last30DayCompletionRate(asOf: Date(), calendar: .current)
    }

    /// What the rate above is a percentage *of*, for the tile that displays it.
    ///
    /// This exists because the two disagreed: every caller hardcoded "30 days" while a
    /// `.timesPerWeek` habit is scored over four whole ISO weeks — no per-day due rule can score a
    /// weekly-target habit coherently. A label naming a window the number was not measured over is
    /// the same defect as a control that looks wired and is not; publishing it beside the value is
    /// what stops the two drifting apart again.
    nonisolated var completionRateWindowLabel: String {
        frequencyType == .timesPerWeek ? "4 weeks" : "30 days"
    }

    /// Reference-date and calendar injectable variant of `last30DayCompletionRate`.
    ///
    /// The percentage is over the days the habit was actually *due* in the window, not over all
    /// 30 days — a Mon/Wed/Fri habit kept perfectly reads 100%, not 43%. With no due days in the
    /// window there is nothing to be a percentage of, so the answer is 0 rather than a made-up
    /// 100.
    func last30DayCompletionRate(asOf referenceDate: Date, calendar: Calendar = .current) -> Int {
        if frequencyType == .timesPerWeek {
            return recentWeeklyTargetRate(asOf: referenceDate, calendar: calendar)
        }

        let today = calendar.startOfDay(for: referenceDate)
        let keys = completionDateKeys
        var due = 0
        var done = 0

        for i in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            if isDue(on: date, calendar: calendar) {
                due += 1
                if keys.contains(DateFormatters.dateKey(from: date, calendar: calendar)) {
                    done += 1
                }
            }
        }

        if due == 0 {
            return 0
        }
        return Int((Double(done) / Double(due) * 100).rounded())
    }

    /// The `.timesPerWeek` half of the 30-day rate, scored in weeks.
    ///
    /// A weekly-target habit has no due *days*, so the day-by-day walk above cannot describe it —
    /// which is exactly how a "Gym, 3x/week" habit kept perfectly for a month came to read 43%
    /// (13 check-ins over 30 unconditionally-due days) beside a healthy streak.
    ///
    /// The unit that means something here is the one `weeklyStreak` already uses: the fixed
    /// Monday-start (ISO) week. Each of the four most recent **complete** weeks earns
    /// `min(weekTotal, target)` out of `target`, so a perfectly kept habit reads 100%, a habit
    /// that manages two of three every week reads 67%, and an extra check-in cannot push a week
    /// past its own target. The in-progress week is left out rather than scored short — the same
    /// forgiveness `currentStreak` gives it.
    private func recentWeeklyTargetRate(asOf referenceDate: Date, calendar: Calendar, weeks: Int = 4) -> Int {
        let isoCalendar = Habit.isoWeekCalendar(inheritingTimeZoneFrom: calendar)
        guard weeks > 0,
              let currentWeekStart = isoCalendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
        else { return 0 }

        let counts = completionCountsByDate()
        let target = max(1, targetCount)
        var earned = 0
        var weekStart = currentWeekStart

        for _ in 0..<weeks {
            guard let previous = isoCalendar.date(byAdding: .day, value: -7, to: weekStart) else { break }
            weekStart = isoCalendar.startOfDay(for: previous)

            var total = 0
            var cursor = weekStart
            for _ in 0..<7 {
                total += counts[DateFormatters.dateKey(from: cursor, calendar: isoCalendar)] ?? 0
                guard let next = isoCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = isoCalendar.startOfDay(for: next)
            }
            earned += min(total, target)
        }

        return Int((Double(earned) / Double(target * weeks) * 100).rounded())
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
