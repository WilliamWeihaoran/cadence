import SwiftUI

struct CadenceTodaySummary: Hashable {
    let activeCount: Int
    let timedCount: Int
    let completedCount: Int

    /// The one quiet line that says what today holds, in the treatment
    /// `CadenceTodaySummary.line` follows: zeros omitted, `nil` when there is nothing to
    /// say, rendered as a single `Theme.dim` line rather than a rank of tinted chips.
    ///
    /// It replaced three `Theme.blue`/`Theme.purple`/`Theme.green` capsules reading
    /// "0 Active · 0 Timed · 0 Done" plus a second two-chip copy of the first two in the header —
    /// so an empty day, which is most days before it is planned, said "0" five times in three hues
    /// beside a header badge already reading 0.
    ///
    /// `activeCount` is deliberately absent: the header badge beside this line *is* the active
    /// count, and repeating it here is the duplication this replaced.
    var line: String? {
        var parts: [String] = []
        if timedCount > 0 { parts.append("\(timedCount) timed") }
        if completedCount > 0 { parts.append("\(completedCount) done") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum CadenceTodayPresentationSupport {
    static func summary(
        activeTasks: [AppTask],
        timedTasks: [AppTask],
        completedTasks: [AppTask]
    ) -> CadenceTodaySummary {
        CadenceTodaySummary(
            activeCount: activeTasks.count,
            timedCount: timedTasks.count,
            completedCount: completedTasks.count
        )
    }

    static func accent(for groupKind: CadenceTodayTaskGroupKind) -> Color {
        switch groupKind {
        case .overdue:
            return Theme.red
        case .pastDo:
            return Theme.amber
        case .dueToday:
            return Theme.red.opacity(0.85)
        case .plannedToday:
            return Theme.blue
        }
    }

    static func symbol(for groupKind: CadenceTodayTaskGroupKind) -> String {
        switch groupKind {
        case .overdue:
            return "exclamationmark.triangle.fill"
        case .pastDo:
            return "calendar.badge.exclamationmark"
        case .dueToday:
            return "flag.fill"
        case .plannedToday:
            return "sun.max.fill"
        }
    }

    /// Today's empty state, at both widths — `iOSCompactTodayEmptyState` is the only reader and it
    /// is the only empty state Today has.
    ///
    /// There used to be an `emptyTitle` beside this reading "Nothing planned for today", left over
    /// from the iPad's own five-card empty deck; nothing had read it since that deck was deleted.
    /// Two spellings of one sentence, one of them unreachable, is how the two hosts start saying
    /// different things again.
    static let emptyCompactTitle = "Nothing planned"
    /// It said "Add a task above…" while the field it pointed at no longer existed on either width:
    /// compact capture is the tab bar's centre `+` and the iPad's is the floating one on this page.
    /// A subtitle naming a control that is not on screen is worse than none.
    static let emptySubtitle = "Add a task with +, or schedule one from Inbox."

    /// The schedule pane's whole empty state: one line, and the one line teaches the gesture.
    ///
    /// It was a floating card — glyph, heading, explanation — laid over the middle of the hour
    /// grid in a `ZStack`, covering two hours of rows. See `iOSSchedulePanel`.
    static let emptyScheduleHint = "No timed blocks yet — tap an hour to schedule one."
}
