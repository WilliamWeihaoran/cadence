import Foundation
import SwiftData

// Deliberately unguarded. This file wrapped its whole body in `#if os(macOS)` while containing
// zero AppKit — the same incidental guard `RemindersManager` and `PrivacyDataResetService` each
// carried, and the reason iOS shipped a full AI settings screen for a feature it could not invoke.
// Nothing moved: the file was already in `Cadence/Services/`, so there is no tombstone and no
// `.stringsdata` collision to avoid.
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

struct AITaskDraftValidation: Equatable {
    var errors: [String]
    var isValid: Bool { errors.isEmpty }
}

/// **One answer to "which list is this note's", for the whole AI note-action path.**
///
/// A note can carry an area *and* a project at once: `DataIntegrityRepairService` merges duplicate
/// notes and deliberately keeps both owners, and both iOS note surfaces hand both straight into the
/// AI menu. That state used to be resolved three separate times inside this one path — the prompt's
/// container name, the iOS review sheet's destination label, and the task insertion — and each of
/// the three independently answered `area ?? project`. One decision spelled three times is three
/// places for it to drift, so it is spelled here once and read from three call sites.
///
/// **Project wins**, because it is the narrower task container: tasks pulled out of a project's
/// note belong to that project, not to whatever area the project sits under. The app already takes
/// this side elsewhere — moving a note to a list explicitly clears the sibling field to keep a
/// single owner (`NoteActionSupport.move`).
struct AINoteContainer: Equatable {
    /// What to call the container, and `nil` when the note has no list. The prompt omits the field
    /// rather than naming an "Inbox" that is not a list the model could reason about.
    var name: String?
    /// Where extracted tasks are created.
    var selection: TaskContainerSelection

    /// A note owned by no list at all. Spelled `noList` rather than `none`, which at a call site
    /// reads as `Optional.none`.
    static let noList = AINoteContainer(name: nil, selection: .inbox)
}

enum AIActionService {
    /// Resolves a note's owners into the single container the prompt, the label and the write all
    /// read. See `AINoteContainer` for why project takes precedence.
    static func container(area: Area?, project: Project?) -> AINoteContainer {
        if let project {
            return AINoteContainer(name: project.name, selection: .project(project.id))
        }
        if let area {
            return AINoteContainer(name: area.name, selection: .area(area.id))
        }
        return .noList
    }

    static func noteContext(note: Note, area: Area? = nil, project: Project? = nil) throws -> AITextNoteContext {
        let title = note.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AIActionError.emptyNote }
        return AITextNoteContext(
            title: CadenceTitleNormalization.display(title, fallback: CadenceTitleNormalization.defaultNoteTitle),
            content: content,
            containerName: container(area: area, project: project).name
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

        let selection = container(area: area, project: project).selection
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
                subtaskTitles: draft.subtaskTitles,
                tags: []
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

    /// A draft date is kept only if it parses as `yyyy-MM-dd`; anything else becomes empty rather
    /// than being handed to `TaskCreationDraft` verbatim.
    ///
    /// Internal rather than private so it can be pinned directly: a model that answers "next
    /// Tuesday" or "2026-13-01" must not silently become a task with a wrong — or a garbage —
    /// due date, and that is a decision worth a test of its own rather than one inferred from
    /// `applyTaskDrafts`.
    ///
    /// Re-formatted, not returned as typed: `DateFormatters.ymd` is lenient about a single-digit
    /// month — `"2026-8-20"` parses — and this used to hand that string straight through to
    /// `TaskCreationDraft.dueDateKey`, where no "due today" check, group or sort key could see it.
    /// Found by `AINoteActionReviewTests`; `DateFormatters.normalizedDateKey` now carries that rule
    /// for every caller that takes a date from outside the app, this one and MCP alike, so there is
    /// one spelling of it rather than two that can drift.
    static func normalizedDate(_ value: String) -> String {
        DateFormatters.normalizedDateKey(value) ?? ""
    }
}
