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
enum CadenceCalendarMonthCellPriority {
    /// How many of each kind a cell draws, and how many items it is not drawing.
    ///
    /// Carries counts rather than the items themselves so that one function can serve two call
    /// sites holding different types — macOS has `CalendarEventItem`, iOS has `EKEvent`, and the
    /// ordering is a fact about the *kinds*, not about either representation.
    struct Split: Equatable, Sendable {
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

/// Who gets the iOS timeline day header's band rows: the day's **all-day events**, then its
/// **unscheduled** tasks. **T-3163.**
///
/// The month cell's rule, reused rather than restated — an all-day event is a commitment made with
/// other people and an unscheduled task can move without asking anybody, which is the argument
/// `CadenceCalendarMonthCellPriority` records for events over tasks. The band has no bundles: a
/// bundle always has a time, so it is a block in the column below.
///
/// `capacity` is the band's fixed row count. The band is a fixed-height strip pinned over the grid,
/// so it cannot grow to fit a busy day; the rest goes into its "+N more" line.
enum CadenceCalendarAllDayBandPriority {
    static let capacity = 2

    static func split(allDayEvents: Int, unscheduledTasks: Int) -> CadenceCalendarMonthCellPriority.Split {
        CadenceCalendarMonthCellPriority.split(
            events: allDayEvents,
            tasks: unscheduledTasks,
            capacity: capacity
        )
    }
}
