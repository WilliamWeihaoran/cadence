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

    /// The width of one day column on a **compact** board, sized so that one column fills the
    /// screen and the *next* one peeks in by `peekFraction` of the container.
    ///
    /// The peek is load-bearing rather than decorative: it is the only thing on a phone that says
    /// there is another day to drag a card onto, which is the board's entire reason to exist as a
    /// mode separate from Week. A fixed 268pt column instead left the neighbour clipped mid-word at
    /// whatever offset the scroll happened to stop at.
    static func compactColumnWidth(
        containerWidth: CGFloat,
        leadingInset: CGFloat,
        columnSpacing: CGFloat,
        peekFraction: CGFloat = 0.17,
        minimumWidth: CGFloat = 200
    ) -> CGFloat {
        let fraction = min(max(peekFraction, 0), 0.5)
        let width = containerWidth * (1 - fraction) - leadingInset - columnSpacing
        return max(minimumWidth, width)
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

    /// Which bundle card, if any, owns a drop landing at `location` in a board day column.
    ///
    /// A day column and the bundle cards inside it are both drop destinations, and one release can
    /// fire both — the column's `schedule` then calls `removeTaskFromBundle` and silently undoes the
    /// bundling the card just did. Which one won used to be decided by a 0.75-second wall-clock
    /// window armed by the card's drop handler and read by the column's, so the outcome depended on
    /// the order SwiftUI happened to deliver two closures in.
    ///
    /// It is a hit test, so it is decided before either handler runs and cannot race: the column
    /// defers exactly when the release point is inside a card the column is drawing. `bundleIDs` is
    /// the column's *current* bundles, so a frame left behind by a card that has since moved to
    /// another day cannot claim a drop.
    ///
    /// Geometry, unlike the timeline's shelf, has to be measured rather than computed: a board
    /// column is a stack of variable-height cards, not a minute axis.
    static func bundleOwningBoardDrop(
        at location: CGPoint,
        bundleIDs: [UUID],
        bundleFrames: [UUID: CGRect]
    ) -> UUID? {
        bundleIDs.first { bundleFrames[$0]?.contains(location) == true }
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

    /// Free-function spelling of `TaskPriority.rank`. Deliberately *not* `private`: this was one
    /// of eight hand-written copies of the same switch, and the only thing keeping the survivors
    /// honest is a test that can name each one
    /// (`TrackingDeleteHelpersTests.priorityRankIsOneOrderingSharedByEveryCaller`). A spelling the
    /// test cannot reach is a spelling free to drift.
    static func priorityRank(_ priority: TaskPriority) -> Int { priority.rank }
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

// MARK: - How a month grid draws a day

/// The treatment a month grid's day badge takes, as the four states it can actually be in.
///
/// The colours are `MonthCalendarPanel`'s — the panel behind every date picker in the app, on both
/// platforms: a **selected** day is a solid `Theme.blue` circle with `Theme.onColor` on it, **today**
/// is `Theme.blue` at `washOpacity` with `Theme.blue` on it, and anything else has no circle at all.
/// The iOS month grids had that pairing the wrong way round — today took the solid fill and the
/// selection took the wash — so the same two facts read as each other's opposite depending on which
/// month surface you were looking at.
///
/// This is the mapping only; the colours are applied at the call sites, because the two grids differ
/// in what "no circle" and "not this month" look like. Keeping the *decision* here is what stops a
/// third and fourth spelling of "today" appearing.
enum CadenceCalendarDayBadge: Hashable, CaseIterable {
    case plain
    case today
    case selected
    /// Today, and the selected day. Needs to be distinguishable from either alone — a grid where
    /// selecting today makes the "today" marker vanish has lost a fact rather than combined two.
    case todayAndSelected

    /// The fill of `Theme.blue` a wash uses. `MonthCalendarPanel`'s number, named once.
    static let washOpacity: Double = 0.15

    static func style(isToday: Bool, isSelected: Bool) -> CadenceCalendarDayBadge {
        switch (isToday, isSelected) {
        case (true, true):   return .todayAndSelected
        case (true, false):  return .today
        case (false, true):  return .selected
        case (false, false): return .plain
        }
    }

    /// The circle behind the day number.
    enum Fill: Hashable {
        /// Whatever the grid's resting cell looks like — no accent at all.
        case none
        /// `Theme.blue` at `washOpacity`.
        case wash
        /// Solid `Theme.blue`.
        case solid
    }

    /// The day number itself.
    enum Label: Hashable {
        /// The grid's ordinary day-number colour, which also carries "not this month".
        case normal
        /// `Theme.blue`, read against a wash.
        case accent
        /// `Theme.onColor`, read against a solid fill.
        case onFill
    }

    var fill: Fill {
        switch self {
        case .plain:                       return .none
        case .today:                       return .wash
        case .selected, .todayAndSelected: return .solid
        }
    }

    var label: Label {
        switch self {
        case .plain:                       return .normal
        case .today:                       return .accent
        case .selected, .todayAndSelected: return .onFill
        }
    }

    /// A ring drawn just outside the badge. The **only** thing separating "today, and selected" from
    /// "selected", since both take the solid fill.
    var showsTodayRing: Bool { self == .todayAndSelected }

    /// Whether the day number is drawn heavier than its neighbours.
    var isEmphasized: Bool { self != .plain }
}

// MARK: - The calendar's date title

/// What the calendar's date title names, and how far from "now" it currently is.
///
/// Every calendar surface now has the same title: the date at the leading edge of what is on screen,
/// with a chevron and a popover that jumps somewhere else. What differs is the *unit* — a timed grid
/// and the Board are looking at a day, Month is looking at a month — and that difference is three
/// paired questions (what does the label say, when is it "now", what does a picked date mean), which
/// is exactly the kind of thing that drifts when it is spelled at the call site.
///
/// This exists because the `‹ ➤ ›` cluster was deleted from all four surfaces. Its middle control
/// was `location.fill` — jump to today, not a direction — so the title had to grow that shortcut
/// before the cluster could go.
enum CadenceCalendarDateTitleFormat: Hashable {
    /// One day: Week, 2 Weeks and the Board, all of which scroll a day at a time.
    case day
    /// One month: the month grid, which scrolls a week row at a time but is read a month at a time.
    case month
}

enum CadenceCalendarDateTitleSupport {
    static func label(
        for date: Date,
        format: CadenceCalendarDateTitleFormat,
        calendar: Calendar = .current
    ) -> String {
        switch format {
        case .day:
            return DateFormatters.shortDate.string(from: date)
        case .month:
            return DateFormatters.monthYear.string(
                from: CadenceCalendarMonthWindow.displayedMonth(topRowStart: date, calendar: calendar)
            )
        }
    }

    /// Whether the title is naming the present. The title renders in `Theme.text` when it is and in
    /// `Theme.blue` when it is not, so the header itself says you have scrolled away — without it a
    /// week in March is indistinguishable at a glance from this one.
    static func isAtNow(
        _ date: Date,
        format: CadenceCalendarDateTitleFormat,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch format {
        case .day:
            return calendar.isDate(date, inSameDayAs: now)
        case .month:
            let displayed = CadenceCalendarMonthWindow.displayedMonth(topRowStart: date, calendar: calendar)
            return calendar.isDate(displayed, equalTo: now, toGranularity: .month)
        }
    }

    /// The day the title's popover should open on. For Month the bound value is a **week row start**,
    /// which is a layout position rather than a date the user ever chose — opening the picker on it
    /// would highlight July 27 under a grid reading "August".
    ///
    /// `displayedMonth` is the right answer for the *title*, and the wrong one for the *seed*: it
    /// resolves the window to its middle day, so an August-aligned window seeded the picker on
    /// August 16 — a day nobody chose and nothing on screen points at, arrived at because six rows
    /// of seven halve to twenty-one. The month is a real reading of the window; the day inside it is
    /// a layout artefact, and the seed is the one place the day is visible.
    ///
    /// So Month names the day itself: **today when the displayed month contains today, otherwise
    /// the first**. Today is the only day of a month the user has a standing relationship with, and
    /// it agrees with `isAtNow` and with the popover's own `Today` row, so the current month opens
    /// with the highlight already where that row would put it. Any other month has no such day, and
    /// the 1st is what "August" means read as a date — stable, and never a number the reader has to
    /// work out. `anchor(forPicked:)` discards the day component either way, so this decides what is
    /// highlighted and nothing about where a pick lands.
    static func pickerDate(
        for date: Date,
        format: CadenceCalendarDateTitleFormat,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        switch format {
        case .day:
            return calendar.startOfDay(for: date)
        case .month:
            let displayed = CadenceCalendarMonthWindow.displayedMonth(topRowStart: date, calendar: calendar)
            if calendar.isDate(displayed, equalTo: now, toGranularity: .month) {
                return calendar.startOfDay(for: now)
            }
            return calendar.dateInterval(of: .month, for: displayed)?.start ?? displayed
        }
    }

    /// The value to write back when a day is picked — the inverse of `pickerDate`. Picking any day of
    /// August in Month scrolls the grid to August's first row, not to the week that day falls in.
    static func anchor(
        forPicked date: Date,
        format: CadenceCalendarDateTitleFormat,
        calendar: Calendar = .current
    ) -> Date {
        switch format {
        case .day:
            return calendar.startOfDay(for: date)
        case .month:
            return CadenceCalendarMonthWindow.topRow(forMonthContaining: date, calendar: calendar)
        }
    }

    /// Where the popover's `Today` row goes. `anchor(forPicked:)` of now, stated separately because
    /// this is the half that replaced a toolbar button and it should be findable by name.
    static func nowAnchor(
        format: CadenceCalendarDateTitleFormat,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        anchor(forPicked: now, format: format, calendar: calendar)
    }
}

// MARK: - Timed grid: zoom

/// How tall an hour is on a timed grid, and what a pinch may do to it.
///
/// The number this replaces was an `Int` 1/2/3 fed through `base + (zoom − 1) × 16`, against a base
/// of 58 (compact) or 64 (regular). So the control labelled "3x" produced 90pt against a 58pt
/// base — about 1.55×. The label was not describing the thing it was attached to, and a continuous
/// pinch makes that kind of discrepancy obvious in a way three discrete steps did not: a user
/// pinching to the stop expects the hour to be three times the hour they started from.
///
/// So `zoom` is now a plain multiplier of the base and nothing else: 1 is the height the grid has
/// always opened at, 3 is three of it (58→174 compact, 64→192 regular). A stored `1`, `2` or `3`
/// from the old control still reads as a legal multiplier, which is why the key did not need to
/// change — see `CalendarTimelineGridTests.zoomStoredByTheOldIntegerControlStillReads`.
enum CadenceCalendarZoom {
    static let minimum: Double = 1
    static let maximum: Double = 3
    static let defaultZoom: Double = 1

    /// The `@AppStorage` key. Named here rather than at the two call sites so the migration note
    /// above sits with the key it is about.
    static let storageKey = "ios.calendar.zoomLevel"

    static func clamp(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return defaultZoom }
        return min(max(zoom, minimum), maximum)
    }

    /// The scale a pinch of `magnification` produces from the zoom it started at, clamped at both
    /// ends. Clamping the *result* rather than the gesture means pinching past a stop and back
    /// returns to where it was, instead of the grid drifting because the excess was accumulated.
    static func zoom(startingFrom startZoom: Double, magnification: CGFloat) -> Double {
        guard magnification.isFinite, magnification > 0 else { return clamp(startZoom) }
        return clamp(clamp(startZoom) * Double(magnification))
    }

    static func hourHeight(base: CGFloat, zoom: Double) -> CGFloat {
        base * CGFloat(clamp(zoom))
    }

    /// The vertical content offset that keeps whatever was under the fingers under the fingers.
    ///
    /// `focusY` is measured from the top of the hour canvas's *viewport*, so `currentOffset +
    /// focusY` is the content point being held; scaling that and putting it back at `focusY` is the
    /// whole rule. Clamped to the scrolled range, because the alternative is asking a scroll view
    /// to go somewhere it cannot and having it silently land somewhere else.
    static func anchoredVerticalOffset(
        currentOffset: CGFloat,
        focusY: CGFloat,
        scale: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return max(0, currentOffset) }
        let held = max(0, currentOffset) + focusY
        let raw = held * scale - focusY
        let maximumOffset = max(0, contentHeight - viewportHeight)
        return min(max(raw, 0), maximumOffset)
    }
}

// MARK: - Timed grid: the day window it scrolls through

/// The day columns a timed grid renders, and how a scroll position maps to a date.
///
/// The grid used to draw exactly `CadenceScheduleSupport.dates(containing:mode:)` — seven columns
/// for Week, fourteen for 2 Weeks — with the toolbar's chevrons rebuilding that window a week at a
/// time. Scrolling sideways reached nothing, because there was nothing either side to reach.
///
/// This is the window the Calendar Board already scrolls through
/// (`CalendarBoardPlannerSupport.plannerRenderDayCount`), reused rather than re-derived: a wide
/// lazy run of day columns with the anchor near its middle, recentred when a scroll approaches
/// either end. The only thing added is the week snap — the window starts on a week boundary, so a
/// Week grid's leading edge lands on a Sunday whenever the user has not deliberately scrolled off
/// one, and every week boundary is a multiple of seven columns in.
enum CadenceCalendarTimelineWindow {
    static let renderDayCount = CalendarBoardPlannerSupport.plannerRenderDayCount

    /// The first day column rendered: half the window behind the anchor, snapped back to the start
    /// of that week. `plannerLeadingDayCount` is 210 — thirty whole weeks — so the snap survives
    /// the subtraction and the window start is itself a week start.
    static func windowStart(for anchorDate: Date, calendar: Calendar = .current) -> Date {
        let weekStart = CadenceScheduleSupport.startOfWeek(containing: anchorDate, calendar: calendar)
        return CalendarBoardPlannerSupport.plannerWindowStart(for: weekStart, calendar: calendar)
    }

    static func date(at index: Int, windowStart: Date, calendar: Calendar = .current) -> Date {
        CalendarBoardPlannerSupport.date(at: index, bufferStart: windowStart, calendar: calendar)
    }

    static func index(for date: Date, windowStart: Date, calendar: Calendar = .current) -> Int {
        CalendarBoardPlannerSupport.dayIndex(
            for: date,
            bufferStart: windowStart,
            calendar: calendar,
            renderDays: renderDayCount
        )
    }

    /// The window to adopt when the leading column nears an end of the rendered run, or `nil` to
    /// leave it alone. Same threshold the Board uses; the no-op guard is what keeps it from
    /// re-scrolling under a finger that is still moving.
    static func recenteredWindowStart(
        leadingIndex: Int,
        leadingDate: Date,
        currentWindowStart: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard CalendarBoardPlannerSupport.shouldRecenter(
            dayIndex: leadingIndex,
            renderDays: renderDayCount
        ) else { return nil }
        let recentered = windowStart(for: leadingDate, calendar: calendar)
        guard !calendar.isDate(recentered, inSameDayAs: currentWindowStart) else { return nil }
        return recentered
    }

    // MARK: Scroll position ↔ column index

    /// The column at the leading edge, for a horizontal content offset.
    static func leadingIndex(scrollOffsetX: CGFloat, columnWidth: CGFloat) -> Int {
        guard columnWidth > 0 else { return 0 }
        let raw = Int((max(0, scrollOffsetX) / columnWidth).rounded())
        return min(max(raw, 0), max(0, renderDayCount - 1))
    }

    /// The content offset that puts `index` at the leading edge.
    static func scrollOffsetX(forIndex index: Int, columnWidth: CGFloat) -> CGFloat {
        CGFloat(min(max(index, 0), max(0, renderDayCount - 1))) * max(0, columnWidth)
    }

    /// The columns actually built, given the one at the leading edge.
    ///
    /// The grid windows its own columns rather than leaning on `LazyHStack`, because the lazy
    /// stack would sit inside a *vertical* scroll view inside the horizontal one — see the note on
    /// `iOSCalendarTimelineGrid` — and which enclosing scroll view drives a lazy stack's visible
    /// region through that nesting is not something to find out in production. Windowing on the
    /// offset this file already reads is the same result with none of the question.
    ///
    /// `margin` columns either side, so a fling has something built to land on and the scroll never
    /// shows a gap before the state catches up.
    static func renderedIndexRange(
        leadingIndex: Int,
        visibleDayCount: Int,
        margin: Int = 7
    ) -> Range<Int> {
        let visible = max(1, visibleDayCount)
        let lower = max(0, leadingIndex - max(0, margin))
        let upper = min(renderDayCount, leadingIndex + visible + max(0, margin))
        guard lower < upper else { return 0..<min(renderDayCount, visible) }
        return lower..<upper
    }

    // MARK: Event fetching

    /// Days of calendar events a timed grid holds at once.
    ///
    /// The grid renders hundreds of columns; it cannot ask EventKit about all of them. It also
    /// cannot ask about exactly what is on screen, because the leading column changes on every
    /// column the user scrolls past and each change would re-run the whole fetch mid-gesture. So
    /// the fetch window is a **week-aligned** four-week span around the leading day: it covers 2
    /// Weeks' fourteen columns with a week of margin either side, and its identity only changes
    /// when the leading column crosses into another week.
    static let eventWindowDayCount = 28

    static func eventWindowStart(leadingDate: Date, calendar: Calendar = .current) -> Date {
        let weekStart = CadenceScheduleSupport.startOfWeek(containing: leadingDate, calendar: calendar)
        return calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
    }

    static func eventWindowDates(leadingDate: Date, calendar: Calendar = .current) -> [Date] {
        let start = eventWindowStart(leadingDate: leadingDate, calendar: calendar)
        return (0..<eventWindowDayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
}
