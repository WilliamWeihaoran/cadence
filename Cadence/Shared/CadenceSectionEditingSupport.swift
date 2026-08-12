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
    static func configs(from drafts: [CadenceSectionDraft]) -> [TaskSectionConfig] {
        let configs = drafts.map(\.config).filter { !$0.name.isEmpty }
        return configs.isEmpty ? [TaskSectionConfig(name: TaskSectionDefaults.defaultName)] : configs
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
