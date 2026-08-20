import Foundation
import SwiftUI

/// One chip on a board card's metadata strip: what it says, and how loudly.
///
/// **The description, not the drawing.** `CadenceBoardMetadataChip` (shared since `7e5459c`) is how
/// a chip *looks*; this is what the card decides to put in one. The two boards had the second half
/// forked — macOS's `KanbanCard.metadataRows` and iOS's `iOSBoardTaskCard.metadataChips` each built
/// their own list from the same `AppTask` and did not agree on what was in it, which is how the iOS
/// card ended up stating a **due** date and never a **do** date. The same task read as undated on
/// iPad and as planned for today on the Mac.
///
/// `nonisolated` for the same reason `TaskOrdering` and `CadencePageHeaderMetrics` are: the project
/// compiles with `-default-isolation MainActor`, and a value type describing a chip should not need
/// an actor to compare. It is also what lets the macOS-built test target pin it while the iOS card
/// that consumes it sits inside `#if os(iOS)`.
nonisolated struct CadenceBoardCardChip: Identifiable, Equatable, Sendable {
    /// Which field the chip states. The order of the cases is the order the strip draws them.
    enum Kind: String, Sendable, CaseIterable {
        case doDate
        case dueDate
        case list
    }

    /// How loud the chip's **label** is. Identity — the glyph's colour — never varies with this;
    /// only the text does. macOS already drew it that way (`KanbanMetaItem` carries `tint` and
    /// `textColor` separately) and it is the better of the two spellings: a due chip whose flag
    /// stops being red when the date is comfortable stops being identifiable as the due chip.
    enum Emphasis: String, Sendable {
        /// The ordinary case. A date the card is merely recording.
        case neutral
        /// Today. Worth noticing, not worth alarm.
        case attention
        /// Past its date and not done.
        case urgent
    }

    let kind: Kind
    let icon: String
    let text: String
    /// The user-owned list colour, for `.list` only. The date chips' identity colour is a `Theme`
    /// token the renderer picks from `kind`, so this value type carries no `Color` and stays
    /// comparable in a test.
    let listColorHex: String?
    let emphasis: Emphasis

    var id: String { kind.rawValue }
}

/// What a board card states about a task — decided once, drawn twice.
///
/// **Deliberately not the whole card.** Three things stay outside it, and each is an argued
/// arrangement difference rather than drift:
///
/// - *The timeline slot and the estimate.* macOS pairs them in `KanbanCardScheduleTopRow` —
///   `9am` beside an editable duration badge — because every element on a macOS board card is a
///   picker. iOS has no pointer to hover a badge with, so it states the whole range in a chip and
///   reaches the estimate through the detail sheet. Same two facts, two shapes; folding them here
///   would force one platform's layout onto the other for no gain.
/// - *Empty-field affordances.* macOS draws a `Due` chip with no date on it when the list does not
///   hide empty due dates, because that chip **is** the due-date picker. An empty chip states
///   nothing, so it is not metadata; it stays where it belongs, in the interaction shell.
/// - *Tags and subtasks.* macOS's card lists them and iOS's does not. That is a real coverage gap
///   and it is recorded rather than closed here — it is a layout decision about a 300pt column, not
///   a de-duplication.
///
/// Not `nonisolated`, unlike the chip it builds: it reads `AppTask` relationships, and
/// `CadenceTaskPresentationSupport` — the closest existing neighbour — is a plain enum for the same
/// reason. The value type carries the isolation-free half, which is the half a test compares.
enum CadenceBoardCardMetadata {
    /// Amber-identity, and the same glyph the do date carries everywhere else in the app.
    static let doDateIcon = "sun.max.fill"
    /// Red-identity, likewise.
    static let dueDateIcon = "flag.fill"
    /// The list chip's glyph when the task is in no list at all.
    static let inboxIcon = "tray.fill"
    /// The list chip's label when the task is in no list at all. `Inbox` is a real place, so the
    /// chip names it rather than going blank — the same rule the task inspector's breadcrumb
    /// follows.
    static let inboxLabel = "Inbox"

    /// The strip, in draw order: do date, due date, then the list.
    ///
    /// Dates first because they are the two facts that change what you do next, and the list last
    /// because it is identity rather than state. macOS already drew them in this order and put the
    /// list on a row of its own; iOS's two-column grid produces the same two rows from the same
    /// three chips.
    ///
    /// A field with no value contributes no chip. `showsContainer` is the one per-board knob and
    /// it exists because the information is genuinely redundant on some boards: a section column
    /// already sits inside one list, and an All Tasks list column *is* a list.
    static func chips(
        for task: AppTask,
        showsContainer: Bool,
        todayKey: String = DateFormatters.todayKey()
    ) -> [CadenceBoardCardChip] {
        var chips: [CadenceBoardCardChip] = []

        if let doDateChip = doDateChip(for: task, todayKey: todayKey) {
            chips.append(doDateChip)
        }
        if let dueDateChip = dueDateChip(for: task, todayKey: todayKey) {
            chips.append(dueDateChip)
        }
        if showsContainer {
            chips.append(listChip(for: task))
        }

        return chips
    }

    static func doDateChip(for task: AppTask, todayKey: String) -> CadenceBoardCardChip? {
        guard !task.scheduledDate.isEmpty else { return nil }
        return CadenceBoardCardChip(
            kind: .doDate,
            icon: doDateIcon,
            text: DateFormatters.relativeDate(from: task.scheduledDate),
            listColorHex: nil,
            emphasis: doDateEmphasis(for: task, todayKey: todayKey)
        )
    }

    static func dueDateChip(for task: AppTask, todayKey: String) -> CadenceBoardCardChip? {
        guard !task.dueDate.isEmpty else { return nil }
        return CadenceBoardCardChip(
            kind: .dueDate,
            icon: dueDateIcon,
            text: DateFormatters.relativeDate(from: task.dueDate),
            listColorHex: nil,
            emphasis: task.isOverdue(todayKey: todayKey) ? .urgent : .neutral
        )
    }

    static func listChip(for task: AppTask) -> CadenceBoardCardChip {
        CadenceBoardCardChip(
            kind: .list,
            icon: task.project?.icon ?? task.area?.icon ?? inboxIcon,
            text: task.containerName.isEmpty ? inboxLabel : task.containerName,
            listColorHex: task.containerColor,
            emphasis: .neutral
        )
    }

    /// Over-do outranks do-today, and a finished task is neither. This is macOS's rule stated once:
    /// its `doDateMetaItem` computed the same three-way choice inline and iOS had no do chip at all
    /// to disagree with. The `isDone` guard is the one `AppTask.isOverdue(todayKey:)` already
    /// applies to the deadline — you did it, so you are not late — and `KanbanCardComputedSupport`
    /// applied it here too; date keys are fixed-width, so the compare is chronological.
    static func doDateEmphasis(for task: AppTask, todayKey: String) -> CadenceBoardCardChip.Emphasis {
        guard !task.isDone else { return .neutral }
        if task.scheduledDate < todayKey { return .urgent }
        if task.scheduledDate == todayKey { return .attention }
        return .neutral
    }
}

extension CadenceBoardCardChip {
    /// The chip's **identity** colour — what the glyph is tinted, and what says "this is the due
    /// date" before you have read the date. It never varies with urgency.
    ///
    /// `Theme.blueHex` is the fallback for a `.list` chip with no colour, which is the same default
    /// `Color(hex:)` call sites already fall back to; the date kinds never carry a hex.
    var identityColor: Color {
        switch kind {
        case .doDate: return Theme.amber
        case .dueDate: return Theme.red
        case .list: return Color(hex: listColorHex ?? Theme.blueHex)
        }
    }

    /// The colour of the chip's **label**. `.attention` takes the chip's own identity — a do date
    /// that is *today* reads amber — and `.urgent` is red on either date, because late is late
    /// whichever one ran out.
    ///
    /// macOS applies this to the label alone and keeps `identityColor` on the glyph; iOS's
    /// read-only `CadenceBoardMetadataChip` applies one colour to both, because a tinted glyph
    /// beside grey text on a grey pill read as disabled. That is a difference between an editable
    /// chip and an inert one, not between two platforms, and it is why the two colours are
    /// separate here rather than pre-blended.
    var labelColor: Color {
        switch emphasis {
        case .neutral: return Theme.dim
        case .attention: return identityColor
        case .urgent: return Theme.red
        }
    }
}
