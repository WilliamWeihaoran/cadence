import SwiftData
import SwiftUI

/// **A task embedded in a note, edited in place through the one schedule panel** ([[T-1481]],
/// the next adoption slice of [[T-3171]]).
///
/// The note editor opens this *inside the note*, directly under the embed's card, rather than in a
/// popover or a sheet: the owner's ruling was that the redesigned inspector opens inline. It is
/// `CadenceSchedulePanel` in edit mode over `CadenceScheduleDraft(editing:)`, saved through
/// `CadenceTaskEditDraftCommit` — the same pair the iOS task editor uses — so the fields a task has
/// are spelled once whichever surface opened them.
///
/// Platform-neutral on purpose. Where it sits in the text, how the note reflows around it and how
/// Escape reaches it belong to each platform's editor; what it edits and how it commits do not.
///
/// ## What it deliberately leaves out
///
/// - **Delete.** A task deleted from inside the note that embeds it would leave the note pointing
///   at nothing; deleting is the full inspector's job. `actions.delete` is `nil`, so the panel
///   draws no Delete control.
/// - **Status.** The card's own checkbox completes and reopens; Start and Cancel stay on the
///   card's status chip, which still opens its own small editor.
/// - **The series' end condition.** The Repeat row is offered (`offersTaskRepeat`), and a change to
///   a task that belongs to a series asks the series-scope question once, at Save. The end rows
///   stay with the full inspector, exactly as they do on iOS.
///
/// ## Dismissal
///
/// Save commits every drafted field at once and closes; Cancel discards the draft and closes. A
/// refused save keeps the panel open over the draft and says so. Clicking elsewhere in the note
/// does **not** close it — the draft is the user's unsaved work, and an inline panel has no
/// "outside" that means "throw it away". The host editor adds its platform's cancel key.
struct CadenceTaskInlinePanel: View {
    @Bindable var task: AppTask
    /// Closes the panel. Called after a landed Save and on Cancel.
    let onClose: () -> Void
    /// Called once a Save has landed, before `onClose`, so the host can repaint the embed's card.
    var onSaved: (AppTask) -> Void = { _ in }
    /// The row the chip that opened the panel names, opened expanded ([[T-3253]] (a)). `nil` for a
    /// host with no chip to read — the iOS card tap — which keeps every row closed.
    var openingRow: CadenceSchedulePanelRow?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var draft: CadenceScheduleDraft
    @State private var saveFailureNotice: String?
    @State private var isAskingRecurrenceScope = false

    /// The draft as the panel opened it: Save compares against it to decide whether the series
    /// moved, the one edit that asks how far it reaches.
    private let openedDraft: CadenceScheduleDraft

    init(
        task: AppTask,
        openingRow: CadenceSchedulePanelRow? = nil,
        onClose: @escaping () -> Void,
        onSaved: @escaping (AppTask) -> Void = { _ in }
    ) {
        _task = Bindable(wrappedValue: task)
        self.openingRow = openingRow
        self.onClose = onClose
        self.onSaved = onSaved
        let opened = CadenceScheduleDraft(editing: task)
        openedDraft = opened
        _draft = State(initialValue: opened)
    }

    private var containerChoice: TaskContainerSelection {
        CadenceTaskComposerSupport.selection(fromToken: draft.listToken)
    }

    /// Resolved against the unfiltered queries (T-514): a task in an archived list saves against
    /// the list it is in.
    private var selectedArea: Area? {
        guard let id = CadenceTaskComposerSupport.selectedAreaID(containerChoice) else { return nil }
        return areas.first { $0.id == id }
    }

    private var selectedProject: Project? {
        guard let id = CadenceTaskComposerSupport.selectedProjectID(containerChoice) else { return nil }
        return projects.first { $0.id == id }
    }

    var body: some View {
        CadenceSchedulePanel(
            draft: $draft,
            listChoices: CadenceSchedulePanelChoice.editableTaskListChoices(
                areas: areas,
                projects: projects,
                selection: containerChoice
            ),
            sectionChoices: CadenceTaskMutationSupport.sectionNames(forArea: selectedArea, project: selectedProject),
            failureNotice: saveFailureNotice,
            titleStatus: titleStatus,
            offersTaskRepeat: true,
            actions: CadenceSchedulePanelActions(commit: save, cancel: onClose, delete: nil)
        ) {
            CadenceSchedulePanelNotesRow(notes: $draft.notes)
        }
        .expanding(openingRow)
        .confirmationDialog(
            CadenceRecurrenceScopeCopy.taskScopeTitle,
            isPresented: $isAskingRecurrenceScope,
            titleVisibility: .visible
        ) {
            Button(CadenceTaskRecurrenceEditScope.thisTask.label) {
                applySave(scope: .thisTask)
            }
            Button(CadenceTaskRecurrenceEditScope.thisAndFuture.label) {
                applySave(scope: .thisAndFuture)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CadenceRecurrenceScopeCopy.taskScopeMessage)
        }
    }

    /// The same state the iOS editor draws on the title row, read live off the task. Cancelled is
    /// the only eyebrow since [[T-5015]] (b) retired In Progress.
    private var titleStatus: CadenceSchedulePanelTitleStatus {
        let status = task.status
        let showsEyebrow = task.isCancelled
        return CadenceSchedulePanelTitleStatus(
            eyebrow: showsEyebrow ? status.label : nil,
            eyebrowTint: CadenceTaskPresentationSupport.statusColor(status),
            isSettled: CadenceTaskCompletionState.resolve(task: task).isSettled
        )
    }

    /// `nil` always: a series edit stops at the scope question, and every outcome is reported
    /// through `saveFailureNotice`.
    private func save() -> String? {
        if Self.asksSeriesScope(draft: draft, opened: openedDraft, task: task) {
            isAskingRecurrenceScope = true
            return nil
        }
        applySave(scope: .thisTask)
        return nil
    }

    /// Whether Save has to ask "only this task, or this and future ones?" first: only when the
    /// draft moved the series **and** there is a series to reach.
    static func asksSeriesScope(draft: CadenceScheduleDraft, opened: CadenceScheduleDraft, task: AppTask) -> Bool {
        draft.changesRecurrence(from: opened) && task.isRecurrenceSeriesMember
    }

    private func applySave(scope: CadenceTaskRecurrenceEditScope) {
        guard CadenceTaskEditDraftCommit.save(
            draft,
            opened: openedDraft,
            to: task,
            area: selectedArea,
            project: selectedProject,
            allTasks: allTasks,
            scope: scope,
            in: modelContext
        ) else {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        onSaved(task)
        onClose()
    }
}

extension CadenceSchedulePanelChoice {
    /// The List rows for editing a task that already exists: the Inbox, the active lists, **plus
    /// the one the task is in**, archived or not, so the row names where the task actually lives
    /// (T-514). The one copy of the rule: `iOSTaskDetailSheet.listChoices` calls this too (T-3204),
    /// pinned by `CadenceContainerPickerConsolidationTests`.
    static func editableTaskListChoices(
        areas: [Area],
        projects: [Project],
        selection: TaskContainerSelection
    ) -> [CadenceSchedulePanelChoice] {
        var rows = [
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .inbox),
                name: CadenceTaskInspectorSupport.inboxSegmentTitle,
                color: Theme.blue,
                systemImage: "tray.full.fill"
            )
        ]
        rows += CadenceTaskComposerSupport.pickableAreas(
            areas,
            selectedID: CadenceTaskComposerSupport.selectedAreaID(selection)
        ).map {
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .area($0.id)),
                name: $0.name,
                color: Color(hex: $0.colorHex),
                systemImage: "tray.full.fill"
            )
        }
        rows += CadenceTaskComposerSupport.pickableProjects(
            projects,
            selectedID: CadenceTaskComposerSupport.selectedProjectID(selection)
        ).map {
            CadenceSchedulePanelChoice(
                id: CadenceTaskComposerSupport.token(for: .project($0.id)),
                name: $0.name,
                color: Color(hex: $0.colorHex),
                systemImage: "checklist"
            )
        }
        return rows
    }
}
