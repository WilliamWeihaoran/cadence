#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// What the embed handlers read from their host at the moment a card is clicked: the tasks the
/// editor resolves `[[task:…]]` against, the task whose notes these are (new embeds are created in
/// its list and section), and the context every commit goes through.
struct TaskNotesEmbedScope {
    let referenceTasks: [AppTask]
    let ownerTask: AppTask
    let modelContext: ModelContext
}

/// **[[T-5120]]: the one live-card embed handler set for the three macOS editors of a task's
/// notes** — `TaskDetailNotesSection` (the inspector box), `TaskNoteEditorPane` (a list's task note
/// pane) and `FocusNotesPanel` (Focus's task notes). Until T-5120 each held its own hand-copied
/// `openTaskReference` / `createEmbeddedTask` / `toggleEmbeddedTask` / `toggleEmbeddedSubtask` /
/// `renameEmbeddedTask` / `openEmbeddedTask` / `editEmbeddedTask` / `hoverEmbeddedTask` plus the
/// two popovers and the inline failure notice, so a fix to one silently missed the others. The
/// three were still identical when they were merged, apart from the hover id prefix, which stays
/// per host.
///
/// The host keeps one of these in `@State`, passes `callbacks(in:)`'s closures to
/// `MarkdownEditor`, attaches `taskNotesEmbedPopovers(_:scope:)` where its popovers were, and draws
/// `embeddedTaskFailureNotice` under the editor. Note-owned editors (`NotePanel`,
/// `NoteEditorPane`) create embeds in the note's container rather than a task's and are not on this
/// type yet — [[T-6721]].
@Observable
final class TaskNotesEmbedHandlers {
    /// The task whose detail popover is open — from a `[[task]]` link, a card body, or the hover
    /// shortcut.
    var linkedTaskForPopover: AppTask?
    /// The field chip whose small editor is open, when the inline task panel does not take it.
    var embeddedTaskEditRequest: TaskEmbedFieldEditRequest?
    /// Set when an edit made on an embedded task card was refused (T-648). The card is drawn by the
    /// text view, so the host shows this under the editor rather than over the card.
    var embeddedTaskFailureNotice: String?

    @ObservationIgnored var editorTextView: CadenceTextView?
    /// Tasks created from this editor that the host's live query may not hold yet (T-349).
    @ObservationIgnored var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @ObservationIgnored let hoverIDPrefix: String
    /// How every card edit commits. A parameter only so a test can refuse the commit; the hosts
    /// take the default.
    @ObservationIgnored private let commit: (ModelContext) throws -> Void

    init(hoverIDPrefix: String, commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.hoverIDPrefix = hoverIDPrefix
        self.commit = commit
    }

    // MARK: - The editor's closures

    struct Callbacks {
        let openTaskReference: (UUID?, String) -> Void
        let createEmbeddedTask: (String) -> MarkdownReferenceSuggestion?
        let toggleEmbeddedTask: (UUID) -> Void
        let toggleEmbeddedSubtask: (UUID, UUID) -> Void
        let renameEmbeddedTask: (UUID, String) -> Void
        let openEmbeddedTask: (UUID) -> Void
        let editEmbeddedTask: (UUID, MarkdownTaskEmbedField) -> Void
        let hoverEmbeddedTask: (UUID, Bool) -> Void
        let textViewChanged: (CadenceTextView?) -> Void
    }

    func callbacks(
        in scope: TaskNotesEmbedScope,
        hoveredTaskManager: HoveredTaskManager,
        hoveredEditableManager: HoveredEditableManager
    ) -> Callbacks {
        Callbacks(
            openTaskReference: { [weak self] in self?.openTaskReference(id: $0, title: $1, in: scope) },
            createEmbeddedTask: { [weak self] in self?.createEmbeddedTask(title: $0, in: scope) },
            toggleEmbeddedTask: { [weak self] in self?.toggleEmbeddedTask(id: $0, in: scope) },
            toggleEmbeddedSubtask: { [weak self] in self?.toggleEmbeddedSubtask(taskID: $0, subtaskID: $1, in: scope) },
            renameEmbeddedTask: { [weak self] in self?.renameEmbeddedTask(id: $0, title: $1, in: scope) },
            openEmbeddedTask: { [weak self] in self?.openEmbeddedTask(id: $0, in: scope) },
            editEmbeddedTask: { [weak self] in self?.editEmbeddedTask(id: $0, field: $1, in: scope) },
            hoverEmbeddedTask: { [weak self] id, hovering in
                self?.hoverEmbeddedTask(
                    id: id,
                    hovering: hovering,
                    in: scope,
                    hoveredTaskManager: hoveredTaskManager,
                    hoveredEditableManager: hoveredEditableManager
                )
            },
            textViewChanged: { [weak self] in self?.editorTextView = $0 }
        )
    }

    // MARK: - Handlers

    /// A `[[task]]` link: by id, then by trimmed, case-insensitive title, against the host's tasks.
    func openTaskReference(id: UUID?, title: String, in scope: TaskNotesEmbedScope) {
        if let id, let linkedTask = scope.referenceTasks.first(where: { $0.id == id }) {
            linkedTaskForPopover = linkedTask
            return
        }

        let targetTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetTitle.isEmpty,
              let linkedTask = scope.referenceTasks.first(where: {
                  $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                      .caseInsensitiveCompare(targetTitle) == .orderedSame
              }) else { return }
        linkedTaskForPopover = linkedTask
    }

    /// A new embed goes into the owner task's area or project (else the Inbox), in its section.
    func createEmbeddedTask(title: String, in scope: TaskNotesEmbedScope) -> MarkdownReferenceSuggestion? {
        let owner = scope.ownerTask
        let container: TaskContainerSelection
        let areas: [Area]
        let projects: [Project]

        if let area = owner.area {
            container = .area(area.id)
            areas = [area]
            projects = []
        } else if let project = owner.project {
            container = .project(project.id)
            areas = []
            projects = [project]
        } else {
            container = .inbox
            areas = []
            projects = []
        }

        let draft = TaskCreationDraft(
            title: title,
            notes: "",
            priority: .none,
            container: container,
            sectionName: owner.resolvedSectionName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )

        // T-364: commit first, hand the reference back second. The editor writes
        // `[[task:UUID|Title]]` into the note only when this returns non-nil, so a refused commit
        // has to return nil rather than leave the note pointing at a task the store never took.
        let created: AppTask?
        do {
            created = try TaskCreationService(areas: areas, projects: projects)
                .createTask(from: draft, into: scope.modelContext)
        } catch {
            return nil
        }
        guard let embeddedTask = created else { return nil }

        recentEmbeddedTasks[embeddedTask.id] = embeddedTask
        editorTextView?.markdownTaskEmbeds[embeddedTask.id] = MarkdownTaskEmbedRenderInfo.task(embeddedTask)
        return .task(embeddedTask)
    }

    func toggleEmbeddedTask(id: UUID, in scope: TaskNotesEmbedScope) {
        guard let embeddedTask = embeddedTask(id: id, in: scope) else { return }
        do {
            try CadenceTaskMutationSupport.setStatus(
                embeddedTask.isDone ? .todo : .done,
                for: embeddedTask,
                modelContext: scope.modelContext,
                commit: commit
            )
        } catch {
            embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        embeddedTaskFailureNotice = nil
        HabitNotificationReconcileSupport.scheduleReconcile(in: scope.modelContext)
        editorTextView?.markdownTaskEmbeds[id] = MarkdownTaskEmbedRenderInfo.task(embeddedTask)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
    }

    /// **T-648.** `refreshEmbeddedTask` repaints the card in the note, so it runs only after the
    /// save took — running it over a swallowed save is a success report.
    func toggleEmbeddedSubtask(taskID: UUID, subtaskID: UUID, in scope: TaskNotesEmbedScope) {
        guard let embeddedTask = embeddedTask(id: taskID, in: scope),
              let subtask = (embeddedTask.subtasks ?? []).first(where: { $0.id == subtaskID }) else { return }
        guard CadenceNoteTaskEmbedEditing.toggleSubtask(subtask, in: scope.modelContext, commit: commit) else {
            embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        embeddedTaskFailureNotice = nil
        refreshEmbeddedTask(embeddedTask)
    }

    /// See `toggleEmbeddedSubtask` — the same claim, about the card's title rather than its ticks.
    func renameEmbeddedTask(id: UUID, title: String, in scope: TaskNotesEmbedScope) {
        guard let embeddedTask = embeddedTask(id: id, in: scope) else { return }
        guard CadenceNoteTaskEmbedEditing.rename(embeddedTask, to: title, in: scope.modelContext, commit: commit) else {
            embeddedTaskFailureNotice = CadenceTaskFieldEditCommit.saveFailureNotice
            return
        }
        embeddedTaskFailureNotice = nil
        refreshEmbeddedTask(embeddedTask)
    }

    func openEmbeddedTask(id: UUID, in scope: TaskNotesEmbedScope) {
        guard let embeddedTask = embeddedTask(id: id, in: scope) else { return }
        linkedTaskForPopover = embeddedTask
    }

    /// Every field chip but status opens the shared task panel **inside the note**, under the card
    /// ([[T-1481]]); status keeps its own small editor, which holds Start and Cancel. Without a
    /// text view yet there is nowhere inline to put it, so the popover is the fallback.
    func editEmbeddedTask(id: UUID, field: MarkdownTaskEmbedField, in scope: TaskNotesEmbedScope) {
        guard let embeddedTask = embeddedTask(id: id, in: scope) else { return }
        if MarkdownInlineTaskPanelRouting.opensPanel(for: field), let editorTextView {
            editorTextView.presentInlineTaskPanel(for: embeddedTask, field: field, in: scope.modelContext) { [weak self] in
                self?.refreshEmbeddedTask($0)
            }
            return
        }
        embeddedTaskEditRequest = TaskEmbedFieldEditRequest(taskID: id, field: field)
    }

    func hoverEmbeddedTask(
        id: UUID,
        hovering: Bool,
        in scope: TaskNotesEmbedScope,
        hoveredTaskManager: HoveredTaskManager,
        hoveredEditableManager: HoveredEditableManager
    ) {
        guard let embeddedTask = embeddedTask(id: id, in: scope) else { return }
        if hovering {
            hoveredTaskManager.beginHovering(embeddedTask, source: .note)
            hoveredEditableManager.beginHovering(id: embeddedTaskHoverID(id)) { [weak self] in
                self?.openEmbeddedTask(id: id, in: scope)
            }
        } else {
            hoveredTaskManager.endHovering(embeddedTask)
            hoveredEditableManager.endHovering(id: embeddedTaskHoverID(id))
            refreshEmbeddedTask(embeddedTask)
        }
    }

    func embeddedTaskHoverID(_ id: UUID) -> String {
        "\(hoverIDPrefix)\(id.uuidString)"
    }

    /// Bring the note text back in line with the tasks it embeds when the task popover closes.
    /// See `NotePanel.reconcileEmbeddedTaskReferenceTitles` for why it hangs off that moment.
    func reconcileEmbeddedTaskReferenceTitles() {
        guard let editorTextView else { return }
        editorTextView.reconcileEmbeddedTaskReferenceTitles(
            titles: editorTextView.markdownTaskEmbeds.mapValues(\.title)
        )
    }

    func refreshEmbeddedTask(_ embeddedTask: AppTask) {
        editorTextView?.markdownTaskEmbeds[embeddedTask.id] = MarkdownTaskEmbedRenderInfo.task(embeddedTask)
        editorTextView?.replaceEmbeddedTaskReferenceTitle(id: embeddedTask.id, title: embeddedTask.title)
        if let editorTextView {
            MarkdownStylist.apply(to: editorTextView)
            editorTextView.needsDisplay = true
        }
    }

    /// The live query first, then the creation-latency cache — re-verified against the store, so a
    /// task deleted elsewhere stops being interactive in this note (T-349).
    func embeddedTask(id: UUID, in scope: TaskNotesEmbedScope) -> AppTask? {
        MarkdownEmbeddedTaskLookup.resolve(
            id: id,
            liveTasks: scope.referenceTasks,
            cache: &recentEmbeddedTasks,
            in: scope.modelContext
        )
    }
}

/// The task popover, the field-chip popover, and the title reconcile on the task popover closing —
/// attached where each host attached its own copies.
private struct TaskNotesEmbedPopovers: ViewModifier {
    @Bindable var handlers: TaskNotesEmbedHandlers
    let scope: TaskNotesEmbedScope

    func body(content: Content) -> some View {
        content
            .popover(item: $handlers.linkedTaskForPopover) { linkedTask in
                TaskDetailPopover(task: linkedTask)
                    .frame(width: 380)
            }
            .onChange(of: handlers.linkedTaskForPopover?.id) { previous, current in
                guard previous != nil, current == nil else { return }
                handlers.reconcileEmbeddedTaskReferenceTitles()
            }
            .popover(item: $handlers.embeddedTaskEditRequest) { request in
                if let embeddedTask = handlers.embeddedTask(id: request.taskID, in: scope) {
                    TaskEmbedFieldEditorPopover(task: embeddedTask, initialField: request.field) {
                        handlers.refreshEmbeddedTask(embeddedTask)
                    }
                } else {
                    Text("Task no longer exists")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .padding()
                }
            }
    }
}

extension View {
    func taskNotesEmbedPopovers(_ handlers: TaskNotesEmbedHandlers, scope: TaskNotesEmbedScope) -> some View {
        modifier(TaskNotesEmbedPopovers(handlers: handlers, scope: scope))
    }
}

#endif
