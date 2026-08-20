import Foundation
import SwiftUI

/// Every measurement the iOS task row varies, as a function of **width alone**.
///
/// This replaces `iOSTaskRowDensity`, a second axis each call site picked for itself. The two were
/// nearly the same thing: on a phone `.compact` and `.regular` resolved to the same horizontal
/// padding (11), the same completion glyph (20pt), the same row spacing (9) and the same secondary
/// line limit (1). They differed by 1pt of vertical padding, half a point of type — and the
/// **title line limit**, 1 against 2. So the axis' only real effect on a phone was that Today
/// truncated a task title to one line while Inbox and All Tasks, one tab of the same tab bar away,
/// wrapped it to two. It also inverted: `.compact` allowed *more* notes preview (80 characters)
/// than `.regular` did at that width (64), so Today showed less of the title and more of the note
/// about it.
///
/// There is deliberately **no density and no surface parameter here**, for the mirror of the
/// reason `CadenceTaskSurfaceOptions` has no size class: "iPhone Today's rows differ from iPhone
/// Inbox's rows" is no longer expressible. A host that wants a tighter row is describing a
/// narrower *pane*, and the pane is what size class already reports.
///
/// The cost, taken deliberately: the two hosts that passed `.compact` at *regular* width — the
/// calendar day inspector and the month agenda — now draw iPad-width rows in a fairly narrow pane.
/// That is one style at one width rather than a third setting, and they were the same rows that
/// made the iPad disagree with itself between its Today column and its Calendar tab.
///
/// `nonisolated` for the same reason `TaskOrdering` is: the project compiles with
/// `-default-isolation MainActor`, which would otherwise make even the synthesized `==`
/// main-actor isolated, and a value type describing paddings should not need an actor to compare.
nonisolated struct CadenceTaskRowMetrics: Equatable, Sendable {
    /// How many lines a task title gets. **One number, at every width and on every surface** — it
    /// is the thing T-78 was actually about. Two, because a truncated title on the screen you plan
    /// your day from is the worse of the two failures, and because it is what every task surface
    /// other than Today already showed.
    static let titleLineLimit = 2

    /// The completion circle's drawn diameter. Constant: only its 44pt-reaching *frame* ramps.
    static let completionCircleDiameter: CGFloat = 16

    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    /// Between the completion circle, the task, and the estimate chip.
    let contentSpacing: CGFloat
    /// Between the title, the notes line, the chips, the tags and the subtask rows.
    let summarySpacing: CGFloat
    /// Between chips on one line of the attribute strip. The *line* spacing is not here — it is
    /// derived from the chip's own hit inset, and a layout ramp must not be able to shrink it.
    let badgeSpacing: CGFloat
    /// The layout size the completion glyph takes; its touch target is expanded to 44pt on top.
    let completionGlyphSize: CGFloat
    let secondaryFontSize: CGFloat
    let secondaryLineLimit: Int
    /// How many characters of the notes preview the secondary line asks for.
    let notesPreviewLimit: Int

    static func metrics(isRegularWidth: Bool) -> CadenceTaskRowMetrics {
        isRegularWidth ? .regularWidth : .compactWidth
    }

    static let regularWidth = CadenceTaskRowMetrics(
        horizontalPadding: 14,
        verticalPadding: 12,
        contentSpacing: 12,
        summarySpacing: 8,
        badgeSpacing: 6,
        completionGlyphSize: 24,
        secondaryFontSize: 12,
        secondaryLineLimit: 2,
        notesPreviewLimit: 120
    )

    static let compactWidth = CadenceTaskRowMetrics(
        horizontalPadding: 11,
        verticalPadding: 9,
        contentSpacing: 9,
        summarySpacing: 6,
        badgeSpacing: 5,
        completionGlyphSize: 20,
        secondaryFontSize: 11,
        secondaryLineLimit: 1,
        notesPreviewLimit: 64
    )
}

struct CadenceSubtaskProgress: Hashable {
    let completed: Int
    let total: Int

    var compactLabel: String {
        "\(completed)/\(total)"
    }

    var label: String {
        total == 1 ? "\(completed)/1 subtask" : "\(completed)/\(total) subtasks"
    }
}

enum CadenceTaskPresentationSupport {
    static func plainPreviewText(from markdown: String, limit: Int? = nil) -> String {
        CadenceMarkdownPresentationSupport.plainPreviewText(from: markdown, limit: limit)
    }

    static func subtaskProgress(for task: AppTask) -> CadenceSubtaskProgress? {
        let subtasks = task.subtasks ?? []
        guard !subtasks.isEmpty else { return nil }
        return CadenceSubtaskProgress(
            completed: subtasks.filter(\.isDone).count,
            total: subtasks.count
        )
    }

    /// How many unfinished subtasks a row lists before it stops and says how many are left.
    ///
    /// Three, measured rather than guessed. Uncapped was tried first and shipped to a screenshot:
    /// one sample row with four subtasks stood ~290pt tall and iPhone Today fell from about five
    /// visible tasks to two and a half — a checklist on one task hiding the rest of the day. The
    /// row still names what is left rather than counting it, which is what the old `0/3` chip got
    /// wrong; it just stops naming at three.
    static let rowSubtaskLimit = 3

    /// How many tags a task row shows before collapsing the rest into a `+N`.
    ///
    /// **Three, and iOS had it.** macOS's `MacTaskRow` capped at two and iOS at three for the same
    /// strip of the same chips on the same task; neither number was argued for, and the narrower
    /// surface is not the one that was showing fewer — macOS's `CompactTagStrip` wraps the whole
    /// decision in `ViewThatFits`, so it already drops to one chip or to a bare `+N` when the row
    /// is genuinely tight. A fixed cap below the point where the row can no longer fit them is
    /// hiding a tag the row had room for.
    static let rowTagLimit = 3

    /// The subtasks a task row lists **beneath** itself, in `order`, capped at `rowSubtaskLimit`.
    ///
    /// Unfinished only. The iOS row used to say `0/3` in a chip, which named a number of things to
    /// do without naming any of them — so the checklist was only ever readable by opening the task.
    /// Finished subtasks stay out because they say nothing new: a row's job here is what is left.
    static func unfinishedSubtasks(for task: AppTask) -> [Subtask] {
        Array(allUnfinishedSubtasks(for: task).prefix(rowSubtaskLimit))
    }

    /// Everything `unfinishedSubtasks` would list if it did not cap — the denominator behind the
    /// overflow line, so the two cannot disagree about what "more" means.
    static func allUnfinishedSubtasks(for task: AppTask) -> [Subtask] {
        (task.subtasks ?? [])
            .filter { !$0.isDone }
            .sorted { $0.order < $1.order }
    }

    /// How many unfinished subtasks the row is **not** showing, or `nil` when it is showing them
    /// all. The row draws a "+N more" line from this; `nil` draws nothing rather than "+0 more".
    static func hiddenSubtaskCount(for task: AppTask) -> Int? {
        let hidden = allUnfinishedSubtasks(for: task).count - rowSubtaskLimit
        return hidden > 0 ? hidden : nil
    }

    /// What a dense task surface — a row on either platform, a board card on either platform —
    /// actually lists beneath the task, and the count it says is left over.
    ///
    /// The pair exists because `unfinishedSubtasks` alone is not the whole decision: **nothing is
    /// listed under a finished task.** A completed task's leftover checklist items are not work any
    /// more, and the surfaces these appear in — Today's Completed section, a board column's
    /// Completed footer — would otherwise fill with tappable items belonging to tasks that are over.
    /// That guard was applied at one call site (iOS's task row) and re-derived nowhere else, so the
    /// three surfaces that gained a subtask list under T-173 would each have had to remember it.
    /// It is a decision, not a shell, so it lives here with the cap it belongs to.
    static func listedSubtasks(for task: AppTask) -> [Subtask] {
        task.isDone ? [] : unfinishedSubtasks(for: task)
    }

    /// The "+N more" that goes with `listedSubtasks`, or `nil` when there is nothing more to say —
    /// including for a finished task, which lists none and therefore hides none.
    static func unlistedSubtaskCount(for task: AppTask) -> Int? {
        task.isDone ? nil : hiddenSubtaskCount(for: task)
    }

    /// Minutes → duration label for task chrome — "45m", "2h", "1h 24m", `"0m"` for nothing.
    ///
    /// The shape (and the non-breaking space that keeps it from wrapping into a wrong number) is
    /// `TimeFormatters.durationLabel(minutes:emptyPlaceholder:)`; only the empty sentinel is this
    /// surface's own. `emptyPlaceholder` lets the callers that want a dash instead of `"0m"` reach
    /// the same formatter rather than writing a fifth copy of it.
    static func estimateLabel(minutes: Int, emptyPlaceholder: String = "0m") -> String {
        TimeFormatters.durationLabel(minutes: minutes, emptyPlaceholder: emptyPlaceholder)
    }

    static func estimateLabel(for task: AppTask) -> String {
        estimateLabel(minutes: task.estimatedMinutes)
    }

    static func scheduledDateLabel(for task: AppTask, todayKey: String = DateFormatters.todayKey()) -> String {
        if task.scheduledStartMin >= 0 {
            let time = TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin)
            if task.scheduledDate == todayKey {
                return time
            }
            return "\(DateFormatters.relativeDate(from: task.scheduledDate)) at \(time)"
        }
        return DateFormatters.relativeDate(from: task.scheduledDate)
    }

    /// The do date as a **day**, never a time — "Today", "3 days ago", "Aug 24".
    ///
    /// `scheduledDateLabel` folds the timeline slot into the same string ("3 days ago at 9:30 AM –
    /// 10 AM"), which is right for a surface with no timeline beside it and wrong for a task row:
    /// there the slot ran to three times the width of every other chip and pushed the row's
    /// metadata onto a second line. The iOS row shows the day here; the Today timeline pane and the
    /// task inspector are where the slot itself is read.
    static func scheduledDayLabel(for task: AppTask) -> String {
        DateFormatters.relativeDate(from: task.scheduledDate)
    }

    static func dueDateLabel(for task: AppTask) -> String {
        DateFormatters.relativeDate(from: task.dueDate)
    }

    static func statusColor(_ status: TaskStatus) -> Color {
        Theme.statusColor(status)
    }
}
