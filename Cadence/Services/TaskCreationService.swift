import Foundation
import SwiftData

/// `nonisolated` because the target defaults to `@MainActor`, which isolates the synthesised
/// `Equatable`/`Hashable` conformances — and a `#expect` macro expands into a nonisolated context,
/// so comparing two of these in a test warns "main actor-isolated conformance ... cannot be used in
/// nonisolated context; this is an error in the Swift 6 language mode" (measured, r32, 2026-08-30).
/// The cases carry only a `UUID`, so there is nothing here that needs the actor. Same shape as
/// T-445's `nonisolated extension` and T-122's `& Sendable`: a Swift 6 prerequisite paid early.
nonisolated enum TaskContainerSelection: Hashable {
    case inbox
    case area(UUID)
    case project(UUID)
}

struct TaskCreationDraft {
    let title: String
    let notes: String
    let priority: TaskPriority
    let container: TaskContainerSelection
    let sectionName: String
    let dueDateKey: String
    let scheduledDateKey: String
    let subtaskTitles: [String]
    let tags: [Tag]
    var scheduledStartMin: Int = -1
    var estimatedMinutes: Int = 30

    var trimmedTitle: String {
        if let shortcut = TaskTitleSupport.priorityShortcut(in: title) {
            return shortcut.title
        }
        return TaskTitleSupport.normalized(title)
    }

    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedPriority: TaskPriority {
        TaskTitleSupport.priorityShortcut(in: title)?.priority ?? priority
    }
}

struct TaskContainerResolver {
    let areas: [Area]
    let projects: [Project]

    func availableSections(for selection: TaskContainerSelection) -> [String] {
        switch selection {
        case .inbox:
            return [TaskSectionDefaults.defaultName]
        case .area(let areaID):
            return areas.first(where: { $0.id == areaID })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        case .project(let projectID):
            return projects.first(where: { $0.id == projectID })?.sectionNames ?? [TaskSectionDefaults.defaultName]
        }
    }

    func normalizedSectionName(_ sectionName: String, for selection: TaskContainerSelection) -> String {
        let validSections = availableSections(for: selection)
        return validSections.first(where: { $0.caseInsensitiveCompare(sectionName) == .orderedSame })
            ?? validSections.first
            ?? TaskSectionDefaults.defaultName
    }

    func applyContainer(_ selection: TaskContainerSelection, to task: AppTask) {
        switch selection {
        case .inbox:
            task.area = nil
            task.project = nil
            task.context = nil
            task.sectionName = TaskSectionDefaults.defaultName
        case .area(let areaID):
            guard let area = areas.first(where: { $0.id == areaID }) else {
                task.sectionName = TaskSectionDefaults.defaultName
                return
            }
            task.area = area
            task.project = nil
            task.context = area.context
        case .project(let projectID):
            guard let project = projects.first(where: { $0.id == projectID }) else {
                task.sectionName = TaskSectionDefaults.defaultName
                return
            }
            task.project = project
            task.area = nil
            task.context = project.resolvedContext
        }
    }
}

struct TaskCreationService {
    let containerResolver: TaskContainerResolver

    init(areas: [Area], projects: [Project]) {
        containerResolver = TaskContainerResolver(areas: areas, projects: projects)
    }

    /// Shown when the creation could not be committed. Held here rather than spelled at each
    /// composer, so the sheets that create a task cannot come to describe the same failure
    /// differently.
    static let saveFailureNotice = "Couldn't save this task."

    /// Builds and inserts the task, and leaves the commit to the caller.
    ///
    /// Prefer `createTask(from:into:)` on any surface that reports success — dismissing, navigating
    /// or handing the task on. See its note for why.
    ///
    /// **T-364 moved every such surface off this method.** What is left are callers that genuinely
    /// do not report success: `SchedulingActions.createTask`, a timeline drop handler that mutates
    /// pending alongside `dropTask`/`addTask` and tells nobody anything, and
    /// `AIActionService.applyTaskDrafts`, which batches many drafts into one `try modelContext.save()`
    /// and rethrows so its review sheets can present the failure. A new caller here needs the same
    /// answer to "what does this surface show when the save throws?"
    @discardableResult
    func insertTask(from draft: TaskCreationDraft, into modelContext: ModelContext) -> AppTask? {
        insertion(from: draft, into: modelContext)?.task
    }

    /// Builds, inserts **and commits** the task, undoing the whole insertion if the commit throws.
    ///
    /// **T-319.** `insertTask` only marks the task pending; the surrounding sheet then saved with
    /// `try?` and dismissed, so a throwing save produced the entire success experience — the sheet
    /// closed, `onCreated` ran, and notification reconciliation swept a task the store never took.
    /// A creation is the case where rolling back is right: there is nothing on screen to hand the
    /// half-made task back to, and the composer still holds every field the user typed, so undoing
    /// and reporting lets them press Add again.
    ///
    /// The undo covers the subtasks too. `AppTask.subtasks` declares no cascade, so deleting only
    /// the task would leave its subtask rows behind in the context, attached to nothing.
    ///
    /// Returns `nil` for a draft with no title — the same "nothing to create" answer `insertTask`
    /// gives, and not a failure.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`; it is
    ///   forwarded so the undo path stays reachable from a test.
    @discardableResult
    func createTask(
        from draft: TaskCreationDraft,
        into modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> AppTask? {
        guard let insertion = insertion(from: draft, into: modelContext) else { return nil }
        try CadencePendingChangePersistence.commitInsert(
            of: insertion.inserted,
            in: modelContext,
            commit: commit
        )
        return insertion.task
    }

    /// The task and every object inserted alongside it, which is what an undo needs to know.
    private func insertion(
        from draft: TaskCreationDraft,
        into modelContext: ModelContext
    ) -> (task: AppTask, inserted: [any PersistentModel])? {
        guard !draft.trimmedTitle.isEmpty else { return nil }

        let task = AppTask(title: draft.trimmedTitle)
        task.notes = draft.trimmedNotes
        task.priority = draft.resolvedPriority
        task.sectionName = containerResolver.normalizedSectionName(draft.sectionName, for: draft.container)
        task.dueDate = draft.dueDateKey
        task.scheduledDate = draft.scheduledDateKey
        task.scheduledStartMin = draft.scheduledDateKey.isEmpty ? -1 : draft.scheduledStartMin
        task.estimatedMinutes = max(5, draft.estimatedMinutes)
        task.tags = TagSupport.sorted(draft.tags)
        containerResolver.applyContainer(draft.container, to: task)

        modelContext.insert(task)
        let subtasks = CadenceTaskMutationSupport.insertSubtasks(
            titled: draft.subtaskTitles,
            into: task,
            modelContext: modelContext
        )
        return (task, [task] + subtasks)
    }
}
