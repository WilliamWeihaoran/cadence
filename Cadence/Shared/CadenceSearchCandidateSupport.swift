import Foundation

// What global search can *see*, and which words reach it.
//
// `CadenceSearchMatcher` is the one scorer; this is the one **candidate** layer that decides what
// gets handed to it. Both existed as two copies before T-377: `GlobalSearchIndexSupport` fed the
// matcher lifecycle aliases and tag *slugs*, `iOSSearchView` fed it neither, so searching `done`
// or a tag's slug found work on the Mac and nothing on the iPhone. Row rendering stays where it
// belongs — each surface draws its own row from these facts — but no surface builds its own field
// list any more.
//
// Pure and `nonisolated`, like the matcher it feeds.

// MARK: - Tasks

/// Which glyph a task row should draw, as a **fact** rather than a symbol name. macOS and iOS
/// disagree about the symbols (and may keep disagreeing — a desktop row also carries an
/// "Active"/"Completed" word in its subtitle where a phone row has no room for one); what they
/// must not disagree about is which of the three states a task is in. Before T-377 iOS had no
/// `scheduled` case at all, so a task with a timeline slot drew a plain circle there and
/// `calendar.badge.clock` on the Mac.
nonisolated enum CadenceTaskSearchGlyph {
    case scheduled
    case completed
    case active
}

/// A tag matches by the name you see **and** by the slug you type, everywhere a tagged thing is
/// searchable. `TagSupport.slug` folds case, diacritics and punctuation, so the two usually
/// normalize to the same string — the pair only pays off for a tag whose slug was set by hand,
/// which is exactly the case a name-only field list cannot find.
///
/// Both halves of the drift T-377 names live here: macOS searched task *and* note tags by slug,
/// iOS searched neither.
nonisolated enum CadenceSearchTagSupport {
    static func text(for tags: [Tag]) -> String {
        tags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
    }
}

nonisolated enum CadenceTaskSearchSupport {
    /// Cancelled work is never searchable. Completed work is, when the surface asks for it —
    /// macOS's palette always does, and iOS gates it behind the "Completed" toggle in the scope
    /// picker, which is a user setting rather than a second policy.
    static func isSearchable(_ task: AppTask, includingCompleted: Bool) -> Bool {
        guard !task.isCancelled else { return false }
        return includingCompleted || !task.isDone
    }

    /// The lifecycle words a task answers to. Two words for a finished task on purpose: users type
    /// both *done* and *completed*, and the matcher scores whole normalized tokens.
    static func lifecycleAliases(for task: AppTask) -> String {
        task.isDone ? "completed done" : "active todo"
    }

    /// The container a row names, with the Inbox spelled out rather than left blank: a task with
    /// no list is findable by typing `inbox` on both surfaces.
    static func containerLabel(for task: AppTask) -> String {
        let name = task.containerName
        return name.isEmpty ? "Inbox" : name
    }

    /// The searchable fields, in matcher order. `fields[0]` is the title and is weighted highest;
    /// everything after it is body text, so the grouping below is about what exists, not about
    /// what ranks.
    static func searchFields(for task: AppTask) -> [String] {
        [
            task.title,
            containerLabel(for: task),
            task.context?.name ?? "",
            task.notes,
            [
                lifecycleAliases(for: task),
                task.priority.label,
                task.resolvedSectionName,
                CadenceSearchTagSupport.text(for: task.sortedTags)
            ].joined(separator: " ")
        ]
    }

    static func matchScore(query: String, task: AppTask) -> Int? {
        CadenceSearchMatcher.matchScore(query: query, fields: searchFields(for: task))
    }

    static func glyph(for task: AppTask) -> CadenceTaskSearchGlyph {
        if task.scheduledStartMin >= 0 { return .scheduled }
        return task.isDone ? .completed : .active
    }
}

// MARK: - Lists

/// Where an area or project sits in its lifecycle. `AreaStatus` has three cases and
/// `ProjectStatus` five, and the macOS palette used to collapse them to
/// `archived ? … : (done ? … : "active")` — which labels a **cancelled** project "Active".
nonisolated enum CadenceListSearchLifecycle {
    case active
    case completed
    case archived
    case paused
    case cancelled

    /// The word shown on a row, and the word the alias field answers to.
    var statusLabel: String {
        switch self {
        case .active: "Active"
        case .completed: "Completed"
        case .archived: "Archived"
        case .paused: "Paused"
        case .cancelled: "Cancelled"
        }
    }

    /// Same shape as `CadenceTaskSearchSupport.lifecycleAliases`: a completed list answers to both
    /// *completed* and *done*.
    var aliases: String {
        switch self {
        case .active: "active"
        case .completed: "completed done"
        case .archived: "archived"
        case .paused: "paused"
        case .cancelled: "cancelled"
        }
    }

    var isActive: Bool { self == .active }
}

/// T-378, decided rather than copied.
///
/// **The rule: typing reaches every list; idle suggestions offer only active ones.**
///
/// The two surfaces disagreed — macOS searched every area and project, iOS pre-filtered to
/// `isActive` — and the ticket is explicit that neither was known to be right. The evidence that
/// decides it:
///
/// - `AppTask.isInActiveContainer` is where this app already wrote the rule down, and it names the
///   surfaces a finished list is hidden from: "the sidebar, All Tasks, the kanban boards and every
///   container picker". Search is not among them. Every `filter(\.isActive)` call site in the app
///   is one of those surfaces — a picker, a sidebar, a board column, a settings counter. They
///   decide *where new work may go*, which is not what search decides.
/// - The third search surface already includes them: `CadenceReadService.search` scores every area
///   and project with no status filter at all, so the MCP `search()` tool answers the inclusive
///   way today.
/// - A hit leads somewhere real on both platforms. `AreaDetailLoader`/`ProjectDetailLoader` and
///   `iOSSearchView`'s own `navigationDestination` all resolve out of an unfiltered `@Query`, so a
///   completed list opens its detail page normally.
/// - Search is the **only** way in. Settings → Lists lists finished areas and projects on both
///   platforms, but its rows offer Reopen/Unarchive/Delete and no navigation
///   (`SettingsListManagementSections.lifecycleCard`, `iOSSettingsTemplateAndListSections`).
///   Excluding them from search makes a finished list's contents unreachable from anywhere.
/// - Both task searches already return tasks that *live in* finished lists — neither filters
///   `isInActiveContainer`. Finding the task inside an archived project while refusing to find the
///   project was the asymmetry, not the policy.
///
/// The idle half is the narrow half, and it is why this is not simply "macOS wins": an empty query
/// is a suggestion list, not a search, and suggesting an archived area as somewhere to go is the
/// pickers' mistake. macOS used to offer them there; it no longer does.
nonisolated enum CadenceListSearchSupport {
    static func lifecycle(of area: Area) -> CadenceListSearchLifecycle {
        switch area.status {
        case .active: .active
        case .done: .completed
        case .archived: .archived
        }
    }

    static func lifecycle(of project: Project) -> CadenceListSearchLifecycle {
        switch project.status {
        case .active: .active
        case .done: .completed
        case .archived: .archived
        case .paused: .paused
        case .cancelled: .cancelled
        }
    }

    /// `query` decides, not a caller flag: "the user has typed something" is the whole difference
    /// between a search and a suggestion list.
    static func isSearching(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isSearchable(_ lifecycle: CadenceListSearchLifecycle, query: String) -> Bool {
        lifecycle.isActive || isSearching(query)
    }

    static func isSearchable(_ area: Area, query: String) -> Bool {
        isSearchable(lifecycle(of: area), query: query)
    }

    static func isSearchable(_ project: Project, query: String) -> Bool {
        isSearchable(lifecycle(of: project), query: query)
    }

    /// One field policy for both list kinds: name, description, the context it hangs off, the
    /// parent area when there is one, then the lifecycle aliases. macOS fed the matcher a
    /// pre-joined "context • area" summary and iOS fed it separate fields; the words were the same
    /// but the *title* field is weighted differently from the body, so identical text could score
    /// differently on the two platforms.
    static func searchFields(for area: Area) -> [String] {
        [
            area.name,
            area.desc,
            area.context?.name ?? "",
            lifecycle(of: area).aliases
        ]
    }

    static func searchFields(for project: Project) -> [String] {
        [
            project.name,
            project.desc,
            project.context?.name ?? "",
            project.area?.name ?? "",
            lifecycle(of: project).aliases
        ]
    }

    static func matchScore(query: String, area: Area) -> Int? {
        CadenceSearchMatcher.matchScore(query: query, fields: searchFields(for: area))
    }

    static func matchScore(query: String, project: Project) -> Int? {
        CadenceSearchMatcher.matchScore(query: query, fields: searchFields(for: project))
    }
}
