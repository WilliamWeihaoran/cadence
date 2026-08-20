import Foundation
import SwiftUI

/// A **bundle member row**: one task listed inside a `TaskBundle`, in the timeline block's
/// inspector, in the Focus panel, and in the iOS calendar block sheet.
///
/// Three views drew this row and disagreed about all three of the things it says:
///
/// | | timeline inspector | Focus panel | iOS block sheet |
/// |---|---|---|---|
/// | time | `max(est, 5)m` | `45/60m` | `\(est)m` |
/// | deadline | due date | due date | **nothing** |
/// | other | — | `Done` | priority |
///
/// None of that was a decision. `max(estimatedMinutes, 5)m` **invented** a five-minute estimate for
/// a task that had none and spelled it in raw minutes, a field every other surface in the app
/// renders as `1h 30m` — and `max(_, 5)` is the exact floor `AppTask.timelineDurationMinutes`
/// documents as rejected, because it cannot tell "no estimate" from "a deliberate short estimate".
/// iOS spent the second line on priority — which is not what a bundle is ordered by — and so had
/// nowhere left to say a task in the block was three days overdue.
///
/// What survives as a real difference is the **Focus** panel's `45/60m`: that panel exists to hand
/// logged minutes to the tasks you tick, so logged-against-estimate is the number it is about.
/// `includesLoggedTime` is that, and it is off by default — one caller, one reason.
nonisolated struct CadenceBundleTaskRowMetrics: Sendable {
    /// 13pt, which all three rows already drew.
    static let titleSize: CGFloat = 13

    /// **`.medium`, and two of the three had it.** The timeline inspector's row was `.semibold`;
    /// a member of a bundle is a row in a list, not the heading of one, and the bundle's own title
    /// is the heading above it.
    static let titleWeight: Font.Weight = .medium

    /// **Two, and iOS had it.** `CadenceTaskRowMetrics.titleLineLimit` is the app's decided answer
    /// for a task row — "a truncated title on the screen you plan your day from is the worse of the
    /// two failures" — and a bundle inspector is exactly that screen. The two macOS rows clamped
    /// to one.
    static var titleLineLimit: Int { CadenceTaskRowMetrics.titleLineLimit }

    /// The secondary line, at the size `CadenceTaskDetailLineLabel` already defaults to.
    static let detailSize: CGFloat = 10

    /// Between the title and the detail line. The three rows drew 4 / 2 / 5.
    static let summarySpacing: CGFloat = 4
}

enum CadenceBundleTaskRowSupport {
    /// The one secondary line a bundle member row shows: how long it is, and when it is due.
    ///
    /// The lead is the estimate in the app's duration vocabulary — `45m`, `1h 30m` — and it is
    /// `nil` rather than `0m` when the task has no estimate, because a row that says `0m` claims a
    /// value the task does not have. Zero is the app's only "unset" sentinel here; the stored
    /// default is 30, so a task nobody has estimated still states half an hour, which is what
    /// `AppTask.timelineDurationMinutes` schedules it as. The due half comes from
    /// `CadenceFocusSupport.dueLabel`, the same overdue-aware label the focus rows and the widgets
    /// use.
    static func detailParts(
        for task: AppTask,
        todayKey: String = DateFormatters.todayKey(),
        includesLoggedTime: Bool = false
    ) -> CadenceTaskDetailLine {
        CadenceTaskDetailLine(
            lead: leadLabel(for: task, includesLoggedTime: includesLoggedTime),
            due: CadenceFocusSupport.dueLabel(forDueDateKey: task.dueDate, todayKey: todayKey),
            isOverdue: task.isOverdue(todayKey: todayKey)
        )
    }

    /// `45/60m` where logged time is the point, the plain estimate everywhere else, and `nil` when
    /// there is neither.
    static func leadLabel(for task: AppTask, includesLoggedTime: Bool) -> String? {
        if includesLoggedTime {
            return TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
        }
        guard task.estimatedMinutes > 0 else { return nil }
        return CadenceTaskPresentationSupport.estimateLabel(minutes: task.estimatedMinutes)
    }
}
