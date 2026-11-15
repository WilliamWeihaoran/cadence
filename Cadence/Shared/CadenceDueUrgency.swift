import SwiftUI

/// How a deadline reads, measured against *today* rather than against the day a surface happens
/// to be drawing. A block parked on next Tuesday still has to read "overdue" when its due date
/// has already passed, so urgency never inherits the column it is rendered in.
///
/// Shared by the timeline task and bundle blocks and the calendar month/all-day chips, so those
/// surfaces rank deadlines identically. It lives here rather than beside the timeline blocks that
/// first needed it: the timeline files are a risk hotspot, and a classifier the calendar grid also
/// depends on should not sit behind `#if os(macOS)` in one of them.
enum CadenceDueUrgency {
    case overdue
    case dueToday
    case later

    /// `nil` means "no due date at all", so an absent marker reliably means "no deadline".
    /// A finished task is never urgent — it collapses to `.later` so a completed block stops
    /// flashing red about a deadline it has already settled.
    static func evaluate(
        dueDateKey: String,
        isDone: Bool = false,
        todayKey: String = DateFormatters.todayKey()
    ) -> CadenceDueUrgency? {
        guard !dueDateKey.isEmpty else { return nil }
        if isDone { return .later }
        if CadenceFocusSupport.isOverdue(dueDateKey: dueDateKey, todayKey: todayKey) { return .overdue }
        return dueDateKey == todayKey ? .dueToday : .later
    }

    /// **[[T-18051]]: the heading over a day's Due section, tinted by the day it is drawn for.**
    ///
    /// The iOS Calendar day inspector lists the tasks whose deadline is the *inspected* day --
    /// past, today or any day ahead. A fixed red eyebrow called next Thursday an alarm over rows
    /// whose own chips read a grey "Due Thu". Red means a deadline has passed: the heading is red
    /// only when `dayKey` is before `todayKey` AND an open task is still in the section; otherwise
    /// it takes the app's resting due colour, amber -- the schedule panel's Due field rule.
    static func dueSectionTint(dayKey: String, tasks: [AppTask], todayKey: String) -> Color {
        let hasOpenTask = tasks.contains { !CadenceTaskQuerySupport.isFinishedTask($0) }
        let urgency = evaluate(dueDateKey: dayKey, isDone: !hasOpenTask, todayKey: todayKey)
        return urgency == .overdue ? Theme.red : Theme.amber
    }

    var tint: Color {
        switch self {
        case .overdue: return Theme.red
        case .dueToday: return Theme.amber
        case .later: return Theme.dim
        }
    }
}
