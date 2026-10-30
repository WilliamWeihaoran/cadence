import SwiftUI

/// The list and section rows a **creating** `CadenceSchedulePanel` offers, as data, for either
/// platform ([[T-3171]]).
///
/// The panel takes `CadenceSchedulePanelChoice` rather than an `[Area]` or a `[Project]` — that is
/// the seam that lets one view serve macOS and iOS — so every host that creates through it has to
/// turn the two queries into rows. Doing that in each host is how the iPad popover ended up
/// offering archived and completed lists while the sheet beside it did not; this is the one
/// spelling of the rule.
///
/// **It holds no platform type and no manager**, only the models the panel's two kinds of list come
/// from, so it compiles and is testable on the Mac.
///
/// The iOS hosts read it too: `iOSScheduleDraftCreation`'s own copy, where these rules were written
/// first, was retired into this one (T-3171 (vi)).
@MainActor
enum CadenceScheduleDraftChoices {

    /// Inbox, then the lists a new task may be put in — **narrowed by the shared picker rule**
    /// (`pickableAreas` / `pickableProjects`: active lists, sorted, plus the one the draft already
    /// names, so a draft routed into an archived list still reads its own row back).
    static func listChoices(
        for draft: CadenceScheduleDraft,
        areas: [Area],
        projects: [Project]
    ) -> [CadenceSchedulePanelChoice] {
        let selection = container(for: draft)
        var rows = [
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .inbox),
                name: "Inbox",
                color: Theme.blue,
                systemImage: "tray.fill"
            )
        ]
        rows += CadenceTaskComposerSupport.pickableAreas(
            areas,
            selectedID: CadenceTaskComposerSupport.selectedAreaID(selection)
        ).map {
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .area($0.id)),
                // [[T-8551]]: a blank-named list reads "Untitled Area", not an empty row and an
                // empty List chip -- the fallback every other list picker already draws.
                name: CadenceAreaPickerSupport.title(for: $0),
                color: Color(hex: $0.colorHex),
                systemImage: "folder.fill"
            )
        }
        rows += CadenceTaskComposerSupport.pickableProjects(
            projects,
            selectedID: CadenceTaskComposerSupport.selectedProjectID(selection)
        ).map {
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .project($0.id)),
                name: CadenceProjectPickerSupport.title(for: $0),
                color: Color(hex: $0.colorHex),
                systemImage: "square.stack.3d.up.fill"
            )
        }
        return rows
    }

    /// The draft's list token as the app's container selection — the one decoding, so no host
    /// re-spells the `"inbox"` / prefixed-id encoding.
    static func container(for draft: CadenceScheduleDraft) -> TaskContainerSelection {
        CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
    }

    static func area(for draft: CadenceScheduleDraft, in areas: [Area]) -> Area? {
        guard let id = CadenceTaskComposerSupport.selectedAreaID(container(for: draft)) else { return nil }
        return areas.first { $0.id == id }
    }

    static func project(for draft: CadenceScheduleDraft, in projects: [Project]) -> Project? {
        guard let id = CadenceTaskComposerSupport.selectedProjectID(container(for: draft)) else { return nil }
        return projects.first { $0.id == id }
    }

    /// **Empty for the Inbox**, so the panel greys its Section row out there. The Inbox has no
    /// sections to choose between — `sectionNames` answers the lone default for it — and every
    /// composer in the app has disabled the row rather than offer a one-row picker.
    static func sectionChoices(
        for draft: CadenceScheduleDraft,
        areas: [Area],
        projects: [Project]
    ) -> [String] {
        let area = area(for: draft, in: areas)
        let project = project(for: draft, in: projects)
        guard area != nil || project != nil else { return [] }
        return CadenceTaskMutationSupport.sectionNames(forArea: area, project: project)
    }
}
