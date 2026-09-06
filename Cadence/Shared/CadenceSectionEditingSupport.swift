import Foundation

/// One kanban column while it is being edited, carrying the identity of the `TaskSectionConfig` it
/// came from.
///
/// Identity is the whole point. The iOS list editor used to edit columns as a newline-separated
/// list of *names*, written back through `Area.sectionNames` / `Project.sectionNames`. That
/// setter matches existing configs by name, so a rename could not be told apart from "delete this
/// column, add that one": the renamed column came back as a fresh `TaskSectionConfig` with a new
/// `uuid`, the default colour, no due date and `isCompleted == false`. Carrying `uuid` through the
/// edit is what makes a rename a rename.
struct CadenceSectionDraft: Identifiable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String
    var dueDate: String
    var isCompleted: Bool
    var isArchived: Bool

    /// The name this column had when the editor opened; `nil` for a column added during the edit.
    /// A draft whose `name` no longer matches this is a rename, and its tasks have to follow it.
    var originalName: String?

    init(config: TaskSectionConfig) {
        id = config.uuid
        name = config.name
        colorHex = config.colorHex
        dueDate = config.dueDate
        isCompleted = config.isCompleted
        isArchived = config.isArchived
        originalName = config.name
    }

    init(name: String) {
        id = UUID()
        self.name = name
        colorHex = TaskSectionDefaults.defaultColorHex
        dueDate = ""
        isCompleted = false
        isArchived = false
        originalName = nil
    }

    var config: TaskSectionConfig {
        TaskSectionConfig(
            uuid: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: colorHex,
            dueDate: dueDate,
            isCompleted: isCompleted,
            isArchived: isArchived
        )
    }
}

/// Turning a list's columns into an editable form and back, plus the task reassignment a rename or
/// a removal implies.
///
/// `AppTask.sectionName` is a plain string pointing at a column by name, so nothing in SwiftData
/// re-points it when a column is renamed or removed. macOS's kanban column calls `moveTasks` for
/// exactly this; iOS did not, which stranded tasks on a name no column had any more. Those then
/// surfaced back on macOS as a phantom column, via `CadenceReadService`'s `extraSections`.
enum CadenceSectionEditingSupport {
    static func drafts(from configs: [TaskSectionConfig]) -> [CadenceSectionDraft] {
        let drafts = configs.map { CadenceSectionDraft(config: $0) }
        return drafts.isEmpty ? [CadenceSectionDraft(name: TaskSectionDefaults.defaultName)] : drafts
    }

    /// Drafts with an empty name are dropped rather than saved as an unnameable column, matching
    /// the newline-list editor this replaced. An edit that removes everything still leaves the
    /// default column, because `normalizedSectionConfigs` would reinstate it anyway.
    ///
    /// **A column that already exists keeps its name instead of being dropped (T-1053).** Dropping
    /// it was not a refusal, it was a deletion: a draft missing from this array is a column the
    /// caller *removed*, so `applySectionConfigEdits` took the whole column out of the blob and
    /// `reassignTasks` emptied its cards into Default. Measured on a real `Area` in a real store —
    /// clearing one text field in the list editor and pressing Save left the list with two columns
    /// instead of three, with no confirmation and nothing said, and took the column's colour and
    /// due date with it. Handing the old name back makes it a *rename* the merge then declines
    /// (`CadenceSectionConfigMerge.applyingChangedFields`), so everything else in the same save
    /// still lands and `clearedColumnNames(in:)` gives the editor the refusal to report.
    ///
    /// A draft with no `originalName` never reached disk, so there is no column, no colour and no
    /// card to lose; those are still dropped without a word.
    static func configs(from drafts: [CadenceSectionDraft]) -> [TaskSectionConfig] {
        let configs = drafts.compactMap { draft -> TaskSectionConfig? in
            var config = draft.config
            guard config.name.isEmpty else { return config }
            guard let originalName = draft.originalName,
                  !originalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            config.name = originalName
            return config
        }
        return configs.isEmpty ? [TaskSectionConfig(name: TaskSectionDefaults.defaultName)] : configs
    }

    /// **The names of columns that already exist and whose name the editor has cleared (T-1053).**
    ///
    /// The seam behind the one sentence a list editor shows for a blank column name. It is
    /// deliberately not "every blank draft": a row added during this edit and left empty has no
    /// column, no colour and no card behind it, and refusing a whole save over an empty row the
    /// user never typed in would be worse than dropping it. A draft with an `originalName` is a
    /// column that exists on disk, and clearing its field used to delete it.
    static func clearedColumnNames(in drafts: [CadenceSectionDraft]) -> [String] {
        drafts.compactMap { draft in
            guard let originalName = draft.originalName,
                  draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return originalName
        }
    }

    /// `(old, new)` for every draft whose name changed. Case-insensitive, because section matching
    /// throughout the app is: a column renamed only in capitalization has not moved.
    static func renames(in drafts: [CadenceSectionDraft]) -> [(from: String, to: String)] {
        drafts.compactMap { draft in
            guard let originalName = draft.originalName else { return nil }
            let newName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty,
                  newName.caseInsensitiveCompare(originalName) != .orderedSame
            else { return nil }
            return (from: originalName, to: newName)
        }
    }

    /// Names that existed when the editor opened and do not survive the save. Their tasks go to the
    /// default column — the same thing macOS's "Delete Column?" confirmation promises.
    static func removedNames(
        original originalConfigs: [TaskSectionConfig],
        drafts: [CadenceSectionDraft]
    ) -> [String] {
        let survivingIDs = Set(configs(from: drafts).map(\.uuid))
        return originalConfigs
            .filter { !survivingIDs.contains($0.uuid) }
            .map(\.name)
    }

    /// Re-points every task that named one of the edited columns. Returns the number of tasks
    /// moved, so a caller can tell "nothing to do" from "did nothing".
    @discardableResult
    static func applySectionNameChanges(
        renames: [(from: String, to: String)],
        removedNames: [String],
        to tasks: [AppTask]
    ) -> Int {
        var moves: [(from: String, to: String)] = renames
        moves.append(contentsOf: removedNames.map { (from: $0, to: TaskSectionDefaults.defaultName) })
        guard !moves.isEmpty else { return 0 }

        var moved = 0
        for task in tasks {
            let current = task.resolvedSectionName
            guard let move = moves.first(where: { $0.from.caseInsensitiveCompare(current) == .orderedSame }),
                  move.to.caseInsensitiveCompare(current) != .orderedSame
            else { continue }
            task.sectionName = move.to
            moved += 1
        }
        return moved
    }
}
