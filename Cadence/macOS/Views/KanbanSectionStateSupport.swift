#if os(macOS)
import SwiftUI
import SwiftData

/// The macOS column's section writes. Every one of them goes through
/// `CadenceSectionConfigMerge` rather than reading the whole array, changing one entry and writing
/// the whole array back — see that type for what the merge keeps and what it still loses
/// (`docs/TODO.md` T-358).
enum KanbanSectionStateSupport {
    static func updateSection(
        sectionID: UUID,
        area: Area?,
        project: Project?,
        mutate: (inout TaskSectionConfig) -> Void
    ) {
        CadenceSectionConfigMerge.container(area: area, project: project)?
            .updateSectionConfig(uuid: sectionID, mutate: mutate)
    }

    /// The column header's due-date popover, committed ([[T-4970]]).
    ///
    /// The header's picker and its Clear used to call `updateSection` and stop, so the date rode
    /// the container's `sectionConfigsRaw` as a pending change until an unrelated save committed
    /// it or an unrelated `rollback()` discarded it — the [[T-4911]] / [[T-503]] shape, one popover
    /// over from the editor's own `clearSectionDueDate`, which T-645 already committed. The undo is
    /// the container's `CadenceListEditSnapshot`, never a `rollback()` of the app's one context.
    static func commitSectionDueDate(
        _ dueDateKey: String,
        sectionID: UUID,
        area: Area?,
        project: Project?,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let undo: CadenceListEditSnapshot?
        if let area {
            undo = CadenceListEditSnapshot(area)
        } else if let project {
            undo = CadenceListEditSnapshot(project)
        } else {
            undo = nil
        }
        updateSection(sectionID: sectionID, area: area, project: project) { config in
            config.dueDate = dueDateKey
        }
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            undo?.restore()
        }
    }

    /// The cards `moveTasks(universeTasks:area:project:from:to:)` will re-point.
    ///
    /// Split out rather than left inline because a refused rename or column delete has to put those
    /// cards' `sectionName` back, and the snapshot must be taken over **the same walk the write
    /// performs** — not a second one that happens to agree today. It is every card in the column,
    /// finished ones included, which is what makes it the wrong set for `editSnapshot(settling:)`
    /// and the right one here: deleting a column moves its whole stack into Default, while a
    /// lifecycle settle only reaches the open half.
    static func tasksMoving(
        universeTasks: [AppTask],
        area: Area?,
        project: Project?,
        from oldName: String
    ) -> [AppTask] {
        universeTasks.filter { task in
            guard task.resolvedSectionName.caseInsensitiveCompare(oldName) == .orderedSame else { return false }
            if area != nil, task.area?.id != area?.id { return false }
            // [[T-15531]]: on an area's board, a task that also holds a project is the project's
            // card ([[T-15431]]); renaming or deleting the area's column must not re-file it.
            if area != nil, project == nil, task.project != nil { return false }
            if project != nil, task.project?.id != project?.id { return false }
            return true
        }
    }

    static func moveTasks(
        universeTasks: [AppTask],
        area: Area?,
        project: Project?,
        from oldName: String,
        to newName: String
    ) {
        for task in tasksMoving(universeTasks: universeTasks, area: area, project: project, from: oldName) {
            task.sectionName = newName
        }
    }

    /// **The rename's card move, taken once and only towards a name the store actually holds
    /// (`docs/TODO.md` T-713).**
    ///
    /// The rename's config write and its card move are one commit, at the end of the edit. They
    /// are still two calls, and this is the second — the config is applied first, so between the
    /// two lines of `commitSectionEdits()` the column's *config* and its *cards* disagree on
    /// purpose. Every part of this function's shape is a guard against the way the per-keystroke
    /// version — the one T-736 removed — got it wrong:
    ///
    /// - **`filedName` is where the cards actually are**, not the name the editor opened with. The
    ///   defect was moving `from` a frozen snapshot: typing `Doing` → `Doingxy` moved the cards to
    ///   `Doingx` and then looked for cards still called `Doing`, found none, and left them under a
    ///   name no column had. Intermediate names no longer reach the store at all, but the same
    ///   thing still happens to a *second* commit in one editing session — Return, type more, pick
    ///   a colour — if the source is not advanced with the cards.
    /// - **The destination is read back out of the container**, matched by `uuid`, so it is a name
    ///   the store was actually asked to hold. An intermediate keystroke never reaches a card.
    /// - **It must equal the name the caller typed.** A rename the editor refused — empty, or
    ///   colliding with another column — leaves the stored name alone, and the cards must not move
    ///   for a name that was never stored.
    ///
    /// Deliberately *not* `CadenceSectionConfigMerge.sectionNameMoves`, which answers a different
    /// question: that one diffs two whole arrays to find every rename and removal a save implied,
    /// which is what the iOS list editor needs on close. Here there is one column, the caller knows
    /// which name it asked for, and a column another device removed mid-keystroke must not send
    /// this list's cards to Default behind a colour press.
    ///
    /// - Returns: the name the cards are now filed under, or `nil` when nothing moved.
    @discardableResult
    static func moveCardsToStoredName(
        universeTasks: [AppTask],
        area: Area?,
        project: Project?,
        columnUUID: UUID,
        typedName: String,
        filedName: String
    ) -> String? {
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project),
              let stored = container.sectionConfigs.first(where: { $0.uuid == columnUUID }),
              stored.name.caseInsensitiveCompare(typedName) == .orderedSame,
              stored.name.caseInsensitiveCompare(filedName) != .orderedSame
        else { return nil }
        moveTasks(universeTasks: universeTasks, area: area, project: project, from: filedName, to: stored.name)
        return stored.name
    }

    /// **Whether the rename field is holding a name the store has not been given (T-714).**
    ///
    /// The editor's rename is draft state until a commit point (T-736/T-738): the field writes
    /// `editorName` and nothing else, so the column keeps drawing its own cards while the user
    /// types. That leaves one way out of the popover with no commit on it — type a name, then
    /// dismiss without touching another control — and this is the question the dismissal asks
    /// before committing.
    ///
    /// It is asked rather than assumed for two reasons. A commit costs a transaction and, on a
    /// popover the user only opened to look at, there is nothing to commit. And an unconditional
    /// commit on the way out would *clear* `saveFailureNotice` on its way to succeeding — so a
    /// refusal the popover was still showing would vanish at the moment the column header was
    /// meant to take it over (T-646).
    ///
    /// The comparison is against the **stored** name, not against the name the popover opened
    /// with: a rename already committed by Return or by a colour press is in the store, and asking
    /// the opening snapshot would commit it a second time. `nil`-safe in the two ways the caller
    /// cannot check for itself — the column may have been deleted, or renamed away, while the
    /// popover was open.
    static func hasUncommittedRename(
        area: Area?,
        project: Project?,
        columnUUID: UUID,
        typedName: String
    ) -> Bool {
        let trimmed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let container = CadenceSectionConfigMerge.container(area: area, project: project),
              let stored = container.sectionConfigs.first(where: { $0.uuid == columnUUID })
        else { return false }
        return stored.name.caseInsensitiveCompare(trimmed) != .orderedSame
    }

    /// **Whether the editor may store `typedName` on this column, and why not when it may not
    /// (T-914).**
    ///
    /// Split out of `ListSectionKanbanColumn.applySectionEdits` so the decision has a seam a test
    /// can drive: the apply is a `private` member of a SwiftUI `View`, and "the rename was refused
    /// and reported as saved" is a behavioural claim, not a source-text one.
    ///
    /// **Both comparisons are against the *stored* column, not against the snapshot the popover
    /// opened with**, which is the same correction `hasUncommittedRename` above carries. A rename
    /// that already landed — by Return, or by a colour press — is in the store, and a rename that
    /// arrived from another device is too; asking the opening snapshot would refuse a name the
    /// column has since given up, or accept one it has since taken.
    ///
    /// **The collision check excludes the column itself by `uuid`.** The old inline form excluded
    /// it by first testing that the typed name differed from `base.name`, which answers a slightly
    /// different question and gets it wrong the moment `base` is stale.
    ///
    /// - Returns: `nil` when the name may be stored — including when it is the name the column
    ///   already has, and when the column is no longer in the list at all, which is not a refusal
    ///   the user can act on and is left to the apply's own guard.
    static func renameRefusal(
        typedName: String,
        columnUUID: UUID,
        area: Area?,
        project: Project?
    ) -> KanbanColumnRenameRefusal? {
        let trimmed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project),
              let stored = container.sectionConfigs.first(where: { $0.uuid == columnUUID })
        else { return nil }
        guard stored.name.caseInsensitiveCompare(trimmed) != .orderedSame else { return nil }

        let taken = container.sectionConfigs.contains {
            $0.uuid != columnUUID && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return taken ? .nameAlreadyTaken : nil
    }

    static func removeSection(sectionID: UUID, area: Area?, project: Project?) {
        CadenceSectionConfigMerge.container(area: area, project: project)?
            .removeSectionConfig(uuid: sectionID)
    }

    /// `base` is the column **as the caller last saw it**. Pass it whenever the caller has been
    /// holding the value for a while — only the fields that differ from it are written, so a
    /// concurrent edit to a different field of the same column survives. Omitting it diffs against
    /// what the model has now, which is the right base for a value read moments ago.
    static func saveSection(
        updatedSection: TaskSectionConfig,
        area: Area?,
        project: Project?,
        base: TaskSectionConfig? = nil
    ) {
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project) else { return }
        let current = container.sectionConfigs
        guard let currentConfig = current.first(where: { $0.uuid == updatedSection.uuid }) else { return }
        let baseConfig = base ?? currentConfig
        container.applySectionConfigEdits(
            base: current.map { $0.uuid == updatedSection.uuid ? baseConfig : $0 },
            edited: current.map { $0.uuid == updatedSection.uuid ? updatedSection : $0 }
        )
    }

    /// The settle a column write performs, decided from the column before and after it -- the one
    /// rule `saveSection` and `toggleSectionArchive` both read ([[T-15661]]).
    ///
    /// Entering completion marks the open work done; entering archive cancels it. **Archive is not
    /// gated on `isCompleted`, as on iOS** (`ModelContext.windDownColumn`): a completed column's
    /// work is normally settled already, so the cancel walks nothing, but a card added to a
    /// completed column afterwards is open -- and a Mac archive that skipped it left that card open
    /// under a column the board no longer draws, still surfacing on Today, while the iPad's archive
    /// of the same column cancelled it. No pointer, touch or width constraint decides which
    /// ([[T-8201]]). Completion leads when one write enters both, which is what the completion
    /// countdown writes (`isCompleted` and `isArchived` together): the work is finished, not
    /// abandoned.
    static func windDownOutcome(
        from current: TaskSectionConfig?,
        to updated: TaskSectionConfig
    ) -> CadenceWindDownOutcome? {
        if updated.isCompleted && current?.isCompleted != true { return .done }
        if updated.isArchived && current?.isArchived != true { return .cancelled }
        return nil
    }
}

/// A Mac kanban column about to be wound down -- Archive Column or Complete Column -- and the
/// confirmation it asks first ([[T-15662]]).
///
/// The iPad's list editor has asked since T-247 (`iOSColumnWindDownTarget`, presented through
/// `iOSWindDownConfirmationSheet`), and the Mac's own sidebar Archive / Complete asks with the same
/// count (`SidebarListWindDown`); the column popover settled every open card in one click. The
/// container differs -- a system confirmation over the column rather than a detented sheet, the
/// presentation each platform has -- but the question is the same one, asked by the same rule:
/// only when `CadenceContainerWindDownSummary.requiresConfirmation`, so an empty column stays one
/// click, and with the count from that summary, the settle's own array.
///
/// The entering transitions only. Unarchive and Reopen settle nothing, and a click during the
/// completion countdown cancels it, so none of the three asks: the two factories answer `nil` and
/// the column performs the toggle directly.
struct KanbanColumnWindDown: Identifiable {
    let section: TaskSectionConfig
    let area: Area?
    let project: Project?
    let outcome: CadenceWindDownOutcome

    var id: String {
        "\(section.uuid)-\(outcome.rawValue)"
    }

    /// The popover button's own words, so the confirmation's button says what was clicked.
    var actionTitle: String {
        outcome == .done ? "Complete Column" : "Archive Column"
    }

    var confirmationTitle: String { "\(actionTitle)?" }

    /// The count, then that the settle outlives the column's own reversal -- the sentence the
    /// sidebar's list confirmation says, from the same summary.
    var confirmationMessage: String {
        summary.confirmationMessage(containerNoun: "column")
    }

    /// Counted on the column **as the model holds it**, never the popover's rename draft: the walk
    /// matches `resolvedSectionName` against `section.name`.
    var summary: CadenceContainerWindDownSummary {
        .forColumn(section, area: area, project: project, outcome: outcome)
    }

    /// The confirmation a Complete Column click asks, or `nil` when it asks nothing: a column that
    /// is completed (the click reopens it), mid-countdown (the click cancels it), offered no
    /// completion at all (Default, an archived column), or with nothing open to mark done.
    static func completionRequest(
        for section: TaskSectionConfig,
        isPendingCompletion: Bool,
        area: Area?,
        project: Project?
    ) -> Self? {
        guard !section.isCompleted, !isPendingCompletion,
              CadenceBoardColumnLifecycleOffer.offersCompletionToggle(section) else { return nil }
        let target = Self(section: section, area: area, project: project, outcome: .done)
        return target.summary.requiresConfirmation ? target : nil
    }

    /// The confirmation an Archive Column click asks, or `nil`: an archived column (the click
    /// unarchives it), Default (which has no lifecycle), or nothing open to cancel. A completed
    /// column with a card added since asks, because archiving it cancels that card ([[T-15661]]).
    static func archiveRequest(
        for section: TaskSectionConfig,
        area: Area?,
        project: Project?
    ) -> Self? {
        guard !section.isArchived, section.supportsLifecycle else { return nil }
        let target = Self(section: section, area: area, project: project, outcome: .cancelled)
        return target.summary.requiresConfirmation ? target : nil
    }
}
#endif
