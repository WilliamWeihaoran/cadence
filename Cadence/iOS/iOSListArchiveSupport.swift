#if os(iOS)
import SwiftData
import SwiftUI

/// The one thing an iOS archive confirmation can be about.
///
/// Areas and projects only — a context is not archivable from any iOS surface, and a kanban column
/// is its own target (`iOSColumnWindDownTarget`) because a column is a `TaskSectionConfig` value
/// inside one of these two rather than a model of its own. It carries the model object for the same
/// reason `iOSListDeletionTarget` does: the confirmation has to identify *which* list is going
/// quiet, and the archive itself takes the object.
enum iOSListArchiveTarget: Identifiable {
    case area(Area)
    case project(Project)

    var id: String {
        switch self {
        case .area(let area): return "area-\(area.id)"
        case .project(let project): return "project-\(project.id)"
        }
    }

    /// Title-cased, because every use is a button title or a sheet title. Deliberately not read off
    /// `CadenceListDeletionKind` — that enum is the delete cascade's vocabulary and its third case
    /// (`context`) is not a thing this action can be about.
    var noun: String {
        switch self {
        case .area: return "Area"
        case .project: return "Project"
        }
    }

    /// The real name, or the same "Untitled …" fallback the delete confirmation uses — a
    /// confirmation with a blank name in it does not say what is about to be archived.
    var name: String {
        let raw: String
        switch self {
        case .area(let area): raw = area.name
        case .project(let project): raw = project.name
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled \(noun)" : raw
    }

    var icon: String {
        switch self {
        case .area(let area): return area.icon
        case .project(let project): return project.icon
        }
    }

    var colorHex: String {
        switch self {
        case .area(let area): return area.colorHex
        case .project(let project): return project.colorHex
        }
    }

    var summary: CadenceContainerWindDownSummary {
        switch self {
        case .area(let area): return .forArea(area)
        case .project(let project): return .forProject(project)
        }
    }
}

extension ModelContext {
    /// The one place iOS archives a list, and the reason T-215 exists.
    ///
    /// Archiving is a **wind-down**, not a status flip: macOS has cancelled the list's remaining
    /// active tasks since long before this file, through exactly this service, and iOS wrote
    /// `status = .archived` and nothing else — so the same list left different open work behind
    /// depending on which device the swipe happened on, and the Mac's All Tasks kept surfacing
    /// tasks the phone had "archived".
    ///
    /// `includingChildProjects: true` matches `EditAreaSheet.apply(_:)`. An area's child projects
    /// keep their own `status`, so their tasks are still reachable from All Tasks after the parent
    /// is filed away — which is precisely why the wind-down has to reach them.
    func archiveList(_ target: iOSListArchiveTarget) {
        switch target {
        case .area(let area):
            area.status = .archived
            TaskContainerLifecycleService.cancelRemainingActiveTasks(
                in: area,
                includingChildProjects: true,
                in: self
            )
        case .project(let project):
            project.status = .archived
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: project, in: self)
        }
        try? save()
    }
}

extension View {
    /// Attaches the one archive confirmation.
    ///
    /// Its host sets the binding only when `CadenceContainerWindDownSummary.requiresConfirmation` says
    /// the archive would cancel something; an empty list is archived on the spot. Both the iPhone
    /// list and the iPad pane route their swipe and their context menu through that one decision,
    /// so the two cannot answer it differently.
    func iOSListArchive(target: Binding<iOSListArchiveTarget?>) -> some View {
        modifier(iOSListArchiveModifier(target: target))
    }
}

private struct iOSListArchiveModifier: ViewModifier {
    @Binding var target: iOSListArchiveTarget?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.sheet(item: $target) { target in
            iOSWindDownConfirmationSheet(subject: target.windDownSubject) {
                modelContext.archiveList(target)
            }
        }
    }
}

/// Everything the confirmation needs from a list, in the vocabulary the sheet speaks.
///
/// Built here rather than in the sheet because the sheet is shared with the kanban column
/// (`iOSColumnWindDownSupport`), and the two containers agree on nothing except that a wind-down
/// settles work irreversibly. See `iOSWindDownSubject`.
extension iOSListArchiveTarget {
    var windDownSubject: iOSWindDownSubject {
        iOSWindDownSubject(
            title: "Archive \(noun)",
            actionIcon: "archivebox.fill",
            headline: "Archiving settles what is left",
            explanation: "The \(noun.lowercased()) moves to Archived and can be restored from there. Restoring it does not reopen the work cancelled below.",
            name: name,
            icon: icon,
            colorHex: colorHex,
            emptyNote: "Nothing is still open in this \(noun.lowercased()) — archiving it cancels no work.",
            summary: summary
        )
    }
}
#endif
