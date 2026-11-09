import SwiftUI

/// The chip row of a note's task-embed card, decided once for the Mac card
/// (`MarkdownTaskEmbedDrawing.displayChips`) and the iOS card (`CadenceTaskEmbedTouchChips`).
///
/// [[T-14324]], under [[T-8201]]: the two cards had drifted in chip ORDER (iOS put the estimate
/// third and the list last), ESTIMATE HUE (Mac blue, iOS amber), the medium-priority hue (Mac the
/// marker-highlight yellow, iOS `Theme.priorityColor`'s amber), the list chip's hue and its "Inbox"
/// chip (iOS drew neither), the section and repeat chips (iOS drew neither) and the timed Do chip's
/// words (iOS "Do Tomorrow 9 AM", Mac "Tomorrow 9 AM"). None of that names a hardware or input
/// constraint, so this one builder now owns the order, every chip's words and hue, and which chips
/// survive a narrow card. Two differences remain, each answering one:
///
/// - **Pointer:** an empty Do, Due or estimate is a slot with `title == nil`. The Mac card draws
///   it as a placeholder chip ("No due date") because its chips are click targets that edit the
///   field under a pointer; the iOS card is one touch target that opens the task (a tappable chip
///   inside a tappable card competes under a finger -- [[T-8201]]'s board-chip precedent), so an
///   empty field there is simply no chip.
/// - **Measuring:** each card measures its chips in its own font; both then drop by `keptIndices`.
nonisolated struct CadenceTaskEmbedChipSlot: Equatable {
    let field: MarkdownTaskEmbedField
    /// `nil` when the field is empty -- see the pointer note above.
    let title: String?
    let tone: CadenceTaskEmbedChipTone
    /// Lower wins when a card cannot fit every chip; see `CadenceTaskEmbedChipRow.Importance`.
    let importance: Int
}

/// Which hue a chip takes. One mapping (`color`) for both cards: the Mac card resolves the same
/// `Color` into sRGB for AppKit drawing.
nonisolated enum CadenceTaskEmbedChipTone: Equatable {
    case missing
    case status(TaskStatus)
    case priority(TaskPriority)
    /// The list's own colour; an empty hex is the Inbox, which has none.
    case container(colorHex: String)
    case section
    case date(CadenceTaskEmbedDateTone)
    case estimate
    case recurrence

    var color: Color {
        switch self {
        case .missing: return Theme.red
        case .status(let status): return Theme.statusColor(status)
        case .priority(let priority): return Theme.priorityColor(priority)
        case .container(let colorHex):
            // A user-owned list colour, not a palette literal.
            return colorHex.isEmpty ? Theme.dim : Color(hex: colorHex)
        case .section: return Theme.dim
        case .date(let tone): return tone.color
        // [[T-14324]]: the Mac card's hues, kept while [[T-14381]] (OWNER CALL) decides whether
        // the card should take the shared editor's field hues instead.
        case .estimate: return Theme.blue
        case .recurrence: return Theme.green
        }
    }
}

nonisolated enum CadenceTaskEmbedChipRow {
    static let missingTitle = "Missing"

    /// Chips render in display order but are budgeted by importance, so a card that cannot fit
    /// every chip drops the least useful one instead of whatever sits last in the row. Lower
    /// wins. A due date outranks the rest: on the Mac card a hidden chip is also an unhittable one.
    enum Importance {
        static let dueDate = 1
        static let container = 2
        static let scheduledDate = 3
        static let priority = 4
        static let status = 5
        static let recurrence = 6
        static let section = 7
        static let emptyDueDate = 8
        static let emptyScheduledDate = 9
        static let estimate = 10
    }

    /// Every chip the card can draw, in display order: status, priority, list, section, Do, Due,
    /// estimate, repeat.
    static func slots(
        for task: MarkdownTaskEmbedRenderInfo,
        relativeTo referenceDate: Date = Date()
    ) -> [CadenceTaskEmbedChipSlot] {
        // A reference whose task is gone says so and nothing else.
        if task.isMissing {
            return [CadenceTaskEmbedChipSlot(field: .status, title: missingTitle, tone: .missing, importance: Importance.status)]
        }

        var slots: [CadenceTaskEmbedChipSlot] = []
        // [[T-5015]] (b): neither an open status nor a snapshot still reading "inprogress" draws a
        // mark of its own; `CadenceInProgressStatusRetirement.drawsStatusChip` decides that.
        let status = TaskStatus(rawValue: task.statusRaw) ?? (task.isDone ? .done : .todo)
        if CadenceInProgressStatusRetirement.drawsStatusChip(status) {
            slots.append(CadenceTaskEmbedChipSlot(field: .status, title: status.label, tone: .status(status), importance: Importance.status))
        }
        if let priority = TaskPriority(rawValue: task.priorityRaw), priority != .none {
            slots.append(CadenceTaskEmbedChipSlot(field: .priority, title: priority.label, tone: .priority(priority), importance: Importance.priority))
        }

        let container = task.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        slots.append(CadenceTaskEmbedChipSlot(
            field: .container,
            title: container.isEmpty ? "Inbox" : container,
            tone: .container(colorHex: container.isEmpty ? "" : task.containerColorHex),
            importance: Importance.container
        ))

        let section = task.sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !section.isEmpty, section.caseInsensitiveCompare(TaskSectionDefaults.defaultName) != .orderedSame {
            slots.append(CadenceTaskEmbedChipSlot(field: .section, title: section, tone: .section, importance: Importance.section))
        }

        // [[T-14321]]: the date hues are `CadenceTaskEmbedDateTone`'s.
        let todayKey = DateFormatters.dateKey(from: referenceDate)
        slots.append(CadenceTaskEmbedChipSlot(
            field: .scheduledDate,
            title: doTitle(for: task, relativeTo: referenceDate),
            tone: .date(CadenceTaskEmbedDateTone.doDate(of: task, todayKey: todayKey)),
            importance: task.scheduledDate.isEmpty ? Importance.emptyScheduledDate : Importance.scheduledDate
        ))
        slots.append(CadenceTaskEmbedChipSlot(
            field: .dueDate,
            title: task.dueDate.isEmpty ? nil : "Due \(DateFormatters.relativeDate(from: task.dueDate, relativeTo: referenceDate))",
            tone: .date(CadenceTaskEmbedDateTone.dueDate(of: task, todayKey: todayKey)),
            importance: task.dueDate.isEmpty ? Importance.emptyDueDate : Importance.dueDate
        ))
        // [[T-14322]]: the words are `CadenceTaskEmbedEstimateLabel`'s.
        slots.append(CadenceTaskEmbedChipSlot(
            field: .estimate,
            title: CadenceTaskEmbedEstimateLabel.label(for: task),
            tone: .estimate,
            importance: Importance.estimate
        ))

        if let recurrence = TaskRecurrenceRule(rawValue: task.recurrenceRaw), recurrence != .none {
            slots.append(CadenceTaskEmbedChipSlot(
                field: .recurrence,
                title: recurrence.label,
                tone: .recurrence,
                importance: Importance.recurrence
            ))
        }
        return slots
    }

    /// A timed Do chip reads "Tomorrow 9 AM": the time already says it is a plan, and the "Do "
    /// it drops is width the row spends on another chip.
    private static func doTitle(for task: MarkdownTaskEmbedRenderInfo, relativeTo referenceDate: Date) -> String? {
        guard !task.scheduledDate.isEmpty else { return nil }
        let date = DateFormatters.relativeDate(from: task.scheduledDate, relativeTo: referenceDate)
        guard task.scheduledStartMin >= 0 else { return "Do \(date)" }
        return "\(date) \(TimeFormatters.timeString(from: task.scheduledStartMin))"
    }

    /// Stable importance ranking; equal importance keeps display order.
    static func rankedIndices(importances: [Int]) -> [Int] {
        importances.indices.sorted {
            importances[$0] == importances[$1] ? $0 < $1 : importances[$0] < importances[$1]
        }
    }

    /// Which chips survive a card `available` wide, picked by importance and handed back in
    /// display order. The most important chip always lays out (a very narrow card truncates its
    /// label rather than dropping it).
    static func keptIndices(importances: [Int], widths: [CGFloat], available: CGFloat, gap: CGFloat) -> [Int] {
        var kept: [Int] = []
        var used: CGFloat = 0
        for index in rankedIndices(importances: importances) {
            guard !kept.isEmpty else {
                kept.append(index)
                used = min(widths[index], available)
                continue
            }
            let next = used + gap + widths[index]
            guard next <= available else { continue }
            kept.append(index)
            used = next
        }
        return kept.sorted()
    }
}

/// One metadata chip on the iOS task-embed card: its field, words and hue.
nonisolated struct CadenceTaskEmbedTouchChip: Equatable {
    let field: MarkdownTaskEmbedField
    let title: String
    let tint: Color
    let importance: Int
}

/// The chip row the iOS task-embed card draws (`iOSMarkdownTaskEmbedLayoutInfo`): the shared
/// `CadenceTaskEmbedChipRow` with its empty-field slots left out, because the iOS card's chips are
/// not touch targets (see `CadenceTaskEmbedChipSlot`).
nonisolated enum CadenceTaskEmbedTouchChips {
    static let missingTitle = CadenceTaskEmbedChipRow.missingTitle

    static func chips(
        for task: MarkdownTaskEmbedRenderInfo,
        relativeTo referenceDate: Date = Date()
    ) -> [CadenceTaskEmbedTouchChip] {
        CadenceTaskEmbedChipRow.slots(for: task, relativeTo: referenceDate).compactMap { slot in
            guard let title = slot.title else { return nil }
            return CadenceTaskEmbedTouchChip(field: slot.field, title: title, tint: slot.tone.color, importance: slot.importance)
        }
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
