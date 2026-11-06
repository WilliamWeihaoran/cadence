import Foundation

/// One field a list editor can carry for an Area or a Project.
///
/// **[[T-8562]].** The iOS editor (`iOSListEditorSheet`) and the macOS sheets (`CreateListSheet`,
/// `EditAreaSheet`, `EditProjectSheet`) each decided their own field set, and the two had drifted
/// apart in both directions with no hardware or input reason for either ([[T-8201]] (d): the
/// container may differ, the fields should not). The owner's ruling is the union, so this enum is
/// the union and `CadenceListEditorFieldSet.fields` is the one place that says which of them a
/// given editor shows. Both platforms gate their rows on it rather than on their own `if`s.
///
/// The identity fields — name, description, colour, icon — are not listed: every editor has drawn
/// all four since `ListEditorIdentityHeader`, and no rule here would ever leave one out.
nonisolated enum CadenceListEditorField: Equatable, Hashable, CaseIterable, Sendable {
    case context
    /// A project's parent area ([[T-10180]] gave the Mac sheets the row iOS already had).
    case area
    /// A project's due date.
    case dueDate
    /// The Apple Calendar the list is linked to. Shown only where calendar access is **already**
    /// granted: the row never asks for access, and with none it would have no calendars to offer.
    case appleCalendar
    case hideEmptyTaskDueDates
    case hideEmptyColumnDueDates
    /// The kanban columns: rename, colour, due date, complete/archive, add, delete, reorder.
    case columns
    /// Active / Completed. An existing list only — a list that does not exist has no status to move.
    case status
    /// Archive / Unarchive. An existing list only.
    case archive
    /// Delete, behind the shared cascade confirmation. An existing list only.
    case delete
}

nonisolated enum CadenceListEditorFieldSet {
    nonisolated enum Kind: Sendable { case area, project }

    /// The fields an editor for `kind` draws, in the order it draws them.
    ///
    /// `isEditing` is false for a new list. `isCalendarAccessGranted` is the platform calendar
    /// manager's `isAuthorized` — read, never requested; this function cannot reach EventKit and
    /// is tested with plain booleans.
    ///
    /// The Apple Calendar link is an edit-time field on both platforms: neither creation sheet has
    /// ever offered it, so there is no drift there to settle, and a list is linked once it exists.
    static func fields(
        kind: Kind,
        isEditing: Bool,
        isCalendarAccessGranted: Bool
    ) -> [CadenceListEditorField] {
        var fields: [CadenceListEditorField] = [.context]
        if kind == .project {
            fields += [.area, .dueDate]
        }
        if isEditing && isCalendarAccessGranted {
            fields.append(.appleCalendar)
        }
        fields += [.hideEmptyTaskDueDates, .hideEmptyColumnDueDates, .columns]
        if isEditing {
            fields += [.status, .archive, .delete]
        }
        return fields
    }

    /// **[[T-11871]]: whether the editor may write `draftName` at all** -- the one test the Save
    /// button, Return in the name field, and every lifecycle row (Status, Archive / Unarchive) read,
    /// on both platforms.
    ///
    /// The lifecycle rows write the pending field edits before they move the list, so they commit
    /// the name exactly as Save does. They used to have no guard, and a cleared name field plus
    /// Status -> Completed stored a nameless list from a sheet whose Save button was refusing it.
    /// A blank draft now refuses them the way it refuses Save (disabled, and guarded behind the
    /// button) rather than keeping the stored name: silently writing every other edit while
    /// dropping one would be a second rule, and the user would see a name they had just cleared.
    static func acceptsName(_ draftName: String) -> Bool {
        !CadenceTitleNormalization.isBlank(draftName)
    }

    /// The Status row's value for an area. Shared so the two editors cannot word one state twice.
    static func statusLabel(_ status: AreaStatus) -> String {
        switch status {
        case .active: return "Active"
        case .done: return "Completed"
        case .archived: return "Archived"
        }
    }

    /// The Status row's value for a project, which can also be paused or cancelled — states no
    /// editor sets, so the row reports them rather than claiming the nearest one.
    static func statusLabel(_ status: ProjectStatus) -> String {
        switch status {
        case .active: return "Active"
        case .done: return "Completed"
        case .archived: return "Archived"
        case .paused: return "Paused"
        case .cancelled: return "Canceled"
        }
    }
}

// MARK: - Lifecycle

/// Moved here from `ListEditorSupportViews.swift` (macOS) so the iOS editor's Status menu ticks
/// from the same mapping the Mac popover does ([[T-11872]], [[T-8201]]).
enum ListEditorLifecycleChoice: CaseIterable {
    case active, completed, archived

    /// What this choice does to the work still open in the list, as a value rather than as a branch
    /// inside a sheet's `apply(_:)`.
    ///
    /// Both edit sheets used to switch on the choice and call
    /// `completeRemainingActiveTasks` / `cancelRemainingActiveTasks` by hand. Swapping those two
    /// calls — so that archiving a list marked its leftovers *done* and completing one cancelled
    /// them — kept every test green, because the only assertion counted both names over the whole
    /// file and both counts were unchanged (`docs/TODO.md` T-161). The mapping is here, and
    /// `CadenceListWindDownSurfaceTests` states it as an equality.
    ///
    /// `nil` for `.active`: reopening a list settles nothing. That is deliberately not
    /// `.done`-with-an-empty-set, because "there is no wind-down" and "wind down zero tasks" are
    /// different sentences and only the first one is true here.
    var windDownOutcome: CadenceWindDownOutcome? {
        switch self {
        case .active: return nil
        case .completed: return .done
        case .archived: return .cancelled
        }
    }

    /// [[T-9947]]: the choice a stored status already is, so the Status popover can tick it.
    init(_ status: AreaStatus) {
        switch status {
        case .active: self = .active
        case .done: self = .completed
        case .archived: self = .archived
        }
    }

    /// `nil` for a project that is paused or cancelled -- states no choice sets -- so no row is
    /// ticked rather than the nearest one.
    init?(_ status: ProjectStatus) {
        switch status {
        case .active: self = .active
        case .done: self = .completed
        case .archived: self = .archived
        case .paused, .cancelled: return nil
        }
    }
}
