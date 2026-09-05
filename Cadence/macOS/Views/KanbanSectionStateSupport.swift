#if os(macOS)
import SwiftUI

/// **Why a column rename did not reach the store, when the *editor* refused it rather than the
/// store (T-914).**
///
/// These are not the failure `saveFailureNotice` is for, and conflating them is the defect this
/// type exists to end. `CadenceInPlaceEditFlush.failureNotice` says "the store would not take your
/// change, it is still here, try again" — an invitation to press the same key again, which is
/// exactly the wrong advice for a name another column already holds. Pressing Return again will
/// refuse it again, forever.
///
/// Before this existed, `applySectionEdits` returned without writing and without saying anything,
/// and `commitSectionEdits` then flushed a context with nothing pending in it, succeeded, and
/// **cleared** the notice. So a refused rename was reported as a rename that landed: the user
/// pressed Return over a duplicate and the column simply kept its old title, with no red line
/// anywhere and nothing to read.
enum KanbanColumnRenameRefusal: Equatable {
    /// The field is empty, or holds only whitespace.
    case emptyName
    /// Another column in this list already holds the name.
    case nameAlreadyTaken

    /// What the popover — or the column header, once the popover has gone — says.
    ///
    /// "A column with this name already exists." is deliberately the sentence the tag editors
    /// already use for the same refusal (`SettingsTagsSection`, `TagPickerPopoverViews`,
    /// `iOSSettingsTagsSection`), because it *is* the same refusal one noun along, and a user who
    /// has met it once should not have to learn a second phrasing for it.
    var notice: String {
        switch self {
        case .emptyName:
            return "A column needs a name."
        case .nameAlreadyTaken:
            return "A column with this name already exists."
        }
    }
}

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
}
#endif
