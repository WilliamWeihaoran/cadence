#if os(macOS)
import Foundation

/// What a column contributes to a task typed into its inline composer.
///
/// The composer is **one** view, used by every board column that already answers "where does this
/// go": a kanban column answers it with a list (and, on a section board, a section); a board day
/// column answers it with a day (and a time range, on a board that has one). This enum is the whole
/// difference between those surfaces, which is why the composer view itself carries no per-surface
/// branch — it asks this file what to seed and what to show.
enum InlineTaskComposerSurface: Equatable {
    /// A kanban column. `container` is the list the column stands for. `sectionName` is the column's
    /// section — the All Tasks board's *list* columns have no section of their own and pass the
    /// default one, exactly as their old create-sheet call declined to seed a section.
    case column(container: TaskContainerSelection, sectionName: String)

    /// A board day column. `startMin` is the column's time-range start in minutes from midnight, or
    /// `-1` when the board has no time range — the macOS Calendar Board's day columns are whole
    /// days, so they pass `-1`.
    case day(dateKey: String, startMin: Int)
}

/// The composer's editable state, minus the title and tags (which the shared title field owns).
///
/// Every field here is reachable from a chip, so what the surface seeded is a starting point rather
/// than a constraint: pick a different list, a different section, a different day, without leaving
/// the column.
struct InlineTaskComposerFields: Equatable {
    var container: TaskContainerSelection
    var sectionName: String
    /// The do date, `""` for none.
    var doDateKey: String
    /// Timeline slot in minutes from midnight, `-1` for none.
    var startMin: Int
}

/// Which chips the composer shows for a given surface and its current field values.
struct InlineTaskComposerChips: Equatable {
    var showsList: Bool
    var showsSection: Bool
    var showsDay: Bool
    var showsTimeRange: Bool
}

enum InlineTaskComposerSupport {
    /// Matches `TaskCreationSeed.estimatedMinutes`, so a card created from a column is the same
    /// length as one created from the sheet.
    static let defaultEstimatedMinutes = 30

    static func initialFields(for surface: InlineTaskComposerSurface) -> InlineTaskComposerFields {
        switch surface {
        case .column(let container, let sectionName):
            let trimmed = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
            return InlineTaskComposerFields(
                container: container,
                sectionName: trimmed.isEmpty ? TaskSectionDefaults.defaultName : trimmed,
                doDateKey: "",
                startMin: -1
            )
        case .day(let dateKey, let startMin):
            return InlineTaskComposerFields(
                container: .inbox,
                sectionName: TaskSectionDefaults.defaultName,
                doDateKey: dateKey,
                startMin: dateKey.isEmpty ? -1 : startMin
            )
        }
    }

    /// A chip appears for what the surface implies **plus** anything the user has since chosen.
    ///
    /// The second half is what keeps the title field's `~` shortcut honest on a day column: that
    /// surface implies no list, but once `~` has routed the draft into one, hiding the list chip
    /// would leave the choice invisible and un-undoable.
    static func chips(for surface: InlineTaskComposerSurface, fields: InlineTaskComposerFields) -> InlineTaskComposerChips {
        // Inbox is the *absence* of a list, and a list is what owns sections — so the section chip
        // has nothing to choose between there. Same rule the create sheet's toolbar uses.
        let hasList = fields.container != .inbox
        switch surface {
        case .column:
            return InlineTaskComposerChips(
                showsList: true,
                showsSection: hasList,
                showsDay: false,
                showsTimeRange: false
            )
        case .day:
            return InlineTaskComposerChips(
                showsList: hasList,
                showsSection: hasList,
                showsDay: true,
                showsTimeRange: fields.startMin >= 0
            )
        }
    }

    /// The label for the time-range chip, or `nil` when the draft holds no timeline slot.
    static func timeRangeLabel(
        for fields: InlineTaskComposerFields,
        estimatedMinutes: Int = defaultEstimatedMinutes
    ) -> String? {
        guard fields.startMin >= 0 else { return nil }
        let duration = max(5, estimatedMinutes)
        return TimeFormatters.timeRange(startMin: fields.startMin, endMin: fields.startMin + duration)
    }

    static func canCreate(title: String) -> Bool {
        !TaskTitleSupport.isEmpty(title)
    }

    /// The draft the composer hands to `TaskCreationService` — the same type, and the same service,
    /// the create sheet uses. Nothing on this path builds an `AppTask` by hand, which is what let
    /// the Calendar Board's old "+" strand an untitled card in a column.
    static func draft(
        title: String,
        fields: InlineTaskComposerFields,
        tags: [Tag],
        estimatedMinutes: Int = defaultEstimatedMinutes
    ) -> TaskCreationDraft {
        TaskCreationDraft(
            title: title,
            notes: "",
            priority: .none,
            container: fields.container,
            sectionName: fields.sectionName,
            dueDateKey: "",
            scheduledDateKey: fields.doDateKey,
            subtaskTitles: [],
            tags: tags,
            // A slot on no day is not a slot; the service enforces the same rule, and agreeing with
            // it here keeps the draft readable on its own.
            scheduledStartMin: fields.doDateKey.isEmpty ? -1 : fields.startMin,
            estimatedMinutes: estimatedMinutes
        )
    }

    /// The section to fall back to when the chosen list does not have the current one — the same
    /// normalization the create sheet runs when its container changes.
    static func normalizedSectionName(
        _ sectionName: String,
        for container: TaskContainerSelection,
        areas: [Area],
        projects: [Project]
    ) -> String {
        TaskContainerResolver(areas: areas, projects: projects)
            .normalizedSectionName(sectionName, for: container)
    }
}
#endif
