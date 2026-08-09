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

    var tint: Color {
        switch self {
        case .overdue: return Theme.red
        case .dueToday: return Theme.amber
        case .later: return Theme.dim
        }
    }
}
