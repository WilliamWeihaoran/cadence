import Foundation
import SwiftData

enum CadenceReadError: Error, LocalizedError, Sendable {
    case storeNotFound([String])
    case invalidDate(String)
    case invalidIdentifier(String)
    case invalidContainerKind(String)
    case invalidStatus(String)
    case invalidScope(String)
    case invalidNoteKind(String)
    case incompleteContainerFilter
    case taskNotFound(String)
    case taskBundleNotFound(String)
    case containerNotFound(String, String)
    case noteNotFound(String)
    case documentNotFound(String)
    case goalNotFound(String)

    var errorDescription: String? {
        switch self {
        case .storeNotFound(let paths):
            return "Could not find Cadence SwiftData store. Checked: \(paths.joined(separator: ", "))"
        case .invalidDate(let value):
            return "Invalid Cadence date key: \(value). Expected yyyy-MM-dd."
        case .invalidIdentifier(let value):
            return "Invalid UUID string: \(value)"
        case .invalidContainerKind(let value):
            return "Invalid container kind: \(value). Expected area or project."
        case .invalidStatus(let value):
            return "Invalid status value: \(value)."
        case .invalidScope(let value):
            return "Invalid search scope: \(value). Expected tasks, containers, documents, notes, core_notes, event_notes, goals, habits, links, or tags."
        case .invalidNoteKind(let value):
            return "Invalid note kind: \(value). Expected daily, weekly, permanent, list, or meeting."
        case .incompleteContainerFilter:
            return "containerKind and containerId must be provided together."
        case .taskNotFound(let value):
            return "No task found with id \(value)."
        case .taskBundleNotFound(let value):
            return "No task bundle found with id \(value)."
        case .containerNotFound(let kind, let id):
            return "No \(kind) found with id \(id)."
        case .noteNotFound(let value):
            return "No note found with id \(value)."
        case .documentNotFound(let value):
            return "No document found with id \(value)."
        case .goalNotFound(let value):
            return "No goal found with id \(value)."
        }
    }
}

struct CadenceTaskListOptions: Sendable {
    var statuses: [String]? = nil
    var includeCompleted: Bool = false
    var dueDateFrom: String? = nil
    var dueDateTo: String? = nil
    var scheduledDate: String? = nil
    var containerKind: String? = nil
    var containerId: String? = nil
    var textQuery: String? = nil
    var tagSlugs: [String]? = nil
    var limit: Int = 50
}

struct CadenceNoteListOptions: Sendable {
    var kind: String? = nil
    var containerKind: String? = nil
    var containerId: String? = nil
    var query: String? = nil
    var tagSlugs: [String]? = nil
    var limit: Int = 50
}

struct CadenceGoalListOptions: Sendable {
    var status: String? = nil
    var contextId: String? = nil
    var query: String? = nil
    var limit: Int = 50
}

struct CadenceHabitListOptions: Sendable {
    var contextId: String? = nil
    var goalId: String? = nil
    var query: String? = nil
    var limit: Int = 50
}

struct CadenceSavedLinkListOptions: Sendable {
    var containerKind: String? = nil
    var containerId: String? = nil
    var query: String? = nil
    var limit: Int = 50
}

struct CadenceTaskBundleListOptions: Sendable {
    var dateKey: String? = nil
    var limit: Int = 50
}

@MainActor
final class CadenceReadService {
    private let context: ModelContext
    private let encoderDateFormatter = ISO8601DateFormatter()

    init(container: ModelContainer) {
        context = ModelContext(container)
        NoteMigrationService.migrateAndRecordFailure(in: context, source: "mcp-read-service-container")
    }

    init(context: ModelContext) {
        self.context = context
        NoteMigrationService.migrateAndRecordFailure(in: context, source: "mcp-read-service-context")
    }

    func todayBrief(dateKey: String? = nil) throws -> CadenceTodayBrief {
        let resolvedDateKey = try resolvedDateKey(dateKey)
        let tasks = try fetchTasks()
        let activeTasks = tasks.filter { !$0.isDone && !$0.isCancelled }

        let scheduled = activeTasks
            .filter { $0.scheduledDate == resolvedDateKey && $0.scheduledStartMin >= 0 }
            .sorted(by: taskSort)
            .map { taskSummary($0, allTasks: tasks) }

        let dueToday = activeTasks
            .filter { $0.dueDate == resolvedDateKey }
            .sorted(by: taskSort)
            .map { taskSummary($0, allTasks: tasks) }

        let overdue = activeTasks
            .filter { !$0.dueDate.isEmpty && $0.dueDate < resolvedDateKey }
            .sorted(by: taskSort)
            .map { taskSummary($0, allTasks: tasks) }

        let inbox = activeTasks
            .filter { $0.area == nil && $0.project == nil }
            .sorted(by: taskSort)
            .prefix(50)
            .map { taskSummary($0, allTasks: tasks) }

        let notes = try coreNotes(dateKey: resolvedDateKey)
        let noteSnippets = [notes.dailyNote, notes.weeklyNote, notes.permanentNote].compactMap { $0 }

        return CadenceTodayBrief(
            dateKey: resolvedDateKey,
            scheduledTasks: scheduled,
            dueToday: dueToday,
            overdue: overdue,
            inbox: Array(inbox),
            noteSnippets: noteSnippets
        )
    }

    func listTasks(options: CadenceTaskListOptions) throws -> [CadenceTaskSummary] {
        let tasks = try fetchTasks()
        var filtered = tasks.filter { !$0.isCancelled }

        if let statuses = options.statuses, !statuses.isEmpty {
            let allowed = try validateTaskStatuses(statuses)
            filtered = filtered.filter { allowed.contains($0.statusRaw.lowercased()) }
        } else if !options.includeCompleted {
            filtered = filtered.filter { !$0.isDone }
        }

        if let dueDateFrom = options.dueDateFrom {
            _ = try parsedDate(dueDateFrom)
            filtered = filtered.filter { !$0.dueDate.isEmpty && $0.dueDate >= dueDateFrom }
        }

        if let dueDateTo = options.dueDateTo {
            _ = try parsedDate(dueDateTo)
            filtered = filtered.filter { !$0.dueDate.isEmpty && $0.dueDate <= dueDateTo }
        }

        if let scheduledDate = options.scheduledDate {
            _ = try parsedDate(scheduledDate)
            filtered = filtered.filter { $0.scheduledDate == scheduledDate }
        }

        if let containerFilter = try resolvedContainerFilter(kind: options.containerKind, id: options.containerId) {
            filtered = try filterTasks(filtered, containerKind: containerFilter.kind, containerID: containerFilter.id)
        }

        if let tagSlugs = options.tagSlugs, !tagSlugs.isEmpty {
            let required = Set(tagSlugs.map(TagSupport.slug(for:)))
            filtered = filtered.filter { task in
                required.isSubset(of: Set(task.sortedTags.map(\.slug)))
            }
        }

        if let query = options.textQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            filtered = filtered.filter { task in
                let tagText = task.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                return CadenceSearchMatcher.matchScore(
                    query: query,
                    fields: [
                        task.title,
                        task.notes,
                        task.project?.name ?? "",
                        task.area?.name ?? "",
                        task.context?.name ?? "",
                        task.resolvedSectionName,
                        tagText,
                    ]
                ) != nil
            }
        }

        return filtered
            .sorted(by: taskSort)
            .prefix(cappedLimit(options.limit))
            .map { taskSummary($0, allTasks: tasks) }
    }

    func getTask(taskID: String) throws -> CadenceTaskDetail {
        let id = try uuid(from: taskID)
        let tasks = try fetchTasks()
        guard let task = tasks.first(where: { $0.id == id }) else {
            throw CadenceReadError.taskNotFound(taskID)
        }

        let subtasks = (task.subtasks ?? [])
            .sorted { $0.order < $1.order }
            .map {
                CadenceSubtaskSummary(
                    id: $0.id.uuidString,
                    title: $0.title,
                    isDone: $0.isDone,
                    order: $0.order
                )
            }

        return CadenceTaskDetail(
            summary: taskSummary(task, allTasks: tasks),
            notes: task.notes,
            actualMinutes: task.actualMinutes,
            subtasks: subtasks,
            createdAt: format(task.createdAt),
            completedAt: task.completedAt.map(format)
        )
    }

    func listTaskBundles(options: CadenceTaskBundleListOptions) throws -> [CadenceTaskBundleSummary] {
        var bundles = try fetchTaskBundles()

        if let dateKey = options.dateKey {
            _ = try parsedDate(dateKey)
            bundles = bundles.filter { $0.dateKey == dateKey }
        }

        return Array(bundles
            .sorted {
                if $0.dateKey != $1.dateKey { return $0.dateKey < $1.dateKey }
                if $0.startMin != $1.startMin { return $0.startMin < $1.startMin }
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            .prefix(cappedLimit(options.limit))
            .map(taskBundleSummary))
    }

    func getTaskBundle(bundleID: String) throws -> CadenceTaskBundleDetail {
        let id = try uuid(from: bundleID)
        guard let bundle = try fetchTaskBundles().first(where: { $0.id == id }) else {
            throw CadenceReadError.taskBundleNotFound(bundleID)
        }
        let tasks = try fetchTasks()
        return CadenceTaskBundleDetail(
            summary: taskBundleSummary(bundle),
            tasks: bundle.sortedTasks.map { taskSummary($0, allTasks: tasks) }
        )
    }

    func listContainers(kind: String? = nil, status: String? = nil, contextID: String? = nil, limit: Int = 50) throws -> [CadenceContainerRef] {
        let contextUUID = try contextID.map(uuid)
        let normalizedKind = try kind.map(normalizeContainerKind)
        let normalizedStatus = try status.map { try validateContainerStatus($0, kind: normalizedKind) }

        var refs: [CadenceContainerRef] = []
        if normalizedKind == nil || normalizedKind == "area" {
            refs += try fetchAreas()
                .filter { area in
                    (normalizedStatus == nil || area.statusRaw == normalizedStatus) &&
                    (contextUUID == nil || area.context?.id == contextUUID)
                }
                .sorted { $0.order < $1.order }
                .map(containerRef)
        }

        if normalizedKind == nil || normalizedKind == "project" {
            refs += try fetchProjects()
                .filter { project in
                    (normalizedStatus == nil || project.statusRaw == normalizedStatus) &&
                    (contextUUID == nil || project.context?.id == contextUUID)
                }
                .sorted { $0.order < $1.order }
                .map(containerRef)
        }

        return Array(refs.prefix(cappedLimit(limit)))
    }

    func containerSummary(kind: String, id: String) throws -> CadenceContainerSummary {
        let uuid = try uuid(from: id)
        let tasks = try fetchTasks()
        let containerTasks = try filterTasks(tasks, containerKind: kind, containerID: uuid)
        let active = containerTasks.filter { !$0.isDone && !$0.isCancelled }
        let today = DateFormatters.todayKey()
        let overdue = active.filter { !$0.dueDate.isEmpty && $0.dueDate < today }
        let links = try linksForContainer(kind: kind, id: uuid)
            .sorted { $0.order < $1.order }
            .map(linkSummary)
        let noteDocuments = try notesForContainer(kind: kind, id: uuid)
            .sorted { $0.order < $1.order }
            .map(documentSummary)

        return CadenceContainerSummary(
            container: try containerRef(kind: kind, id: uuid),
            activeTaskCount: active.count,
            completedTaskCount: containerTasks.filter(\.isDone).count,
            overdueTaskCount: overdue.count,
            sections: try sectionSummaries(kind: kind, id: uuid, tasks: containerTasks),
            documents: noteDocuments,
            links: links
        )
    }

    func coreNotes(dateKey: String? = nil) throws -> CadenceCoreNotesSnapshot {
        let resolvedDateKey = try resolvedDateKey(dateKey)
        let resolvedWeekKey = try weekKey(for: resolvedDateKey)

        let notes = try fetchNotes()
        let daily = notes.first { $0.kind == .daily && $0.dateKey == resolvedDateKey }
        let weekly = notes.first { $0.kind == .weekly && $0.weekKey == resolvedWeekKey }
        let permanent = notes.first { $0.kind == .permanent }

        return CadenceCoreNotesSnapshot(
            dateKey: resolvedDateKey,
            weekKey: resolvedWeekKey,
            dailyNote: daily.map { notePayload($0, key: resolvedDateKey) },
            weeklyNote: weekly.map { notePayload($0, key: resolvedWeekKey) },
            permanentNote: permanent.map { notePayload($0, key: nil) }
        )
    }

    func listDocuments(containerKind: String? = nil, containerID: String? = nil, query: String? = nil, limit: Int = 50) throws -> [CadenceDocumentSummary] {
        var docs = try fetchNotes().filter { $0.kind == .list }

        if let containerFilter = try resolvedContainerFilter(kind: containerKind, id: containerID) {
            docs = try notesForContainer(kind: containerFilter.kind, id: containerFilter.id)
        }

        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            docs = docs.filter { doc in
                let tagText = doc.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                return CadenceSearchMatcher.matchScore(query: query, fields: [doc.title, doc.content, doc.area?.name ?? "", doc.project?.name ?? "", tagText]) != nil
            }
        }

        let noteSummaries = docs
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(documentSummary)
        return Array(noteSummaries.prefix(cappedLimit(limit)))
    }

    func getDocument(documentID: String) throws -> CadenceDocumentDetail {
        let id = try uuid(from: documentID)
        if let doc = try fetchNotes().first(where: { $0.kind == .list && $0.id == id }) {
            return CadenceDocumentDetail(
                id: doc.id.uuidString,
                title: doc.displayTitle,
                container: documentContainer(doc),
                content: doc.content,
                order: doc.order,
                createdAt: format(doc.createdAt),
                updatedAt: format(doc.updatedAt),
                tags: tagSummaries(doc.sortedTags)
            )
        }

        throw CadenceReadError.documentNotFound(documentID)
    }

    func listTags(includeArchived: Bool = false, query: String? = nil, limit: Int = 50) throws -> [CadenceTagDetail] {
        var tags = try fetchTags()
        if !includeArchived {
            tags = tags.filter { !$0.isArchived }
        }
        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            tags = tags.filter { tag in
                CadenceSearchMatcher.matchScore(query: query, fields: [tag.name, tag.slug, tag.desc]) != nil
            }
        }
        return Array(TagSupport.sorted(tags)
            .prefix(cappedLimit(limit))
            .map(tagDetail))
    }

    func listNotes(options: CadenceNoteListOptions) throws -> [CadenceNoteSummary] {
        var notes = try fetchNotes()

        if let kind = options.kind {
            let normalizedKind = try validateNoteKind(kind)
            notes = notes.filter { $0.kindRaw == normalizedKind }
        }

        if let containerFilter = try resolvedContainerFilter(kind: options.containerKind, id: options.containerId) {
            notes = try filterNotes(notes, containerKind: containerFilter.kind, containerID: containerFilter.id)
        }

        if let tagSlugs = options.tagSlugs, !tagSlugs.isEmpty {
            let required = Set(tagSlugs.map(TagSupport.slug(for:)))
            notes = notes.filter { note in
                required.isSubset(of: Set(note.sortedTags.map(\.slug)))
            }
        }

        if let query = options.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            notes = notes.filter { note in
                let tagText = note.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                return CadenceSearchMatcher.matchScore(query: query, fields: [note.displayTitle, note.content, noteKey(note) ?? "", tagText]) != nil
            }
        }

        return Array(notes
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(cappedLimit(options.limit))
            .map(noteSummary))
    }

    func getNote(noteID: String) throws -> CadenceNoteDetail {
        let id = try uuid(from: noteID)
        let notes = try fetchNotes()
        let tasks = try fetchTasks()
        guard let note = notes.first(where: { $0.id == id }) else {
            throw CadenceReadError.noteNotFound(noteID)
        }

        return CadenceNoteDetail(
            summary: noteSummary(note),
            content: note.content,
            order: note.order,
            createdAt: format(note.createdAt),
            updatedAt: format(note.updatedAt),
            linkedNotes: NoteReferenceResolver.linkedNotes(for: note, in: notes).map(noteSummary),
            backlinks: NoteReferenceResolver.backlinks(for: note, in: notes).map(noteSummary),
            linkedTasks: NoteReferenceResolver.linkedTasks(for: note, in: tasks).map { taskSummary($0, allTasks: tasks) }
        )
    }

    func listGoals(options: CadenceGoalListOptions) throws -> [CadenceGoalSummary] {
        let contextUUID = try options.contextId.map(uuid)
        let normalizedStatus = try options.status.map(validateGoalStatus)
        var goals = try fetchGoals()

        if let normalizedStatus {
            goals = goals.filter { $0.statusRaw == normalizedStatus }
        }
        if let contextUUID {
            goals = goals.filter { $0.context?.id == contextUUID }
        }
        if let query = options.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            goals = goals.filter { goal in
                CadenceSearchMatcher.matchScore(query: query, fields: [goal.title, goal.desc, goal.context?.name ?? "", goal.statusRaw]) != nil
            }
        }

        return Array(goals
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .prefix(cappedLimit(options.limit))
            .map(goalSummary))
    }

    func getGoal(goalID: String) throws -> CadenceGoalDetail {
        let id = try uuid(from: goalID)
        let goals = try fetchGoals()
        let tasks = try fetchTasks()
        guard let goal = goals.first(where: { $0.id == id }) else {
            throw CadenceReadError.goalNotFound(goalID)
        }
        let contribution = GoalContributionResolver.summary(for: goal)
        let habitMomentum = GoalHabitMomentumResolver.summary(for: goal)
        let directTasks = (goal.tasks ?? [])
            .filter { !$0.isCancelled }
            .sorted(by: taskSort)
            .map { taskSummary($0, allTasks: tasks) }

        return CadenceGoalDetail(
            summary: goalSummary(goal),
            contribution: CadenceGoalContributionSnapshot(
                totalTasks: contribution.totalTasks,
                completedTasks: contribution.completedTasks,
                directTaskCount: contribution.directTaskCount,
                linkedListCount: contribution.linkedListCount,
                focusMinutes: contribution.focusMinutes,
                overdueTaskCount: contribution.overdueTaskCount,
                recentCompletedCount: contribution.recentCompletedCount,
                nextActionTitle: contribution.nextActionTitle,
                progress: contribution.progress
            ),
            habitMomentum: CadenceGoalHabitMomentumSnapshot(
                linkedHabitCount: habitMomentum.linkedHabitCount,
                dueTodayCount: habitMomentum.dueTodayCount,
                doneTodayCount: habitMomentum.doneTodayCount,
                thisWeekCount: habitMomentum.thisWeekCount,
                last7DayCount: habitMomentum.last7DayCount
            ),
            linkedContainers: (goal.listLinks ?? []).compactMap { link in
                if let area = link.area { return containerRef(area) }
                if let project = link.project { return containerRef(project) }
                return nil
            },
            directTasks: directTasks,
            subGoals: (goal.subGoals ?? []).map(goalSummary),
            habits: (goal.habits ?? []).map(habitSummary)
        )
    }

    func listHabits(options: CadenceHabitListOptions) throws -> [CadenceHabitSummary] {
        let contextUUID = try options.contextId.map(uuid)
        let goalUUID = try options.goalId.map(uuid)
        var habits = try fetchHabits()

        if let contextUUID {
            habits = habits.filter { $0.context?.id == contextUUID }
        }
        if let goalUUID {
            habits = habits.filter { $0.goal?.id == goalUUID }
        }
        if let query = options.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            habits = habits.filter { habit in
                CadenceSearchMatcher.matchScore(query: query, fields: [habit.title, habit.context?.name ?? "", habit.goal?.title ?? "", habit.frequencyTypeRaw]) != nil
            }
        }

        return Array(habits
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .prefix(cappedLimit(options.limit))
            .map(habitSummary))
    }

    func listLinks(options: CadenceSavedLinkListOptions) throws -> [CadenceSavedLinkSummary] {
        var links = try fetchLinks()

        if let containerFilter = try resolvedContainerFilter(kind: options.containerKind, id: options.containerId) {
            links = try filterLinks(links, containerKind: containerFilter.kind, containerID: containerFilter.id)
        }

        if let query = options.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            links = links.filter { link in
                CadenceSearchMatcher.matchScore(query: query, fields: [link.title, link.url, link.area?.name ?? "", link.project?.name ?? ""]) != nil
            }
        }

        return Array(links
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .prefix(cappedLimit(options.limit))
            .map(linkSummary))
    }

    func search(query: String, scopes: [String]? = nil, limit: Int = 50) throws -> [CadenceSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let selectedScopes = try validateScopes(scopes ?? ["tasks", "containers", "documents", "core_notes", "event_notes", "goals", "habits", "links", "tags"])
        let noteScopes = Set(["documents", "notes", "core_notes", "event_notes"])
        let notes = selectedScopes.isDisjoint(with: noteScopes) ? [] : try fetchNotes()
        var hits: [CadenceSearchHit] = []

        if selectedScopes.contains("tasks") {
            let tasks = try fetchTasks()
            hits += tasks.compactMap { task in
                let tagText = task.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                let fields = [task.title, task.notes, task.area?.name ?? "", task.project?.name ?? "", task.context?.name ?? "", tagText]
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: fields) else { return nil }
                return CadenceSearchHit(
                    entityType: "task",
                    entityId: task.id.uuidString,
                    title: resolvedTitle(task.title, fallback: "Untitled Task"),
                    subtitle: [task.project?.name ?? task.area?.name ?? "Inbox", task.statusRaw].joined(separator: " - "),
                    excerpt: excerpt(task.notes.isEmpty ? task.title : task.notes),
                    score: score
                )
            }
        }

        if selectedScopes.contains("containers") {
            hits += try fetchAreas().compactMap { area in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [area.name, area.desc, area.context?.name ?? ""]) else { return nil }
                return CadenceSearchHit(entityType: "area", entityId: area.id.uuidString, title: area.name, subtitle: area.context?.name ?? "No context", excerpt: excerpt(area.desc), score: score)
            }
            hits += try fetchProjects().compactMap { project in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [project.name, project.desc, project.context?.name ?? "", project.area?.name ?? ""]) else { return nil }
                return CadenceSearchHit(entityType: "project", entityId: project.id.uuidString, title: project.name, subtitle: project.context?.name ?? "No context", excerpt: excerpt(project.desc), score: score)
            }
        }

        if selectedScopes.contains("documents") {
            let noteDocs = notes.filter { $0.kind == .list }
            hits += noteDocs.compactMap { doc in
                let tagText = doc.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [doc.title, doc.content, doc.area?.name ?? "", doc.project?.name ?? "", tagText]) else { return nil }
                return CadenceSearchHit(entityType: "document", entityId: doc.id.uuidString, title: doc.displayTitle, subtitle: documentContainer(doc)?.name ?? "No container", excerpt: excerpt(doc.content), score: score)
            }
        }

        if selectedScopes.contains("core_notes") {
            hits += notes.filter { [.daily, .weekly, .permanent].contains($0.kind) }.compactMap { note in
                let key = note.kind == .daily ? note.dateKey : (note.kind == .weekly ? note.weekKey : "notepad permanent note")
                let tagText = note.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [key, note.title, note.content, tagText]) else { return nil }
                return CadenceSearchHit(entityType: noteEntityType(note), entityId: note.id.uuidString, title: note.displayTitle, subtitle: noteSubtitle(note), excerpt: excerpt(note.content), score: score)
            }
        }

        if selectedScopes.contains("event_notes") {
            let meetingNotes = notes.filter { $0.kind == .meeting }
            hits += meetingNotes.compactMap { note in
                let title = note.displayTitle
                let tagText = note.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                let fields = [title, note.content, note.eventDateKey, tagText]
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: fields) else { return nil }
                return CadenceSearchHit(
                    entityType: "event_note",
                    entityId: note.id.uuidString,
                    title: title,
                    subtitle: "Meeting note",
                    excerpt: excerpt(note.content),
                    score: score
                )
            }
        }

        if selectedScopes.contains("notes") {
            hits += notes.compactMap { note in
                let tagText = note.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [note.displayTitle, note.content, noteKey(note) ?? "", tagText]) else { return nil }
                return CadenceSearchHit(entityType: noteEntityType(note), entityId: note.id.uuidString, title: note.displayTitle, subtitle: noteSubtitle(note), excerpt: excerpt(note.content), score: score)
            }
        }

        if selectedScopes.contains("goals") {
            hits += try fetchGoals().compactMap { goal in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [goal.title, goal.desc, goal.context?.name ?? "", goal.statusRaw]) else { return nil }
                return CadenceSearchHit(
                    entityType: "goal",
                    entityId: goal.id.uuidString,
                    title: resolvedTitle(goal.title, fallback: "Untitled Goal"),
                    subtitle: [goal.context?.name ?? "No context", goal.statusRaw].joined(separator: " - "),
                    excerpt: excerpt(goal.desc),
                    score: score
                )
            }
        }

        if selectedScopes.contains("habits") {
            hits += try fetchHabits().compactMap { habit in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [habit.title, habit.context?.name ?? "", habit.goal?.title ?? "", habit.frequencyTypeRaw]) else { return nil }
                return CadenceSearchHit(
                    entityType: "habit",
                    entityId: habit.id.uuidString,
                    title: resolvedTitle(habit.title, fallback: "Untitled Habit"),
                    subtitle: [habit.context?.name ?? "No context", "\(habit.currentStreak) day streak"].joined(separator: " - "),
                    excerpt: habit.goal?.title ?? "",
                    score: score
                )
            }
        }

        if selectedScopes.contains("links") {
            hits += try fetchLinks().compactMap { link in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [link.title, link.url, link.area?.name ?? "", link.project?.name ?? ""]) else { return nil }
                return CadenceSearchHit(
                    entityType: "saved_link",
                    entityId: link.id.uuidString,
                    title: resolvedTitle(link.title, fallback: link.url),
                    subtitle: linkContainer(link)?.name ?? "No container",
                    excerpt: excerpt(link.url),
                    score: score
                )
            }
        }

        if selectedScopes.contains("tags") {
            hits += try fetchTags().compactMap { tag in
                guard !tag.isArchived,
                      let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [tag.name, tag.slug, tag.desc]) else { return nil }
                return CadenceSearchHit(
                    entityType: "tag",
                    entityId: tag.id.uuidString,
                    title: resolvedTitle(tag.name, fallback: tag.slug),
                    subtitle: tag.slug,
                    excerpt: excerpt(tag.desc),
                    score: score
                )
            }
        }

        return Array(CadenceSearchMatcher.rank(hits, query: trimmed).prefix(cappedLimit(limit)))
    }

    func recentMCPWrites(limit: Int = 50) throws -> [CadenceMCPAuditEntry] {
        try CadenceMCPAuditLogger.recentEntries(
            limit: limit,
            logURL: CadenceModelContainerFactory.auditLogURL()
        )
    }

    func noteMigrationHealth() throws -> NoteMigrationHealthReport {
        try NoteMigrationService.healthCheck(in: context)
    }

    private func fetchTasks() throws -> [AppTask] {
        try context.fetch(FetchDescriptor<AppTask>())
    }

    private func fetchAreas() throws -> [Area] {
        try context.fetch(FetchDescriptor<Area>())
    }

    private func fetchProjects() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>())
    }

    private func fetchNotes() throws -> [Note] {
        try context.fetch(FetchDescriptor<Note>())
    }

    private func fetchTags() throws -> [Tag] {
        try context.fetch(FetchDescriptor<Tag>())
    }

    private func fetchGoals() throws -> [Goal] {
        try context.fetch(FetchDescriptor<Goal>())
    }

    private func fetchHabits() throws -> [Habit] {
        try context.fetch(FetchDescriptor<Habit>())
    }

    private func fetchLinks() throws -> [SavedLink] {
        try context.fetch(FetchDescriptor<SavedLink>())
    }

    private func fetchTaskBundles() throws -> [TaskBundle] {
        try context.fetch(FetchDescriptor<TaskBundle>())
    }

    private func taskSummary(_ task: AppTask, allTasks: [AppTask]) -> CadenceTaskSummary {
        CadenceTaskSummary(
            id: task.id.uuidString,
            title: resolvedTitle(task.title, fallback: "Untitled Task"),
            status: task.statusRaw,
            priority: task.priorityRaw,
            dueDate: task.dueDate,
            scheduledDate: task.scheduledDate,
            scheduledStartMin: task.scheduledStartMin,
            estimatedMinutes: task.estimatedMinutes,
            container: taskContainer(task),
            goal: task.goal.map(goalRef),
            sectionName: task.resolvedSectionName,
            tags: tagSummaries(task.sortedTags),
            isDone: task.isDone,
            isCancelled: task.isCancelled
        )
    }

    private func taskBundleSummary(_ bundle: TaskBundle) -> CadenceTaskBundleSummary {
        CadenceTaskBundleSummary(
            id: bundle.id.uuidString,
            title: bundle.displayTitle,
            dateKey: bundle.dateKey,
            startMin: bundle.startMin,
            durationMinutes: bundle.durationMinutes,
            endMin: bundle.endMin,
            totalEstimatedMinutes: bundle.totalEstimatedMinutes,
            taskCount: bundle.sortedTasks.count,
            activeTaskCount: bundle.activeTasks.count,
            createdAt: format(bundle.createdAt)
        )
    }

    private func tagDetail(_ tag: Tag) -> CadenceTagDetail {
        CadenceTagDetail(
            summary: tagSummary(tag),
            taskCount: (tag.tasks ?? []).filter { !$0.isCancelled }.count,
            noteCount: (tag.notes ?? []).count,
            createdAt: format(tag.createdAt),
            updatedAt: format(tag.updatedAt)
        )
    }

    private func noteSummary(_ note: Note) -> CadenceNoteSummary {
        CadenceNoteSummary(
            id: note.id.uuidString,
            kind: note.kind.rawValue,
            title: note.displayTitle,
            key: noteKey(note),
            container: documentContainer(note),
            updatedAt: format(note.updatedAt),
            excerpt: excerpt(note.content),
            tags: tagSummaries(note.sortedTags)
        )
    }

    private func goalSummary(_ goal: Goal) -> CadenceGoalSummary {
        CadenceGoalSummary(
            id: goal.id.uuidString,
            title: resolvedTitle(goal.title, fallback: "Untitled Goal"),
            description: goal.desc,
            startDate: goal.startDate,
            endDate: goal.endDate,
            progressType: goal.progressTypeRaw,
            targetHours: goal.targetHours,
            loggedHours: goal.loggedHours,
            colorHex: goal.colorHex,
            status: goal.statusRaw,
            progress: goal.progress,
            contextId: goal.context?.id.uuidString,
            contextName: goal.context?.name,
            parentGoalId: goal.parentGoal?.id.uuidString,
            parentGoalTitle: goal.parentGoal?.title,
            linkedListCount: (goal.listLinks ?? []).filter { $0.area != nil || $0.project != nil }.count,
            taskCount: (goal.tasks ?? []).filter { !$0.isCancelled }.count,
            habitCount: (goal.habits ?? []).count,
            createdAt: format(goal.createdAt)
        )
    }

    private func habitSummary(_ habit: Habit) -> CadenceHabitSummary {
        let today = DateFormatters.todayKey()
        return CadenceHabitSummary(
            id: habit.id.uuidString,
            title: resolvedTitle(habit.title, fallback: "Untitled Habit"),
            icon: habit.icon,
            colorHex: habit.colorHex,
            frequencyType: habit.frequencyTypeRaw,
            frequencyDays: habit.frequencyDays,
            targetCount: habit.targetCount,
            order: habit.order,
            contextId: habit.context?.id.uuidString,
            contextName: habit.context?.name,
            goal: habit.goal.map(goalRef),
            currentStreak: habit.currentStreak,
            completionCount: (habit.completions ?? []).count,
            completedToday: (habit.completions ?? []).contains { $0.date == today },
            createdAt: format(habit.createdAt)
        )
    }

    private func linkSummary(_ link: SavedLink) -> CadenceSavedLinkSummary {
        CadenceSavedLinkSummary(
            id: link.id.uuidString,
            title: resolvedTitle(link.title, fallback: link.url),
            url: link.url,
            container: linkContainer(link),
            order: link.order,
            createdAt: format(link.createdAt)
        )
    }

    private func linkContainer(_ link: SavedLink) -> CadenceContainerRef? {
        if let area = link.area {
            return containerRef(area)
        }
        if let project = link.project {
            return containerRef(project)
        }
        return nil
    }

    private func taskContainer(_ task: AppTask) -> CadenceContainerRef? {
        if let area = task.area {
            return containerRef(area)
        }
        if let project = task.project {
            return containerRef(project)
        }
        return nil
    }

    private func documentContainer(_ doc: Note) -> CadenceContainerRef? {
        if let area = doc.area {
            return containerRef(area)
        }
        if let project = doc.project {
            return containerRef(project)
        }
        return nil
    }

    private func containerRef(_ area: Area) -> CadenceContainerRef {
        CadenceContainerRef(
            kind: "area",
            id: area.id.uuidString,
            name: area.name,
            contextId: area.context?.id.uuidString,
            contextName: area.context?.name,
            status: area.statusRaw,
            colorHex: area.colorHex,
            icon: area.icon
        )
    }

    private func containerRef(_ project: Project) -> CadenceContainerRef {
        CadenceContainerRef(
            kind: "project",
            id: project.id.uuidString,
            name: project.name,
            contextId: project.context?.id.uuidString,
            contextName: project.context?.name,
            status: project.statusRaw,
            colorHex: project.colorHex,
            icon: project.icon
        )
    }

    private func containerRef(kind: String, id: UUID) throws -> CadenceContainerRef {
        switch kind.lowercased() {
        case "area":
            guard let area = try fetchAreas().first(where: { $0.id == id }) else {
                throw CadenceReadError.containerNotFound(kind, id.uuidString)
            }
            return containerRef(area)
        case "project":
            guard let project = try fetchProjects().first(where: { $0.id == id }) else {
                throw CadenceReadError.containerNotFound(kind, id.uuidString)
            }
            return containerRef(project)
        default:
            throw CadenceReadError.invalidContainerKind(kind)
        }
    }

    private func goalRef(_ goal: Goal) -> CadenceGoalRef {
        CadenceGoalRef(
            id: goal.id.uuidString,
            title: goal.title,
            status: goal.statusRaw,
            progress: goal.progress
        )
    }

    private func documentSummary(_ doc: Note) -> CadenceDocumentSummary {
        CadenceDocumentSummary(
            id: doc.id.uuidString,
            title: doc.displayTitle,
            container: documentContainer(doc),
            updatedAt: format(doc.updatedAt),
            excerpt: excerpt(doc.content),
            tags: tagSummaries(doc.sortedTags)
        )
    }

    private func notePayload(_ note: Note, key: String?) -> CadenceNotePayload {
        CadenceNotePayload(id: note.id.uuidString, kind: note.kind.rawValue, key: key, content: note.content, updatedAt: format(note.updatedAt), excerpt: excerpt(note.content), tags: tagSummaries(note.sortedTags))
    }

    private func tagSummaries(_ tags: [Tag]) -> [CadenceTagSummary] {
        tags.map(tagSummary)
    }

    private func tagSummary(_ tag: Tag) -> CadenceTagSummary {
        CadenceTagSummary(
            id: tag.id.uuidString,
            slug: tag.slug,
            name: tag.name,
            colorHex: tag.colorHex,
            description: tag.desc,
            isArchived: tag.isArchived
        )
    }

    private func notesForContainer(kind: String, id: UUID) throws -> [Note] {
        switch try normalizeContainerKind(kind) {
        case "area":
            return try fetchNotes().filter { $0.kind == .list && $0.area?.id == id }
        case "project":
            return try fetchNotes().filter { $0.kind == .list && $0.project?.id == id }
        default:
            throw CadenceReadError.invalidContainerKind(kind)
        }
    }

    private func filterNotes(_ notes: [Note], containerKind: String, containerID: UUID) throws -> [Note] {
        switch try normalizeContainerKind(containerKind) {
        case "area":
            return notes.filter { $0.area?.id == containerID }
        case "project":
            return notes.filter { $0.project?.id == containerID }
        default:
            throw CadenceReadError.invalidContainerKind(containerKind)
        }
    }

    private func linksForContainer(kind: String, id: UUID) throws -> [SavedLink] {
        switch try normalizeContainerKind(kind) {
        case "area":
            return try fetchLinks().filter { $0.area?.id == id }
        case "project":
            return try fetchLinks().filter { $0.project?.id == id }
        default:
            throw CadenceReadError.invalidContainerKind(kind)
        }
    }

    private func filterLinks(_ links: [SavedLink], containerKind: String, containerID: UUID) throws -> [SavedLink] {
        switch try normalizeContainerKind(containerKind) {
        case "area":
            return links.filter { $0.area?.id == containerID }
        case "project":
            return links.filter { $0.project?.id == containerID }
        default:
            throw CadenceReadError.invalidContainerKind(containerKind)
        }
    }

    private func sectionSummaries(kind: String, id: UUID, tasks: [AppTask]) throws -> [CadenceSectionSummary] {
        let configuredSections: [TaskSectionConfig]
        switch try normalizeContainerKind(kind) {
        case "area":
            guard let area = try fetchAreas().first(where: { $0.id == id }) else {
                throw CadenceReadError.containerNotFound(kind, id.uuidString)
            }
            configuredSections = area.sectionConfigs
        case "project":
            guard let project = try fetchProjects().first(where: { $0.id == id }) else {
                throw CadenceReadError.containerNotFound(kind, id.uuidString)
            }
            configuredSections = project.sectionConfigs
        default:
            throw CadenceReadError.invalidContainerKind(kind)
        }

        let sectionNames = Set(configuredSections.map { $0.name.lowercased() })
        let extraSections = Set(tasks.map(\.resolvedSectionName).filter { !sectionNames.contains($0.lowercased()) })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { TaskSectionConfig(name: $0) }

        return (configuredSections + extraSections).map { config in
            let sectionTasks = tasks.filter { $0.resolvedSectionName.caseInsensitiveCompare(config.name) == .orderedSame }
            return CadenceSectionSummary(
                name: config.name,
                colorHex: config.colorHex,
                dueDate: config.dueDate,
                isCompleted: config.isCompleted,
                isArchived: config.isArchived,
                taskCount: sectionTasks.count,
                activeTaskCount: sectionTasks.filter { !$0.isDone && !$0.isCancelled }.count,
                completedTaskCount: sectionTasks.filter(\.isDone).count
            )
        }
    }

    private func noteEntityType(_ note: Note) -> String {
        switch note.kind {
        case .daily: return "daily_note"
        case .weekly: return "weekly_note"
        case .permanent: return "permanent_note"
        case .list: return "document"
        case .meeting: return "event_note"
        }
    }

    private func noteKey(_ note: Note) -> String? {
        switch note.kind {
        case .daily:
            return note.dateKey.isEmpty ? nil : note.dateKey
        case .weekly:
            return note.weekKey.isEmpty ? nil : note.weekKey
        case .permanent:
            return nil
        case .list:
            return nil
        case .meeting:
            return note.eventDateKey.isEmpty ? nil : note.eventDateKey
        }
    }

    private func noteSubtitle(_ note: Note) -> String {
        switch note.kind {
        case .daily: return "Daily note"
        case .weekly: return "Weekly note"
        case .permanent: return "Permanent note"
        case .list: return documentContainer(note)?.name ?? "No container"
        case .meeting: return "Meeting note"
        }
    }

    private func filterTasks(_ tasks: [AppTask], containerKind: String, containerID: UUID) throws -> [AppTask] {
        switch try normalizeContainerKind(containerKind) {
        case "area":
            return tasks.filter { $0.area?.id == containerID }
        case "project":
            return tasks.filter { $0.project?.id == containerID }
        default:
            throw CadenceReadError.invalidContainerKind(containerKind)
        }
    }

    private func taskSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
        if lhs.scheduledDate != rhs.scheduledDate { return lhs.scheduledDate < rhs.scheduledDate }
        if lhs.scheduledStartMin != rhs.scheduledStartMin { return lhs.scheduledStartMin < rhs.scheduledStartMin }
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.createdAt > rhs.createdAt
    }

    private func resolvedDateKey(_ dateKey: String?) throws -> String {
        try CadenceMCPServiceSupport.resolvedDateKey(dateKey)
    }

    private func weekKey(for dateKey: String) throws -> String {
        try CadenceMCPServiceSupport.weekKey(for: dateKey)
    }

    private func parsedDate(_ dateKey: String) throws -> Date {
        try CadenceMCPServiceSupport.parsedDate(dateKey)
    }

    private func uuid(from id: String) throws -> UUID {
        try CadenceMCPServiceSupport.uuid(from: id)
    }

    private func normalizeContainerKind(_ value: String) throws -> String {
        try CadenceMCPServiceSupport.normalizeContainerKind(value)
    }

    private func resolvedContainerFilter(kind: String?, id: String?) throws -> (kind: String, id: UUID)? {
        try CadenceMCPServiceSupport.resolvedContainerFilter(kind: kind, id: id)
    }

    private func validateTaskStatuses(_ statuses: [String]) throws -> Set<String> {
        let valid = Set(TaskStatus.allCases.map(\.rawValue))
        return try Set(statuses.map { status in
            let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard valid.contains(normalized) else {
                throw CadenceReadError.invalidStatus(status)
            }
            return normalized
        })
    }

    private func validateContainerStatus(_ status: String, kind: String?) throws -> String {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let valid: Set<String>
        switch kind {
        case "area":
            valid = Set(AreaStatus.allCases.map(\.rawValue))
        case "project":
            valid = Set(ProjectStatus.allCases.map(\.rawValue))
        default:
            valid = Set(AreaStatus.allCases.map(\.rawValue)).union(ProjectStatus.allCases.map(\.rawValue))
        }
        guard valid.contains(normalized) else {
            throw CadenceReadError.invalidStatus(status)
        }
        return normalized
    }

    private func validateGoalStatus(_ status: String) throws -> String {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let valid = Set(GoalStatus.allCases.map(\.rawValue))
        guard valid.contains(normalized) else {
            throw CadenceReadError.invalidStatus(status)
        }
        return normalized
    }

    private func validateNoteKind(_ kind: String) throws -> String {
        let normalized = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard NoteKind(rawValue: normalized) != nil else {
            throw CadenceReadError.invalidNoteKind(kind)
        }
        return normalized
    }

    private func validateScopes(_ scopes: [String]) throws -> Set<String> {
        let valid = Set(["tasks", "containers", "documents", "notes", "core_notes", "event_notes", "goals", "habits", "links", "tags"])
        return try Set(scopes.map { scope in
            let normalized = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard valid.contains(normalized) else {
                throw CadenceReadError.invalidScope(scope)
            }
            return normalized
        })
    }

    private func cappedLimit(_ limit: Int) -> Int {
        CadenceMCPServiceSupport.cappedLimit(limit)
    }

    private func format(_ date: Date) -> String {
        encoderDateFormatter.string(from: date)
    }

    private func excerpt(_ text: String, maxLength: Int = 240) -> String {
        CadenceMCPServiceSupport.excerpt(text, maxLength: maxLength)
    }

    private func resolvedTitle(_ value: String, fallback: String) -> String {
        CadenceMCPServiceSupport.resolvedTitle(value, fallback: fallback)
    }
}
