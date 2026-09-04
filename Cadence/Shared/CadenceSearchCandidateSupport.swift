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
        CadenceTitleNormalization.display(task.containerName, fallback: "Inbox")
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

// MARK: - Identity

/// The **identity leg** of a search row's order, spelled once.
///
/// `CadenceSearchMatcher.rank` takes three legs — score, title, identity — and the third is what
/// makes the order *total*: two rows that tie on score and title are otherwise left in whatever
/// order the store handed them over, which is a property of the store rather than of search
/// (T-372a). Every surface therefore needs an identity per row, and the question this enum answers
/// is what that string should say.
///
/// **Why an enum and not a literal per call site.** macOS built `"task-\(uuid)"` inline at nine
/// construction sites and iOS had none; adding a tenth spelling on the phone would have been the
/// near-copy this repo's rules forbid, and the two surfaces would have been free to disagree about
/// the prefix for the same entity. They are the same string now.
///
/// **Why the type prefix, and not the bare UUID.** A section can merge two tables: iOS's Lists
/// section is areas *and* projects, its Goals and Habits section is both, and macOS's palette
/// merges every category into one list. A bare `uuidString` identifies a row only as long as no
/// second table is in the list with it — the same reason `CadenceReadService.search` ties on
/// `entityType:entityId` rather than on `entityId`. The prefix is the entity type; the suffix is
/// the entity.
///
/// Deliberately **not** the row's SwiftUI identity contract, and not a payload anything parses.
/// Nothing reads these back apart from `lookupIdentifier` on the event case, so the spellings are
/// free to be whatever reads best in a failure message.
nonisolated enum CadenceSearchIdentity {
    static func task(_ id: UUID) -> String { "task-\(id.uuidString)" }
    static func area(_ id: UUID) -> String { "area-\(id.uuidString)" }
    static func project(_ id: UUID) -> String { "project-\(id.uuidString)" }
    static func goal(_ id: UUID) -> String { "goal-\(id.uuidString)" }
    static func habit(_ id: UUID) -> String { "habit-\(id.uuidString)" }

    /// iOS's Notes section searches every note kind; macOS's palette has a *meeting-notes* section
    /// and no general one. Two cases rather than one because they are two different row
    /// populations, and `event-note-` is the string macOS's palette has always used.
    static func note(_ id: UUID) -> String { "note-\(id.uuidString)" }
    static func eventNote(_ id: UUID) -> String { "event-note-\(id.uuidString)" }

    /// **Occurrence-scoped, not `rawIdentifier`.** Pass `CadenceEventNoteSupport.identifier(for:)`.
    ///
    /// `CadenceCalendarEventSearchSupport.identity(of:)` deliberately drops the `#occurrence=`
    /// suffix, and its note says why: that comparator comes *after* a start-instant leg, and two
    /// occurrences of one series never share a start, so the suffix could not break a tie there.
    /// Here the leg before it is the **score**, and every occurrence of a recurring meeting scores
    /// identically on the same title — so the suffix is the only thing that tells them apart, and
    /// dropping it would put a week of standups back in fetch order.
    static func event(_ occurrenceIdentifier: String) -> String { "event-\(occurrenceIdentifier)" }

    /// A static destination row rather than a stored entity. The key is whatever that surface's
    /// catalog uses as its own stable handle — `CadenceFeatureDestination.rawValue` on iOS, the
    /// page definition's label on macOS — because neither catalog has a UUID and both are unique
    /// within the one section that draws them.
    static func page(_ key: String) -> String { "page-\(key)" }

    static func command(_ rawValue: String) -> String { "command-\(rawValue)" }
}

// MARK: - Idle suggestion windows

/// Where a row sits in an idle suggestion list that **merges two tables** — iOS Search's Lists
/// section (areas then projects) and its Goals and Habits section (goals then habits).
///
/// `table` is the concatenation order the section was already built in; `order` is the user's own
/// manual ordering inside that table. Deliberately **partial**: `Area.order`, `Project.order`,
/// `Goal.order` and `Habit.order` all default to `0`, so anything created outside a reorder UI
/// ties, and two rows with the same rank are genuinely equally-ranked. Completing it is
/// `CadenceSearchSuggestionWindow`'s job, once, rather than each section's.
nonisolated struct CadenceSearchSuggestionRank: Comparable {
    let table: Int
    let order: Int

    init(table: Int, order: Int) {
        self.table = table
        self.order = order
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.table == rhs.table ? lhs.order < rhs.order : lhs.table < rhs.table
    }
}

/// The **idle** half of search: the handful of rows a section suggests before anything is typed.
///
/// **T-498, and the bug is sharper than an ordering bug.** T-479 gave the *scored* branches a total
/// order through `CadenceSearchMatcher.rank`'s identity leg. The idle branches took `prefix(8)`
/// straight off a partial order in four of six sections — tasks sorted on due date then a per-list
/// `order` (so cross-list ties are routine), and lists, notes and progress prefixed straight off
/// `@Query` order. On a partial order the *window itself* is nondeterministic, not just its
/// arrangement: rows tied with the last one that fits are dropped by fetch order, so **which eight**
/// suggestions the screen offers changes between two identical reads.
///
/// Deliberately **not** routed through `iOSSearchIndexSupport.rankedResults`. An idle list is
/// chronological or manual on purpose — "what is due next", "your lists in the order you arranged
/// them" — and the score funnel would re-sort every one of them to alphabetical, since with no query
/// every row scores 0 and the title leg decides. What the two halves share is the *identity* leg,
/// spelled by `CadenceSearchIdentity` in both.
nonisolated enum CadenceSearchSuggestionWindow {
    /// The first `limit` rows of `items` under `orderedBefore` **completed by `identity`**.
    ///
    /// `orderedBefore` stays the caller's, because each section orders on something different and
    /// none of it belongs here. Its ties are detected rather than declared: under a strict weak
    /// ordering `lhs` and `rhs` are equivalent exactly when neither precedes the other, so this
    /// needs no `Key` type, no `Comparable` conformance, and no second closure that a call site
    /// could forget to keep in step with the first.
    static func take<Item>(
        _ items: [Item],
        limit: Int,
        identity: (Item) -> String,
        orderedBefore: (Item, Item) -> Bool
    ) -> [Item] {
        items
            // `identity` once per item rather than once per comparison, for the reason
            // `CadenceSearchMatcher.rank` decorates: these are interpolated UUID strings.
            .map { (item: $0, identity: identity($0)) }
            .sorted { lhs, rhs in
                if orderedBefore(lhs.item, rhs.item) { return true }
                if orderedBefore(rhs.item, lhs.item) { return false }
                return lhs.identity < rhs.identity
            }
            .prefix(limit)
            .map(\.item)
    }
}
