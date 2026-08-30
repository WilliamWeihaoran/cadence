import Foundation

/// The project half of `CadencePickerSupport` — the two facts that are `Project`'s rather than the
/// picker's, and the name its call site reads it by.
///
/// **T-514.** `CadencePickerSupport` said `Project` deliberately was not a conformer, because
/// "nothing picks a project on its own — `iOSContainerChoicePopover` picks Inbox-or-area-or-project
/// as one grouped three-way control — and a conformance nothing reads is a claim nothing checks".
/// The grouped control is exactly what turned out to need it. It offered `projects.filter(\.isActive)`
/// and nothing else, so a task filed in a project that had since been archived or finished could not
/// be moved out of it: the row naming where the task actually *is* was missing from the list, and
/// the breadcrumb above it resolved the same id against the same filtered array and fell through to
/// **"Inbox"**.
///
/// So the conformance is read now, by `CadenceTaskComposerSupport.pickableProjects(_:selectedID:)`,
/// which is the three-way control's half of `selectable(_:selectedID:)` — hide what you could newly
/// pick, never the one already assigned. That is the same rule T-446 wrote for `Context` and T-488
/// generalised for `Area`; this is its third and, for now, last type.
typealias CadenceProjectPickerSupport = CadencePickerSupport<Project>

extension Project: CadencePickable {
    /// `isActive`, matching `Area` and not `Context`: a project has four states and only `active`
    /// is a place you would newly file something. `paused`, `done` and `archived` are all retired
    /// from fresh choices — and, exactly as for the other two types, none of them hides the project
    /// a task is already in. `CadencePickerSupport.selectable(_:selectedID:)` owns that half.
    var isOfferableInPicker: Bool { isActive }

    /// Declared in `CadenceTitleNormalization`, in `Models/`, for the same reason `Area`'s and
    /// `Context`'s are: it is the tree every target compiles, so it is where a label the app and
    /// `CadenceMCPServer` both show has to live.
    static var untitledPickerName: String { CadenceTitleNormalization.defaultProjectName }
}
