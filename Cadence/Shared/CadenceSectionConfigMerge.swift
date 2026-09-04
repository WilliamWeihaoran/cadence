import Foundation
import SwiftData

/// The one point at which a list's kanban columns are written.
///
/// **Why this exists.** All of a list's section state is a single JSON blob —
/// `Area.sectionConfigsRaw` / `Project.sectionConfigsRaw`, read back through the `sectionConfigs`
/// computed property — so the whole array is what any one save writes. Two *editors* opened on the
/// same list that edit different columns each write a whole array, and the second write used to win
/// outright: the first editor's column came back with whatever values the second editor happened to
/// open with. `TaskSectionConfig` has carried a stable `uuid` all along; what was missing was a
/// moment at which that identity is consulted at write time (`docs/TODO.md` T-358).
///
/// **This is a write-time merge and only a write-time merge (`docs/TODO.md` T-625).** Nothing calls
/// it on the way *in*. The app installs no remote-change observer, so when CloudKit lands a peer's
/// `sectionConfigsRaw` the string arrives whole and replaces what was there, unread by this type.
/// Two devices therefore converge only in the ordering where the peer's blob is already in
/// `current` when the local save runs; in the other ordering the local edit is overwritten and no
/// merge happens at all. Per-column conflict resolution would mean columns as their own rows — a
/// new `@Model` plus a migration of every existing blob, and this project has no
/// `SchemaMigrationPlan`, which is the same constraint that makes order last-writer-wins below.
/// `SectionConfigRoundTripTests`'
/// `aPeersBlobLandingAfterALocalMergeReplacesItWholeBecauseNothingMergesOnImport` asserts the
/// limit; read it before believing any broader claim about two devices.
///
/// **The shape of a write.** Every writer states three arrays:
///
/// - `base` — the configs the caller *opened* with. For a sheet or popover that snapshots on
///   appear, this is minutes old. For an in-place mutation it is the array read one line earlier,
///   and the merge then degenerates to "apply the edit".
/// - `edited` — the configs the caller *wants*.
/// - `current` — the configs the model has **right now**, read at the last possible moment so a
///   remote change that landed while the sheet was open is in it.
///
/// **Per-column semantics.** Matching is by `uuid`, falling back to a case-insensitive name match
/// when a `uuid` is not found. The fallback is not decoration: a list still on the legacy
/// `sectionNamesRaw` string has no stored uuids at all, so `sectionConfigs`' getter mints a fresh
/// one on *every read*, and a uuid-only merge would read two reads of the same list as a full
/// delete-and-replace.
///
/// - A column in `base`, `edited` and `current` gets a **field-level diff**: only the fields the
///   caller actually changed (`name`, `colorHex`, `dueDate`, `isCompleted`, `isArchived`) are
///   applied onto the current value. A concurrent edit to a *different field of the same column*
///   therefore survives too, which a whole-config replace keyed by `uuid` would still lose.
/// - A column in `edited` but no longer in `current`, which `base` had, was **deleted on another
///   device**. It stays deleted. A stale snapshot must not resurrect it — the case a naive
///   uuid merge gets wrong.
/// - A column in `current` that `base` never had was **added on another device**. It is kept,
///   even though the caller's array has no idea it exists.
/// - A column in `base` and `current` but not in `edited` was removed by this caller. It goes.
///
/// **Order is last-writer-wins, and deliberately so.** Two devices that reorder the same list
/// cannot both win; there is no per-column field that could hold "position" independently, and
/// inventing one would need a schema change this project has no `SchemaMigrationPlan` for. So the
/// rule is narrowed rather than dropped: a caller that *did not touch order* (its `base` and
/// `edited` agree on the sequence of the columns they share) keeps `current`'s order and merely
/// slots its own new columns in at the end. A caller that **did** reorder imposes its order, and
/// any concurrent reorder from another device is lost. Only a genuine reorder can clobber a
/// reorder.
///
/// Nothing here writes `sectionConfigsRaw` or `sectionNamesRaw` directly. The result goes through
/// the `sectionConfigs` setter exactly as before, so the legacy `sectionNamesRaw` mirror and the
/// Default-column normalisation are untouched.
enum CadenceSectionConfigMerge {
    static func merged(
        base: [TaskSectionConfig],
        edited: [TaskSectionConfig],
        current: [TaskSectionConfig]
    ) -> [TaskSectionConfig] {
        let baseByID = index(base)
        let editedByID = index(edited)
        let currentByID = index(current)
        let baseNames = Set(base.map { nameKey($0.name) })

        var currentIDByName: [String: UUID] = [:]
        for config in current where currentIDByName[nameKey(config.name)] == nil {
            currentIDByName[nameKey(config.name)] = config.uuid
        }

        // Pass one: every column the caller still has, matched against what is on the model now.
        var consumed = Set<UUID>()
        var survivingByCurrentID: [UUID: TaskSectionConfig] = [:]
        var addedByCaller: [TaskSectionConfig] = []
        var callerOrder: [TaskSectionConfig] = []

        for config in edited {
            let baseConfig = baseByID[config.uuid]
            let matchID = currentMatch(
                for: config,
                baseConfig: baseConfig,
                currentByID: currentByID,
                currentIDByName: currentIDByName,
                consumed: consumed
            )

            guard let matchID, let currentConfig = currentByID[matchID] else {
                // Nothing on the model carries this identity. Either the caller just added the
                // column, or another device deleted it while this caller held a stale snapshot.
                if baseConfig == nil {
                    addedByCaller.append(config)
                    callerOrder.append(config)
                }
                continue
            }

            consumed.insert(matchID)
            let resolved: TaskSectionConfig
            if let baseConfig {
                resolved = applyingChangedFields(from: baseConfig, to: config, onto: currentConfig)
            } else {
                // The caller added a column the model already has under this identity; the
                // caller's values win, on the model's uuid.
                resolved = TaskSectionConfig(
                    uuid: currentConfig.uuid,
                    name: config.name,
                    colorHex: config.colorHex,
                    dueDate: config.dueDate,
                    isCompleted: config.isCompleted,
                    isArchived: config.isArchived
                )
            }
            survivingByCurrentID[matchID] = resolved
            callerOrder.append(resolved)
        }

        // Pass two: columns on the model the caller's array never mentioned. One of those is a
        // concurrent add and must be kept; the other is a column this caller removed.
        for config in current where !consumed.contains(config.uuid) {
            let wasOpenedWith = baseByID[config.uuid] != nil || baseNames.contains(nameKey(config.name))
            guard !wasOpenedWith else { continue }
            survivingByCurrentID[config.uuid] = config
        }

        // Order.
        var result: [TaskSectionConfig] = []
        var emitted = Set<UUID>()
        func emit(_ config: TaskSectionConfig) {
            guard !emitted.contains(config.uuid) else { return }
            emitted.insert(config.uuid)
            result.append(config)
        }

        if callerReordered(base: base, edited: edited, baseByID: baseByID, editedByID: editedByID) {
            callerOrder.forEach(emit)
            for config in current {
                if let surviving = survivingByCurrentID[config.uuid] { emit(surviving) }
            }
        } else {
            for config in current {
                if let surviving = survivingByCurrentID[config.uuid] { emit(surviving) }
            }
            addedByCaller.forEach(emit)
        }
        return result
    }

    /// The task re-pointing a merge implies, derived from the merge's own result rather than from
    /// the caller's intent.
    ///
    /// `AppTask.sectionName` is a plain string, so nothing re-points it when a column is renamed or
    /// removed. Deriving the moves from `merged` rather than from the editor's drafts is what makes
    /// a column *another device* deleted send its tasks to Default too — asking the drafts would
    /// only ever name the columns this editor removed, and the rest would be stranded on a name no
    /// column has any more.
    static func sectionNameMoves(
        base: [TaskSectionConfig],
        merged: [TaskSectionConfig]
    ) -> (renames: [(from: String, to: String)], removedNames: [String]) {
        let mergedByID = index(merged)
        var mergedIDByName: [String: UUID] = [:]
        for config in merged where mergedIDByName[nameKey(config.name)] == nil {
            mergedIDByName[nameKey(config.name)] = config.uuid
        }

        var renames: [(from: String, to: String)] = []
        var removedNames: [String] = []
        for config in base {
            let survivor = mergedByID[config.uuid]
                ?? mergedIDByName[nameKey(config.name)].flatMap { mergedByID[$0] }
            guard let survivor else {
                removedNames.append(config.name)
                continue
            }
            let newName = survivor.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty,
                  newName.caseInsensitiveCompare(config.name) != .orderedSame
            else { continue }
            renames.append((from: config.name, to: newName))
        }
        return (renames: renames, removedNames: removedNames)
    }

    /// The list being edited, as the one thing every section writer needs. Both surfaces hold an
    /// `Area?` and a `Project?` and exactly one of them is set.
    static func container(area: Area?, project: Project?) -> (any CadenceSectionConfigContainer)? {
        if let area { return area }
        if let project { return project }
        return nil
    }

    // MARK: - Internals

    private static func currentMatch(
        for config: TaskSectionConfig,
        baseConfig: TaskSectionConfig?,
        currentByID: [UUID: TaskSectionConfig],
        currentIDByName: [String: UUID],
        consumed: Set<UUID>
    ) -> UUID? {
        if currentByID[config.uuid] != nil, !consumed.contains(config.uuid) {
            return config.uuid
        }
        // Fall back to the name the column had when the caller opened, not the name it is being
        // renamed to: on disk it is still the old one.
        let key = nameKey(baseConfig?.name ?? config.name)
        if let candidate = currentIDByName[key], !consumed.contains(candidate) {
            return candidate
        }
        return nil
    }

    private static func applyingChangedFields(
        from base: TaskSectionConfig,
        to edited: TaskSectionConfig,
        onto current: TaskSectionConfig
    ) -> TaskSectionConfig {
        var result = current
        if edited.name != base.name { result.name = edited.name }
        if edited.colorHex != base.colorHex { result.colorHex = edited.colorHex }
        if edited.dueDate != base.dueDate { result.dueDate = edited.dueDate }
        if edited.isCompleted != base.isCompleted { result.isCompleted = edited.isCompleted }
        if edited.isArchived != base.isArchived { result.isArchived = edited.isArchived }
        return result
    }

    /// Whether the caller moved a column relative to the ones it shares with `base`. Adding or
    /// removing a column is not a reorder.
    private static func callerReordered(
        base: [TaskSectionConfig],
        edited: [TaskSectionConfig],
        baseByID: [UUID: TaskSectionConfig],
        editedByID: [UUID: TaskSectionConfig]
    ) -> Bool {
        let inBase = base.map(\.uuid).filter { editedByID[$0] != nil }
        let inEdited = edited.map(\.uuid).filter { baseByID[$0] != nil }
        return inBase != inEdited
    }

    private static func index(_ configs: [TaskSectionConfig]) -> [UUID: TaskSectionConfig] {
        Dictionary(configs.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// A list that owns kanban columns. `Area` and `Project` carry the same `sectionConfigsRaw` blob
/// and the same normalisation, and every section writer in the app has had to spell both branches
/// by hand; this is the one they share.
protocol CadenceSectionConfigContainer: AnyObject {
    var sectionConfigs: [TaskSectionConfig] { get set }
}

extension Area: CadenceSectionConfigContainer {}
extension Project: CadenceSectionConfigContainer {}

extension CadenceSectionConfigContainer {
    /// **The stale-snapshot write.** For a sheet or popover that read the columns when it opened,
    /// edited a draft of them, and is now saving. `current` is read here, not by the caller, so it
    /// is as fresh as it can be.
    ///
    /// **It writes only when the merge produced something different (T-738).** This assigned
    /// unconditionally while its sibling `mutateSectionConfigs` guarded, and the asymmetry was not
    /// a decision: a merge that resolved to what is already stored still re-serialised
    /// `sectionConfigsRaw`, still dirtied the object, and still pushed a CloudKit record. Every
    /// caller here is an editor closing or committing, and an editor that changed nothing is the
    /// ordinary case — a popover opened and shut, a colour pressed that was already selected, a
    /// commit point reached twice in one session.
    @discardableResult
    func applySectionConfigEdits(
        base: [TaskSectionConfig],
        edited: [TaskSectionConfig]
    ) -> [TaskSectionConfig] {
        let current = sectionConfigs
        let merged = CadenceSectionConfigMerge.merged(
            base: base,
            edited: edited,
            current: current
        )
        guard merged != current else { return current }
        sectionConfigs = merged
        return sectionConfigs
    }

    /// **The in-place write.** Reads the columns exactly once and hands that same array in as both
    /// `base` and `current`, so the merge degenerates to "apply this edit" — there is no staleness
    /// inside one synchronous mutation. It goes through the merge anyway so there is one write
    /// path to reason about rather than twenty.
    func mutateSectionConfigs(_ transform: ([TaskSectionConfig]) -> [TaskSectionConfig]) {
        let current = sectionConfigs
        let merged = CadenceSectionConfigMerge.merged(
            base: current,
            edited: transform(current),
            current: current
        )
        // A transform that declined — no such column, or a name already taken — used to `return`
        // without writing. Keep that: an identical write still dirties the object and still pushes
        // a CloudKit record.
        guard merged != current else { return }
        sectionConfigs = merged
    }

    @discardableResult
    func updateSectionConfig(uuid: UUID, mutate: (inout TaskSectionConfig) -> Void) -> Bool {
        var found = false
        mutateSectionConfigs { configs in
            guard let index = configs.firstIndex(where: { $0.uuid == uuid }) else { return configs }
            found = true
            var updated = configs
            mutate(&updated[index])
            return updated
        }
        return found
    }

    /// Refuses a name another column already has, which is the rule every add site spelled itself.
    @discardableResult
    func addSectionConfig(_ config: TaskSectionConfig) -> Bool {
        var added = false
        mutateSectionConfigs { configs in
            guard !configs.contains(where: { $0.name.caseInsensitiveCompare(config.name) == .orderedSame })
            else { return configs }
            added = true
            return configs + [config]
        }
        return added
    }

    func removeSectionConfig(uuid: UUID) {
        mutateSectionConfigs { $0.filter { $0.uuid != uuid } }
    }

    /// Reordering is last-writer-wins; see the note on `CadenceSectionConfigMerge`.
    ///
    /// **It commits, and it is the one reorder in the app no `\.order` sweep can find (T-870).**
    /// A kanban column's position is its index in this re-serialised blob — there is no per-column
    /// order field — so the audit that produced `CadenceOrderCommit` for the four row reorders had
    /// to be told about this one by hand. It had the same defect and worse: the board redrew the
    /// dragged column in its new place, `mutateSectionConfigs` wrote `sectionConfigsRaw`, and
    /// nothing saved. A rearrangement the user can see is a success report (T-614), so a column
    /// that stays where it was dropped and comes back at next launch is the exact failure that rule
    /// exists to catch.
    ///
    /// The undo is the previous blob, put back — not `modelContext.rollback()`, which would take
    /// unrelated pending work on the app's single context with it. Same reason as everywhere else;
    /// see `CadencePendingChangePersistence.commitEdit`.
    ///
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container.
    /// - Returns: Whether the new column order is in the store. `true` for a transform that
    ///   declined — no such column, or the merge produced what was already there — because there is
    ///   then nothing pending and the board is drawing what the store holds. `false` means the
    ///   columns are back as they were found and the caller must show
    ///   `CadenceOrderCommit.failureNotice`.
    @discardableResult
    func reorderSectionConfigs(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        _ transform: ([TaskSectionConfig]) -> [TaskSectionConfig]
    ) -> Bool {
        let previous = sectionConfigs
        mutateSectionConfigs(transform)
        guard sectionConfigs != previous else { return true }

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                sectionConfigs = previous
            }
        } catch {
            return false
        }
        return true
    }
}
