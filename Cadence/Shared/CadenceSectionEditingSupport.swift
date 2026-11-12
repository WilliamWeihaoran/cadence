import Foundation
import SwiftData

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

    /// **The Default column a list's editor starts with when it has no columns yet ([[T-14501]]).**
    ///
    /// Built from a config, so it carries `originalName` and reads as `isDefaultColumn`. Seeding
    /// with `init(name:)` made it an *added* column: the iOS New List editor drew its name as a
    /// field, offered a colour and let it be swiped away, and a rename to "Backlog" saved a list
    /// with two columns, because `normalizedSectionConfigs` found no Default and inserted one.
    /// That is [[T-5835]]'s bug, which its fix closed only for a list that already existed.
    static func defaultColumnSeed() -> CadenceSectionDraft {
        CadenceSectionDraft(config: TaskSectionConfig(name: TaskSectionDefaults.defaultName))
    }

    /// Whether this draft is the list's existing **Default** column, which cannot be renamed or
    /// removed (T-5835) — the Mac's column popover says so and shows no name field for it.
    ///
    /// Keyed on `originalName`, not `name`: it is the column the editor opened with that is fixed,
    /// whatever its field holds now. A column added during this edit is never it, even one typed
    /// as "Default". Case-insensitive, because that is how `TaskSectionConfig.isDefault` matches.
    var isDefaultColumn: Bool {
        guard let originalName else { return false }
        return originalName.caseInsensitiveCompare(TaskSectionDefaults.defaultName) == .orderedSame
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

/// **The one write that completes a kanban column, on both platforms ([[T-15722]]).**
///
/// Completing a column also archives it: the column is finished, so it leaves the board and is
/// reached again through Show Archived (Mac) or the list editor (iPad), whose Unarchive brings it
/// back open. The Mac's completion countdown (`SectionCompletionAnimationManager`) always wrote
/// both flags -- its sweep is built around the column leaving -- while the iPad's
/// `ModelContext.windDownColumn(.complete)` wrote `isCompleted` alone and said the column "stays
/// on the board", so one gesture filed the column away on one device and not the other. No
/// pointer, touch or width constraint decides which ([[T-8201]]), and the rest of the model
/// already reads a completed column as an archived one ([[T-15661]]). The flag pair is decided
/// here once, for the stored config and for the iPad editor's draft of it alike, so the two can
/// never be written apart again.
///
/// The settle that goes with it -- the open cards marked done -- is not here: it belongs to the
/// caller's commit, as `KanbanSectionStateSupport.windDownOutcome` (Mac) and `windDownColumn`
/// (iPad) already arrange.
nonisolated protocol CadenceColumnLifecycleFlags {
    var isCompleted: Bool { get set }
    var isArchived: Bool { get set }
}

nonisolated extension CadenceColumnLifecycleFlags {
    mutating func markColumnCompleted() {
        isCompleted = true
        isArchived = true
    }
}

nonisolated extension TaskSectionConfig: CadenceColumnLifecycleFlags {}
extension CadenceSectionDraft: CadenceColumnLifecycleFlags {}

/// Turning a list's columns into an editable form and back, plus the task reassignment a rename or
/// a removal implies.
///
/// `AppTask.sectionName` is a plain string pointing at a column by name, so nothing in SwiftData
/// re-points it when a column is renamed or removed. macOS's kanban column calls `moveTasks` for
/// exactly this; iOS did not, which stranded tasks on a name no column had any more. Those then
/// surfaced back on macOS as a phantom column, via `CadenceReadService`'s `extraSections`.
enum CadenceSectionEditingSupport {
    /// **Deleting a column, in the Mac's words on both platforms** ([[T-8564]]). The Mac board's
    /// column popover raised this before it deleted; the iOS list editor's swipe removed the row
    /// and said nothing, and on Save the column's cards moved to Default unannounced. One
    /// sentence, read by `KanbanSectionColumnView` and `iOSListEditorSheet`.
    static let columnDeleteConfirmationTitle = "Delete Column?"

    static func columnDeleteConfirmationMessage(columnName: String) -> String {
        "This will delete the column \"\(columnName)\" and move its tasks into \(TaskSectionDefaults.defaultName)."
    }

    /// Whether removing this draft from the iOS list editor asks first ([[T-8564]]). Only a column
    /// the editor opened with: one added during this edit has no `TaskSectionConfig` on disk, so
    /// no task can be in it and there is nothing to say about where its cards go.
    static func deletionNeedsConfirmation(_ draft: CadenceSectionDraft) -> Bool {
        draft.originalName != nil && !draft.isDefaultColumn
    }

    /// The name the confirmation states: what the row reads now, or the saved name when the
    /// field has been cleared, since a blank pair of quotes names nothing.
    static func deletionConfirmationName(for draft: CadenceSectionDraft) -> String {
        let typed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? (draft.originalName ?? typed) : typed
    }

    static func creationRefusal(
        for name: String,
        existingConfigs: [TaskSectionConfig]
    ) -> KanbanColumnRenameRefusal? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }
        return existingConfigs.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        } ? .nameAlreadyTaken : nil
    }

    /// Returns a notice on refusal; only a committed creation answers nil.
    static func createSection(
        named name: String,
        colorHex: String,
        in container: any CadenceSectionConfigContainer,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> String? {
        if let refusal = creationRefusal(for: name, existingConfigs: container.sectionConfigs) {
            return refusal.notice
        }
        let config = TaskSectionConfig(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: colorHex
        )
        switch container.addSectionConfig(config, in: modelContext, commit: commit) {
        case .added:
            return nil
        case .declined:
            return KanbanColumnRenameRefusal.nameAlreadyTaken.notice
        case .refused:
            return CadenceSectionConfigAddOutcome.refusalNotice
        }
    }

    static func drafts(from configs: [TaskSectionConfig]) -> [CadenceSectionDraft] {
        let drafts = configs.map { CadenceSectionDraft(config: $0) }
        return drafts.isEmpty ? [CadenceSectionDraft.defaultColumnSeed()] : drafts
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
        let configs = zip(drafts, storedNames(for: drafts)).compactMap { draft, name -> TaskSectionConfig? in
            guard let name else { return nil }
            var config = draft.config
            config.name = name
            return config
        }
        return configs.isEmpty ? [TaskSectionConfig(name: TaskSectionDefaults.defaultName)] : configs
    }

    /// **The name each draft is saved under, or `nil` for a draft that is dropped ([[T-17035]]).**
    ///
    /// A cleared field keeps the column's saved name (T-1053, above). **A name another column
    /// already holds is refused the same way.** `normalizedSectionConfigs` keeps only the first
    /// config of each case-insensitive name and drops the rest, so renaming "Doing" to "todo" on a
    /// list that has "Todo" -- or to "Default" -- used to delete one of the two columns on Save:
    /// its colour and due date went, and its cards were emptied into Default, or into the other
    /// column, with nothing said. The macOS column popover refuses the same rename
    /// (`KanbanSectionStateSupport.renameRefusal`); this is that refusal for the touch editor.
    ///
    /// Only a draft whose name the user changed can be refused -- a renamed column keeps its saved
    /// name, an added one is dropped -- and when two changed drafts collide, both are. Reverting a
    /// rename can make it collide with a third draft renamed onto the old name, so this settles to
    /// a fixed point. The key is the normalizer's own (trimmed, lowercased), so what passes here is
    /// exactly what the normalizer keeps.
    static func storedNames(for drafts: [CadenceSectionDraft]) -> [String?] {
        func trimmed(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let saved: [String?] = drafts.map { draft in
            draft.originalName.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
        }
        var names: [String?] = drafts.indices.map { index in
            let typed = trimmed(drafts[index].name)
            return typed.isEmpty ? saved[index] : typed
        }
        var settled = drafts.indices.map { names[$0] != nil && names[$0] == saved[$0] }
        var changed = true
        while changed {
            changed = false
            var counts: [String: Int] = [:]
            for name in names.compactMap({ $0 }) { counts[name.lowercased(), default: 0] += 1 }
            for index in names.indices where !settled[index] {
                guard let name = names[index], counts[name.lowercased(), default: 0] > 1 else { continue }
                names[index] = saved[index]
                settled[index] = true
                changed = true
            }
        }
        return names
    }

    /// **The names the editor refused because another column holds them ([[T-17035]])** -- the
    /// seam behind the "already exists" sentence, as `clearedColumnNames(in:)` is behind the
    /// empty-name one. What the user typed, trimmed, for every draft `storedNames(for:)` did not
    /// save under it.
    static func collidingColumnNames(in drafts: [CadenceSectionDraft]) -> [String] {
        zip(drafts, storedNames(for: drafts)).compactMap { draft, stored in
            let typed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty, stored != typed else { return nil }
            return typed
        }
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

    /// **The list editor's column edit, re-filing only the cards on this list's board ([[T-15531]]).**
    ///
    /// On an area that is the rule `CadenceTaskQuerySupport.listedTasks(for:)` names, not the raw
    /// `area.tasks` edge: a task holding both an area and a project is the project's ([[T-15431]])
    /// and sits on the project's board, so renaming or deleting an area column must leave its
    /// `sectionName` alone -- the in-app twin of the MCP fix in [[T-15512]]. The inherited-context
    /// cascade is a different walk and still reaches every task on the edge.
    ///
    /// The rule is restated rather than called ([[T-15565]]): this file is compiled into the
    /// `CadenceMCPServer` target, which does not compile `CadenceTaskQuerySupport` -- the same
    /// restatement `CadenceReadService`/`CadenceWriteService` make ([[T-15434]]). The T-15531 tests
    /// in `CadenceAreaProjectFilingCountTests` hold it to the shared rule's answer.
    @discardableResult
    static func refileColumnCards(
        base: [TaskSectionConfig],
        merged: [TaskSectionConfig],
        area: Area?,
        project: Project?
    ) -> Int {
        let cards: [AppTask]
        if let area {
            cards = (area.tasks ?? []).filter { $0.project == nil }
        } else {
            cards = project?.tasks ?? []
        }
        let moves = CadenceSectionConfigMerge.sectionNameMoves(base: base, merged: merged)
        return applySectionNameChanges(renames: moves.renames, removedNames: moves.removedNames, to: cards)
    }
}
