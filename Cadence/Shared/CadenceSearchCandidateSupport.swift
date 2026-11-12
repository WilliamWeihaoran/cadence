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

/// Which glyph a task row should draw: the state as a fact, and the one symbol per state both
/// search surfaces draw for it. Before T-377 iOS had no `scheduled` case at all, so a task with a
/// timeline slot drew a plain circle there and `calendar.badge.clock` on the Mac.
///
/// **The symbols are one set since [[T-11195]] (a), under [[T-8201]].** Cmd+K drew
/// `checkmark.circle` for an active task *and* a completed one, defended by the "Active" /
/// "Completed" word at the end of its subtitle; that word is a subtitle choice ([[T-8763]]), not a
/// hardware or input constraint, and a glyph that reads the same for open and finished work says
/// nothing. Both rows now draw iOS's pair -- an open `circle`, a filled check -- the same pair the
/// app's other task-state glyphs use.
nonisolated enum CadenceTaskSearchGlyph {
    case scheduled
    case completed
    case active

    var systemImage: String {
        switch self {
        case .scheduled: "calendar.badge.clock"
        case .completed: "checkmark.circle.fill"
        case .active: "circle"
        }
    }
}

/// The search field's placeholder on both search surfaces ([[T-11195]] (b), under [[T-8201]]).
///
/// One list of what the field finds. The Mac's said "Jump anywhere or run a command" and iOS's
/// "Tasks, lists, notes, events"; only the command half answers an input difference -- Cmd+K's
/// Commands section is the keyboard palette's, and iOS Search has none (`.commands` lists nothing
/// there) -- so that half is the one thing the Mac adds.
nonisolated enum CadenceSearchFieldPrompt {
    static let searchable = "Tasks, lists, notes, events"

    static func text(offersCommands: Bool) -> String {
        offersCommands ? "\(searchable), or a command" : searchable
    }
}

/// The facts an **Event Notes** search row's subtitle names, on both surfaces ([[T-11195]] (c),
/// under [[T-8201]]): the event's day, then its time range when the note has one. Each surface
/// joins them in its own separator, the shape [[T-8526]] gave list rows.
///
/// No kind word: both surfaces draw these rows in a section of their own titled Event Notes, so
/// iOS's `Event / Nov 4` (from `NoteReferencePanelSupport.noteKindDetail`, which is right for the
/// mixed note-reference picker it also serves) said the section's name again and dropped the time
/// the Mac row showed. A note with no parseable day names its kind instead, so the line is never
/// blank.
nonisolated enum CadenceSearchEventNoteSupport {
    static let undatedLabel = "Event note"

    static func subtitleFacts(for note: Note, relativeTo referenceDate: Date = Date()) -> [String] {
        guard let date = DateFormatters.date(from: note.eventDateKey) else { return [undatedLabel] }
        let day = DateFormatters.absoluteDay(date, relativeTo: referenceDate)
        // [[T-16880]]: "All day" for an all-day event's note, as the event's own row says.
        guard let time = CadenceEventNoteTimeLabel.label(startMin: note.eventStartMin, endMin: note.eventEndMin) else {
            return [day]
        }
        return [day, time]
    }
}

/// The glyph an Apple Calendar event's search row draws, on both search surfaces ([[T-10185]],
/// under [[T-8201]]).
///
/// One symbol, whether the event is timed or all-day: the row's own detail line already says
/// "All day" or the time range, so the glyph only has to say "this is an event". The Mac's Cmd+K
/// row has drawn plain `calendar` since it existed; iOS Search spelled the choice inline and
/// inverted it -- `isAllDay ? "calendar.badge.clock" : "calendar"` -- so an all-day event wore a
/// clock and a timed one did not.
nonisolated enum CadenceSearchEventGlyph {
    static let systemImage = "calendar"
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
    ///
    /// **[[T-16940]]: "Inbox" only for a task in no list.** This read `display(task.containerName,
    /// fallback: "Inbox")`, so a task filed in a blank-named area or project was called "Inbox" in
    /// Cmd+K's and iOS Search's task rows (and answered the query `inbox`), while its list chip,
    /// the sidebar and the list's own search row say "Untitled Area" / "Untitled Project" --
    /// `CadenceBoardCardMetadata.listTitle(for:)`'s rule ([[T-11892]]), spelled here because that
    /// type is main-actor and this enum is not. Project before area, as `containerName` reads.
    static func containerLabel(for task: AppTask) -> String {
        if let project = task.project {
            return CadenceTitleNormalization.display(project.name, fallback: CadenceTitleNormalization.defaultProjectName)
        }
        if let area = task.area {
            return CadenceTitleNormalization.display(area.name, fallback: CadenceTitleNormalization.defaultAreaName)
        }
        return "Inbox"
    }

    /// The subtitle a task result draws on iOS Search: the container, plus ` / <section>` only
    /// when the task sits in a section the user named (T-5880). The default section is never
    /// spelled out — every other surface suppresses it — so an unsectioned task in "Work" reads
    /// "Work", not "Work / Default". An Inbox task has nowhere to be sectioned and reads "Inbox".
    static func resultSubtitle(for task: AppTask) -> String {
        let container = containerLabel(for: task)
        guard task.project != nil || task.area != nil else { return container }
        let section = task.resolvedSectionName
        guard section.caseInsensitiveCompare(TaskSectionDefaults.defaultName) != .orderedSame else {
            return container
        }
        return "\(container) / \(section)"
    }

    /// The searchable fields, in matcher order. `fields[0]` is the title and is weighted highest;
    /// everything after it is body text, so the grouping below is about what exists, not about
    /// what ranks.
    ///
    /// **[[T-16942]]: the title field is the title the row draws** -- "Untitled Task" for a blank
    /// one, as the Focus picker already matches ([[T-13871]]). The raw title was blank, so
    /// `untitled` did not find the row that says it, and `CadenceSearchMatcher` drops empty fields
    /// before taking `fields[0]` as the title, so the task's LIST name was scored as its title.
    static func searchFields(for task: AppTask) -> [String] {
        [
            TaskTitleSupport.displayTitle(task.title),
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

    /// **Completion is asked first** ([[T-14012]]), the order `TaskCompletionAnimationManager.glyph(for:)`
    /// already uses. A finished task keeps its timeline slot, so asking the slot first drew a done
    /// task -- visible once the Completed filter is on -- with the open-work clock instead of the
    /// filled check, on both search surfaces.
    static func glyph(for task: AppTask) -> CadenceTaskSearchGlyph {
        if task.isDone { return .completed }
        return task.scheduledStartMin >= 0 ? .scheduled : .active
    }

    /// How many tasks the query matches that the Completed filter is holding back ([[T-6971]],
    /// lifted here for iOS by [[T-6975]] so both search surfaces count the same rows).
    ///
    /// **Zero whenever nothing is being held back** — the filter is on, or the field is blank —
    /// so a caller can draw its hint on `> 0` alone. Counted through the same `isSearchable` and
    /// `searchFields` both surfaces build their task rows from, so the hint and the list cannot
    /// disagree about which tasks match: a task is counted exactly when turning Completed on would
    /// add its row. Cancelled work is unsearchable either way and is never counted.
    static func withheldCompletedMatchCount(
        tasks: [AppTask],
        query: String,
        includingCompleted: Bool
    ) -> Int {
        guard !includingCompleted,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return 0 }
        let preparedQuery = CadenceSearchMatcher.PreparedQuery(query)
        return tasks.reduce(into: 0) { count, task in
            guard isSearchable(task, includingCompleted: true),
                  !isSearchable(task, includingCompleted: false),
                  CadenceSearchMatcher.matchScore(query: preparedQuery, fields: searchFields(for: task)) != nil
            else { return }
            count += 1
        }
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
        case .cancelled: "Canceled"
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
        case .cancelled: "canceled cancelled"
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
    ///
    /// [[T-16942]]: the name field is `resultTitle`, the name the row draws, for the reason
    /// `CadenceTaskSearchSupport.searchFields` gives.
    static func searchFields(for area: Area) -> [String] {
        [
            resultTitle(for: area),
            area.desc,
            area.context?.name ?? "",
            lifecycle(of: area).aliases
        ]
    }

    static func searchFields(for project: Project) -> [String] {
        [
            resultTitle(for: project),
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

    /// A list row's title, never blank ([[T-8524]]). iOS Search tested `name.isEmpty`, so a list
    /// named only spaces drew a row with a glyph and nothing beside it, where Cmd+K's
    /// `CadenceTitleNormalization.display` already said "Untitled Area" / "Untitled Project".
    static func resultTitle(for area: Area) -> String {
        CadenceTitleNormalization.display(area.name, fallback: CadenceTitleNormalization.defaultAreaName)
    }

    static func resultTitle(for project: Project) -> String {
        CadenceTitleNormalization.display(project.name, fallback: CadenceTitleNormalization.defaultProjectName)
    }

    /// The names a project row sits under — its context, then its area — with blank ones dropped
    /// ([[T-8524]]). iOS joined `[context?.name, area?.name].compactMap { $0 }`, which drops a
    /// missing container but keeps one named `""`, so a project in an untitled area read
    /// "Work / " with nothing after the separator.
    static func containerNames(for project: Project) -> [String] {
        [project.context?.name, project.area?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The area twin: its context's name, trimmed, or nothing when it has none or it is blank.
    /// [[T-17141]]: the iOS Lists page and list header read `area.context?.name` raw, so an area
    /// under a context named "  " drew a line of spaces where its subtitle goes.
    static func containerNames(for area: Area) -> [String] {
        [area.context?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// The facts an Area or Project search row shows, in the order both rows show them ([[T-8526]]).
///
/// iOS Search and Cmd+K used to describe one list with different facts: Cmd+K typed
/// `No context` for a list with no context, iOS typed `Area` for an area and nothing for a
/// project, Cmd+K said `Active` on every active row, and iOS dropped the count on a finished
/// one. The owner call ([[T-11030]], under [[T-8201]]): the context name when there is one, the
/// area for a project when there is one, `N active tasks` always, then the lifecycle word only
/// when the list is not active. A word that names an absence is noise, and so is `Active` on a
/// row that is.
///
/// Split in two because the iOS row lays the containers and the status on separate lines; Cmd+K
/// draws `facts` on one. Each platform keeps its own separator ([[T-7205]]) — the facts are
/// this type's.
nonisolated struct CadenceListSearchRowFacts: Equatable {
    /// The names the list sits under, blank ones dropped: the context, then (for a project) the area.
    let containers: [String]
    /// The open count in `GoalLinkTarget.openTaskLabel`'s words, then the lifecycle word when the
    /// list is not active.
    let status: [String]

    /// Every fact, containers first.
    var facts: [String] { containers + status }
}

extension CadenceListSearchSupport {
    /// The pure half, so the order and the omissions are testable without a model.
    @MainActor
    static func rowFacts(
        containers: [String],
        lifecycle: CadenceListSearchLifecycle,
        openTaskCount: Int
    ) -> CadenceListSearchRowFacts {
        let named = containers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var status = [GoalLinkTarget.openTaskLabel(count: openTaskCount)]
        if !lifecycle.isActive { status.append(lifecycle.statusLabel) }
        return CadenceListSearchRowFacts(containers: named, status: status)
    }

    @MainActor
    static func rowFacts(for area: Area) -> CadenceListSearchRowFacts {
        rowFacts(
            containers: containerNames(for: area),
            lifecycle: lifecycle(of: area),
            openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: area)
        )
    }

    @MainActor
    static func rowFacts(for project: Project) -> CadenceListSearchRowFacts {
        rowFacts(
            containers: containerNames(for: project),
            lifecycle: lifecycle(of: project),
            openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: project)
        )
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

/// **What an empty search field suggests for tasks, notes and lists, on both surfaces**
/// ([[T-8764]]; lists [[T-11194]]).
///
/// iOS Search already answered "what is on today's plate" and "what was I just writing"; Cmd+K had
/// no idle branch for either section, so an empty query scored every row the same and
/// `CadenceSearchMatcher.rank` broke the tie on title — the palette suggested the first ten tasks and
/// first eight notes **A to Z**. The Mac's events section had already been given an idle branch for
/// that exact reason; this is the same fix for the other two, and one rule rather than a copy.
///
/// Membership and order live here. **How many rows a surface draws stays the surface's**: iOS cuts
/// `limit` rows, the palette returns the whole ordered list and lets `resultCap` and its continuation
/// row decide (T-1473), so "show more" reveals the *next* suggestions in the same order.
nonisolated enum CadenceSearchIdleSuggestions {
    /// iOS Search's idle window for each section.
    static let limit = 8

    /// Open work on today's plate: exactly what the Today page lists, through
    /// `AppTask.isTodayWork(todayKey:)` -- due on or before `today`, or planned for it **or for an
    /// earlier day and never done** (Today's Leftover). Cancelled and completed work is never
    /// suggested, whatever the Completed filter says -- the filter widens a *search*, and a
    /// suggestion list of finished work answers nothing.
    ///
    /// **[[T-14011]].** This was a second, narrower spelling -- `scheduledDate == today` or
    /// `dueDate <= today` -- with no past-do arm, so a task planned for yesterday with no due date
    /// sat on Today and was missing from both search surfaces' idle Tasks list: [[T-353]]'s widget
    /// defect, again, in the one place that rule had not reached.
    static func isSuggested(_ task: AppTask, today: String) -> Bool {
        task.isTodayWork(todayKey: today)
    }

    /// Due date (undated last), then the user's manual order, then identity (T-498). `order` is
    /// per-list, so two tasks due the same day in two lists tie on both legs routinely — and a tie at
    /// the last row that fits decides *membership*, not only arrangement.
    static func tasks(_ tasks: [AppTask], today: String, limit: Int = .max) -> [AppTask] {
        CadenceSearchSuggestionWindow.take(
            tasks.filter { isSuggested($0, today: today) },
            limit: limit,
            identity: { CadenceSearchIdentity.task($0.id) },
            orderedBefore: { lhs, rhs in
                if lhs.dueDate != rhs.dueDate {
                    if lhs.dueDate.isEmpty { return false }
                    if rhs.dueDate.isEmpty { return true }
                    return lhs.dueDate < rhs.dueDate
                }
                return lhs.order < rhs.order
            }
        )
    }

    /// A note with neither a title nor any text has nothing to show in a row or to be found by.
    ///
    /// **"Text" is what the user wrote, measured as the Notes list measures it** ([[T-15731]]).
    /// This used to test `content` or `displayTitle`, and `displayTitle` is never empty -- every kind
    /// falls back to a word ("Notepad", "Untitled") or its period key -- so the filter passed every
    /// note. Daily and weekly notes are created *for* you, titled with their key, the moment a day
    /// or week is opened, and a fresh row is the most recently edited one: browsing a few days in
    /// Notes filled both search surfaces' idle Notes section with blank days, which the Notes list
    /// itself hides (`NotesListVisibility.hasContent`). A period note now needs content; any other
    /// kind exists because someone made it, so a title it was given still counts.
    static func hasVisibleText(_ note: Note) -> Bool {
        if NotesListVisibility.hasContent(note) { return true }
        switch note.kind {
        case .daily, .weekly:
            return false
        case .permanent, .list, .meeting:
            return !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// **Areas before projects, each in the user's own arrangement, ties broken by identity**
    /// (T-498, [[T-11194]]) — one window across both kinds, split back into the two sections.
    ///
    /// iOS Search cut this window by hand from its own row candidates while Cmd+K had no idle
    /// branch for lists at all: an empty query scored every list alike, `CadenceSearchMatcher.rank`
    /// broke the tie on title, and the palette listed Areas and Projects **A to Z** where the phone
    /// listed them in the order the sidebar shows them. The same defect [[T-8764]] fixed for tasks
    /// and notes. Membership (`CadenceListSearchSupport.isSearchable`) stays the caller's; this
    /// orders what it is given. `Area.order` and `Project.order` both default to 0, so the identity
    /// leg decides membership at the window's edge for every list made outside the reorder UI.
    static func lists(areas: [Area], projects: [Project], limit: Int = .max) -> (areas: [Area], projects: [Project]) {
        enum Item {
            case area(Area)
            case project(Project)
        }
        let window = CadenceSearchSuggestionWindow.take(
            areas.map(Item.area) + projects.map(Item.project),
            limit: limit,
            identity: { item in
                switch item {
                case .area(let area): CadenceSearchIdentity.area(area.id)
                case .project(let project): CadenceSearchIdentity.project(project.id)
                }
            },
            orderedBefore: { lhs, rhs in
                func rank(_ item: Item) -> CadenceSearchSuggestionRank {
                    switch item {
                    case .area(let area): CadenceSearchSuggestionRank(table: 0, order: area.order)
                    case .project(let project): CadenceSearchSuggestionRank(table: 1, order: project.order)
                    }
                }
                return rank(lhs) < rank(rhs)
            }
        )
        return window.reduce(into: (areas: [Area](), projects: [Project]())) { out, item in
            switch item {
            case .area(let area): out.areas.append(area)
            case .project(let project): out.projects.append(project)
            }
        }
    }

    /// Most recently edited first, ties broken by identity (T-498). Two notes share an `updatedAt`
    /// whenever one write touched both — a migration pass, an import, a bulk tag edit — which is
    /// exactly when a window gets cut out of a partial order. Which *kinds* a section draws stays the
    /// caller's (the palette gives event notes their own section); this only orders what it is given.
    static func notes(_ notes: [Note], limit: Int = .max) -> [Note] {
        CadenceSearchSuggestionWindow.take(
            notes.filter(hasVisibleText),
            limit: limit,
            identity: { CadenceSearchIdentity.note($0.id) },
            orderedBefore: { $0.updatedAt > $1.updatedAt }
        )
    }
}
