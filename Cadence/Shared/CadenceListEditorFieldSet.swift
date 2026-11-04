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
