import Foundation
import SwiftData

nonisolated enum CadenceReadError: Error, LocalizedError, Sendable {
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
    case contextNotFound(String)
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
            return "Invalid search scope: \(value). Expected tasks, containers, contexts, documents, notes, core_notes, event_notes, goals, habits, links, or tags."
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
        case .contextNotFound(let value):
            return "No context found with id \(value)."
        case .noteNotFound(let value):
            return "No note found with id \(value)."
        case .documentNotFound(let value):
            return "No document found with id \(value)."
        case .goalNotFound(let value):
            return "No goal found with id \(value)."
        }
    }
}

nonisolated struct CadenceTaskListOptions: Sendable {
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
    var offset: Int = 0
}

nonisolated struct CadenceNoteListOptions: Sendable {
    var kind: String? = nil
    var containerKind: String? = nil
    var containerId: String? = nil
    var query: String? = nil
    var tagSlugs: [String]? = nil
    var limit: Int = 50
    var offset: Int = 0
}

nonisolated struct CadenceGoalListOptions: Sendable {
    var status: String? = nil
    var contextId: String? = nil
    var query: String? = nil
    var limit: Int = 50
    var offset: Int = 0
}

nonisolated struct CadenceHabitListOptions: Sendable {
    var contextId: String? = nil
    var goalId: String? = nil
    var query: String? = nil
    var limit: Int = 50
    var offset: Int = 0
}

nonisolated struct CadenceSavedLinkListOptions: Sendable {
    var containerKind: String? = nil
    var containerId: String? = nil
    var query: String? = nil
    var limit: Int = 50
    var offset: Int = 0
}

nonisolated struct CadenceTaskBundleListOptions: Sendable {
    var dateKey: String? = nil
    var limit: Int = 50
    var offset: Int = 0
}

@MainActor
final class CadenceReadService {
    private let context: ModelContext
    private let encoderDateFormatter = ISO8601DateFormatter()

    /// Startup steps executed by *this* instance. `0` when the caller said the store was already
    /// prepared. T-309 is a counting bug, so it is asserted as a count.
    private(set) var executedStartupStepCount = 0

    /// Rows this service has materialised out of the store since it was created, through explicit
    /// fetch descriptors. Relationship traversals are not counted — they are edges from a row that
    /// is already in memory, which is the thing being switched *to*.
    ///
    /// **T-384 exists because nothing could see this number.** `limit` capped the response while
    /// every read ran `context.fetch(FetchDescriptor<Model>())` — the whole table — and then
    /// filtered, sorted and sliced in memory, so `list_tasks(limit: 1)` and `list_tasks(limit:
    /// 5000)` did identical work and no test could tell them apart. Diagnostic only: nothing in a
    /// response is derived from it and no behaviour branches on it.
    private(set) var fetchedRowCount = 0

    init(container: ModelContainer, performsMigrations: Bool = true) {
        context = ModelContext(container)
        if performsMigrations {
            executedStartupStepCount = CadenceMCPStorePreparation.migrateNotes(
                in: context,
                source: "mcp-read-service-container"
            )
        }
    }

    init(context: ModelContext, performsMigrations: Bool = true) {
        self.context = context
        if performsMigrations {
            executedStartupStepCount = CadenceMCPStorePreparation.migrateNotes(
                in: context,
                source: "mcp-read-service-context"
            )
        }
    }

    /// The dashboard summary for a date, with every task section paged.
    ///
    /// **All four sections go through the same slice, which is the fix (T-385).** The inbox alone
    /// used to end in `.prefix(50)` while its three siblings were unbounded, so the one cap in the
    /// response was both undisclosed and inconsistent with the rest of it. Sharing one
    /// `CadencePage.paging` call means no section can acquire a private cap without the envelope
    /// reporting it: whatever is cut, `totalCount` still names the whole section.
    ///
    /// `limit` and `offset` apply to each section separately but identically — see
    /// `CadenceTodayBrief`.
    func todayBrief(dateKey: String? = nil, limit: Int = 50, offset: Int = 0) throws -> CadenceTodayBrief {
        let resolvedDateKey = try resolvedDateKey(dateKey)
        // Active-only at the store (T-384). Every section below is a subset of it, and the whole
        // table was being read only to satisfy `taskSummary`'s dead `allTasks:` parameter — with
        // that gone, nothing here wanted the finished work. The paging is untouched.
        let done = Self.doneStatusRaw
        let cancelled = Self.cancelledStatusRaw
        let activeTasks = try fetchAll(
            AppTask.self,
            where: #Predicate { $0.statusRaw != done && $0.statusRaw != cancelled }
        )

        func section(_ isIncluded: (AppTask) -> Bool) -> CadencePage<CadenceTaskSummary> {
            CadencePage.paging(
                activeTasks.filter(isIncluded).sorted(by: taskSort),
                offset: offset,
                limit: limit
            ) { taskSummary($0) }
        }

        let scheduled = section { $0.scheduledDate == resolvedDateKey && $0.scheduledStartMin >= 0 }
        let dueToday = section { $0.dueDate == resolvedDateKey }
        let overdue = section { !$0.dueDate.isEmpty && $0.dueDate < resolvedDateKey }
        let inbox = section { $0.area == nil && $0.project == nil }

        let notes = try coreNotes(dateKey: resolvedDateKey)
        let noteSnippets = [notes.dailyNote, notes.weeklyNote, notes.permanentNote].compactMap { $0 }

        return CadenceTodayBrief(
            dateKey: resolvedDateKey,
            scheduledTasks: scheduled,
            dueToday: dueToday,
            overdue: overdue,
            inbox: inbox,
            noteSnippets: noteSnippets
        )
    }

    /// **The candidate set is chosen before anything is filtered (T-384).**
    ///
    /// This used to open with `fetchTasks()` — every row in the store, unconditionally — and then
    /// run seven `filter`s, a sort and a slice over the result, so `list_tasks(limit: 1)` did the
    /// same work as `list_tasks(limit: 5000)`. Two things now happen at the store instead: a named
    /// container answers from its own `tasks` edge, and everything else fetches under a status
    /// predicate.
    ///
    /// **What deliberately stays in memory.** The explicit `statuses` filter, because it compares
    /// `statusRaw.lowercased()` and SwiftData's predicate grammar has no `lowercased()` — pushing
    /// it down would silently change which rows a mixed-case stored value matches. Tag membership
    /// and `textQuery` scoring, because both are `CadenceSearchMatcher` work over related rows.
    /// And the sort: `taskSort` ends on `id.uuidString`, which no `SortDescriptor` can express, so
    /// the ordering — and therefore the offset/limit slice — cannot move to the store without
    /// giving up the total order T-372 established ([[T-415]]). Narrowing the candidate set is the
    /// part that was available; slicing at the store is not, and claiming otherwise would be worse
    /// than leaving it.
    func listTasks(options: CadenceTaskListOptions) throws -> CadencePage<CadenceTaskSummary> {
        let cancelled = Self.cancelledStatusRaw
        let done = Self.doneStatusRaw
        // `isCancelled` is `statusRaw == "cancelled"` exactly — `TaskStatus(rawValue:)` does not
        // fold case — so this predicate keeps precisely the rows the old `filter` kept.
        let excludesDone = (options.statuses?.isEmpty ?? true) && !options.includeCompleted
        let statusPredicate: Predicate<AppTask> = excludesDone
            ? #Predicate { $0.statusRaw != cancelled && $0.statusRaw != done }
            : #Predicate { $0.statusRaw != cancelled }

        // Normalized rather than parsed-and-discarded: these three filters compare the caller's
        // string against stored keys, so a lenient spelling like `"2026-8-20"` used to validate and
        // then quietly match nothing at all (`>=`, `<=` and `==` all read it as a different day).
        let dueDateFrom = try normalizedDateKey(options.dueDateFrom)
        let dueDateTo = try normalizedDateKey(options.dueDateTo)
        let scheduledDate = try normalizedDateKey(options.scheduledDate)
        let containerFilter = try resolvedContainerFilter(kind: options.containerKind, id: options.containerId)

        var filtered: [AppTask]
        if let containerFilter {
            // One `Area`/`Project` row plus its `tasks` edge. An unknown id yields an empty page,
            // which is what the whole-table filter produced too.
            filtered = try containerModel(kind: containerFilter.kind, id: containerFilter.id)?.tasks ?? []
            filtered = filtered.filter { !$0.isCancelled }
            if excludesDone {
                filtered = filtered.filter { !$0.isDone }
            }
        } else {
            filtered = try fetchAll(AppTask.self, where: statusPredicate)
        }

        if let statuses = options.statuses, !statuses.isEmpty {
            let allowed = try validateTaskStatuses(statuses)
            filtered = filtered.filter { allowed.contains($0.statusRaw.lowercased()) }
        }

        if let dueDateFrom {
            filtered = filtered.filter { !$0.dueDate.isEmpty && $0.dueDate >= dueDateFrom }
        }

        if let dueDateTo {
            filtered = filtered.filter { !$0.dueDate.isEmpty && $0.dueDate <= dueDateTo }
        }

        if let scheduledDate {
            filtered = filtered.filter { $0.scheduledDate == scheduledDate }
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

        return CadencePage.paging(
            filtered.sorted(by: taskSort),
            offset: options.offset,
            limit: options.limit
        ) { taskSummary($0) }
    }

    func getTask(taskID: String) throws -> CadenceTaskDetail {
        let id = try uuid(from: taskID)
        guard let task = try fetchFirst(AppTask.self, where: #Predicate { $0.id == id }) else {
            throw CadenceReadError.taskNotFound(taskID)
        }

        let subtasks = (task.subtasks ?? [])
            .sorted(by: CadenceMCPOrdering.precedes)
            .map {
                CadenceSubtaskSummary(
                    id: $0.id.uuidString,
                    title: $0.title,
                    isDone: $0.isDone,
                    order: $0.order
                )
            }

        return CadenceTaskDetail(
            summary: taskSummary(task),
            notes: task.notes,
            actualMinutes: task.actualMinutes,
            subtasks: subtasks,
            createdAt: format(task.createdAt),
            completedAt: task.completedAt.map(format)
        )
    }

    func listTaskBundles(options: CadenceTaskBundleListOptions) throws -> CadencePage<CadenceTaskBundleSummary> {
        let dateKey = try normalizedDateKey(options.dateKey)
        let bundles = try fetchAll(
            TaskBundle.self,
            where: dateKey.map { key in #Predicate<TaskBundle> { $0.dateKey == key } }
        )

        let ordered = bundles.sorted {
            if $0.dateKey != $1.dateKey { return $0.dateKey < $1.dateKey }
            if $0.startMin != $1.startMin { return $0.startMin < $1.startMin }
            let titles = $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle)
            if titles != .orderedSame { return titles == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
        return CadencePage.paging(ordered, offset: options.offset, limit: options.limit, transform: taskBundleSummary)
    }

    func getTaskBundle(bundleID: String) throws -> CadenceTaskBundleDetail {
        let id = try uuid(from: bundleID)
        guard let bundle = try fetchFirst(TaskBundle.self, where: #Predicate { $0.id == id }) else {
            throw CadenceReadError.taskBundleNotFound(bundleID)
        }
        return CadenceTaskBundleDetail(
            summary: taskBundleSummary(bundle),
            tasks: bundle.sortedTasks.map { taskSummary($0) }
        )
    }

    /// Areas and projects as **one** ordered sequence, not two concatenated ones (T-383).
    ///
    /// This used to sort each kind separately, append projects behind areas, and only then apply
    /// `prefix(cappedLimit(limit))`. With more areas than the limit that cut every project — the
    /// caller asked for containers and got a page that could not contain one, with nothing in the
    /// response saying so. [[T-372]] made it worse in the only way determinism can: before it, the
    /// order was unstable and *which* rows you lost varied between reads; after it, you lose all
    /// projects, every time.
    ///
    /// Merging rather than requiring `kind` or returning per-kind buckets, because merging is the
    /// option that keeps T-372's total order meaningful. `CadenceMCPOrdering.precedes` is already
    /// defined over `SortKey`, not over `Area` or `Project`, and it ends on `id` — so it is
    /// *already* a total order across both kinds and needs no new rule to merge them. Buckets would
    /// need two offsets and two `hasMore` flags for one `limit`; requiring `kind` would turn the
    /// default 50-row call into an error. One ordered list is the only shape `CadencePage`'s single
    /// `offset` can page honestly.
    ///
    /// Kind-filtered calls are unchanged. The unfiltered call now interleaves the two kinds by
    /// `order`/name/id instead of listing all areas first; that ordering change is the fix, not a
    /// side effect of it.
    func listContainers(kind: String? = nil, status: String? = nil, contextID: String? = nil, limit: Int = 50, offset: Int = 0) throws -> CadencePage<CadenceContainerRef> {
        let contextUUID = try contextID.map(uuid)
        let normalizedKind = try kind.map(normalizeContainerKind)
        let normalizedStatus = try status.map { try validateContainerStatus($0, kind: normalizedKind) }

        // A named context answers from its own `areas` / `projects` edges; otherwise the status
        // filter — a plain string comparison — goes to the store as a predicate (T-384). An
        // unknown context id yields no rows, matching the filter this replaces.
        let scopedContext = try contextUUID.flatMap { try contextModel($0) }
        let scopedToContext = contextUUID != nil

        var candidates: [(key: CadenceMCPOrdering.SortKey, container: CadenceResolvedContainer)] = []
        if normalizedKind == nil || normalizedKind == "area" {
            let areas: [Area] = scopedToContext
                ? (scopedContext?.areas ?? [])
                : try fetchAll(Area.self, where: normalizedStatus.map { s in #Predicate<Area> { $0.statusRaw == s } })
            candidates += areas
                .filter { normalizedStatus == nil || $0.statusRaw == normalizedStatus }
                .map { (CadenceMCPOrdering.sortKey($0), CadenceResolvedContainer.area($0)) }
        }

        if normalizedKind == nil || normalizedKind == "project" {
            let projects: [Project] = scopedToContext
                ? (scopedContext?.projects ?? [])
                : try fetchAll(Project.self, where: normalizedStatus.map { s in #Predicate<Project> { $0.statusRaw == s } })
            candidates += projects
                .filter { normalizedStatus == nil || $0.statusRaw == normalizedStatus }
                .map { (CadenceMCPOrdering.sortKey($0), CadenceResolvedContainer.project($0)) }
        }

        candidates.sort { CadenceMCPOrdering.precedes($0.key, $1.key) }

        return CadencePage.paging(candidates, offset: offset, limit: limit) { candidate in
            switch candidate.container {
            case .area(let area):
                return containerRef(area)
            case .project(let project):
                return containerRef(project)
            }
        }
    }

    func listContexts(includeArchived: Bool = false, query: String? = nil, limit: Int = 50, offset: Int = 0) throws -> CadencePage<CadenceContextRef> {
        var contexts = try fetchAll(
            Context.self,
            where: includeArchived ? nil : #Predicate<Context> { !$0.isArchived }
        )
        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            contexts = contexts.filter { context in
                CadenceSearchMatcher.matchScore(query: query, fields: [context.name, context.icon]) != nil
            }
        }
        return CadencePage.paging(
            contexts.sorted(by: CadenceMCPOrdering.precedes),
            offset: offset,
            limit: limit,
            transform: contextRef
        )
    }

    func containerSummary(kind: String, id: String) throws -> CadenceContainerSummary {
        let uuid = try uuid(from: id)
        // **One container row, resolved once** — this used to fetch the task, link and note tables
        // whole and filter each down to this container, and then resolve the container itself
        // twice more for the `container:` field and the section configs (T-384). The unknown-id
        // error is unchanged: `containerRef(kind:id:)` used to raise `containerNotFound` a few
        // lines below, and this guard raises the same case with the same payload.
        guard let model = try containerModel(kind: kind, id: uuid) else {
            throw CadenceReadError.containerNotFound(kind, uuid.uuidString)
        }
        let containerTasks = model.tasks
        let active = containerTasks.filter { !$0.isDone && !$0.isCancelled }
        let today = DateFormatters.todayKey()
        let overdue = active.filter { !$0.dueDate.isEmpty && $0.dueDate < today }
        let links = model.links
            .sorted(by: CadenceMCPOrdering.precedes)
            .map(linkSummary)
        let noteDocuments = model.documents
            .sorted(by: CadenceMCPOrdering.precedes)
            .map(documentSummary)

        return CadenceContainerSummary(
            container: containerRef(model),
            activeTaskCount: active.count,
            completedTaskCount: containerTasks.filter(\.isDone).count,
            overdueTaskCount: overdue.count,
            sections: sectionSummaries(for: model, tasks: containerTasks),
            documents: noteDocuments,
            links: links
        )
    }

    func contextSummary(contextID: String) throws -> CadenceContextSummary {
        let id = try uuid(from: contextID)
        // Six whole-table fetches became one row and its edges (T-384). `Context` carries inverse
        // relationships for areas, projects, goals and tasks, and the documents and links this
        // reported were always "the ones on those areas and projects" — which is what the areas'
        // and projects' own edges hold.
        guard let context = try contextModel(id) else {
            throw CadenceReadError.contextNotFound(contextID)
        }

        let areas = (context.areas ?? []).sorted(by: CadenceMCPOrdering.precedes)
        let projects = (context.projects ?? []).sorted(by: CadenceMCPOrdering.precedes)
        let goals = context.goals ?? []
        let tasks = context.tasks ?? []
        let activeTasks = tasks.filter { !$0.isDone && !$0.isCancelled }
        // Deduped by id: a note or link carrying *both* an area and a project would be reached
        // twice through the edges, where the old whole-table filter saw each row once. Spelled out
        // in typed steps rather than one chained expression — the inferred version was an
        // "unable to type-check in reasonable time" build failure, not a style preference.
        var containerNotes: [Note] = []
        var containerLinks: [SavedLink] = []
        for area in areas {
            containerNotes.append(contentsOf: area.notes ?? [])
            containerLinks.append(contentsOf: area.links ?? [])
        }
        for project in projects {
            containerNotes.append(contentsOf: project.notes ?? [])
            containerLinks.append(contentsOf: project.links ?? [])
        }
        let notes: [Note] = deduped(containerNotes, by: { $0.id }).filter { $0.kind == .list }
        let links: [SavedLink] = deduped(containerLinks, by: { $0.id })
        let today = DateFormatters.todayKey()

        return CadenceContextSummary(
            context: contextRef(context),
            inboxTaskCount: tasks.filter { $0.area == nil && $0.project == nil && !$0.isCancelled }.count,
            activeTaskCount: activeTasks.count,
            completedTaskCount: tasks.filter(\.isDone).count,
            scheduledTaskCount: activeTasks.filter { !$0.scheduledDate.isEmpty }.count,
            overdueTaskCount: activeTasks.filter { !$0.dueDate.isEmpty && $0.dueDate < today }.count,
            activeGoalCount: goals.filter { $0.status == .active }.count,
            documentCount: notes.count,
            linkCount: links.count,
            areas: areas.map(containerRef),
            projects: projects.map(containerRef)
        )
    }

    func coreNotes(dateKey: String? = nil) throws -> CadenceCoreNotesSnapshot {
        let resolvedDateKey = try resolvedDateKey(dateKey)
        let resolvedWeekKey = try weekKey(for: resolvedDateKey)

        // Three narrow reads instead of one whole-`Note`-table scan (T-384). `first` over an
        // unordered fetch and `fetchLimit = 1` over the same predicate pick equally arbitrarily
        // when the store holds duplicates, which is the contract this already had.
        let dailyKind = NoteKind.daily.rawValue
        let weeklyKind = NoteKind.weekly.rawValue
        let permanentKind = NoteKind.permanent.rawValue
        let daily = try fetchFirst(
            Note.self,
            where: #Predicate { $0.kindRaw == dailyKind && $0.dateKey == resolvedDateKey }
        )
        let weekly = try fetchFirst(
            Note.self,
            where: #Predicate { $0.kindRaw == weeklyKind && $0.weekKey == resolvedWeekKey }
        )
        // Oldest, matching `NoteMigrationService.permanentNote(in:)`. Notepad holds many notes
        // now, and a bare `first` over an unordered fetch would put a different one in the
        // snapshot from one read to the next. The tie-break is `id.uuidString`, which no
        // `SortDescriptor` can express, so this still ranks in memory — over permanent notes
        // only, not over every note in the store.
        let permanent = try fetchAll(Note.self, where: #Predicate { $0.kindRaw == permanentKind })
            .min { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }

        return CadenceCoreNotesSnapshot(
            dateKey: resolvedDateKey,
            weekKey: resolvedWeekKey,
            dailyNote: daily.map { notePayload($0, key: resolvedDateKey) },
            weeklyNote: weekly.map { notePayload($0, key: resolvedWeekKey) },
            permanentNote: permanent.map { notePayload($0, key: nil) }
        )
    }

    func listDocuments(containerKind: String? = nil, containerID: String? = nil, query: String? = nil, limit: Int = 50, offset: Int = 0) throws -> CadencePage<CadenceDocumentSummary> {
        let listKind = Self.listNoteKindRaw
        let containerFilter = try resolvedContainerFilter(kind: containerKind, id: containerID)
        var docs: [Note]
        if let containerFilter {
            docs = try containerModel(kind: containerFilter.kind, id: containerFilter.id)?.documents ?? []
        } else {
            docs = try fetchAll(Note.self, where: #Predicate { $0.kindRaw == listKind })
        }

        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            docs = docs.filter { doc in
                let tagText = doc.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
                return CadenceSearchMatcher.matchScore(query: query, fields: [doc.title, doc.content, doc.area?.name ?? "", doc.project?.name ?? "", tagText]) != nil
            }
        }

        return CadencePage.paging(
            docs.sorted(by: CadenceMCPOrdering.recencyPrecedes),
            offset: offset,
            limit: limit,
            transform: documentSummary
        )
    }

    func getDocument(documentID: String) throws -> CadenceDocumentDetail {
        let id = try uuid(from: documentID)
        let listKind = Self.listNoteKindRaw
        if let doc = try fetchFirst(Note.self, where: #Predicate { $0.id == id && $0.kindRaw == listKind }) {
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

    func listTags(includeArchived: Bool = false, query: String? = nil, limit: Int = 50, offset: Int = 0) throws -> CadencePage<CadenceTagDetail> {
        var tags = try fetchAll(
            Tag.self,
            where: includeArchived ? nil : #Predicate<Tag> { !$0.isArchived }
        )
        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            tags = tags.filter { tag in
                CadenceSearchMatcher.matchScore(query: query, fields: [tag.name, tag.slug, tag.desc]) != nil
            }
        }
        return CadencePage.paging(TagSupport.sorted(tags), offset: offset, limit: limit, transform: tagDetail)
    }

    func listNotes(options: CadenceNoteListOptions) throws -> CadencePage<CadenceNoteSummary> {
        let normalizedKind = try options.kind.map(validateNoteKind)
        let containerFilter = try resolvedContainerFilter(kind: options.containerKind, id: options.containerId)

        var notes: [Note]
        if let containerFilter {
            notes = try containerModel(kind: containerFilter.kind, id: containerFilter.id)?.allNotes ?? []
            if let normalizedKind {
                notes = notes.filter { $0.kindRaw == normalizedKind }
            }
        } else {
            notes = try fetchAll(
                Note.self,
                where: normalizedKind.map { k in #Predicate<Note> { $0.kindRaw == k } }
            )
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

        return CadencePage.paging(
            notes.sorted(by: CadenceMCPOrdering.recencyPrecedes),
            offset: options.offset,
            limit: options.limit,
            transform: noteSummary
        )
    }

    func getNote(noteID: String) throws -> CadenceNoteDetail {
        let id = try uuid(from: noteID)
        // The note itself is one row. The two whole-table fetches below are *not* removable —
        // backlinks and `[[wiki]]` resolution are defined over every note, `linkedTasks` over every
        // task — but they now happen only for an id that exists (T-384).
        guard let note = try fetchFirst(Note.self, where: #Predicate { $0.id == id }) else {
            throw CadenceReadError.noteNotFound(noteID)
        }
        let notes = try fetchNotes()
        let tasks = try fetchTasks()

        return CadenceNoteDetail(
            summary: noteSummary(note),
            content: note.content,
            order: note.order,
            createdAt: format(note.createdAt),
            updatedAt: format(note.updatedAt),
            linkedNotes: NoteReferenceResolver.linkedNotes(for: note, in: notes).map(noteSummary),
            backlinks: NoteReferenceResolver.backlinks(for: note, in: notes).map(noteSummary),
            linkedTasks: NoteReferenceResolver.linkedTasks(for: note, in: tasks).map { taskSummary($0) }
        )
    }

    func listGoals(options: CadenceGoalListOptions) throws -> CadencePage<CadenceGoalSummary> {
        let contextUUID = try options.contextId.map(uuid)
        let normalizedStatus = try options.status.map(validateGoalStatus)
        var goals: [Goal]
        if let contextUUID {
            goals = try contextModel(contextUUID)?.goals ?? []
        } else {
            goals = try fetchAll(
                Goal.self,
                where: normalizedStatus.map { s in #Predicate<Goal> { $0.statusRaw == s } }
            )
        }
        if let normalizedStatus {
            goals = goals.filter { $0.statusRaw == normalizedStatus }
        }
        if let query = options.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            goals = goals.filter { goal in
                CadenceSearchMatcher.matchScore(query: query, fields: [goal.title, goal.desc, goal.context?.name ?? "", goal.statusRaw]) != nil
            }
        }

        return CadencePage.paging(
            goals.sorted(by: CadenceMCPOrdering.precedes),
            offset: options.offset,
            limit: options.limit,
            transform: goalSummary
        )
    }

    func getGoal(goalID: String) throws -> CadenceGoalDetail {
        let id = try uuid(from: goalID)
        guard let goal = try fetchFirst(Goal.self, where: #Predicate { $0.id == id }) else {
            throw CadenceReadError.goalNotFound(goalID)
        }
        let contribution = GoalContributionResolver.summary(for: goal)
        let habitMomentum = GoalHabitMomentumResolver.summary(for: goal)
        // These arrays must use the same traversal as the counts beside them in the response.
        // `directTaskCount` and `linkedHabitCount` recurse into milestones; while these two read
        // the goal's own relationship flat, one payload could report `directTaskCount: 1` next to
        // an empty `directTasks: []`, which is harder for a consumer to reason about than the
        // constant `0` it replaced.
        let directTasks = GoalContributionResolver.directTasks(for: goal)
            .sorted(by: taskSort)
            .map { taskSummary($0) }

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
            habits: GoalHabitMomentumResolver.linkedHabits(for: goal).map(habitSummary)
        )
    }

    func listHabits(options: CadenceHabitListOptions) throws -> CadencePage<CadenceHabitSummary> {
        let contextUUID = try options.contextId.map(uuid)
        let goalUUID = try options.goalId.map(uuid)
        // The narrower of the two edges wins: a goal owns fewer habits than a context does.
        var habits: [Habit]
        if let goalUUID {
            habits = try fetchFirst(Goal.self, where: #Predicate { $0.id == goalUUID })?.habits ?? []
        } else if let contextUUID {
            habits = try contextModel(contextUUID)?.habits ?? []
        } else {
            habits = try fetchHabits()
        }
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

        return CadencePage.paging(
            habits.sorted(by: CadenceMCPOrdering.precedes),
            offset: options.offset,
            limit: options.limit,
            transform: habitSummary
        )
    }

    func listLinks(options: CadenceSavedLinkListOptions) throws -> CadencePage<CadenceSavedLinkSummary> {
        let containerFilter = try resolvedContainerFilter(kind: options.containerKind, id: options.containerId)
        var links: [SavedLink]
        if let containerFilter {
            links = try containerModel(kind: containerFilter.kind, id: containerFilter.id)?.links ?? []
        } else {
            links = try fetchLinks()
        }

        if let query = options.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            links = links.filter { link in
                CadenceSearchMatcher.matchScore(query: query, fields: [link.title, link.url, link.area?.name ?? "", link.project?.name ?? ""]) != nil
            }
        }

        return CadencePage.paging(
            links.sorted(by: CadenceMCPOrdering.precedes),
            offset: options.offset,
            limit: options.limit,
            transform: linkSummary
        )
    }

    func search(query: String, scopes: [String]? = nil, limit: Int = 50, offset: Int = 0) throws -> CadencePage<CadenceSearchHit> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty(offset: max(offset, 0)) }

        let selectedScopes = try validateScopes(scopes ?? ["tasks", "containers", "contexts", "documents", "core_notes", "event_notes", "goals", "habits", "links", "tags"])
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
                    title: CadenceTitleNormalization.display(task.title, fallback: CadenceTitleNormalization.defaultTaskTitle),
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

        if selectedScopes.contains("contexts") {
            hits += try fetchContexts().compactMap { context in
                guard let score = CadenceSearchMatcher.matchScore(query: trimmed, fields: [context.name, context.icon]) else { return nil }
                let areaCount = (context.areas ?? []).count
                let projectCount = (context.projects ?? []).count
                let goalCount = (context.goals ?? []).count
                let habitCount = (context.habits ?? []).count
                return CadenceSearchHit(
                    entityType: "context",
                    entityId: context.id.uuidString,
                    title: CadenceTitleNormalization.display(context.name, fallback: CadenceTitleNormalization.defaultContextName),
                    subtitle: context.isArchived ? "Archived context" : "Context",
                    excerpt: "\(areaCount) areas - \(projectCount) projects - \(goalCount) goals - \(habitCount) habits",
                    score: score
                )
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
                    subtitle: noteSubtitle(note),
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
                    title: CadenceTitleNormalization.display(goal.title, fallback: CadenceTitleNormalization.defaultGoalTitle),
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
                    title: CadenceTitleNormalization.display(habit.title, fallback: CadenceTitleNormalization.defaultHabitTitle),
                    // The unit comes from the frequency, not from the sentence: `currentStreak`
                    // counts *weeks* for `.timesPerWeek`, so a hardcoded "day" turned eight kept
                    // weeks into "8 day streak" — a number an MCP client would then repeat back to
                    // the user as weaker than a ten-day daily habit. `HabitStreakUnit.phrase` is
                    // the same spelling the in-app search index uses for this exact subtitle.
                    subtitle: [habit.context?.name ?? "No context", habit.streakUnit.phrase(habit.currentStreak)].joined(separator: " - "),
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
                    title: CadenceTitleNormalization.display(link.title, fallback: link.url),
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
                    title: CadenceTitleNormalization.display(tag.name, fallback: tag.slug),
                    subtitle: tag.slug,
                    excerpt: excerpt(tag.desc),
                    score: score
                )
            }
        }

        // Hits carry the score `matchScore` already produced above, so rank on it directly.
        //
        // **T-372a: `identity` is what makes this a total order.** `entityType` has to be in it,
        // not just `entityId`. This list is the merge of eleven scope loops over eight different
        // tables, so two rows can share a title and a score *and* be different kinds of thing —
        // and `entityId` alone would then order an area against a task by an id the caller cannot
        // see or predict. Pairing it with the type makes the tie-break the same string the caller
        // already reads back off the hit.
        let ranked = CadenceSearchMatcher.rank(
            hits,
            score: { $0.score },
            title: { $0.title },
            identity: { "\($0.entityType):\($0.entityId)" }
        )
        return CadencePage.paging(ranked, offset: offset, limit: limit) { $0 }
    }

    func recentMCPWrites(limit: Int = 50, offset: Int = 0) throws -> CadencePage<CadenceMCPAuditEntry> {
        try CadenceMCPAuditLogger.recentEntries(
            limit: limit,
            offset: offset,
            logURL: CadenceModelContainerFactory.auditLogURL()
        )
    }

    func noteMigrationHealth() throws -> NoteMigrationHealthReport {
        try NoteMigrationService.healthCheck(in: context)
    }

    /// Every read in this file goes through one of these two, so `fetchedRowCount` cannot drift
    /// and a predicate cannot be quietly forgotten in a corner.
    ///
    /// `predicate: nil` is still a whole-table scan and several callers legitimately want one —
    /// `search_cadence` scores free text over every row, `getNote` needs the full note set to
    /// resolve backlinks. What T-384 removed is the *unnecessary* ones: a detail lookup that
    /// fetched a table in order to run `first(where:)` on it, and a list filter the store could
    /// have applied itself.
    private func fetchAll<Model: PersistentModel>(
        _ type: Model.Type = Model.self,
        where predicate: Predicate<Model>? = nil
    ) throws -> [Model] {
        let results = try context.fetch(FetchDescriptor<Model>(predicate: predicate))
        fetchedRowCount += results.count
        return results
    }

    /// One row, or `nil` — predicate plus `fetchLimit = 1`, the shape
    /// `CadenceDeepLinkResolutionSupport.task(with:in:)` has always used for the same job.
    private func fetchFirst<Model: PersistentModel>(
        _ type: Model.Type = Model.self,
        where predicate: Predicate<Model>
    ) throws -> Model? {
        var descriptor = FetchDescriptor<Model>(predicate: predicate)
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        fetchedRowCount += results.count
        return results.first
    }

    private func fetchTasks() throws -> [AppTask] {
        try fetchAll(AppTask.self)
    }

    private func fetchContexts() throws -> [Context] {
        try fetchAll(Context.self)
    }

    private func fetchAreas() throws -> [Area] {
        try fetchAll(Area.self)
    }

    private func fetchProjects() throws -> [Project] {
        try fetchAll(Project.self)
    }

    private func fetchNotes() throws -> [Note] {
        try fetchAll(Note.self)
    }

    private func fetchTags() throws -> [Tag] {
        try fetchAll(Tag.self)
    }

    private func fetchGoals() throws -> [Goal] {
        try fetchAll(Goal.self)
    }

    private func fetchHabits() throws -> [Habit] {
        try fetchAll(Habit.self)
    }

    private func fetchLinks() throws -> [SavedLink] {
        try fetchAll(SavedLink.self)
    }

    private func fetchTaskBundles() throws -> [TaskBundle] {
        try fetchAll(TaskBundle.self)
    }

    /// Raw values hoisted so a `#Predicate` captures a `String` rather than reaching through
    /// `TaskStatus` / `NoteKind` — SwiftData compiles a narrow expression grammar and an enum
    /// round-trip is not in it.
    private static let doneStatusRaw = TaskStatus.done.rawValue
    private static let cancelledStatusRaw = TaskStatus.cancelled.rawValue
    private static let listNoteKindRaw = NoteKind.list.rawValue

    /// The dead `allTasks:` parameter is gone, and removing it is most of T-384's win on the
    /// detail lookups. It was **read by nothing** in this function, while `getTask`,
    /// `getTaskBundle` and `getGoal` each fetched every task in the store purely to supply it.
    private func taskSummary(_ task: AppTask) -> CadenceTaskSummary {
        CadenceTaskSummary(
            id: task.id.uuidString,
            title: CadenceTitleNormalization.display(task.title, fallback: CadenceTitleNormalization.defaultTaskTitle),
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
            title: CadenceTitleNormalization.display(goal.title, fallback: CadenceTitleNormalization.defaultGoalTitle),
            description: goal.desc,
            startDate: goal.startDate,
            endDate: goal.endDate,
            progressType: goal.progressTypeRaw,
            targetHours: goal.targetHours,
            loggedHours: goal.loggedHours,
            colorHex: goal.colorHex,
            icon: goal.icon,
            kind: goal.kindRaw,
            status: goal.statusRaw,
            progress: goal.progress,
            contextId: goal.context?.id.uuidString,
            contextName: goal.context?.name,
            parentGoalId: goal.parentGoal?.id.uuidString,
            parentGoalTitle: goal.parentGoal?.title,
            isTopLevel: goal.isTopLevel,
            ownLinkedListCount: (goal.listLinks ?? []).filter { $0.area != nil || $0.project != nil }.count,
            ownTaskCount: (goal.tasks ?? []).filter { !$0.isCancelled }.count,
            ownSubGoalCount: (goal.subGoals ?? []).count,
            ownHabitCount: (goal.habits ?? []).count,
            createdAt: format(goal.createdAt)
        )
    }

    private func habitSummary(_ habit: Habit) -> CadenceHabitSummary {
        let today = DateFormatters.todayKey()
        return CadenceHabitSummary(
            id: habit.id.uuidString,
            title: CadenceTitleNormalization.display(habit.title, fallback: CadenceTitleNormalization.defaultHabitTitle),
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
            title: CadenceTitleNormalization.display(link.title, fallback: link.url),
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

    /// Replaced the `containerRef(kind:id:)` that re-fetched the row its only caller had already
    /// resolved.
    private func containerRef(_ model: ContainerModel) -> CadenceContainerRef {
        switch model {
        case .area(let area): return containerRef(area)
        case .project(let project): return containerRef(project)
        }
    }

    private func contextRef(_ context: Context) -> CadenceContextRef {
        CadenceContextRef(
            id: context.id.uuidString,
            name: CadenceTitleNormalization.display(context.name, fallback: CadenceTitleNormalization.defaultContextName),
            colorHex: context.colorHex,
            icon: context.icon,
            order: context.order,
            isArchived: context.isArchived,
            areaCount: (context.areas ?? []).count,
            projectCount: (context.projects ?? []).count,
            activeTaskCount: (context.tasks ?? []).filter { !$0.isDone && !$0.isCancelled }.count,
            goalCount: (context.goals ?? []).count,
            habitCount: (context.habits ?? []).count
        )
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

    /// One container, resolved once, so its own `tasks` / `notes` / `links` edges answer the
    /// "in this list" question.
    ///
    /// **This is T-384 in miniature.** "Notes in project P" used to mean fetching every `Note` in
    /// the store and keeping the ones whose `project?.id` matched — five near-identical copies of
    /// that shape, one per entity pair. A to-many edge already holds exactly that answer, so the
    /// whole-table fetch bought nothing. Deliberately *not* a `#Predicate` on `note.project?.id`
    /// either: the edge is one traversal from a row already in memory and needs nothing from
    /// SwiftData's predicate grammar to be correct.
    private enum ContainerModel {
        case area(Area)
        case project(Project)

        var tasks: [AppTask] {
            switch self {
            case .area(let area): return area.tasks ?? []
            case .project(let project): return project.tasks ?? []
            }
        }

        var links: [SavedLink] {
            switch self {
            case .area(let area): return area.links ?? []
            case .project(let project): return project.links ?? []
            }
        }

        var sectionConfigs: [TaskSectionConfig] {
            switch self {
            case .area(let area): return area.sectionConfigs
            case .project(let project): return project.sectionConfigs
            }
        }

        /// `.list` notes only — the documents surface. `notesForContainer` filtered on the same
        /// kind before this existed.
        var documents: [Note] {
            allNotes.filter { $0.kind == .list }
        }

        /// Every note filed under this container regardless of kind — what `list_notes` filters by
        /// container, which is not restricted to documents.
        var allNotes: [Note] {
            switch self {
            case .area(let area): return area.notes ?? []
            case .project(let project): return project.notes ?? []
            }
        }
    }

    /// `nil` when no such container exists — which is what every list caller already did with an
    /// unknown id: an empty page, not an error.
    private func containerModel(kind: String, id: UUID) throws -> ContainerModel? {
        switch try normalizeContainerKind(kind) {
        case "area":
            return try fetchFirst(Area.self, where: #Predicate { $0.id == id }).map(ContainerModel.area)
        case "project":
            return try fetchFirst(Project.self, where: #Predicate { $0.id == id }).map(ContainerModel.project)
        default:
            throw CadenceReadError.invalidContainerKind(kind)
        }
    }

    private func contextModel(_ id: UUID) throws -> Context? {
        try fetchFirst(Context.self, where: #Predicate { $0.id == id })
    }

    private func sectionSummaries(for model: ContainerModel, tasks: [AppTask]) -> [CadenceSectionSummary] {
        let configuredSections = model.sectionConfigs

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

    /// The human line under a search hit's title — prose, not a key.
    ///
    /// **This was the fifth spelling of the note-kind switch, and the last one still in the retired
    /// vocabulary** (`docs/TODO.md` T-278, the tail of T-239). It said "Permanent note" and "Meeting
    /// note" for the surfaces the app calls **Notepad** and **Event Notes**; it now reads
    /// `NoteReferencePanelSupport.noteKindLabel`, the app's one answer, so a rename cannot leave
    /// this surface behind again.
    ///
    /// **Why changing MCP response prose is a decision this can make, given
    /// `CadenceMCPServer/AGENTS.md`'s "change response DTOs on purpose or not at all".** The DTO is
    /// untouched: `CadenceSearchHit`'s key set is unchanged and `noteEntityType` still returns
    /// `daily_note` / `weekly_note` / `permanent_note` / `document` / `event_note`, which is the
    /// discriminator a client matches on. `subtitle` is already free-form across this whole
    /// function — a container name, a tag slug, a status — and free-form *in this switch*, where
    /// `.list` returns a user-typed name, so no caller can have been matching an enumerated set
    /// against it. It is not a scored field either: `CadenceSearchMatcher.matchScore` is handed the
    /// title, content, key and tag text, never the subtitle, so no ranking moves. And the old prose
    /// was not a deliberately-preserved raw-value vocabulary: `.meeting`'s stable key had *already*
    /// moved to `event_note` while this line still said "Meeting note", so the two halves of one hit
    /// disagreed. Nothing persisted is involved, and nothing in `CadenceMCPServer/`,
    /// `plugins/cadence-mcp/` or the tests named these strings.
    ///
    /// `.list` keeps the container name rather than taking `noteKindDetail`: on this surface the
    /// list a document is filed under is the useful half, and `noteKindDetail` would append dates to
    /// the other four kinds — a larger response change than the ticket asked for.
    private func noteSubtitle(_ note: Note) -> String {
        switch note.kind {
        case .list: return documentContainer(note)?.name ?? "No container"
        case .daily, .weekly, .permanent, .meeting:
            return NoteReferencePanelSupport.noteKindLabel(note.kind)
        }
    }

    /// First occurrence wins, by `id`. Needed once edges replace whole-table filters: a row
    /// reachable through two containers arrives twice. Takes the id explicitly because
    /// `PersistentModel`'s `Identifiable.ID` is `PersistentIdentifier`, not the model's `UUID`.
    private func deduped<Model: PersistentModel>(_ models: [Model], by identity: (Model) -> UUID) -> [Model] {
        var seen = Set<UUID>()
        return models.filter { seen.insert(identity($0)).inserted }
    }

    private func taskSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
        if lhs.scheduledDate != rhs.scheduledDate { return lhs.scheduledDate < rhs.scheduledDate }
        if lhs.scheduledStartMin != rhs.scheduledStartMin { return lhs.scheduledStartMin < rhs.scheduledStartMin }
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        // Same reason as `CadenceMCPOrdering`: `createdAt` is a `Date` written by a save, and a
        // seeded or imported batch shares one.
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func resolvedDateKey(_ dateKey: String?) throws -> String {
        try CadenceMCPServiceSupport.resolvedDateKey(dateKey)
    }

    private func weekKey(for dateKey: String) throws -> String {
        try CadenceMCPServiceSupport.weekKey(for: dateKey)
    }

    /// `nil` in, `nil` out; anything else is normalized to a canonical key or throws.
    private func normalizedDateKey(_ dateKey: String?) throws -> String? {
        try CadenceMCPServiceSupport.validatedOptionalDate(dateKey)
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
        let valid = Set(["tasks", "containers", "contexts", "documents", "notes", "core_notes", "event_notes", "goals", "habits", "links", "tags"])
        return try Set(scopes.map { scope in
            let normalized = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard valid.contains(normalized) else {
                throw CadenceReadError.invalidScope(scope)
            }
            return normalized
        })
    }

    private func format(_ date: Date) -> String {
        encoderDateFormatter.string(from: date)
    }

    private func excerpt(_ text: String, maxLength: Int = 240) -> String {
        CadenceMCPServiceSupport.excerpt(text, maxLength: maxLength)
    }
}
