import SwiftUI

/// One metadata chip on the iOS task-embed card: its words and its hue.
nonisolated struct CadenceTaskEmbedTouchChip: Equatable {
    let title: String
    let tint: Color
}

/// The chip row the iOS task-embed card draws, in the note editor (`iOSMarkdownTaskEmbedLayoutInfo`).
/// Focus's read-only note (iOSMarkdownPreview) drew it too until [[T-10900]] deleted that dead view.
///
/// [[T-9271]]: those two files each built this row privately, and both had drifted from the rule
/// the Mac card (`MarkdownTaskEmbedDrawingSupport.displayChips`) and the rest of the app follow:
///
/// - **Every open task carried a `Todo` chip**, and a snapshot still reading "inprogress" an
///   `In Progress` one. [[T-5015]] (b) — an owner decision — is that neither status draws a mark of
///   its own, and `CadenceInProgressStatusRetirement.drawsStatusChip` is where that is decided.
/// - **Low priority was green**, the colour that means done on the same card; it is blue
///   everywhere else (`Theme.priorityColor`).
///
/// One builder now, so the editor and the Focus copy of the same card cannot disagree either.
nonisolated enum CadenceTaskEmbedTouchChips {
    static let missingTitle = "Missing"

    static func chips(
        for task: MarkdownTaskEmbedRenderInfo,
        relativeTo referenceDate: Date = Date()
    ) -> [CadenceTaskEmbedTouchChip] {
        // A reference whose task is gone says so and nothing else, as the Mac card does.
        if task.isMissing {
            return [CadenceTaskEmbedTouchChip(title: missingTitle, tint: Theme.red)]
        }

        var chips: [CadenceTaskEmbedTouchChip] = []
        let status = TaskStatus(rawValue: task.statusRaw) ?? (task.isDone ? .done : .todo)
        if CadenceInProgressStatusRetirement.drawsStatusChip(status) {
            chips.append(CadenceTaskEmbedTouchChip(title: status.label, tint: Theme.statusColor(status)))
        }

        if let priority = TaskPriority(rawValue: task.priorityRaw), priority != .none {
            chips.append(CadenceTaskEmbedTouchChip(title: priority.label, tint: Theme.priorityColor(priority)))
        }
        // [[T-14322]]: the Mac card's words, from the one shared rule. This read
        // `durationLabel(actual:estimated:)` behind `estimatedMinutes > 0`, so a plain 1h estimate
        // read "-/1h" where the Mac card says "1h", and time logged against a task with no
        // estimate drew no chip at all where the Mac card says "30m/-".
        if let estimate = CadenceTaskEmbedEstimateLabel.label(for: task) {
            chips.append(CadenceTaskEmbedTouchChip(title: estimate, tint: Theme.amber))
        }
        // [[T-14321]]: the date chips take the Mac card's urgency hues through the one shared
        // rule below. They were a flat blue Do and a flat red Due, so "Due Tomorrow" -- and the
        // due date of work already done -- read as overdue on iOS while the Mac card drew them dim.
        let todayKey = DateFormatters.dateKey(from: referenceDate)
        if !task.scheduledDate.isEmpty {
            let date = DateFormatters.relativeDate(from: task.scheduledDate, relativeTo: referenceDate)
            let time = task.scheduledStartMin >= 0 ? " \(TimeFormatters.timeString(from: task.scheduledStartMin))" : ""
            chips.append(CadenceTaskEmbedTouchChip(
                title: "Do \(date)\(time)",
                tint: CadenceTaskEmbedDateTone.doDate(of: task, todayKey: todayKey).color
            ))
        }
        if !task.dueDate.isEmpty {
            let date = DateFormatters.relativeDate(from: task.dueDate, relativeTo: referenceDate)
            chips.append(CadenceTaskEmbedTouchChip(
                title: "Due \(date)",
                tint: CadenceTaskEmbedDateTone.dueDate(of: task, todayKey: todayKey).color
            ))
        }
        if !task.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(CadenceTaskEmbedTouchChip(title: task.containerName, tint: Theme.muted))
        }
        return chips
    }
}

/// How urgent a task-embed card's Do and Due chips read, decided once for the Mac card
/// (`MarkdownTaskEmbedDrawingSupport.displayChips`) and the iOS card (`CadenceTaskEmbedTouchChips`)
/// ([[T-14321]], under [[T-8201]]: a chip's hue is pure UI, so it cannot differ by platform).
///
/// The rule is the Mac card's, which it always drew: a due date is red only once it has passed on
/// an unfinished task; a do date is red once it has passed, the highlight accent on the day itself,
/// and dim otherwise; nothing on a finished task is urgent. The iOS card painted every Due red and
/// every Do blue, so "Due Tomorrow" and the due date of a task already done read as overdue.
/// `isDone` is the only settled state excluded, as in `AppTask.isOverdue(todayKey:)`.
nonisolated enum CadenceTaskEmbedDateTone: Equatable {
    case neutral
    case today
    case overdue

    static func dueDate(of task: MarkdownTaskEmbedRenderInfo, todayKey: String) -> CadenceTaskEmbedDateTone {
        guard !task.isDone, AppTask.isDueDateOverdue(task.dueDate, todayKey: todayKey) else { return .neutral }
        return .overdue
    }

    static func doDate(of task: MarkdownTaskEmbedRenderInfo, todayKey: String) -> CadenceTaskEmbedDateTone {
        guard !task.isDone, !task.scheduledDate.isEmpty else { return .neutral }
        if task.scheduledDate < todayKey { return .overdue }
        if task.scheduledDate == todayKey { return .today }
        return .neutral
    }

    /// The SwiftUI hue; the Mac card maps the same three cases onto its `MarkdownStylist` colours,
    /// which are these tokens in `NSColor`.
    var color: Color {
        switch self {
        case .neutral: return Theme.dim
        case .today: return Theme.markerHighlightAccent
        case .overdue: return Theme.red
        }
    }
}

/// What a task-embed card's estimate chip says, for the Mac card and the iOS card alike
/// ([[T-14322]], under [[T-8201]]). The Mac card's rule, which it always drew: logged time reads
/// `actual/estimate` ("30m/1h", "30m/-"); an estimate alone reads as itself ("1h"); neither is
/// `nil`, and each card says that its own way -- the Mac card's chip is a click target that names
/// the empty field ("No estimate"), the iOS card leaves the chip out.
nonisolated enum CadenceTaskEmbedEstimateLabel {
    static func label(for task: MarkdownTaskEmbedRenderInfo) -> String? {
        if task.actualMinutes > 0 {
            return TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: task.estimatedMinutes)
        }
        guard task.estimatedMinutes > 0 else { return nil }
        return TimeFormatters.durationLabel(minutes: task.estimatedMinutes, emptyPlaceholder: "-")
    }
}
