import Foundation
import SwiftUI

enum CadenceScheduleSupport {
    /// The hours every day canvas in the app draws: the whole day, `00:00..<24:00`.
    ///
    /// It used to be `6..<23` here and `0..<24` in macOS's two globals — the same idea spelled
    /// three times, and the two spellings disagreed. A task at 05:00 or 23:30 had no row of its
    /// own on iOS: it was clamped into 06:00 or 22:00, printing a time the row it sat in
    /// contradicted. A window is only worth having if something outside it cannot exist, and the
    /// task detail's time picker offers every quarter hour of the day.
    ///
    /// `schedStartHour` / `schedEndHour` (macOS schedule panel) and `calStartHour` / `calEndHour`
    /// (macOS calendar page) are now aliases of these two, so there is one number to change and
    /// `CalendarTimelineRangeTests.everyTimelineOnEveryPlatformDrawsTheSameHours` fails if a
    /// fourth spelling appears.
    static let calendarStartHour = 0
    static let calendarEndHour = 24

    /// The hour rows a day canvas draws, in order — `ForEach(CadenceScheduleSupport.calendarHours)`
    /// rather than a fourth place that writes `calendarStartHour..<calendarEndHour` by hand.
    static var calendarHours: Range<Int> { calendarStartHour..<calendarEndHour }

    static var calendarHourCount: Int { calendarEndHour - calendarStartHour }

    // `includeCompleted` is deliberately **not** defaulted on any function below.
    //
    // There were five siblings over the same data carrying three different default polarities
    // (`tasks` true, `scheduledTasks` false, `bundles` true, `tasksByScheduledDate` false,
    // `bundlesByDate` false), so a caller could not form a habit — each call needed the
    // declaration open to know what it did. The result was visible: the macOS calendar page
    // draws completed *tasks* (it passed `true`) but drops completed *bundles* (it took the
    // default), and macOS's schedule panel keeps completed items while iPad Today drops them,
    // in both cases purely according to whether someone typed the argument. Requiring it makes
    // each surface's choice a statement rather than an accident.
    //
    // The sixth, `tasks(on:from:includeCompleted:)`, was deleted outright — it had no callers,
    // and it was the source of the `= true` precedent the other two copied.

    /// The one ordering for scheduled task rows on a day: start minute, then the app's total
    /// task tie-break.
    ///
    /// Both callers below used to stop at a bare `$0.order < $1.order`. `order` is assigned
    /// **per container** — `CadenceTaskQuerySupport.nextTaskOrder(in:)` maxes over one list —
    /// so two tasks scheduled at the same minute out of two different lists compared equal in
    /// both directions and `sorted` was free to return either arrangement. Every surface these
    /// functions feed is cross-list: iPad Today, the iOS calendar, and the macOS calendar page
    /// and schedule panel. `TaskOrdering.fallbackPrecedes` closes it on `id`, and it lives in
    /// `Models/`, which every target compiles.
    nonisolated static func scheduledTaskPrecedes(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        if lhs.scheduledStartMin != rhs.scheduledStartMin {
            return lhs.scheduledStartMin < rhs.scheduledStartMin
        }
        return TaskOrdering.fallbackPrecedes(lhs, rhs)
    }

    /// The one ordering for bundle rows: day, start minute, title, then id — **total**, for the
    /// same reason. Nothing in `TaskBundle` stops two bundles sharing a `dateKey` and a
    /// `startMin`, and `startMin` alone was the entire comparator at both call sites below.
    ///
    /// `displayTitle` rather than `title` because that is the string the row draws: an untitled
    /// bundle reads "Block" on screen and should sort where it reads. (It read "Task Bundle" until
    /// T-567 gave the noun one home in `TaskBundle.defaultDisplayTitle`; sorting on `title` would
    /// have put every untitled bundle at the top under an empty string either way.)
    nonisolated static func bundlePrecedes(_ lhs: TaskBundle, _ rhs: TaskBundle) -> Bool {
        if lhs.dateKey != rhs.dateKey { return lhs.dateKey < rhs.dateKey }
        if lhs.startMin != rhs.startMin { return lhs.startMin < rhs.startMin }
        let titles = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
        if titles != .orderedSame { return titles == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func scheduledTasks(
        on dateKey: String,
        from tasks: [AppTask],
        includeCompleted: Bool,
        excludeBundled: Bool
    ) -> [AppTask] {
        tasks
            .filter {
                !$0.isCancelled &&
                (includeCompleted || !$0.isDone) &&
                (!excludeBundled || $0.bundle == nil) &&
                $0.scheduledDate == dateKey &&
                $0.scheduledStartMin >= 0
            }
            .sorted(by: scheduledTaskPrecedes)
    }

    static func bundles(on dateKey: String, from bundles: [TaskBundle], includeCompleted: Bool) -> [TaskBundle] {
        bundles
            .filter { $0.dateKey == dateKey && (includeCompleted || !$0.isCompleted) }
            .sorted(by: bundlePrecedes)
    }

    /// Which hour row of an hour-by-hour day list a scheduled minute belongs in.
    ///
    /// The clamp is no longer doing the job it was written for. It was added because the row list
    /// ran `6..<23` while the task detail's time picker offered every quarter hour, so a task at
    /// 05:00 matched no row *and* was not in "Ready to Schedule" (which needs
    /// `scheduledStartMin == -1`) — it vanished from the pane. Now that the rows are the whole day
    /// every real minute-of-day has a row of its own and nothing is clamped.
    ///
    /// It stays because the argument is an `Int`, not a time. `bundles(inHourRow:)` reads
    /// `TaskBundle.startMin` with no lower-bound filter of its own, and both fields are plain
    /// stored properties that a drag, a bad import or a CloudKit row from an older build can leave
    /// outside `0..<1440`. Clamping keeps such an item visible in the first or last row — where it
    /// still prints its own real time range — instead of dropping it out of the pane silently,
    /// which is the failure this function exists to prevent.
    static func timelineHourRow(
        forMinute minute: Int,
        startHour: Int = calendarStartHour,
        endHour: Int = calendarEndHour
    ) -> Int {
        let lastRow = max(startHour, endHour - 1)
        return min(max(minute / 60, startHour), lastRow)
    }

    static func tasks(
        inHourRow hour: Int,
        from tasks: [AppTask],
        startHour: Int = calendarStartHour,
        endHour: Int = calendarEndHour
    ) -> [AppTask] {
        // `scheduledStartMin == -1` means "no time at all", which belongs in the unscheduled
        // list, not clamped into the first row.
        tasks.filter {
            $0.scheduledStartMin >= 0 &&
            timelineHourRow(forMinute: $0.scheduledStartMin, startHour: startHour, endHour: endHour) == hour
        }
    }

    static func bundles(
        inHourRow hour: Int,
        from bundles: [TaskBundle],
        startHour: Int = calendarStartHour,
        endHour: Int = calendarEndHour
    ) -> [TaskBundle] {
        bundles.filter {
            timelineHourRow(forMinute: $0.startMin, startHour: startHour, endHour: endHour) == hour
        }
    }

    /// The hour a freshly opened day timeline should be scrolled to.
    ///
    /// A timeline draws from `calendarStartHour` and a scroll view opens at its top, so a canvas
    /// left to itself opens at its first hour whatever the time of day. That was already wrong at
    /// 6 AM; at midnight it is worse, and the grid now starts at midnight. When the span on screen
    /// includes **today** the answer is the current hour, backed off by `leadHours` so the hour
    /// just gone is still visible for context. Otherwise there is no "now" to honour, and the best
    /// available default is the user's own work-hours start — the same `calendar.workHours.*.v1`
    /// window the amber band on each column already draws — rather than a second hardcoded hour.
    ///
    /// This is **derived on every open and never persisted**. A measured or derived scroll offset
    /// written into a defaults key is what put the Calendar Board seven months in the past
    /// (`ecaf80f`): a garbage reading became a saved anchor and compounded across launches.
    static func initialTimelineHour(
        showsToday: Bool,
        now: Date = Date(),
        workHoursStartMinute: Int = CalendarWorkHoursPreferences.defaultStartMinute,
        leadHours: Int = 1,
        startHour: Int = calendarStartHour,
        endHour: Int = calendarEndHour,
        calendar: Calendar = .current
    ) -> Int {
        let lastHour = max(startHour, endHour - 1)
        let preferred: Int
        if showsToday {
            preferred = calendar.component(.hour, from: now) - max(0, leadHours)
        } else {
            preferred = CalendarWorkHoursPreferences.normalizedStartMinute(workHoursStartMinute) / 60
        }
        return min(max(preferred, startHour), lastHour)
    }

    /// Where that hour sits in a day canvas whose rows are `hourHeight` tall — the content offset a
    /// scroll view is placed at, not a persisted value.
    ///
    /// `topInset` is whatever the canvas scrolls *past* before its first hour line: on iOS the day
    /// header band with the day numbers and their chips. Leaving it out placed every hour one
    /// header too high, which reads as the rule being off by an hour rather than the geometry.
    static func timelineScrollOffset(
        forHour hour: Int,
        hourHeight: CGFloat,
        startHour: Int = calendarStartHour,
        topInset: CGFloat = 0
    ) -> CGFloat {
        max(0, topInset + CGFloat(hour - startHour) * max(0, hourHeight))
    }

    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func dates(containing anchorDate: Date, mode: CadenceCalendarViewMode, calendar: Calendar = .current) -> [Date] {
        let start: Date
        switch mode {
        case .week, .twoWeeks:
            start = startOfWeek(containing: anchorDate, calendar: calendar)
        case .month:
            start = calendar.startOfDay(for: anchorDate)
        }

        return (0..<mode.daysCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    static func shiftedDate(_ date: Date, mode: CadenceCalendarViewMode, by value: Int, calendar: Calendar = .current) -> Date {
        switch mode {
        case .week:
            return calendar.date(byAdding: .day, value: value * 7, to: date) ?? date
        case .twoWeeks:
            return calendar.date(byAdding: .day, value: value * 14, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: value, to: date) ?? date
        }
    }

    /// Column headings for a grid built by `monthGridDays`, in that grid's own column order.
    ///
    /// `Calendar.shortWeekdaySymbols` is indexed by weekday *number*, so `[0]` is always Sunday
    /// no matter what `firstWeekday` is: it is localized in content but fixed in order. The grid
    /// below snaps to `firstWeekday` via `dateInterval(of: .weekOfMonth)`, so pairing the two
    /// directly labelled every cell with the wrong weekday outside Sunday-first regions — in
    /// Germany the header read `So Mo Di…` over columns that started on Monday, and in Saudi
    /// Arabia the skew was six columns. The labels being in the right language is what made it
    /// hard to see. Rotating here keeps the headings and the columns derived from one place.
    /// How wide a weekday heading spells itself. Both month grids read this rather than each
    /// hand-rolling an array, because they drifted apart while they did: the macOS date picker
    /// hard-coded a Sunday-first `["Su", "Mo", …]` while this function rotated a *localized* array,
    /// so the two disagreed about the order in Monday-first regions and about the language
    /// everywhere else.
    enum WeekdaySymbolWidth {
        /// `Sun` — the iOS month grid, which has the room.
        case short
        /// `Su` — the compact date-picker panel, which does not.
        case compact
    }

    /// English weekday headings, rotated to the locale's own week start.
    ///
    /// The split is deliberate and is the whole point of this function. **Language is pinned**, for
    /// the reason `DateFormatters` pins every fixed-format formatter: the app is English-only, so a
    /// localized array rendered `周日 周一` beside untranslated chrome. **Week start is not pinned**,
    /// because `firstWeekday` is not a language preference — a UK or German user wants Monday first
    /// in an English app, and honouring that is correct rather than a half-measure.
    ///
    /// When the app is actually localized (`docs/TODO.md` T-18) the pin comes off and this returns
    /// `calendar.shortWeekdaySymbols` again.
    static func weekdaySymbols(
        calendar: Calendar = .current,
        width: WeekdaySymbolWidth = .short
    ) -> [String] {
        var english = Calendar(identifier: calendar.identifier)
        english.locale = Locale(identifier: "en_US_POSIX")
        let base = english.shortWeekdaySymbols
        let symbols = width == .compact ? base.map { String($0.prefix(2)) } : base
        let offset = calendar.firstWeekday - 1
        guard symbols.count == 7, offset > 0, offset < 7 else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// How many blank cells precede the 1st in a month grid, given where the locale starts its week.
    ///
    /// The macOS picker computed this as `weekday - 1`, which is Sunday-first unconditionally — so
    /// in a Monday-first region its grid was shifted by one against its own headings. Sharing the
    /// arithmetic is what stops the headings and the cells disagreeing.
    static func leadingBlankCount(forFirstOf month: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: month)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    static func monthGridDays(for monthDate: Date, calendar: Calendar = .current) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate),
              let gridStart = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)?.start,
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let gridEnd = calendar.dateInterval(of: .weekOfMonth, for: lastDay)?.end
        else { return [] }

        var result: [Date] = []
        var cursor = gridStart
        while cursor < gridEnd {
            result.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd
        }
        return result
    }

    static func calendarTitle(for anchorDate: Date, mode: CadenceCalendarViewMode, calendar: Calendar = .current) -> String {
        switch mode {
        case .month:
            return DateFormatters.monthYear.string(from: anchorDate)
        case .week, .twoWeeks:
            let days = dates(containing: anchorDate, mode: mode, calendar: calendar)
            guard let first = days.first, let last = days.last else {
                return DateFormatters.monthYear.string(from: anchorDate)
            }
            if calendar.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(DateFormatters.monthAbbrev.string(from: first)) \(DateFormatters.dayNumber.string(from: first))-\(DateFormatters.dayNumber.string(from: last))"
            }
            return "\(DateFormatters.monthAbbrev.string(from: first)) \(DateFormatters.dayNumber.string(from: first)) - \(DateFormatters.monthAbbrev.string(from: last)) \(DateFormatters.dayNumber.string(from: last))"
        }
    }

    static func tasksByScheduledDate(_ tasks: [AppTask], includeCompleted: Bool) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil &&
            task.scheduledStartMin >= 0 &&
            !task.scheduledDate.isEmpty &&
            !task.isCancelled &&
            (includeCompleted || !task.isDone) {
            result[task.scheduledDate, default: []].append(task)
        }
        return result.mapValues { $0.sorted(by: scheduledTaskPrecedes) }
    }

    static func unscheduledTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil &&
            task.scheduledStartMin == -1 &&
            !task.scheduledDate.isEmpty &&
            !task.isCancelled &&
            !task.isDone {
            result[task.scheduledDate, default: []].append(task)
        }
        return result.mapValues { CadenceTaskQuerySupport.sortedTasks($0, sortMode: .priority) }
    }

    static func monthTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil && !task.isCancelled {
            if !task.scheduledDate.isEmpty {
                result[task.scheduledDate, default: []].append(task)
            } else if !task.dueDate.isEmpty {
                result[task.dueDate, default: []].append(task)
            }
        }
        return result.mapValues { CadenceTaskQuerySupport.sortedTasks($0, sortMode: .priority) }
    }

    static func bundlesByDate(_ bundles: [TaskBundle], includeCompleted: Bool) -> [String: [TaskBundle]] {
        var result: [String: [TaskBundle]] = [:]
        for bundle in bundles where includeCompleted || !bundle.isCompleted {
            result[bundle.dateKey, default: []].append(bundle)
        }
        return result.mapValues { $0.sorted(by: bundlePrecedes) }
    }

    static func items<T>(on dateKey: String, in itemsByDate: [String: [T]]) -> [T] {
        itemsByDate[dateKey] ?? []
    }

    static func dueOnlyTasks(on dateKey: String, from tasks: [AppTask]) -> [AppTask] {
        CadenceTaskQuerySupport.sortedTasks(
            tasks.filter {
                !$0.isCancelled &&
                !$0.isDone &&
                $0.dueDate == dateKey &&
                $0.scheduledDate != dateKey
            },
            sortMode: .priority
        )
    }

    static func calendarDayTasks(on dateKey: String, from tasks: [AppTask]) -> [AppTask] {
        CadenceTaskQuerySupport.sortedTasks(
            tasks.filter {
                !$0.isCancelled &&
                ($0.scheduledDate == dateKey || $0.dueDate == dateKey)
            },
            sortMode: .priority
        )
    }

    /// The minutes-from-midnight span an event occupies **on one particular day**.
    ///
    /// Taking only the hour/minute of each end (which is what the iOS timeline did) throws away
    /// the day, so anything crossing midnight came out with `end < start`: a 23:00 → 00:00 event
    /// fell through to the 15-minute floor, and every day of a multi-day timed event drew the
    /// same sliver. Clamping to the day's own bounds instead gives the part of the event that
    /// belongs on this column, and a day fully inside the event spans the whole column.
    static func minuteRange(
        from startDate: Date,
        to endDate: Date,
        on day: Date,
        calendar: Calendar = .current
    ) -> (start: Int, end: Int) {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)

        let clampedStart = min(max(startDate, dayStart), dayEnd)
        let clampedEnd = min(max(endDate, clampedStart), dayEnd)

        let start = Int(clampedStart.timeIntervalSince(dayStart) / 60)
        let end = Int(clampedEnd.timeIntervalSince(dayStart) / 60)
        return (start, max(start + 15, end))
    }

    /// The same span, clamped into the hours a day column actually draws, so a block that runs
    /// past the last hour line is trimmed rather than painted outside the grid. The label keeps
    /// the true range; only the geometry is clamped.
    static func timelineVisibleRange(
        start: Int,
        end: Int,
        startHour: Int = calendarStartHour,
        endHour: Int = calendarEndHour
    ) -> (start: Int, end: Int) {
        let lowerBound = startHour * 60
        let upperBound = endHour * 60
        let clampedStart = min(max(start, lowerBound), max(lowerBound, upperBound - 15))
        let clampedEnd = min(max(end, clampedStart + 15), upperBound)
        return (clampedStart, max(clampedStart + 15, clampedEnd))
    }

    static func blockRange(startMinute: Int, fallbackDuration: Int) -> (start: Int, end: Int) {
        let start = max(calendarStartHour * 60, startMinute)
        let duration = max(15, fallbackDuration)
        let end = min(calendarEndHour * 60, start + duration)
        return (start, max(start + 15, end))
    }

    static func timeRangeLabel(startMinute: Int, endMinute: Int) -> String {
        TimeFormatters.timeRange(startMin: startMinute, endMin: endMinute)
    }

    // MARK: - Ready-to-schedule slots

    /// The grid the one-tap slots snap to. Half hours, which is also the granularity
    /// `CalendarWorkHoursPreferences.selectable*Minutes` offers, so a work window can never fall
    /// between two candidates.
    static let scheduleSlotStep = 30

    /// The minutes already taken on a day, as half-open `start..<end` spans — what a suggested slot
    /// must not land inside.
    static func busyMinuteRanges(tasks: [AppTask], bundles: [TaskBundle]) -> [Range<Int>] {
        let taskRanges: [Range<Int>] = tasks.compactMap { task in
            guard task.scheduledStartMin >= 0 else { return nil }
            let end = max(task.scheduledEndMin, task.scheduledStartMin + 1)
            return task.scheduledStartMin..<end
        }
        let bundleRanges: [Range<Int>] = bundles.map { bundle in
            bundle.startMin..<max(bundle.endMin, bundle.startMin + 1)
        }
        return taskRanges + bundleRanges
    }

    /// The one-tap start times offered beside a task that has a day but no time.
    ///
    /// These were three literals — 9 AM, 1 PM, 4 PM — chosen when the timeline drew 6 AM to 11 PM.
    /// Against the full 24-hour grid they cover much less of the day, and none of the three knows
    /// anything about the day it is being offered on: they are unchanged at 6 PM, and unchanged
    /// when all three hours are already booked solid.
    ///
    /// The replacement is derived from three things the app already holds:
    /// - **now**, so a slot is never in the past. The earliest candidate is the next half hour.
    /// - **the work-hours window** (`calendar.workHours.*.v1`, the same band the day timeline draws
    ///   in amber), so the suggestions sit inside the hours the user actually works. When what is
    ///   left of that window cannot supply `count` free slots — late in the day, or a full
    ///   calendar — the search widens to the rest of the day rather than repeating a booked hour.
    /// - **the day's existing blocks**, so a slot that would collide with something already
    ///   scheduled is not offered.
    ///
    /// The result is spread across the searched window rather than taken from the front of it:
    /// three adjacent half hours are one choice presented three times. It is never empty — at
    /// 23:50 the honest answer is a single 11:30 PM chip, not a row of controls that cannot fire.
    static func readyScheduleSlots(
        now: Date = Date(),
        workStartMinute: Int = CalendarWorkHoursPreferences.defaultStartMinute,
        workEndMinute: Int = CalendarWorkHoursPreferences.defaultEndMinute,
        busyRanges: [Range<Int>] = [],
        durationMinutes: Int = 30,
        count: Int = 3,
        calendar: Calendar = .current
    ) -> [Int] {
        let step = scheduleSlotStep
        let duration = max(15, durationMinutes)
        let dayEnd = calendarEndHour * 60
        let lastStart = max(0, ((dayEnd - duration) / step) * step)
        let work = CalendarWorkHoursPreferences.normalizedRange(
            startMinute: workStartMinute,
            endMinute: workEndMinute
        )

        let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let earliest = min(roundedUpToStep(nowMinute, step: step), lastStart)
        let lowerBound = min(max(earliest, roundedUpToStep(work.startMinute, step: step)), lastStart)
        let workUpperBound = min(((work.endMinute - duration) / step) * step, lastStart)

        func freeSlots(through upperBound: Int) -> [Int] {
            guard upperBound >= lowerBound else { return [] }
            return stride(from: lowerBound, through: upperBound, by: step).filter { start in
                let end = start + duration
                return !busyRanges.contains { $0.lowerBound < end && start < $0.upperBound }
            }
        }

        var pool = freeSlots(through: workUpperBound)
        if pool.count < count {
            let widened = freeSlots(through: lastStart)
            if widened.count > pool.count { pool = widened }
        }
        if pool.isEmpty {
            // Every remaining half hour is booked. Offering the next one anyway beats offering
            // nothing: the row's only actions are these chips.
            pool = Array(stride(from: lowerBound, through: lastStart, by: step))
        }

        return spread(pool, count: count)
    }

    private static func roundedUpToStep(_ minute: Int, step: Int) -> Int {
        guard step > 0 else { return minute }
        let clamped = max(0, minute)
        return ((clamped + step - 1) / step) * step
    }

    /// `count` values taken evenly across `pool`, first and last included, in order and deduplicated.
    private static func spread(_ pool: [Int], count: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard pool.count > count else { return pool }
        guard count > 1 else { return [pool[0]] }

        var picked: [Int] = []
        for step in 0..<count {
            let index = (step * (pool.count - 1)) / (count - 1)
            let value = pool[index]
            if picked.last != value { picked.append(value) }
        }
        return picked
    }
}
