import Foundation

/// The details line a scheduled task's timeline block prints under its title, on both platforms
/// ([[T-13141]], under [[T-8201]]).
///
/// The Mac block (`timelineBlockBody`) has always printed the task's actual/estimate and its
/// deadline -- "-/30m", "Overdue Aug 14", "Due today" -- under the title, and let the deadline win
/// the one line a short block has. iOS's block (`iOSTimelineTaskBlock`) printed the title and the
/// time range and nothing else, so an overdue task scheduled into today read as on track on an
/// iPhone and as overdue on a Mac. Nothing about touch or screen width chooses that: it was one
/// card's anatomy drawn twice. Both blocks now read this one value, so which facts the line
/// carries, when it is absent, and which of its words take the primary ink tier are one decision.
///
/// Fonts and the height gates stay with each block: those answer each platform's own type scale.
struct CadenceTimelineTaskBlockDetails: Equatable {
    /// `TimeFormatters.durationLabel(actual:estimated:)` -- "3m/15m", "-/30m". `nil` when neither
    /// side is known ("-/-"), which says nothing a reader can use.
    let durationLabel: String?
    /// `CadenceFocusSupport.dueLabel` -- "Overdue Aug 14", "Due today", "Due tomorrow". `nil`
    /// without a due date.
    let dueLabel: String?
    /// Overdue or due today, for an unfinished task. The block's plate admits only white-family
    /// ink, so urgency is carried by the ink TIER (primary over secondary) and by the words, never
    /// by a red or amber hue -- see `timelineBlockBody`'s measured note.
    let dueIsUrgent: Bool

    /// Nothing to print: the block draws no details line at all rather than an empty one.
    var isEmpty: Bool { durationLabel == nil && dueLabel == nil }

    /// The placeholder `TimeFormatters.durationLabel(actual:estimated:)` returns when both sides
    /// are unknown.
    static let unknownDurationLabel = "-/-"

    static func resolve(
        actualMinutes: Int,
        durationMinutes: Int,
        dueDateKey: String,
        isDone: Bool,
        todayKey: String
    ) -> CadenceTimelineTaskBlockDetails {
        let duration = TimeFormatters.durationLabel(actual: actualMinutes, estimated: durationMinutes)
        let urgency = CadenceDueUrgency.evaluate(dueDateKey: dueDateKey, isDone: isDone, todayKey: todayKey)
        return CadenceTimelineTaskBlockDetails(
            durationLabel: duration == unknownDurationLabel ? nil : duration,
            dueLabel: CadenceFocusSupport.dueLabel(forDueDateKey: dueDateKey, todayKey: todayKey),
            dueIsUrgent: urgency == .overdue || urgency == .dueToday
        )
    }

    /// The block's own reading: `durationMinutes` is the length the block is drawn for
    /// (`AppTask.timelineDurationMinutes` on a live block).
    static func resolve(task: AppTask, durationMinutes: Int, todayKey: String) -> CadenceTimelineTaskBlockDetails {
        resolve(
            actualMinutes: task.actualMinutes,
            durationMinutes: durationMinutes,
            dueDateKey: task.dueDate,
            isDone: task.isDone,
            todayKey: todayKey
        )
    }
}
