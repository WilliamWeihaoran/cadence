#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// Where a card created from the editor is filed, and what else rides in that creation's commit.
/// The one real policy difference between the hosts ([[T-6721]]): a task's notes file into the
/// owner task's list and section; `NotePanel`'s core notes into the Inbox; a `NoteEditorPane` into
/// its list note's area or project, and it bumps that note's `updatedAt` in the same commit.
struct TaskNotesEmbedTarget {
    /// Checked first: a non-nil area wins over `project`, else the Inbox.
    let area: Area?
    let project: Project?
    let sectionName: String
    /// A note whose `updatedAt` is bumped inside the creation's commit and put back when the
    /// commit is refused, so a refused embed cannot leave the note marked as edited.
    var touchedNote: Note? = nil

    /// A task's notes: the owner's area or project, in the owner's section.
    static func ownerTask(_ task: AppTask) -> Self {
        Self(area: task.area, project: task.project, sectionName: task.resolvedSectionName)
    }

    /// `NotePanel`'s core notes (today, week, notepad) belong to no list: the Inbox, default section.
    static var coreNotes: Self {
        Self(area: nil, project: nil, sectionName: TaskSectionDefaults.defaultName)
    }

    /// `NoteEditorPane`: a list note files into its list — the area or project the host passes,
    /// else the note's own — and any other kind of note into the Inbox; default section either way.
    /// The note's `updatedAt` rides in the creation's commit.
    static func noteEditor(_ note: Note, area: Area?, project: Project?) -> Self {
        let isListNote = note.kind == .list
        return Self(
            area: isListNote ? (area ?? note.area) : nil,
            project: isListNote ? (project ?? note.project) : nil,
            sectionName: TaskSectionDefaults.defaultName,
            touchedNote: note
        )
    }
}

/// What the embed handlers read from their host at the moment a card is clicked: the tasks the
/// editor resolves `[[task:…]]` against, where a new embed is filed, and the context every commit
/// goes through.
struct TaskNotesEmbedScope {
    let referenceTasks: [AppTask]
    let embedTarget: TaskNotesEmbedTarget
    let modelContext: ModelContext

    init(referenceTasks: [AppTask], embedTarget: TaskNotesEmbedTarget, modelContext: ModelContext) {
        self.referenceTasks = referenceTasks
        self.embedTarget = embedTarget
        self.modelContext = modelContext
    }

    /// A task's notes editor: new embeds go into the owner task's list and section.
    init(referenceTasks: [AppTask], ownerTask: AppTask, modelContext: ModelContext) {
        self.init(referenceTasks: referenceTasks, embedTarget: .ownerTask(ownerTask), modelContext: modelContext)
    }
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
/// [[T-6721]] moved the two note-owned editors, `NotePanel` and `NoteEditorPane`, onto it too.
/// Their one difference is host policy and arrives in the `scope`: where a new embed is filed
/// (`TaskNotesEmbedTarget`). A `[[task]]` link's id reads the creation cache in every host
/// ([[T-6781]]); until then only `NotePanel` did.
///
/// The host keeps one of these in `@State`, passes `callbacks(in:)`'s closures to
/// `MarkdownEditor`, attaches `taskNotesEmbedPopovers(_:scope:)` where its popovers were, and draws
/// `embeddedTaskFailureNotice` under the editor.
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

    /// **[[T-7336]].** Closes whichever of the two popovers is open and says whether one was, so an
    /// Escape the host would spend on closing its sheet closes the popover instead.
    func closeOpenPopover() -> Bool {
        guard linkedTaskForPopover != nil || embeddedTaskEditRequest != nil else { return false }
        linkedTaskForPopover = nil
        embeddedTaskEditRequest = nil
        return true
    }
    /// Tasks created from this editor that the host's live query may not hold yet (T-349).
    @ObservationIgnored var recentEmbeddedTasks: [UUID: AppTask] = [:]
    @ObservationIgnored let hoverIDPrefix: String
    /// How every card edit and card creation commits. A parameter only so a test can refuse the
    /// commit; the hosts take the default.
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
    /// **[[T-6781]]: the id lookup reads the creation cache in every host,** as the card handlers
    /// below always have — a task created from this note a moment ago opens from its link before the
    /// host's query holds it. Safe everywhere because `embeddedTask(id:in:)` tries the live tasks
    /// first and re-checks a cached task against the store ([[T-349]]), so a deleted one does not open.
    func openTaskReference(id: UUID?, title: String, in scope: TaskNotesEmbedScope) {
        if let id, let linkedTask = embeddedTask(id: id, in: scope) {
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

    /// A new embed goes into the scope's target area or project (else the Inbox), in its section.
    func createEmbeddedTask(title: String, in scope: TaskNotesEmbedScope) -> MarkdownReferenceSuggestion? {
        let target = scope.embedTarget
        let container: TaskContainerSelection
        let areas: [Area]
        let projects: [Project]

        if let area = target.area {
            container = .area(area.id)
            areas = [area]
            projects = []
        } else if let project = target.project {
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
            sectionName: target.sectionName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )

        // T-364, two orderings in one. The reference is handed back only after the commit lands,
        // because the editor writes `[[task:UUID|Title]]` into the note exactly when this returns
        // non-nil — a nil return is what keeps the note free of a dangling reference. And a host
        // note's timestamp bump rides in that same commit and is put back when it is refused, the
        // shape `AINoteActionSupport.append` uses, so a refused creation cannot leave the note
        // marked as edited for an embed that was never written.
        let note = target.touchedNote
        let previousUpdatedAt = note?.updatedAt
        note?.updatedAt = Date()
        func putTheNoteBumpBack() {
            if let note, let previousUpdatedAt { note.updatedAt = previousUpdatedAt }
        }

        let created: AppTask?
        do {
            created = try TaskCreationService(areas: areas, projects: projects)
                .createTask(from: draft, into: scope.modelContext, commit: commit)
        } catch {
            putTheNoteBumpBack()
            return nil
        }
        guard let embeddedTask = created else {
            putTheNoteBumpBack()
            return nil
        }

        recentEmbeddedTasks[embeddedTask.id] = embeddedTask
        editorTextView?.markdownTaskEmbeds[embeddedTask.id] = MarkdownTaskEmbedRenderInfo.task(embeddedTask)
        return .task(embeddedTask)
    }

    /// The card's circle toggles *settled*, not *done* ([[T-8394]], the rule T-344 decided): it
    /// asks the shared `CadenceTaskMutationSupport.toggleCompletion`, which reads `isFinishedTask`,
    /// so a cancelled card restores to todo as iOS's embed card already did. Reading `isDone` here
    /// completed a cancelled task on one click, minting the successor of a recurring one.
    func toggleEmbeddedTask(id: UUID, in scope: TaskNotesEmbedScope) {
        guard let embeddedTask = embeddedTask(id: id, in: scope) else { return }
        do {
            try CadenceTaskMutationSupport.toggleCompletion(
                embeddedTask,
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

    /// Bring the open note's `[[task:UUID|Title]]` source back in line with the tasks it embeds.
    ///
    /// Run when the task popover this editor opens on a card closes, which is the one moment where
    /// a rename has demonstrably just happened and this note is the note on screen. The inline
    /// rename over the card already writes both halves; the popover writes `task.title` alone, and
    /// the card goes on looking right because it is drawn from the live task rather than from the
    /// text under it. `MarkdownTaskEmbedParser` decides which references move — the same call iOS
    /// makes when its task sheet dismisses.
    ///
    /// This closes the renames made *through this note*. A rename made anywhere else while the note
    /// is open — Today's task column beside the core notes, a list, the timeline — still leaves the
    /// reference stale until the pointer next crosses the card (`hoverEmbeddedTask`) or the note is
    /// reopened after a rename here.
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
