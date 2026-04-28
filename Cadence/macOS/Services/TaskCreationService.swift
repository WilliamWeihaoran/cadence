#if os(macOS)
import Foundation
import SwiftData

struct TaskCreationDraft {
    let title: String
    let notes: String
    let priority: TaskPriority
    let container: TaskContainerSelection
    let sectionName: String
    let dueDateKey: String
    let scheduledDateKey: String
    let subtaskTitles: [String]

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
            task.context = project.context
        }
    }
}

struct TaskCreationService {
    let containerResolver: TaskContainerResolver

    init(areas: [Area], projects: [Project]) {
        containerResolver = TaskContainerResolver(areas: areas, projects: projects)
    }

    @discardableResult
    func insertTask(from draft: TaskCreationDraft, into modelContext: ModelContext, syncCalendar: Bool = true) -> AppTask? {
        guard !draft.trimmedTitle.isEmpty else { return nil }

        let task = AppTask(title: draft.trimmedTitle)
        task.notes = draft.trimmedNotes
        task.priority = draft.priority
        task.sectionName = containerResolver.normalizedSectionName(draft.sectionName, for: draft.container)
        task.dueDate = draft.dueDateKey
        task.scheduledDate = draft.scheduledDateKey
        containerResolver.applyContainer(draft.container, to: task)

        modelContext.insert(task)
        insertSubtasks(draft.subtaskTitles, parent: task, into: modelContext)

        if syncCalendar {
            SchedulingActions.syncToCalendarIfLinked(task)
        }
        return task
    }

    private func insertSubtasks(_ titles: [String], parent task: AppTask, into modelContext: ModelContext) {
        for (index, title) in titles.enumerated() {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let subtask = Subtask(title: trimmed)
            subtask.parentTask = task
            subtask.order = index
            modelContext.insert(subtask)
        }
    }
}
#endif
