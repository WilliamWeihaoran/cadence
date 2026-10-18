import Foundation

/// Which of a month-grid day cell's items take the rows the cell can draw, and which of them fall
/// into the "+N more" line.
///
/// **Events outrank tasks, and that is the owner's decision (T-3088).** An event is a time-bound
/// commitment you cannot reschedule unilaterally — being somewhere at 2pm was agreed with other
/// people — so an event the cell hides costs the reader more than a hidden task, which can move
/// without asking anybody. It is also the ranking a user arrives with: Apple Calendar and
/// Fantastical both spend a crowded month cell's rows on events first.
///
/// **Bundles stay above both**, which is not part of that decision but is what both platforms
/// already did. A bundle is the shape of the day rather than one of its items, and the owner's
/// argument ranks events against *tasks*, not against the day's plan.
///
/// **This exists as one function because the two platforms had two different answers.** macOS's
/// `MonthDayCell` filled its slots bundles → tasks → events, so events were the first thing a
/// crowded day dropped — exactly backwards. iOS's `iOSCalendarMonthDayCell` filled them
/// bundles → events → tasks, which was already right, but through three hardcoded per-kind
/// `prefix` caps (3 bundles, 4 − bundles events, 5 − bundles − events tasks) rather than a stated
/// rule. Neither spelling was reachable from the other, and a per-platform copy of an ordering is
/// how the two came to disagree in the first place.
///
/// The **capacity** stays each platform's own: macOS derives it from the row height it was given
/// (`CalendarMonthCellLayout.chipCapacity`, minus the slot the overflow label takes), the iOS cell
/// has a fixed slot count. How many rows there are is a layout question; which items get them is
/// this one.
nonisolated enum CadenceCalendarMonthCellPriority {
    /// How many of each kind a cell draws, and how many items it is not drawing.
    ///
    /// Carries counts rather than the items themselves so that one function can serve two call
    /// sites holding different types — macOS has `CalendarEventItem`, iOS has `EKEvent`, and the
    /// ordering is a fact about the *kinds*, not about either representation.
    nonisolated struct Split: Equatable, Sendable {
        /// Event chips the cell draws.
        var events: Int
        /// Task chips the cell draws.
        var tasks: Int
        /// Everything the cell is not drawing — the number the "+N more" line states.
        var hidden: Int

        /// Chips drawn in total. Never exceeds the capacity it was built against.
        var visible: Int { events + tasks }
    }

    /// Fills `capacity` chip slots from the three counts in priority order, and reports the
    /// remainder as one number.
    ///
    /// `hidden` is computed from the same three counts the visible rows came out of, rather than
    /// taken from the caller, so the cell cannot draw one partition and label a different one.
    /// **The `bundles:` leg went with [[T-3170]].** It ranked FIRST, ahead of events and tasks,
    /// and it is gone from both platforms in the same pass rather than left taking a literal `0`
    /// from each: macOS's `MonthBundleChip` was the last thing that drew a Block, and iOS's cell
    /// had already been passing `0` since the eleventh pass. The order events-then-tasks is
    /// unchanged and is still the whole argument this type exists to record.
    static func split(events: Int, tasks: Int, capacity: Int) -> Split {
        let eventCount = max(0, events)
        let taskCount = max(0, tasks)
        var remaining = max(0, capacity)

        let drawnEvents = min(eventCount, remaining)
        remaining -= drawnEvents
        let drawnTasks = min(taskCount, remaining)

        let total = eventCount + taskCount
        return Split(
            events: drawnEvents,
            tasks: drawnTasks,
            hidden: total - (drawnEvents + drawnTasks)
        )
    }
}

/// Who gets the all-day strip's rows over a timeline day column: the day's **all-day events** and
/// its **unscheduled** tasks. **T-1474**, which replaced T-3163's flat two-row budget.
///
/// **One rule for both platforms.** iOS draws the strip from this split. macOS's band scrolls
/// inside a fixed frame and so never hides anything, which in this rule's terms is an unbounded
/// `capacity` — `Int.max` is supported and draws every item, events first. Until T-1474 the two
/// platforms stacked the strip in opposite orders (Mac tasks first, iOS events first), so a
/// crowded day lost appointments on one and tasks on the other.
///
/// **Why events fill first — the structural argument, not a ranking of importance.** An all-day
/// event appears NOWHERE ELSE in the app: hiding one costs a navigation to find it again. An
/// unscheduled task is also listed in Today, in its own list and in Inbox. (The rationale this
/// replaced — that an all-day event is a commitment made with other people — was withdrawn by the
/// owner: a subscribed holiday or a birthday is an all-day event nobody committed to, and an
/// unscheduled task can be the most urgent thing in the store.)
///
/// **The owner's cap rule (2026-10-17), in three parts:**
/// 1. **No rationing until overflow.** If `events + tasks <= capacity`, every item is drawn.
/// 2. **On overflow, tasks are reserved `min(taskCount, min(capacity / 2, 3))` rows** and events
///    take every remaining row. The `min(taskCount, …)` is load-bearing: a flat reserve with one
///    task would leave blank rows. A reserve the tasks cannot fill flows back to events, and rows
///    the events cannot fill flow back to tasks, so an overflowing strip is always full.
/// 3. **Overflow keeps the "+N more" line**, which opens the day. It is drawn BELOW the capacity's
///    chip rows rather than taking one of them.
///
/// **What does NOT reach the strip, however long it is: a timed event.** `EKEvent.isAllDay` is the
/// only door. An event from Monday 07:30 to Thursday 16:15 is a block in the grid on all four days
/// (its real start, two full days, its real end) and never touches the strip, because it genuinely
/// occupies those hours and an all-day flag means something different from a long duration. The
/// same for tasks: only UNSCHEDULED tasks reach the strip. `CadenceCalendarFixtureEvents.Fixture.
/// multiDay` is the pinned example.
nonisolated enum CadenceCalendarAllDayBandPriority {
    /// Chip rows on a compact-width (iPhone) strip.
    static let compactCapacity = 6
    /// Chip rows on a regular-width (iPad) strip.
    static let regularCapacity = 8
    /// The most rows the task reserve ever holds, whatever the capacity.
    static let maximumReservedTaskRows = 3

    /// The strip's chip-row budget. iPhone and iPad differ by layout, so the size class decides.
    static func capacity(isRegularWidth: Bool) -> Int {
        isRegularWidth ? regularCapacity : compactCapacity
    }

    /// Rows held for unscheduled tasks when the strip overflows: `min(tasks, min(capacity / 2, 3))`.
    static func reservedTaskRows(unscheduledTasks: Int, capacity: Int) -> Int {
        min(max(0, unscheduledTasks), min(max(0, capacity) / 2, maximumReservedTaskRows))
    }

    /// Fills `capacity` chip rows: events first, after holding the task reserve.
    ///
    /// Below overflow the reserve is never binding (`events <= capacity - tasks <= capacity -
    /// reserve`), which is how part 1 of the rule falls out of the same arithmetic as part 2.
    static func split(
        allDayEvents: Int,
        unscheduledTasks: Int,
        capacity: Int
    ) -> CadenceCalendarMonthCellPriority.Split {
        let eventCount = max(0, allDayEvents)
        let taskCount = max(0, unscheduledTasks)
        let rows = max(0, capacity)

        let reserve = reservedTaskRows(unscheduledTasks: taskCount, capacity: rows)
        let drawnEvents = min(eventCount, rows - reserve)
        let drawnTasks = min(taskCount, rows - drawnEvents)

        return CadenceCalendarMonthCellPriority.Split(
            events: drawnEvents,
            tasks: drawnTasks,
            hidden: (eventCount - drawnEvents) + (taskCount - drawnTasks)
        )
    }
}
