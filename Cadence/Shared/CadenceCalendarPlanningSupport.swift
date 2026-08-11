import Foundation
import SwiftUI

enum CadenceCalendarViewMode: String, CaseIterable, Hashable {
    case week = "Week"
    case twoWeeks = "2 Weeks"
    case month = "Month"

    static let pickerCases: [CadenceCalendarViewMode] = [.week, .month]

    var daysCount: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 1
        }
    }
}

enum CadenceCalendarPresentation: String, CaseIterable, Hashable {
    case timeline = "Timeline"
    case board = "Board"
}

// MARK: - Board rails

/// The two rails pinned either side of the Calendar Board's day columns.
///
/// A rail is an **inbox**, not a day: Overdue holds work whose do date has already passed,
/// Unscheduled holds work with no do date at all. Neither is a date, which is why the board
/// plates them differently from a day column — see `CalendarBoardRailColumn`.
enum CalendarBoardRail: String, CaseIterable, Identifiable {
    case overdue
    case unscheduled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overdue:     return "OVERDUE"
        case .unscheduled: return "UNSCHEDULED"
        }
    }

    var dotColor: Color {
        switch self {
        case .overdue:     return Theme.red
        case .unscheduled: return Theme.dim
        }
    }

    /// Overdue is derived from a do date already in the past, and backdating a task is never what
    /// a drag means — so the rail refuses drops rather than accepting one and no-oping. Must stay
    /// in agreement with `CalendarBoardPlannerSupport.dropAction(for:)` returning `nil`.
    var acceptsDrops: Bool { self != .overdue }
}

/// Where a card was released on the Calendar Board.
enum CalendarBoardDropTarget: Equatable {
    case day(String)
    case rail(CalendarBoardRail)
}

/// The mutation a board drop performs. Both cases write the task's **do date** — the single field
/// the board buckets on — so every accepted drop visibly lands the card where it was dropped.
enum CalendarBoardDropAction: Equatable {
    case setDoDate(String)
    case clearDoDate
}

/// What a board column's "+" does. A day column knows the date the new card belongs on, so it can
/// insert one inline. The Unscheduled rail has no date to place it on — it is a backlog — so it
/// opens the full create sheet instead, exactly as the Planning page's add row did.
enum CalendarBoardAddAction: Equatable {
    case insertInline(dateKey: String)
    case presentCreateSheet
}

enum CalendarBoardPlannerSupport {
    static let visibleDayCount = 7
    static let defaultRenderDayCount = 3650
    static let plannerRenderDayCount = 420
    static let plannerLeadingDayCount = plannerRenderDayCount / 2
    static let plannerRecenterThreshold = 42
    static let allDaySortMinute = -1
    static let untimedSortMinute = Int.max

    static func date(at dayIndex: Int, bufferStart: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: dayIndex, to: bufferStart) ?? bufferStart)
    }

    /// The first day column a board renders: `plannerLeadingDayCount` days of buffer behind the
    /// anchor, so the board can be scrolled backwards as well as forwards.
    ///
    /// Pass `notBefore` to floor that window at a day — the macOS board passes today, because its
    /// Overdue rail already shows every past-dated card and a past day column would show the same
    /// card twice. The floor is **opt-in**: a board without rails (iOS) has nothing to catch what a
    /// floor would hide, so it keeps the full leading buffer and stays scrollable into the past.
    static func plannerWindowStart(
        for anchorDate: Date,
        notBefore today: Date? = nil,
        calendar: Calendar = .current
    ) -> Date {
        let lead = calendar.date(byAdding: .day, value: -plannerLeadingDayCount, to: anchorDate) ?? anchorDate
        let start = calendar.startOfDay(for: lead)
        guard let today else { return start }
        return max(calendar.startOfDay(for: today), start)
    }

    /// Clamps a board anchor to the first rendered day column, so the toolbar title and the
    /// scrolled-to column can never disagree about which day the board is showing.
    static func clampedBoardDate(
        _ date: Date,
        notBefore today: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        max(calendar.startOfDay(for: today), calendar.startOfDay(for: date))
    }

    static func dayIndex(
        for date: Date,
        bufferStart: Date,
        calendar: Calendar = .current,
        renderDays: Int = defaultRenderDayCount
    ) -> Int {
        let raw = calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: date)).day ?? 0
        return min(max(raw, 0), max(0, renderDays - 1))
    }

    /// Whether the visible column has drifted close enough to an end of the rendered window that
    /// the window should be rebuilt around it. Proximity only — see `recenteredWindowStart`, which
    /// is what callers should ask, because a window can sit against its leading edge legitimately.
    static func shouldRecenter(dayIndex: Int, renderDays: Int = plannerRenderDayCount) -> Bool {
        guard renderDays > plannerRecenterThreshold * 2 else { return false }
        return dayIndex <= plannerRecenterThreshold || dayIndex >= renderDays - plannerRecenterThreshold - 1
    }

    /// The window start to adopt when the visible column nears an edge, or `nil` to leave the
    /// window alone.
    ///
    /// A floored window (`notBefore`) *rests* at day index 0: today is its first column, so the
    /// first six weeks of scrolling sit permanently inside `shouldRecenter`'s leading band. Asking
    /// proximity alone there re-scrolls the board on nearly every column crossing — mid-gesture,
    /// under the user's finger. There is nothing to recenter *toward* once the window already
    /// starts at the floor, so this returns `nil` whenever the rebuilt start would not actually
    /// move, and the trailing edge keeps working unchanged.
    static func recenteredWindowStart(
        visibleDayIndex dayIndex: Int,
        visibleDate: Date,
        currentWindowStart: Date,
        renderDays: Int = plannerRenderDayCount,
        notBefore today: Date? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        guard shouldRecenter(dayIndex: dayIndex, renderDays: renderDays) else { return nil }
        let recentered = plannerWindowStart(for: visibleDate, notBefore: today, calendar: calendar)
        guard !calendar.isDate(recentered, inSameDayAs: currentWindowStart) else { return nil }
        return recentered
    }

    static func title(for anchorDate: Date, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: anchorDate)
        let end = calendar.date(byAdding: .day, value: visibleDayCount - 1, to: start) ?? start
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(DateFormatters.monthAbbrev.string(from: start)) \(DateFormatters.dayNumber.string(from: start))-\(DateFormatters.dayNumber.string(from: end))"
        }
        return "\(DateFormatters.monthAbbrev.string(from: start)) \(DateFormatters.dayNumber.string(from: start)) - \(DateFormatters.monthAbbrev.string(from: end)) \(DateFormatters.dayNumber.string(from: end))"
    }

    static func dateByMovingWindow(_ date: Date, by delta: Int, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: delta * visibleDayCount, to: date) ?? date)
    }

    /// Whether stepping the window by `delta` would actually move it. With the day columns floored
    /// at today, stepping back from the first week clamps straight back to where it started — so
    /// the toolbar arrow that would do it is disabled rather than left as a dead control.
    static func canMoveWindow(
        from date: Date,
        by delta: Int,
        notBefore today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let moved = clampedBoardDate(
            dateByMovingWindow(date, by: delta, calendar: calendar),
            notBefore: today,
            calendar: calendar
        )
        return !calendar.isDate(moved, inSameDayAs: date)
    }

    /// The key the board should write into the calendar's remembered day, or `nil` to leave it be.
    ///
    /// That remembered day belongs to the **timeline**, which browses freely into the past; the
    /// board borrows it as a starting point but clamps it forward to today. Writing the clamped
    /// value straight back would erase a remembered past day the moment the user glanced at the
    /// Board and switched away again. So the board only persists a position it actually moved to:
    /// sitting on the clamped image of what is already remembered writes nothing.
    static func rememberedDateKeyWriteBack(
        boardDate: Date,
        rememberedKey: String,
        notBefore today: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        let boardKey = DateFormatters.dateKey(from: boardDate, calendar: calendar)
        guard let remembered = DateFormatters.date(from: rememberedKey, in: calendar) else { return boardKey }
        let clamped = clampedBoardDate(remembered, notBefore: today, calendar: calendar)
        return calendar.isDate(clamped, inSameDayAs: boardDate) ? nil : boardKey
    }

    /// Day-column bucketing for the **macOS** Calendar Board, which pairs its day columns with the
    /// Overdue and Unscheduled rails.
    ///
    /// Buckets **strictly by do date** — the one field a board drop writes. Folding a due-only task
    /// into its due column instead would mean the board bucketed on either date while every drop
    /// wrote only one of them, so dragging such a card to the Unscheduled rail would clear a do
    /// date it never had and the card would snap straight back. Nothing is lost by leaving it out:
    /// a do-dateless task is exactly what the Unscheduled rail holds.
    ///
    /// A board with no rails must **not** use this — see `tasksByBoardDateFoldingDueDates`.
    static func tasksByBoardDate(from allTasks: [AppTask]) -> [String: [AppTask]] {
        tasksByBoardDate(from: allTasks) { $0.scheduledDate.isEmpty ? nil : $0.scheduledDate }
    }

    /// Day-column bucketing for the **iOS** board, which has no rails: its day columns are the only
    /// place a card can appear. A do-dateless task therefore falls back to its due day rather than
    /// dropping out of the board entirely, which is what bucketing strictly on the do date would do
    /// to it here. Work with neither date is still absent — but it has no day to be shown on.
    static func tasksByBoardDateFoldingDueDates(from allTasks: [AppTask]) -> [String: [AppTask]] {
        tasksByBoardDate(from: allTasks) { task in
            if !task.scheduledDate.isEmpty { return task.scheduledDate }
            return task.dueDate.isEmpty ? nil : task.dueDate
        }
    }

    private static func tasksByBoardDate(
        from allTasks: [AppTask],
        dateKey: (AppTask) -> String?
    ) -> [String: [AppTask]] {
        var grouped: [String: [AppTask]] = [:]

        for task in allTasks {
            guard !task.isCancelled, task.bundle == nil, let key = dateKey(task) else { continue }
            grouped[key, default: []].append(task)
        }

        return grouped.mapValues { tasks in
            tasks.sorted { lhs, rhs in
                boardTaskSort(lhs, rhs)
            }
        }
    }

    // MARK: Rails

    /// Which rail a task belongs to, or `nil` when a day column owns it instead.
    ///
    /// Buckets on the same do date `tasksByBoardDate` and every drop use, so the rails and the day
    /// columns partition the board's open work exactly once — no card in two places, none in none.
    static func rail(for task: AppTask, todayKey: String) -> CalendarBoardRail? {
        let doDate = task.scheduledDate
        guard !doDate.isEmpty else { return .unscheduled }
        return doDate < todayKey ? .overdue : nil
    }

    static func railTasks(from allTasks: [AppTask], todayKey: String) -> [CalendarBoardRail: [AppTask]] {
        var rails: [CalendarBoardRail: [AppTask]] = [:]
        for task in CadenceTaskQuerySupport.openTasks(from: allTasks) where task.bundle == nil {
            guard let rail = rail(for: task, todayKey: todayKey) else { continue }
            rails[rail, default: []].append(task)
        }
        return rails.mapValues { tasks in
            tasks.sorted { lhs, rhs in
                railTaskSort(lhs, rhs)
            }
        }
    }

    /// "N unscheduled · N overdue" — carried over from the Planning page this board absorbed.
    static func railSummaryLine(_ railTasks: [CalendarBoardRail: [AppTask]]) -> String {
        let unscheduled = railTasks[.unscheduled]?.count ?? 0
        let overdue = railTasks[.overdue]?.count ?? 0
        return "\(unscheduled) unscheduled · \(overdue) overdue"
    }

    /// What dropping a card on this target writes. `nil` means the target refuses drops outright —
    /// the drop destination is never installed for it.
    static func dropAction(for target: CalendarBoardDropTarget) -> CalendarBoardDropAction? {
        switch target {
        case .day(let dateKey):
            return dateKey.isEmpty ? nil : .setDoDate(dateKey)
        case .rail(.unscheduled):
            return .clearDoDate
        case .rail(.overdue):
            return nil
        }
    }

    /// What the "+" on this column creates, or `nil` when the column has no add affordance at all
    /// (Overdue, which is a derived state nothing can be created into).
    ///
    /// A day column inserts inline because the column itself supplies the do date. The Unscheduled
    /// rail has no date to supply, so a bare inline insert would leave an untitled, unplaced card
    /// sitting in the backlog; it opens the create sheet instead, which is what the Planning page's
    /// add row did before this board absorbed it.
    static func addAction(for target: CalendarBoardDropTarget) -> CalendarBoardAddAction? {
        switch target {
        case .day(let dateKey):
            return dateKey.isEmpty ? nil : .insertInline(dateKey: dateKey)
        case .rail(.unscheduled):
            return .presentCreateSheet
        case .rail(.overdue):
            return nil
        }
    }

    /// Clearing the do date also drops the timeline slot: a task with no day cannot own a start
    /// minute on one, and leaving `scheduledStartMin` behind would strand it on the timeline.
    static func apply(_ action: CalendarBoardDropAction, to task: AppTask) {
        switch action {
        case .setDoDate(let dateKey):
            task.scheduledDate = dateKey
        case .clearDoDate:
            task.scheduledDate = ""
            task.scheduledStartMin = -1
        }
    }

    /// Ported from the Planning page: order by the task's date anchor, then its timeline slot,
    /// then priority, then manual order.
    static func railTaskSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let lhsKey = railAnchorKey(for: lhs)
        let rhsKey = railAnchorKey(for: rhs)
        if lhsKey != rhsKey { return lhsKey < rhsKey }

        if lhs.scheduledStartMin != rhs.scheduledStartMin {
            if lhs.scheduledStartMin < 0 { return false }
            if rhs.scheduledStartMin < 0 { return true }
            return lhs.scheduledStartMin < rhs.scheduledStartMin
        }

        let lhsPriority = priorityRank(lhs.priority)
        let rhsPriority = priorityRank(rhs.priority)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }

        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// The earliest date the task is anchored to (do date or due date). Used for *ordering* rail
    /// cards only — never for deciding which rail they land in. The sentinel sorts undated work last.
    static func railAnchorKey(for task: AppTask) -> String {
        [task.scheduledDate, task.dueDate]
            .filter { !$0.isEmpty }
            .min() ?? "9999-99-99"
    }

    static func boardTaskSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        sortKey(for: lhs, kindRank: 0) < sortKey(for: rhs, kindRank: 0)
    }

    static func sortKey(for task: AppTask, kindRank: Int) -> CalendarBoardSortKey {
        CalendarBoardSortKey(
            startMinute: task.scheduledStartMin >= 0 ? task.scheduledStartMin : untimedSortMinute,
            kindRank: kindRank,
            plannedRank: task.scheduledDate.isEmpty ? 1 : 0,
            priorityRank: priorityRank(task.priority),
            order: task.order,
            createdAt: task.createdAt,
            id: task.id.uuidString
        )
    }

    static func sortKey(for bundle: TaskBundle, kindRank: Int) -> CalendarBoardSortKey {
        CalendarBoardSortKey(
            startMinute: bundle.startMin,
            kindRank: kindRank,
            plannedRank: 0,
            priorityRank: 0,
            order: 0,
            createdAt: bundle.createdAt,
            id: bundle.id.uuidString
        )
    }

    static func sortKeyForCalendarEvent(
        id: String,
        startMinute: Int,
        isAllDay: Bool,
        kindRank: Int
    ) -> CalendarBoardSortKey {
        CalendarBoardSortKey(
            startMinute: isAllDay ? allDaySortMinute : startMinute,
            kindRank: kindRank,
            plannedRank: 0,
            priorityRank: 0,
            order: 0,
            createdAt: .distantPast,
            id: id
        )
    }

    private static func priorityRank(_ priority: TaskPriority) -> Int { priority.rank }
}

struct CalendarBoardSortKey: Equatable, Comparable {
    let startMinute: Int
    let kindRank: Int
    let plannedRank: Int
    let priorityRank: Int
    let order: Int
    let createdAt: Date
    let id: String

    static func < (lhs: CalendarBoardSortKey, rhs: CalendarBoardSortKey) -> Bool {
        if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
        if lhs.kindRank != rhs.kindRank { return lhs.kindRank < rhs.kindRank }
        if lhs.plannedRank != rhs.plannedRank { return lhs.plannedRank < rhs.plannedRank }
        if lhs.priorityRank != rhs.priorityRank { return lhs.priorityRank > rhs.priorityRank }
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }
}

enum CadenceScheduleSupport {
    static let calendarStartHour = 6
    static let calendarEndHour = 23

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
            .sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
    }

    static func bundles(on dateKey: String, from bundles: [TaskBundle], includeCompleted: Bool) -> [TaskBundle] {
        bundles
            .filter { $0.dateKey == dateKey && (includeCompleted || !$0.isCompleted) }
            .sorted { $0.startMin < $1.startMin }
    }

    static func tasks(in hour: Int, from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { $0.scheduledStartMin / 60 == hour }
    }

    static func bundles(in hour: Int, from bundles: [TaskBundle]) -> [TaskBundle] {
        bundles.filter { $0.startMin / 60 == hour }
    }

    static func itemCount(on dateKey: String, tasks: [AppTask], bundles: [TaskBundle]) -> Int {
        let taskCount = tasks.filter { !$0.isCancelled && ($0.scheduledDate == dateKey || $0.dueDate == dateKey) }.count
        let bundleCount = bundles.filter { $0.dateKey == dateKey }.count
        return taskCount + bundleCount
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
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        guard symbols.count == 7, offset > 0, offset < 7 else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
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
        return result.mapValues { tasks in
            tasks.sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
        }
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
        return result.mapValues { $0.sorted { $0.startMin < $1.startMin } }
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

    static func blockRange(startMinute: Int, fallbackDuration: Int) -> (start: Int, end: Int) {
        let start = max(calendarStartHour * 60, startMinute)
        let duration = max(15, fallbackDuration)
        let end = min(calendarEndHour * 60, start + duration)
        return (start, max(start + 15, end))
    }

    static func timeRangeLabel(startMinute: Int, endMinute: Int) -> String {
        TimeFormatters.timeRange(startMin: startMinute, endMin: endMinute)
    }
}
