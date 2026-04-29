import Foundation
import SwiftData

#if os(macOS)
enum AIActionError: LocalizedError, Equatable {
    case emptyNote
    case emptyTaskTitle
    case invalidPriority(String)
    case invalidDate(String)
    case invalidScheduledStartMin(Int)
    case invalidEstimate(Int)
    case invalidDrafts(String)

    var errorDescription: String? {
        switch self {
        case .emptyNote:
            return "This note is empty, so there is nothing useful to send to AI yet."
        case .emptyTaskTitle:
            return "Task drafts need a title before they can be created."
        case .invalidPriority(let priority):
            return "Invalid priority: \(priority). Expected none, low, medium, or high."
        case .invalidDate(let value):
            return "Invalid date: \(value). Expected yyyy-MM-dd."
        case .invalidScheduledStartMin(let value):
            return "Invalid scheduled time: \(value). Expected 0...1439."
        case .invalidEstimate(let value):
            return "Invalid estimate: \(value). Expected 1...1440 minutes."
        case .invalidDrafts(let message):
            return message
        }
    }
}
#endif

struct AITaskDraftValidation: Equatable {
    var errors: [String]
    var isValid: Bool { errors.isEmpty }
}

enum AIActionService {
    static func noteContext(note: Note, area: Area? = nil, project: Project? = nil) throws -> AITextNoteContext {
        let title = note.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AIActionError.emptyNote }
        return AITextNoteContext(
            title: title.isEmpty ? "Untitled Note" : title,
            content: content,
            containerName: area?.name ?? project?.name
        )
    }

    static func validation(for draft: AITaskDraft) -> AITaskDraftValidation {
        var errors: [String] = []
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AIActionError.emptyTaskTitle.errorDescription ?? "Missing title.")
        }
        if TaskPriority(rawValue: draft.priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) == nil {
            errors.append(AIActionError.invalidPriority(draft.priority).errorDescription ?? "Invalid priority.")
        }
        for date in [draft.dueDate, draft.scheduledDate] where !date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if DateFormatters.date(from: date) == nil {
                errors.append(AIActionError.invalidDate(date).errorDescription ?? "Invalid date.")
            }
        }
        if let scheduledStartMin = draft.scheduledStartMin, !(0...1439).contains(scheduledStartMin) {
            errors.append(AIActionError.invalidScheduledStartMin(scheduledStartMin).errorDescription ?? "Invalid scheduled time.")
        }
        if draft.scheduledStartMin != nil && draft.scheduledDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AIActionError.invalidDate("scheduledDate required when scheduledStartMin is set").errorDescription ?? "Missing scheduled date.")
        }
        if let estimatedMinutes = draft.estimatedMinutes, !(1...1440).contains(estimatedMinutes) {
            errors.append(AIActionError.invalidEstimate(estimatedMinutes).errorDescription ?? "Invalid estimate.")
        }
        return AITaskDraftValidation(errors: errors)
    }

    @discardableResult
    @MainActor
    static func applyTaskDrafts(
        _ drafts: [AITaskDraft],
        selectedIDs: Set<UUID>,
        area: Area? = nil,
        project: Project? = nil,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext
    ) throws -> [AppTask] {
        var created: [AppTask] = []
        let selected = drafts.filter { selectedIDs.contains($0.id) }
        let validationErrors = selected.flatMap { validation(for: $0).errors }
        guard validationErrors.isEmpty else {
            throw AIActionError.invalidDrafts(validationErrors.joined(separator: " "))
        }

        let selection: TaskContainerSelection
        if let area {
            selection = .area(area.id)
        } else if let project {
            selection = .project(project.id)
        } else {
            selection = .inbox
        }
        let service = TaskCreationService(areas: areas, projects: projects)
        for draft in selected {
            guard let priority = TaskPriority(rawValue: draft.priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                throw AIActionError.invalidPriority(draft.priority)
            }
            let dueDate = normalizedDate(draft.dueDate)
            let scheduledDate = normalizedDate(draft.scheduledDate)
            let taskDraft = TaskCreationDraft(
                title: draft.title,
                notes: draft.notes,
                priority: priority,
                container: selection,
                sectionName: draft.sectionName.isEmpty ? TaskSectionDefaults.defaultName : draft.sectionName,
                dueDateKey: dueDate,
                scheduledDateKey: scheduledDate,
                subtaskTitles: draft.subtaskTitles
            )
            guard let task = service.insertTask(from: taskDraft, into: modelContext) else { continue }
            if let scheduledStartMin = draft.scheduledStartMin {
                guard !scheduledDate.isEmpty else { throw AIActionError.invalidDate("scheduledDate required when scheduledStartMin is set") }
                guard (0...1439).contains(scheduledStartMin) else { throw AIActionError.invalidScheduledStartMin(scheduledStartMin) }
                task.scheduledStartMin = scheduledStartMin
            }
            if let estimatedMinutes = draft.estimatedMinutes {
                guard (1...1440).contains(estimatedMinutes) else { throw AIActionError.invalidEstimate(estimatedMinutes) }
                task.estimatedMinutes = estimatedMinutes
            }
            created.append(task)
        }
        if modelContext.hasChanges {
            try modelContext.save()
        }
        return created
    }

    private static func normalizedDate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return DateFormatters.date(from: trimmed) == nil ? "" : trimmed
    }
}
