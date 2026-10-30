#if os(macOS)
import SwiftUI
import EventKit

struct GlobalSearchIndexedSource {
    let sections: [GlobalSearchSection]
}

/// **Where a list document opens, and the one reason one is not offered at all** (T-3084).
///
/// A `.list` note is reached through its list's **Documents** tab, not through the Notes page:
/// `NotesNavigationManager.page(for: .list)` is `nil` and stays `nil`, because there is no Notes
/// page for one to land on. That `nil` is also why the palette dropped list documents for a year
/// — the candidate gate asked the Notes page whether it could open a note and took "no" for "not
/// a note".
///
/// **One type answers both halves**: whether a row exists for the note, which
/// `GlobalSearchIndexSupport.noteSubtitle(for:)` asks, and where selecting the row goes, which
/// `RootCommandActionSupport.handleSearchSelection` asks. The defect this ticket was reopened for
/// is a hit that cannot be opened, so the gate and the destination must not be able to disagree
/// about a note; keeping them one function is what makes that structural rather than remembered.
///
/// **Area before project**, which is the order `NoteReferencePanelSupport` already names a list
/// note's container in and the order `GlobalSearchIndexSupport.listNoteSubtitle(for:)` repeats, so
/// the list the row names is the list the row opens. A note carrying both relationships is filed
/// in both columns by `CadenceListNoteSupport.notes(for:project:in:)`; this picks one of two real
/// homes rather than guessing at an impossible state.
enum GlobalSearchListNoteRoute: Equatable {
    case area(UUID)
    case project(UUID)

    /// `nil` for every kind but `.list`, and for a list document filed under no list.
    static func route(for note: Note) -> GlobalSearchListNoteRoute? {
        guard note.kind == .list else { return nil }
        if let area = note.area { return .area(area.id) }
        if let project = note.project { return .project(project.id) }
        return nil
    }

    /// The sidebar row the Documents tab is opened inside.
    var sidebarItem: SidebarItem {
        switch self {
        case .area(let id): .area(id)
        case .project(let id): .project(id)
        }
    }
}

enum GlobalSearchIndexSupport {
    static func buildIndexedSource(
        query: String,
        hiddenTabs: Set<SidebarStaticDestination>,
        areas: [Area],
        projects: [Project],
        tasks: [AppTask],
        notes: [Note],
        eventResults: [GlobalSearchResult],
        sidebarTabColorsRaw: String,
        includesCompletedTasks: Bool
    ) -> GlobalSearchIndexedSource {
        var sections: [GlobalSearchSection] = []

        appendSection(
            .commands,
            results: commandResults(query: query, sidebarTabColorsRaw: sidebarTabColorsRaw),
            query: query,
            into: &sections
        )
        appendSection(
            .pages,
            results: pageResults(query: query, hiddenTabs: hiddenTabs, sidebarTabColorsRaw: sidebarTabColorsRaw),
            query: query,
            into: &sections
        )
        appendSection(.areas, results: areaResults(areas: areas, query: query), query: query, into: &sections)
        appendSection(.projects, results: projectResults(projects: projects, query: query), query: query, into: &sections)
        appendSection(
            .tasks,
            results: taskResults(tasks: tasks, query: query, includingCompleted: includesCompletedTasks),
            query: query,
            into: &sections
        )
        appendSection(.events, results: eventResults, query: query, into: &sections)
        let taskTitles = MarkdownTaskEmbedTitleCache.titles(for: tasks)
        appendSection(
            .meetingNotes,
            results: eventNoteResults(
                notes: notes,
                query: query,
                taskTitles: taskTitles
            ),
            query: query,
            into: &sections
        )
        appendSection(
            .notes,
            results: noteResults(notes: notes, query: query, taskTitles: taskTitles),
            query: query,
            into: &sections
        )

        return GlobalSearchIndexedSource(sections: sections)
    }

    static func appendSection(
        _ category: GlobalSearchCategory,
        results: [GlobalSearchResult],
        query: String,
        into sections: inout [GlobalSearchSection]
    ) {
        guard !results.isEmpty else { return }
        sections.append(.init(category: category, results: results, cap: resultCap(for: category, query: query)))
    }

    /// How many rows a section lists before its continuation row — **the whole of what used to be
    /// a `prefix` inside each `*Results` function** (T-1473).
    ///
    /// **The numbers did not change and were not meant to.** The owner considered raising them and
    /// rejected it: a large enough result set truncates silently again, which is the same defect at
    /// a higher threshold. What changed is that the four functions below now return *everything*
    /// they matched, so the count a section withholds is a number that exists and can be said out
    /// loud, and the rows behind it can be revealed in place.
    ///
    /// **The idle numbers are lower than the live ones on purpose.** An empty field is a suggestion
    /// list rather than an answer, so it shows a shorter sample of a set the user never narrowed.
    ///
    /// `Int.max` for the five uncapped categories rather than an optional: Commands and Pages are
    /// fixed catalogs of six and seven, and Areas and Projects have never been capped here. Making
    /// "no cap" a number keeps one arithmetic path through `CadenceSearchResultCap`, where an
    /// optional would mean every caller branching before it could ask for a count.
    static func resultCap(for category: GlobalSearchCategory, query: String) -> Int {
        let isIdle = !CadenceListSearchSupport.isSearching(query)
        switch category {
        case .tasks: return isIdle ? 10 : 14
        case .events: return isIdle ? 6 : 12
        case .meetingNotes, .notes: return isIdle ? 8 : 12
        case .commands, .pages, .areas, .projects: return .max
        }
    }

    /// `sidebarTabColorsRaw` is `CadencePreferenceKeys.sidebarTabColors` — the same preference
    /// Settings → Sidebar writes and both sidebars read. Threading it this far is the point of
    /// T-244: the palette hand-assigned its own `Theme` accents and never read this string, so a
    /// retinted destination kept its old colour here.
    static func commandResults(query: String, sidebarTabColorsRaw: String) -> [GlobalSearchResult] {
        let preparedQuery = CadenceSearchMatcher.PreparedQuery(query)
        return rankedResults(
            GlobalSearchCommandDefinition.all.compactMap { definition in
                guard matches(query: preparedQuery, fields: [definition.title, definition.subtitle, definition.aliases]) else { return nil }
                return GlobalSearchResult(
                    id: CadenceSearchIdentity.command(definition.command.rawValue),
                    category: .commands,
                    title: definition.title,
                    subtitle: definition.subtitle,
                    icon: definition.icon,
                    tintHex: definition.tintHex(sidebarTabColorsRaw: sidebarTabColorsRaw),
                    destination: .command(definition.command)
                )
            },
            query: query, preparedQuery: preparedQuery
        )
    }

    static func pageResults(
        query: String,
        hiddenTabs: Set<SidebarStaticDestination>,
        sidebarTabColorsRaw: String
    ) -> [GlobalSearchResult] {
        let preparedQuery = CadenceSearchMatcher.PreparedQuery(query)
        return rankedResults(GlobalSearchPageDefinition.all.compactMap { page in
            // A destination the sidebar does not route to as a page cannot be a palette row.
            // Every entry in the catalog has one; this is the guard rather than a fallback so a
            // future `.lists` or `.search` entry drops out instead of opening the wrong page.
            guard let item = page.item else { return nil }
            let subtitle = if let toggleable = page.toggleable, hiddenTabs.contains(toggleable) {
                "\(page.baseSubtitle) • Hidden from sidebar"
            } else {
                page.baseSubtitle
            }
            guard matches(query: preparedQuery, fields: [page.label, subtitle, page.aliases]) else { return nil }
            return GlobalSearchResult(
                id: CadenceSearchIdentity.page(page.label),
                category: .pages,
                title: page.label,
                subtitle: subtitle,
                icon: page.icon,
                tintHex: page.tintHex(sidebarTabColorsRaw: sidebarTabColorsRaw),
                destination: .sidebar(item)
            )
        }, query: query, preparedQuery: preparedQuery)
    }

    /// Which lists search can see, and which words reach them, is `CadenceListSearchSupport`'s
    /// decision — the T-378 rule is recorded there. The subtitle below is this surface's own row
    /// rendering, built from the shared lifecycle fact rather than from a second
    /// `isArchived ? … : isDone ? …` chain, which labelled a *cancelled* project "Active".
    /// The open count reads through `GoalLinkTarget.openTaskLabel(count:)`, so one open task says
    /// "1 active task" rather than the hand-spelled "1 active tasks" ([[T-4455]]).
    static func areaResults(areas: [Area], query: String) -> [GlobalSearchResult] {
        let preparedQuery = CadenceSearchMatcher.PreparedQuery(query)
        return rankedResults(areas.compactMap { area in
            guard CadenceListSearchSupport.isSearchable(area, query: query) else { return nil }
            let contextName = area.context?.name ?? "No context"
            guard matches(query: preparedQuery, fields: CadenceListSearchSupport.searchFields(for: area)) else { return nil }
            return GlobalSearchResult(
                id: CadenceSearchIdentity.area(area.id),
                category: .areas,
                // [[T-7202]]: a blank name drew a row with no title; iOS Search's list rows
                // already say "Untitled Area" / "Untitled Project".
                title: CadenceTitleNormalization.display(area.name, fallback: CadenceTitleNormalization.defaultAreaName),
                subtitle: "\(contextName) • \(GoalLinkTarget.openTaskLabel(count: CadenceTaskQuerySupport.openTaskCount(for: area))) • \(CadenceListSearchSupport.lifecycle(of: area).statusLabel)",
                icon: area.icon,
                tintHex: area.colorHex,
                destination: .area(area.id)
            )
        }, query: query, preparedQuery: preparedQuery)
    }

    static func projectResults(projects: [Project], query: String) -> [GlobalSearchResult] {
        let preparedQuery = CadenceSearchMatcher.PreparedQuery(query)
        return rankedResults(projects.compactMap { project in
            guard CadenceListSearchSupport.isSearchable(project, query: query) else { return nil }
            let contextName = project.context?.name ?? "No context"
            let areaName = project.area?.name
            let summary = [contextName, areaName].compactMap { $0 }.joined(separator: " • ")
            guard matches(query: preparedQuery, fields: CadenceListSearchSupport.searchFields(for: project)) else { return nil }
            return GlobalSearchResult(
                id: CadenceSearchIdentity.project(project.id),
                category: .projects,
                title: CadenceTitleNormalization.display(project.name, fallback: CadenceTitleNormalization.defaultProjectName),
                subtitle: "\(summary) • \(GoalLinkTarget.openTaskLabel(count: CadenceTaskQuerySupport.openTaskCount(for: project))) • \(CadenceListSearchSupport.lifecycle(of: project).statusLabel)",
                icon: project.icon,
                tintHex: project.colorHex,
                destination: .project(project.id)
            )
        }, query: query, preparedQuery: preparedQuery)
    }

    /// **Completed work is excluded unless the caller asks for it** (T-1476), which is the iOS
    /// behaviour the owner chose as the shared one. The palette used to pass `true`
    /// unconditionally and offer no way to say otherwise, so the same query answered differently
    /// on a Mac and on an iPhone. Fields, aliases and the glyph state come from
    /// `CadenceTaskSearchSupport` so the two surfaces cannot drift apart again (T-377) — what
    /// stays here is the row: this subtitle, and the symbol names the desktop draws.
    ///
    /// **The default is the decision, not a convenience.** `false` is what the owner settled on
    /// for both platforms, so a call site that forgets to say gets the decided behaviour rather
    /// than the old one — and the free test suite catches the difference, because
    /// `CadenceSearchCandidateSupportTests` searches a fixture whose only match is completed.
    ///
    /// The surface that flips it is a persisted user setting
    /// (`CadencePreferenceKeys.searchIncludesCompletedTasks`), not a second inclusion policy:
    /// which tasks are searchable *at all* stays `CadenceTaskSearchSupport`'s to say, and
    /// cancelled work is never searchable either way.
    ///
    /// **An empty query suggests rather than ranks** ([[T-8764]]): today's and overdue open work in
    /// `CadenceSearchIdleSuggestions` order, the rule iOS Search reads. Ranking an empty query scores
    /// every task alike and breaks the tie on title, which listed the first ten tasks A to Z.
    static func taskResults(
        tasks: [AppTask],
        query: String,
        includingCompleted: Bool = false,
        today: String = DateFormatters.todayKey()
    ) -> [GlobalSearchResult] {
        let base = tasks
            .filter { CadenceTaskSearchSupport.isSearchable($0, includingCompleted: includingCompleted) }

        guard CadenceListSearchSupport.isSearching(query) else {
            return CadenceSearchIdleSuggestions.tasks(base, today: today).map { taskResult(for: $0) }
        }

        let preparedQuery = CadenceSearchMatcher.PreparedQuery(query)
        return rankedResults(base.compactMap { task in
            guard matches(query: preparedQuery, fields: CadenceTaskSearchSupport.searchFields(for: task)) else { return nil }
            return taskResult(for: task)
        }, query: query, preparedQuery: preparedQuery)
    }

    /// One palette task row.
    static func taskResult(for task: AppTask) -> GlobalSearchResult {
        let container = CadenceTaskSearchSupport.containerLabel(for: task)
        let tags = task.sortedTags

        let meta: [String] = [
            container,
            tags.isEmpty ? nil : tags.map(\.name).joined(separator: ", "),
            task.scheduledDate.isEmpty ? nil : "Do \(DateFormatters.relativeDate(from: task.scheduledDate))",
            task.dueDate.isEmpty ? nil : "Due \(DateFormatters.relativeDate(from: task.dueDate))",
            task.isDone ? "Completed" : "Active"
        ].compactMap { $0 }

        return GlobalSearchResult(
            id: CadenceSearchIdentity.task(task.id),
            category: .tasks,
            title: TaskTitleSupport.displayTitle(task.title),
            subtitle: meta.joined(separator: " • "),
            icon: taskIcon(for: CadenceTaskSearchSupport.glyph(for: task)),
            tintHex: task.containerColor,
            destination: .task(task.id)
        )
    }

    /// How many tasks the query matches that the Completed filter is holding back ([[T-6971]]).
    /// The rule lives in `CadenceTaskSearchSupport.withheldCompletedMatchCount` so iOS Search
    /// counts the same rows ([[T-6975]]); this name stays as the palette's entry point.
    static func withheldCompletedTaskMatchCount(
        tasks: [AppTask],
        query: String,
        includingCompleted: Bool
    ) -> Int {
        CadenceTaskSearchSupport.withheldCompletedMatchCount(
            tasks: tasks,
            query: query,
            includingCompleted: includingCompleted
        )
    }

    /// The desktop's symbols for the three shared glyph states. `completed` and `active` draw the
    /// same circle here on purpose: this row already carries the word "Completed" or "Active" at
    /// the end of its subtitle, which an iOS row has no room for.
    static func taskIcon(for glyph: CadenceTaskSearchGlyph) -> String {
        switch glyph {
        case .scheduled: "calendar.badge.clock"
        case .completed, .active: "checkmark.circle"
        }
    }

    /// `events` arrives from `searchEvents`, so it is already filtered against the query and
    /// sorted chronologically. What is left to decide is which of them the section shows.
    ///
    /// Truncating *before* ranking — `events.prefix(12)` then `rankedResults` — ranked the twelve
    /// chronologically earliest matches rather than the twelve best, so a query's strongest match
    /// was dropped before scoring ever saw it if twelve weaker ones happened to fall earlier in
    /// the window. Every other section here already ranks first and prefixes second.
    ///
    /// The empty-query branch stays **unranked** on purpose, and is not the same bug:
    /// `searchEvents` has already answered "what is coming up" in chronological order, so the
    /// earliest ones *are* the answer. Ranking them would be worse, not merely redundant — an
    /// empty query scores everything equally, and `CadenceSearchMatcher.rank` breaks that tie on
    /// title, which would have ordered a 365-day window alphabetically. This is the shape
    /// `iOSSearchView.eventResults` already had: chronological when idle, scored when searching.
    ///
    /// **Neither branch truncates any more** (T-1473). The six-and-twelve are unchanged as
    /// *numbers* and now live in `resultCap(for:query:)`, where the section that draws them can
    /// also say how many it is holding back. Returning the full list is what makes that count
    /// expressible; the idle branch's chronological order is what makes revealing the rest mean
    /// "the next events", which is the only order an idle list could continue in.
    static func eventResults(
        from events: [EKEvent],
        query: String,
        relativeTo referenceDate: Date = Date()
    ) -> [GlobalSearchResult] {
        guard CadenceListSearchSupport.isSearching(query) else {
            // Closures rather than `map(eventResult(for:))`: a method *reference* is passed as a
            // nonisolated function value and loses this enum's main-actor isolation.
            return events.map { eventResult(for: $0, relativeTo: referenceDate) }
        }
        return rankedResults(events.map { eventResult(for: $0, relativeTo: referenceDate) }, query: query)
    }

    /// The day reads "Sat, Mar 28" in the reference date's year and "Sat, Mar 28, 2027" outside it
    /// (`DateFormatters.absoluteDay`, [[T-6252]]): the window runs 60 days back to 365 forward, so a
    /// recurring event's occurrences a year apart otherwise read identically.
    static func eventResult(for event: EKEvent, relativeTo referenceDate: Date = Date()) -> GlobalSearchResult {
        let item = CalendarEventItem(event: event)
        let startDate = event.startDate ?? Date()
        let timeLabel = "\(DateFormatters.dayOfWeek.string(from: startDate)), \(DateFormatters.absoluteDay(startDate, relativeTo: referenceDate))"
        // All-day events reach this list now that `searchEvents` stopped dropping them, and
        // `CalendarEventItem` clamps one to 00:00 + 1440 minutes — which reads as
        // "12:00 AM – 12:00 AM". iOS already says "All day" here; so does this.
        // A timed row names the whole event, not its start day ([[T-8752]]): `item` is clipped to
        // the start day, which printed a 10 PM -> 2 AM event as "10 PM – 12 AM". Same rule as
        // iOS Search's row (`iOSCalendarEventSupport.timeRangeLabel(for:)`, [[T-8574]]).
        let timeRange = event.isAllDay
            ? "All day"
            : CadenceScheduleSupport.eventListTimeRangeLabel(
                from: startDate,
                to: event.endDate ?? startDate.addingTimeInterval(30 * 60)
            )
        let subtitle = [
            item.calendarTitle,
            timeLabel,
            timeRange
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")

        return GlobalSearchResult(
            id: CadenceSearchIdentity.event(item.id),
            category: .events,
            title: item.title,
            subtitle: subtitle,
            icon: "calendar",
            tintHex: item.calendarColor.globalSearchHexString() ?? Theme.purpleHex,
            destination: .event(item.id)
        )
    }

    /// `taskTitles` names the note's task embeds from the live task rather than from the title
    /// cached in `[[task:UUID|Title]]`, so renaming a task makes the note findable under its new
    /// name and stops matching the old one. Built once for the whole pass, not per note.
    static func eventNoteResults(
        notes: [Note],
        query: String,
        taskTitles: [UUID: String],
        relativeTo referenceDate: Date = Date()
    ) -> [GlobalSearchResult] {
        let preparedQuery = CadenceSearchMatcher.PreparedQuery(query)
        // Idle, the section is the most recently edited event notes, unranked ([[T-8764]]): ranking
        // an empty query ties every row and breaks the tie on title, which read A to Z. Searching,
        // `rankedResults` is a total order, so the input order does not matter.
        let isSearching = CadenceListSearchSupport.isSearching(query)
        let meetingNotes = notes.filter { $0.kind == .meeting }
        let ordered = isSearching ? meetingNotes : CadenceSearchIdleSuggestions.notes(meetingNotes)

        let rows: [GlobalSearchResult] = ordered.compactMap { note in
            let title = note.displayTitle
            let dateLabel: String
            if let date = DateFormatters.date(from: note.eventDateKey) {
                if note.eventStartMin >= 0, note.eventEndMin >= 0 {
                    dateLabel = "\(DateFormatters.absoluteDay(date, relativeTo: referenceDate)) • \(TimeFormatters.timeRange(startMin: note.eventStartMin, endMin: note.eventEndMin))"
                } else {
                    dateLabel = DateFormatters.absoluteDay(date, relativeTo: referenceDate)
                }
            } else {
                dateLabel = "Event note"
            }
            let tagText = CadenceSearchTagSupport.text(for: note.sortedTags)
            let content = MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)
            guard matches(query: preparedQuery, fields: [title, content, dateLabel, tagText]) else { return nil }
            return GlobalSearchResult(
                id: CadenceSearchIdentity.eventNote(note.id),
                category: .meetingNotes,
                title: title,
                subtitle: dateLabel,
                icon: "doc.text",
                tintHex: Theme.purpleHex,
                destination: .eventNote(note.id)
            )
        }
        guard isSearching else { return rows }
        return rankedResults(rows, query: query, preparedQuery: preparedQuery)
    }

    /// **Every note kind the Notes page or a list's Documents tab can open** (T-3084).
    ///
    /// The candidate gate used to be a `filter` on `NotesNavigationManager.page(for:) != nil`
    /// *plus* a second `case .list, .meeting: return nil` inside the switch — two gates saying the
    /// same thing, and the one a reader reached first said nothing about why. There is one gate
    /// now: `noteSubtitle(for:)` returns `nil` for exactly the notes this section does not draw,
    /// so adding a `NoteKind` makes that switch non-exhaustive instead of silently dropping it.
    ///
    /// **An empty query suggests the most recently edited notes** ([[T-8764]]), in
    /// `CadenceSearchIdleSuggestions` order as iOS Search does, rather than ranking every note alike
    /// and listing them A to Z.
    static func noteResults(notes: [Note], query: String, taskTitles: [UUID: String]) -> [GlobalSearchResult] {
        guard CadenceListSearchSupport.isSearching(query) else {
            return CadenceSearchIdleSuggestions.notes(notes.filter { noteSubtitle(for: $0) != nil })
                .compactMap { note in
                    noteSubtitle(for: note).map { noteResult(note, subtitle: $0, taskTitles: taskTitles) }
                }
        }
        let preparedQuery = CadenceSearchMatcher.PreparedQuery(query)
        return rankedResults(notes.compactMap { note -> GlobalSearchResult? in
            guard let subtitle = noteSubtitle(for: note) else { return nil }
            let title = NoteReferencePanelSupport.searchTitle(note)
            let content = MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)
            let tags = CadenceSearchTagSupport.text(for: note.sortedTags)
            let fields = [title, content, subtitle, tags] + NoteReferencePanelSupport.searchKeyFields(note)
            guard matches(query: preparedQuery, fields: fields) else { return nil }
            return noteResult(note, subtitle: subtitle, taskTitles: taskTitles)
        }, query: query, preparedQuery: preparedQuery)
    }

    /// One Notes row; `subtitle` is `noteSubtitle(for:)`'s, which is also the gate. `detail` is
    /// the body excerpt iOS Search shows under the same note, from the one shared rule ([[T-8763]]).
    static func noteResult(_ note: Note, subtitle: String, taskTitles: [UUID: String]) -> GlobalSearchResult {
        GlobalSearchResult(
            id: CadenceSearchIdentity.note(note.id), category: .notes,
            title: NoteReferencePanelSupport.searchTitle(note), subtitle: subtitle, icon: "doc.text",
            tintHex: Theme.purpleHex, destination: .note(note.id),
            detail: CadenceSearchNoteExcerpt.text(for: note, taskTitles: taskTitles)
        )
    }

    /// The Notes row's subtitle, **and the section's whole candidate gate**: `nil` means this
    /// section does not draw the note at all.
    ///
    /// Two kinds return `nil`, for unrelated reasons. `.meeting` has its own **Event Notes**
    /// section one row group up and must not appear twice. A `.list` document filed under no list
    /// has nowhere to open — `GlobalSearchListNoteRoute` is the only route to one — and the defect
    /// this ticket was reopened for is a hit that cannot be opened, so it is not offered.
    ///
    /// The dated lines name the day or week in words ([[T-7205]] (a)) — `Daily • Oct 26`,
    /// `Weekly • Oct 26 – Nov 1` — through the same `NoteReferencePanelSupport.datedName` iOS
    /// Search reads, so the two platforms say one date. The storage key stays a match field.
    static func noteSubtitle(for note: Note) -> String? {
        switch note.kind {
        case .daily: return "Daily • \(NoteReferencePanelSupport.datedName(note) ?? note.dateKey)"
        case .weekly: return "Weekly • \(NoteReferencePanelSupport.datedName(note) ?? note.weekKey)"
        case .permanent: return "Notepad"
        case .list:
            guard GlobalSearchListNoteRoute.route(for: note) != nil else { return nil }
            return listNoteSubtitle(for: note)
        case .meeting: return nil
        }
    }

    /// "List • Marketing", or the bare kind when the list it is filed under has a blank name.
    ///
    /// Same shape as the `Daily •` / `Weekly •` lines beside it, and the same area-before-project
    /// preference `GlobalSearchListNoteRoute.route(for:)` routes by, so the list this row names is
    /// the list selecting it opens. `NoteReferencePanelSupport.noteKindDetail` answers the same
    /// question for iOS but answers it without the kind prefix, which would read as an untitled
    /// row here.
    static func listNoteSubtitle(for note: Note) -> String {
        let container = [note.area?.name, note.project?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let container else { return "List" }
        return "List • \(container)"
    }

    /// **T-372a: `id` is the tie-break.** `GlobalSearchResult.id` is already the
    /// category-prefixed entity id every row here is built with (`"task-<uuid>"`,
    /// `"event-note-<uuid>"`), so it is both stable across rebuilds of the index and unique
    /// across the categories this list merges. Those nine spellings are
    /// `CadenceSearchIdentity`'s since T-479, unchanged in value: the iOS search surface needed
    /// the same strings, and a tenth hand-typed `"task-\(uuid)"` is how two surfaces come to
    /// disagree about the prefix for one entity. Two tasks called "Admin" in two lists score the
    /// same and title the same, and without this leg `Cmd+K` listed them in whichever order the
    /// `@Query` happened to hand over — so the arrow keys landed on a different one between
    /// keystrokes.
    static func rankedResults(
        _ results: [GlobalSearchResult],
        query: String,
        preparedQuery: CadenceSearchMatcher.PreparedQuery? = nil
    ) -> [GlobalSearchResult] {
        CadenceSearchMatcher.rank(
            results,
            query: preparedQuery ?? CadenceSearchMatcher.PreparedQuery(query),
            title: { $0.title },
            fields: { [$0.title, $0.subtitle] },
            identity: { $0.id }
        )
    }

    static func matches(query: CadenceSearchMatcher.PreparedQuery, fields: [String]) -> Bool {
        CadenceSearchMatcher.matchScore(query: query, fields: fields) != nil
    }
}
#endif
