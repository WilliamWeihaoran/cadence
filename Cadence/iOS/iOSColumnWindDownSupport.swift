#if os(iOS)
import SwiftData
import SwiftUI

/// The two ways a kanban column is wound down, both of which settle the work still in it.
///
/// Only the *entering* transitions are here. Unarchiving and reopening settle nothing — they change
/// a flag — which is why they are a plain call on `ModelContext` below rather than a target this
/// enum could name.
enum iOSColumnWindDownAction {
    case archive
    case complete

    var outcome: CadenceWindDownOutcome {
        switch self {
        case .archive: return .cancelled
        case .complete: return .done
        }
    }
}

/// One kanban column about to be wound down, carrying the list it belongs to.
///
/// **A column is not a model.** It is a `TaskSectionConfig` value JSON-encoded into
/// `Area.sectionConfigsRaw` / `Project.sectionConfigsRaw`, and `AppTask.sectionName` is only a
/// string pointing at one — so "the tasks in this column" is a query, run by
/// `TaskContainerLifecycleService` against `resolvedSectionName`, and the list has to travel with
/// the column for it to be answerable at all.
///
/// The `config` must be the one **on the model**, never a `CadenceSectionDraft`'s rendering of it.
/// The list editor can hold a column renamed but not saved; counting or settling against that name
/// would walk a column no task points at yet.
struct iOSColumnWindDownTarget: Identifiable {
    let config: TaskSectionConfig
    let area: Area?
    let project: Project?
    let action: iOSColumnWindDownAction

    var id: String {
        "\(config.uuid)-\(action)"
    }

    /// The settle's own array, counted before the fact — see
    /// `CadenceContainerWindDownSummary.forColumn`.
    var summary: CadenceContainerWindDownSummary {
        .forColumn(config, area: area, project: project, outcome: action.outcome)
    }

    var name: String {
        config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Column" : config.name
    }

    var windDownSubject: iOSWindDownSubject {
        switch action {
        case .archive:
            return iOSWindDownSubject(
                title: "Archive Column",
                actionIcon: "archivebox.fill",
                headline: "Archiving settles what is left",
                explanation: "The column leaves the board and can be unarchived from this editor. Unarchiving it does not reopen the work cancelled below.",
                name: name,
                icon: "square.grid.3x2",
                colorHex: config.colorHex,
                emptyNote: "Nothing is still open in this column — archiving it cancels no work.",
                summary: summary
            )
        case .complete:
            return iOSWindDownSubject(
                title: "Complete Column",
                actionIcon: "checkmark.circle.fill",
                headline: "Completing settles what is left",
                explanation: "The column is marked complete and stays on the board. Reopening it does not reopen the work marked done below.",
                name: name,
                icon: "square.grid.3x2",
                colorHex: config.colorHex,
                emptyNote: "Nothing is still open in this column — completing it changes no work.",
                summary: summary
            )
        }
    }
}

extension ModelContext {
    /// The one place iOS archives or completes a kanban column, and the reason T-247 exists.
    ///
    /// Winding a column down is a settle, not a flag: macOS's `KanbanSectionColumnView` has called
    /// `TaskContainerLifecycleService` on both transitions since long before this file, while iOS
    /// wrote the flag onto a `CadenceSectionDraft` and saved it with every other edit in the list
    /// editor. So the same column left different open work behind depending on which device the
    /// board was on, and the Mac kept surfacing cards from a column the phone had filed away.
    ///
    /// **No `!isCompleted` guard on the archive branch, unlike macOS.** macOS skips the cancel when
    /// the column is already complete, which is normally a no-op — a completed column's work has
    /// been settled — and is *wrong* the moment a task is added to a completed column, because then
    /// the count this action promised and the settle it performed disagree. A confirmation that can
    /// over-promise is worse than none, so the settle here is unconditional and always walks the
    /// array `summary` counted.
    func windDownColumn(_ target: iOSColumnWindDownTarget) {
        updateColumn(uuid: target.config.uuid, area: target.area, project: target.project) { config in
            switch target.action {
            case .archive: config.isArchived = true
            case .complete: config.isCompleted = true
            }
        }

        switch target.action {
        case .archive:
            TaskContainerLifecycleService.cancelRemainingActiveTasks(
                in: target.config,
                area: target.area,
                project: target.project,
                in: self
            )
        case .complete:
            TaskContainerLifecycleService.completeRemainingActiveTasks(
                in: target.config,
                area: target.area,
                project: target.project,
                in: self
            )
        }
        try? save()
    }

    /// The reverse of both, and deliberately not a wind-down: it settles nothing, so it asks
    /// nothing. Clearing `isCompleted` alongside `isArchived` matches macOS's unarchive — a column
    /// that comes back to the board comes back open — and is a no-op for a column that was only
    /// completed.
    func reopenColumn(_ config: TaskSectionConfig, area: Area?, project: Project?) {
        updateColumn(uuid: config.uuid, area: area, project: project) { config in
            config.isArchived = false
            config.isCompleted = false
        }
        try? save()
    }

    /// Read-modify-write through `sectionConfigs`, never `sectionConfigsRaw`: the raw string is
    /// JSON and hand-editing it is how a column loses its `uuid`.
    private func updateColumn(
        uuid: UUID,
        area: Area?,
        project: Project?,
        mutate: (inout TaskSectionConfig) -> Void
    ) {
        if let area {
            var configs = area.sectionConfigs
            guard let index = configs.firstIndex(where: { $0.uuid == uuid }) else { return }
            mutate(&configs[index])
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard let index = configs.firstIndex(where: { $0.uuid == uuid }) else { return }
            mutate(&configs[index])
            project.sectionConfigs = configs
        }
    }
}

extension View {
    /// Attaches the column wind-down confirmation.
    ///
    /// It only ever *asks*. Performing is the host's `perform`, so the immediate path (nothing open
    /// to settle) and the confirmed path run the same code — including the part that keeps the
    /// editor's draft in step with the flag that was just written.
    func iOSColumnWindDown(
        target: Binding<iOSColumnWindDownTarget?>,
        perform: @escaping (iOSColumnWindDownTarget) -> Void
    ) -> some View {
        modifier(iOSColumnWindDownModifier(target: target, perform: perform))
    }
}

private struct iOSColumnWindDownModifier: ViewModifier {
    @Binding var target: iOSColumnWindDownTarget?
    let perform: (iOSColumnWindDownTarget) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $target) { target in
            iOSWindDownConfirmationSheet(subject: target.windDownSubject) {
                perform(target)
            }
        }
    }
}

/// The lifecycle half of a column row in the list editor, opted into whole.
///
/// The same shape as `iOSBoardTaskCardBundleDrop`: the current state and the three transitions are
/// useless apart, and a row that cannot act on a column — one added during this edit, which has no
/// `TaskSectionConfig` on the model and therefore no tasks — is handed `nil` rather than a set of
/// closures that would have nothing to write to.
struct iOSSectionRowLifecycle {
    let isCompleted: Bool
    let isArchived: Bool
    let complete: () -> Void
    let archive: () -> Void
    let reopen: () -> Void

    var stateLabel: String {
        if isArchived { return "Archived" }
        if isCompleted { return "Completed" }
        return "Active"
    }
}
#endif
