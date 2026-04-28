import Foundation
import SwiftData

enum CadenceReadError: Error, LocalizedError, Sendable {
    case storeNotFound([String])
    case invalidDate(String)
    case invalidIdentifier(String)
    case invalidContainerKind(String)
    case invalidStatus(String)
    case invalidScope(String)
    case incompleteContainerFilter
    case taskNotFound(String)
    case containerNotFound(String, String)
    case documentNotFound(String)

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
            return "Invalid search scope: \(value). Expected tasks, containers, documents, core_notes, or event_notes."
        case .incompleteContainerFilter:
            return "containerKind and containerId must be provided together."
        case .taskNotFound(let value):
            return "No task found with id \(value)."
        case .containerNotFound(let kind, let id):
            return "No \(kind) found with id \(id)."
        case .documentNotFound(let value):
            return "No document found with id \(value)."
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
    var limit: Int = 50
}

@MainActor
final class CadenceReadService {
    private let context: ModelContext
    private let encoderDateFormatter = ISO8601DateFormatter()

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    init(context: ModelContext) {
        self.context = context
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
            .filter { $0.area == nil && $0.project == nil && $0.goal == nil }
            .sorted(by: taskSort)
            .prefix(50)
            .map { taskSummary($0, allTasks: tasks) }

        let blocked = blockedTasks(from: activeTasks, allTasks: tasks, limit: 50)
        let notes = try coreNotes(dateKey: resolvedDateKey)
        let noteSnippets = [notes.dailyNote, notes.weeklyNote, notes.permanentNote].compactMap { $0 }

        return CadenceTodayBrief(
            dateKey: resolvedDateKey,
            scheduledTasks: scheduled,
            dueToday: dueToday,
            overdue: overdue,
            inbox: Array(inbox),
            blockedTasks: blocked,
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

        if let query = options.textQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            filtered = filtered.filter { task in
                CadenceSearchMatcher.matchScore(
                    query: query,
                    fields: [
                        task.title,
                        task.notes,
                        task.project?.name ?? "",
                        task.area?.name ?? "",
                        task.goal?.title ?? "",
                        task.context?.name ?? "",
                        task.resolvedSectionName,
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
            dependencyTaskIds: task.dependencyTaskIDs.map(\.uuidString),
            subtasks: subtasks,
            createdAt: format(task.createdAt),
            completedAt: task.completedAt.map(format)
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
        let allTasks = tasks
        let active = containerTasks.filter { !$0.isDone && !$0.isCancelled }
        let today = DateFormatters.todayKey()
        let overdue = active.filter { !$0.dueDate.isEmpty && $0.dueDate < today }
        let blocked = active.filter { $0.isBlocked(in: allTasks) }
        let documents = try documentsForContainer(kind: kind, id: uuid)
            .sorted { $0.order < $1.order }
            .map(documentSummary)

        return CadenceContainerSummary(
            container: try containerRef(kind: kind, id: uuid),
            activeTaskCount: active.count,
            completedTaskCount: containerTasks.filter(\.isDone).count,
            overdueTaskCount: overdue.count,
            blockedTaskCount: blocked.count,
            documents: documents
        )
    }

    func coreNotes(dateKey: String? = nil) throws -> CadenceCoreNotesSnapshot {
        let resolvedDateKey = try resolvedDateKey(dateKey)
        let resolvedWeekKey = try weekKey(for: resolvedDateKey)

        let daily = try fetchDailyNotes().first { $0.date == resolvedDateKey }
        let weekly = try fetchWeeklyNotes().first { $0.weekKey == resolvedWeekKey }
        let permanent = try fetchPermNotes().first

        return CadenceCoreNotesSnapshot(
            dateKey: resolvedDateKey,
            weekKey: resolvedWeekKey,
            dailyNote: daily.map { notePayload($0) },
            weeklyNote: weekly.map { notePayload($0) },
            permanentNote: permanent.map { notePayload($0) }
        )
    }

    func listDocuments(containerKind: String? = nil, containerID: String? = nil, query: String? = nil, limit: Int = 50) throws -> [CadenceDocumentSummary] {
        var docs = try fetchDocuments()

        if let containerFilter = try resolvedContainerFilter(kind: containerKind, id: containerID) {
            docs = try documentsForContainer(kind: containerFilter.kind, id: containerFilter.id)
        }

        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            docs = docs.filter { doc in
                CadenceSearchMatcher.matchScore(query: query, fields: [doc.title, doc.content, doc.area?.name ?? "", doc.project?.name ?? ""]) != nil
            }
        }

        return docs
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(cappedLimit(limit))
            .map(documentSummary)
    }

    func getDocument(documentID: String) throws -> CadenceDocumentDetail {
        let id = try uuid(from: documentID)
        guard let doc = try fetchDocuments().first(where: { $0.id == id }) else {
            throw CadenceReadError.documentNotFound(documentID)
        }

        return CadenceDocumentDetail(
            id: doc.id.uuidString,
            title: resolvedTitle(doc.title, fallback: "Untitled"),
            container: documentContainer(doc),
            content: doc.content,
            order: doc.order,
            createdAt: format(doc.createdAt),
            updatedAt: format(doc.updatedAt)
        )
    }

    func search(query: String, scopes: [String]? = nil, limit: Int = 50) throws -> [CadenceSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let selectedScopes = try validateScopes(scopes ?? ["tasks", "containers", "documents", "core_notes", "event_notes"])
        var hits: [CadenceSearchHit] = []

        if selectedScopes.contains("tasks") {
            let tasks = try fetchTasks()
            hits += tasks.compactMap { task in
                let fields = [task.title, task.notes, task.area?.name ?? "", task.project?.name ?? "", task.goal?.title ?? "", task.context?.name ?? ""]
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: fields) else { return nil }
                return CadenceSearchHit(
                    entityType: "task",
                    entityId: task.id.uuidString,
                    title: resolvedTitle(task.title, fallback: "Untitled Task"),
                    subtitle: [task.project?.name ?? task.area?.name ?? task.goal?.title ?? "Inbox", task.statusRaw].joined(separator: " - "),
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
            hits += try fetchDocuments().compactMap { doc in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [doc.title, doc.content, doc.area?.name ?? "", doc.project?.name ?? ""]) else { return nil }
                return CadenceSearchHit(entityType: "document", entityId: doc.id.uuidString, title: resolvedTitle(doc.title, fallback: "Untitled"), subtitle: documentContainer(doc)?.name ?? "No container", excerpt: excerpt(doc.content), score: score)
            }
        }

        if selectedScopes.contains("core_notes") {
            hits += try fetchDailyNotes().compactMap { note in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [note.date, note.content]) else { return nil }
                return CadenceSearchHit(entityType: "daily_note", entityId: note.id.uuidString, title: note.date, subtitle: "Daily note", excerpt: excerpt(note.content), score: score)
            }
            hits += try fetchWeeklyNotes().compactMap { note in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [note.weekKey, note.content]) else { return nil }
                return CadenceSearchHit(entityType: "weekly_note", entityId: note.id.uuidString, title: note.weekKey, subtitle: "Weekly note", excerpt: excerpt(note.content), score: score)
            }
            hits += try fetchPermNotes().compactMap { note in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: ["notepad permanent note", note.content]) else { return nil }
                return CadenceSearchHit(entityType: "permanent_note", entityId: note.id.uuidString, title: "Notepad", subtitle: "Permanent note", excerpt: excerpt(note.content), score: score)
            }
        }

        if selectedScopes.contains("event_notes") {
            hits += try fetchEventNotes().compactMap { note in
                let title = resolvedTitle(note.title, fallback: "Event Note")
                let fields = [title, note.content, note.eventDateKey]
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

        return Array(CadenceSearchMatcher.rank(hits, query: trimmed).prefix(cappedLimit(limit)))
    }

    func blockedTasks(containerKind: String? = nil, containerID: String? = nil, limit: Int = 50) throws -> [CadenceBlockedTask] {
        let tasks = try fetchTasks()
        var candidates = tasks.filter { !$0.isDone && !$0.isCancelled }
        if let containerFilter = try resolvedContainerFilter(kind: containerKind, id: containerID) {
            candidates = try filterTasks(candidates, containerKind: containerFilter.kind, containerID: containerFilter.id)
        }
        return Array(blockedTasks(from: candidates, allTasks: tasks, limit: cappedLimit(limit)).prefix(cappedLimit(limit)))
    }

    private func blockedTasks(from candidates: [AppTask], allTasks: [AppTask], limit: Int) -> [CadenceBlockedTask] {
        candidates
            .filter { $0.isBlocked(in: allTasks) }
            .sorted(by: taskSort)
            .prefix(limit)
            .map { task in
                CadenceBlockedTask(
                    task: taskSummary(task, allTasks: allTasks),
                    unresolvedDependencies: task.unresolvedDependencies(in: allTasks).map { taskSummary($0, allTasks: allTasks) }
                )
            }
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

    private func fetchDocuments() throws -> [Document] {
        try context.fetch(FetchDescriptor<Document>())
    }

    private func fetchDailyNotes() throws -> [DailyNote] {
        try context.fetch(FetchDescriptor<DailyNote>())
    }

    private func fetchWeeklyNotes() throws -> [WeeklyNote] {
        try context.fetch(FetchDescriptor<WeeklyNote>())
    }

    private func fetchPermNotes() throws -> [PermNote] {
        try context.fetch(FetchDescriptor<PermNote>())
    }

    private func fetchEventNotes() throws -> [EventNote] {
        try context.fetch(FetchDescriptor<EventNote>())
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
            isBlocked: task.isBlocked(in: allTasks),
            isDone: task.isDone,
            isCancelled: task.isCancelled
        )
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

    private func documentContainer(_ doc: Document) -> CadenceContainerRef? {
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

    private func documentSummary(_ doc: Document) -> CadenceDocumentSummary {
        CadenceDocumentSummary(
            id: doc.id.uuidString,
            title: resolvedTitle(doc.title, fallback: "Untitled"),
            container: documentContainer(doc),
            updatedAt: format(doc.updatedAt),
            excerpt: excerpt(doc.content)
        )
    }

    private func notePayload(_ note: DailyNote) -> CadenceNotePayload {
        CadenceNotePayload(id: note.id.uuidString, kind: "daily", key: note.date, content: note.content, updatedAt: format(note.updatedAt), excerpt: excerpt(note.content))
    }

    private func notePayload(_ note: WeeklyNote) -> CadenceNotePayload {
        CadenceNotePayload(id: note.id.uuidString, kind: "weekly", key: note.weekKey, content: note.content, updatedAt: format(note.updatedAt), excerpt: excerpt(note.content))
    }

    private func notePayload(_ note: PermNote) -> CadenceNotePayload {
        CadenceNotePayload(id: note.id.uuidString, kind: "permanent", key: nil, content: note.content, updatedAt: format(note.updatedAt), excerpt: excerpt(note.content))
    }

    private func documentsForContainer(kind: String, id: UUID) throws -> [Document] {
        switch try normalizeContainerKind(kind) {
        case "area":
            return try fetchDocuments().filter { $0.area?.id == id }
        case "project":
            return try fetchDocuments().filter { $0.project?.id == id }
        default:
            throw CadenceReadError.invalidContainerKind(kind)
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
        guard let dateKey, !dateKey.isEmpty else { return DateFormatters.todayKey() }
        _ = try parsedDate(dateKey)
        return dateKey
    }

    private func weekKey(for dateKey: String) throws -> String {
        DateFormatters.weekKey(from: try parsedDate(dateKey))
    }

    private func parsedDate(_ dateKey: String) throws -> Date {
        guard let date = DateFormatters.date(from: dateKey) else {
            throw CadenceReadError.invalidDate(dateKey)
        }
        return date
    }

    private func uuid(from id: String) throws -> UUID {
        guard let uuid = UUID(uuidString: id) else {
            throw CadenceReadError.invalidIdentifier(id)
        }
        return uuid
    }

    private func normalizeContainerKind(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "area" || normalized == "project" else {
            throw CadenceReadError.invalidContainerKind(value)
        }
        return normalized
    }

    private func resolvedContainerFilter(kind: String?, id: String?) throws -> (kind: String, id: UUID)? {
        let normalizedKind = kind?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (normalizedKind?.isEmpty == false ? normalizedKind : nil, normalizedID?.isEmpty == false ? normalizedID : nil) {
        case (.none, .none):
            return nil
        case (.some(let kind), .some(let id)):
            return (try normalizeContainerKind(kind), try uuid(from: id))
        default:
            throw CadenceReadError.incompleteContainerFilter
        }
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

    private func validateScopes(_ scopes: [String]) throws -> Set<String> {
        let valid = Set(["tasks", "containers", "documents", "core_notes", "event_notes"])
        return try Set(scopes.map { scope in
            let normalized = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard valid.contains(normalized) else {
                throw CadenceReadError.invalidScope(scope)
            }
            return normalized
        })
    }

    private func cappedLimit(_ limit: Int) -> Int {
        min(max(limit, 0), 200)
    }

    private func format(_ date: Date) -> String {
        encoderDateFormatter.string(from: date)
    }

    private func excerpt(_ text: String, maxLength: Int = 240) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedTitle(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
