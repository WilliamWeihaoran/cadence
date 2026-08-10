import SwiftData
import Foundation

@Model final class Habit {
    var id: UUID = UUID()
    var title: String = ""
    var icon: String = "star.fill"
    var colorHex: String = "#4a9eff"
    var frequencyTypeRaw: String = "daily"

    var frequencyType: HabitFrequency {
        get { HabitFrequency(rawValue: frequencyTypeRaw) ?? .daily }
        set { frequencyTypeRaw = newValue.rawValue }
    }
    /// JSON [Int]: daysOfWeek=[0-6], timesPerWeek=[n], monthly=[dayOfMonth], daily=[]
    var frequencyDaysRaw: String = "[]"
    var targetCount: Int = 1
    var order: Int = 0
    var createdAt: Date = Date()
    /// Minutes from midnight for a daily reminder notification; nil = no reminder set.
    /// Matches the `scheduledStartMin` minutes-from-midnight convention used elsewhere.
    /// `nil` always means "no reminder" and is never conflated with `0` (midnight) since this
    /// is an `Optional<Int>`, not a sentinel value.
    ///
    /// Audit note: there is intentionally NO range clamp/validation here (unlike
    /// `frequencyDays`, whose JSON get/set already degrades malformed input). Values are
    /// expected to be produced by pickers that only ever emit 0...1439, but nothing at the
    /// model layer currently enforces that. Adding enforcement safely would require switching
    /// this to the same raw-storage + computed-property pattern already used for
    /// `frequencyType`/`frequencyDays` in this file, which renames the persisted attribute —
    /// there is no `SchemaMigrationPlan` in `CadenceSchema.swift`, so that rename would silently
    /// drop any reminder time already stored in a user's existing CloudKit data. That's out of
    /// scope for a targeted bug-hunt pass; flagging here rather than fixing blind.
    var reminderMinuteOfDay: Int? = nil

    var context: Context? = nil
    var pursuit: Pursuit? = nil
    var goal: Goal? = nil
    @Relationship(inverse: \HabitCompletion.habit) var completions: [HabitCompletion]? = nil

    /// JSON get/set for `frequencyDaysRaw`. Degrades to `[]` on malformed/corrupt JSON rather
    /// than crashing; does not otherwise validate/clamp element values (callers are expected to
    /// supply day-of-week indices or a single target/day-of-month value depending on
    /// `frequencyType`), so out-of-range ints still round-trip unchanged.
    var frequencyDays: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: Data(frequencyDaysRaw.utf8))) ?? [] }
        set { frequencyDaysRaw = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    /// Consecutive-period streak, aware of `frequencyType` and `HabitCompletion.count` vs.
    /// `targetCount`. Always evaluated as-of "now" using the system calendar; see the
    /// `currentStreak(asOf:calendar:)` overload for the deterministic/testable variant.
    var currentStreak: Int {
        currentStreak(asOf: Date(), calendar: .current)
    }

    /// Calendar/reference-date-injectable variant of `currentStreak`, so tests can pin both
    /// "today" and the timezone/calendar deterministically (e.g. for week- or DST-boundary
    /// regression tests) instead of depending on the wall-clock date at test-run time.
    ///
    /// Semantics by `frequencyType`:
    /// - `.daily` / `.daysOfWeek` / `.monthly`: a day-based streak. Only days the habit is
    ///   actually due (`isDue(on:)`) can extend or break the streak; non-due days are skipped
    ///   without effect. A day is "satisfied" when its total completion count (summed across
    ///   any `HabitCompletion` rows for that date) is >= the per-day requirement — `targetCount`
    ///   for `.daily`/`.monthly` (where it represents a literal per-day quantity), or simply
    ///   "any completion" for `.daysOfWeek` (where `targetCount` instead represents the number
    ///   of scheduled days per week and is unrelated to a single day's count). Exactly one
    ///   currently-due-but-not-yet-completed day ("today", if today is due) is forgiven without
    ///   breaking the streak, matching the pre-existing `.daily` behavior.
    /// - `.timesPerWeek`: a week-based streak using fixed Monday-start (ISO 8601) weeks. A week
    ///   is satisfied when the sum of completion counts across that week is >= `targetCount`,
    ///   met on any day(s) within the week. Exactly one still-in-progress current week is
    ///   forgiven the same way "today" is forgiven for day-based habits.
    func currentStreak(asOf referenceDate: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: referenceDate)
        switch frequencyType {
        case .timesPerWeek:
            return weeklyStreak(referenceToday: today, calendar: calendar)
        case .daily, .daysOfWeek, .monthly:
            return dailyBasedStreak(referenceToday: today, calendar: calendar)
        }
    }

    private func completionCountsByDate() -> [String: Int] {
        var result: [String: Int] = [:]
        for completion in completions ?? [] {
            result[completion.date, default: 0] += max(0, completion.count)
        }
        return result
    }

    private func dailyBasedStreak(referenceToday today: Date, calendar: Calendar) -> Int {
        let counts = completionCountsByDate()
        let requiredPerDay = frequencyType == .daysOfWeek ? 1 : max(1, targetCount)
        // Decoded once for the whole walk rather than once per day inspected. `frequencyDays`
        // allocates a `JSONDecoder` on every read and this loop can visit hundreds of days.
        // Deliberately a local, not a stored property: nothing here can outlive the walk and
        // drift from `frequencyDaysRaw`.
        let days = frequencyDays

        func isSatisfied(_ date: Date) -> Bool {
            (counts[DateFormatters.dateKey(from: date, calendar: calendar)] ?? 0) >= requiredPerDay
        }

        guard var cursor = Self.mostRecentDueDate(onOrBefore: today, habit: self, frequencyDays: days, calendar: calendar) else {
            return 0
        }

        if !isSatisfied(cursor) {
            guard calendar.isDate(cursor, inSameDayAs: today),
                  let dayBefore = calendar.date(byAdding: .day, value: -1, to: cursor),
                  let fallback = Self.mostRecentDueDate(onOrBefore: dayBefore, habit: self, frequencyDays: days, calendar: calendar),
                  isSatisfied(fallback) else {
                return 0
            }
            cursor = fallback
        }

        var streak = 0
        var iterations = 0
        let maxIterations = 3800 // ~10y safety bound against pathological/empty schedules
        while isSatisfied(cursor) {
            streak += 1
            iterations += 1
            if iterations >= maxIterations { break }
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: cursor),
                  let previousDue = Self.mostRecentDueDate(onOrBefore: dayBefore, habit: self, frequencyDays: days, calendar: calendar) else {
                break
            }
            cursor = previousDue
        }
        return streak
    }

    private static func mostRecentDueDate(onOrBefore date: Date, habit: Habit, frequencyDays: [Int], calendar: Calendar) -> Date? {
        var cursor = date
        var iterations = 0
        let maxIterations = 3800
        while !habit.isDue(on: cursor, frequencyDays: frequencyDays, calendar: calendar) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
            cursor = previous
            iterations += 1
            if iterations >= maxIterations { return nil }
        }
        return cursor
    }

    private func weeklyStreak(referenceToday today: Date, calendar: Calendar) -> Int {
        // Weeks are fixed Monday-start (ISO 8601) regardless of locale/system first-weekday,
        // matching the Monday=1...Sunday=7 convention used by `weekdayIndex`. The timezone is
        // still inherited from the caller's calendar so DST-boundary math stays correct.
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone

        let counts = completionCountsByDate()
        let target = max(1, targetCount)

        func weekStart(containing date: Date) -> Date? {
            isoCalendar.dateInterval(of: .weekOfYear, for: date)?.start
        }

        func weekTotal(startingAt start: Date) -> Int {
            var total = 0
            var cursor = start
            for _ in 0..<7 {
                total += counts[DateFormatters.dateKey(from: cursor, calendar: isoCalendar)] ?? 0
                guard let next = isoCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return total
        }

        guard var weekCursor = weekStart(containing: today) else { return 0 }

        if weekTotal(startingAt: weekCursor) < target {
            guard let previousWeek = isoCalendar.date(byAdding: .day, value: -7, to: weekCursor),
                  weekTotal(startingAt: previousWeek) >= target else {
                return 0
            }
            weekCursor = previousWeek
        }

        var streak = 0
        var iterations = 0
        let maxIterations = 600 // ~11.5y of weeks safety bound
        while weekTotal(startingAt: weekCursor) >= target {
            streak += 1
            iterations += 1
            if iterations >= maxIterations { break }
            guard let previousWeek = isoCalendar.date(byAdding: .day, value: -7, to: weekCursor) else { break }
            weekCursor = previousWeek
        }
        return streak
    }

    init(title: String, context: Context? = nil, goal: Goal? = nil) {
        self.title = title
        self.context = context
        self.goal = goal
    }

    static func weekdayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    /// Lives here (not in `HabitInsights.swift`) so this file has no cross-file dependency:
    /// `HabitInsights.swift` isn't included in every target that compiles `Habit.swift` (e.g.
    /// `CadenceMCPServer`), but `currentStreak(asOf:calendar:)` above needs this.
    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        isDue(on: date, frequencyDays: frequencyDays, calendar: calendar)
    }

    /// Variant that takes an already-decoded `frequencyDays`, so a caller walking many dates for
    /// one habit pays the JSON decode once instead of per date. Not a cache: the value is a
    /// parameter with the lifetime of the caller's loop, never stored on the model.
    private func isDue(on date: Date, frequencyDays: [Int], calendar: Calendar = .current) -> Bool {
        switch frequencyType {
        case .daily:
            return true
        case .daysOfWeek:
            return frequencyDays.contains(Self.weekdayIndex(for: date, calendar: calendar))
        case .timesPerWeek:
            return true
        case .monthly:
            let day = calendar.component(.day, from: date)
            let target = frequencyDays.first ?? 1
            let range = calendar.range(of: .day, in: .month, for: date)
            let lastDay = range?.upperBound.advanced(by: -1) ?? 31
            return day == min(max(1, target), lastDay)
        }
    }
}
