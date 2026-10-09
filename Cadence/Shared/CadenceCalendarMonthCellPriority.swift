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
        /// Bundle chips the cell draws.
        var bundles: Int
        /// Event chips the cell draws.
        var events: Int
        /// Task chips the cell draws.
        var tasks: Int
        /// Everything the cell is not drawing — the number the "+N more" line states.
        var hidden: Int

        /// Chips drawn in total. Never exceeds the capacity it was built against.
        var visible: Int { bundles + events + tasks }
    }

    /// Fills `capacity` chip slots from the three counts in priority order, and reports the
    /// remainder as one number.
    ///
    /// `hidden` is computed from the same three counts the visible rows came out of, rather than
    /// taken from the caller, so the cell cannot draw one partition and label a different one.
    static func split(bundles: Int, events: Int, tasks: Int, capacity: Int) -> Split {
        let bundleCount = max(0, bundles)
        let eventCount = max(0, events)
        let taskCount = max(0, tasks)
        var remaining = max(0, capacity)

        let drawnBundles = min(bundleCount, remaining)
        remaining -= drawnBundles
        let drawnEvents = min(eventCount, remaining)
        remaining -= drawnEvents
        let drawnTasks = min(taskCount, remaining)

        let total = bundleCount + eventCount + taskCount
        return Split(
            bundles: drawnBundles,
            events: drawnEvents,
            tasks: drawnTasks,
            hidden: total - (drawnBundles + drawnEvents + drawnTasks)
        )
    }
}
