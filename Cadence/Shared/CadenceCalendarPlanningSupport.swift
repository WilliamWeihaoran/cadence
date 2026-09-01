import Foundation
import SwiftUI

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

    /// The walk both bucketings above share. Three exclusions, and only two of them are mechanical:
    /// a bundled task is drawn by its bundle's card, and a task with no key has no column to sit in.
    ///
    /// `!task.isCancelled` is the third, and it is a **policy, not an oversight**: the Board is what
    /// the Planning page became, and work you have abandoned has no place on a plan. Cancelled tasks
    /// stay reachable in the Completed sections of the list surfaces (T-147) — being off the Board
    /// costs them nothing. Nor is this guard load-bearing for the day column's own active/completed
    /// split, which reads `CadenceTaskQuerySupport.isFinishedTask` and would file a cancelled card
    /// correctly if one ever arrived (T-203). So do not "fix" it by letting cancelled work through.
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
            .min() ?? TaskOrdering.noDateSortKey
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
