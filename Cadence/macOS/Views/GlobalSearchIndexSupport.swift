#if os(macOS)
import SwiftUI
import EventKit

struct GlobalSearchIndexedSource {
    let sections: [GlobalSearchSection]
}

enum GlobalSearchIndexSupport {
    static func buildIndexedSource(
        query: String,
        hiddenTabs: Set<SidebarStaticDestination>,
        areas: [Area],
        projects: [Project],
        tasks: [AppTask],
        notes: [Note],
        goals: [Goal],
        habits: [Habit],
        eventResults: [GlobalSearchResult],
        sidebarTabColorsRaw: String
    ) -> GlobalSearchIndexedSource {
        var sections: [GlobalSearchSection] = []

        appendSection(
            .commands,
            results: commandResults(query: query, sidebarTabColorsRaw: sidebarTabColorsRaw),
            into: &sections
        )
        appendSection(
            .pages,
            results: pageResults(query: query, hiddenTabs: hiddenTabs, sidebarTabColorsRaw: sidebarTabColorsRaw),
            into: &sections
        )
        appendSection(.areas, results: areaResults(areas: areas, query: query), into: &sections)
        appendSection(.projects, results: projectResults(projects: projects, query: query), into: &sections)
        appendSection(.tasks, results: taskResults(tasks: tasks, query: query), into: &sections)
        appendSection(.events, results: eventResults, into: &sections)
        appendSection(
            .meetingNotes,
            results: eventNoteResults(
                notes: notes,
                query: query,
                taskTitles: MarkdownTaskEmbedTitleCache.titles(for: tasks)
            ),
            into: &sections
        )
        appendSection(.goals, results: goalResults(goals: goals, query: query), into: &sections)
        appendSection(.habits, results: habitResults(habits: habits, query: query), into: &sections)

        return GlobalSearchIndexedSource(sections: sections)
    }

    static func appendSection(
        _ category: GlobalSearchCategory,
        results: [GlobalSearchResult],
        into sections: inout [GlobalSearchSection]
    ) {
        guard !results.isEmpty else { return }
        sections.append(.init(category: category, results: results))
    }

    /// `sidebarTabColorsRaw` is `CadencePreferenceKeys.sidebarTabColors` — the same preference
    /// Settings → Sidebar writes and both sidebars read. Threading it this far is the point of
    /// T-244: the palette hand-assigned its own `Theme` accents and never read this string, so a
    /// retinted destination kept its old colour here.
    static func commandResults(query: String, sidebarTabColorsRaw: String) -> [GlobalSearchResult] {
        rankedResults(
            GlobalSearchCommandDefinition.all.compactMap { definition in
                guard matches(query: query, fields: [definition.title, definition.subtitle, definition.aliases]) else { return nil }
                return GlobalSearchResult(
                    id: "command-\(definition.command.rawValue)",
                    category: .commands,
                    title: definition.title,
                    subtitle: definition.subtitle,
                    icon: definition.icon,
                    tintHex: definition.tintHex(sidebarTabColorsRaw: sidebarTabColorsRaw),
                    destination: .command(definition.command)
                )
            },
            query: query
        )
    }

    static func pageResults(
        query: String,
        hiddenTabs: Set<SidebarStaticDestination>,
        sidebarTabColorsRaw: String
    ) -> [GlobalSearchResult] {
        rankedResults(GlobalSearchPageDefinition.all.compactMap { page in
            // A destination the sidebar does not route to as a page cannot be a palette row.
            // Every entry in the catalog has one; this is the guard rather than a fallback so a
            // future `.lists` or `.search` entry drops out instead of opening the wrong page.
            guard let item = page.item else { return nil }
            let subtitle = if let toggleable = page.toggleable, hiddenTabs.contains(toggleable) {
                "\(page.baseSubtitle) • Hidden from sidebar"
            } else {
                page.baseSubtitle
            }
            guard matches(query: query, fields: [page.label, subtitle, page.aliases]) else { return nil }
            return GlobalSearchResult(
                id: "page-\(page.label)",
                category: .pages,
                title: page.label,
                subtitle: subtitle,
                icon: page.icon,
                tintHex: page.tintHex(sidebarTabColorsRaw: sidebarTabColorsRaw),
                destination: .sidebar(item)
            )
        }, query: query)
    }

    /// Which lists search can see, and which words reach them, is `CadenceListSearchSupport`'s
    /// decision — the T-378 rule is recorded there. The subtitle below is this surface's own row
    /// rendering, built from the shared lifecycle fact rather than from a second
    /// `isArchived ? … : isDone ? …` chain, which labelled a *cancelled* project "Active".
    static func areaResults(areas: [Area], query: String) -> [GlobalSearchResult] {
        rankedResults(areas.compactMap { area in
            guard CadenceListSearchSupport.isSearchable(area, query: query) else { return nil }
            let contextName = area.context?.name ?? "No context"
            guard matches(query: query, fields: CadenceListSearchSupport.searchFields(for: area)) else { return nil }
            return GlobalSearchResult(
                id: "area-\(area.id.uuidString)",
                category: .areas,
                title: area.name,
                subtitle: "\(contextName) • \(CadenceTaskQuerySupport.openTaskCount(for: area)) active tasks • \(CadenceListSearchSupport.lifecycle(of: area).statusLabel)",
                icon: area.icon,
                tintHex: area.colorHex,
                destination: .area(area.id)
            )
        }, query: query)
    }

    static func projectResults(projects: [Project], query: String) -> [GlobalSearchResult] {
        rankedResults(projects.compactMap { project in
            guard CadenceListSearchSupport.isSearchable(project, query: query) else { return nil }
            let contextName = project.context?.name ?? "No context"
            let areaName = project.area?.name
            let summary = [contextName, areaName].compactMap { $0 }.joined(separator: " • ")
            guard matches(query: query, fields: CadenceListSearchSupport.searchFields(for: project)) else { return nil }
            return GlobalSearchResult(
                id: "project-\(project.id.uuidString)",
                category: .projects,
                title: project.name,
                subtitle: "\(summary) • \(CadenceTaskQuerySupport.openTaskCount(for: project)) active tasks • \(CadenceListSearchSupport.lifecycle(of: project).statusLabel)",
                icon: project.icon,
                tintHex: project.colorHex,
                destination: .project(project.id)
            )
        }, query: query)
    }

    /// The palette always includes completed tasks; iOS asks the same helper with its "Completed"
    /// toggle. Fields, aliases and the glyph state come from `CadenceTaskSearchSupport` so the two
    /// surfaces cannot drift apart again (T-377) — what stays here is the row: this subtitle, and
    /// the symbol names the desktop draws.
    static func taskResults(tasks: [AppTask], query: String) -> [GlobalSearchResult] {
        let base = tasks
            .filter { CadenceTaskSearchSupport.isSearchable($0, includingCompleted: true) }
            .sorted {
                if $0.isDone != $1.isDone { return !$0.isDone && $1.isDone }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt > $1.createdAt
            }

        return Array(rankedResults(base.compactMap { task in
            let container = CadenceTaskSearchSupport.containerLabel(for: task)
            guard matches(query: query, fields: CadenceTaskSearchSupport.searchFields(for: task)) else { return nil }

            let meta: [String] = [
                container,
                task.sortedTags.isEmpty ? nil : task.sortedTags.map(\.name).joined(separator: ", "),
                task.scheduledDate.isEmpty ? nil : "Do \(DateFormatters.relativeDate(from: task.scheduledDate))",
                task.dueDate.isEmpty ? nil : "Due \(DateFormatters.relativeDate(from: task.dueDate))",
                task.isDone ? "Completed" : "Active"
            ].compactMap { $0 }

            return GlobalSearchResult(
                id: "task-\(task.id.uuidString)",
                category: .tasks,
                title: task.title.isEmpty ? "Untitled Task" : task.title,
                subtitle: meta.joined(separator: " • "),
                icon: taskIcon(for: CadenceTaskSearchSupport.glyph(for: task)),
                tintHex: task.containerColor,
                destination: .task(task.id)
            )
        }, query: query).prefix(query.isEmpty ? 10 : 14))
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

    static func goalResults(goals: [Goal], query: String) -> [GlobalSearchResult] {
        Array(rankedResults(goals.compactMap { goal in
            let contextName = goal.context?.name ?? "No context"
            let parentName = goal.parentGoal?.title ?? ""
            guard matches(query: query, fields: [goal.title, goal.desc, contextName, parentName, goal.kind.label]) else { return nil }
            return GlobalSearchResult(
                id: "goal-\(goal.id.uuidString)",
                category: .goals,
                title: goal.title,
                subtitle: "\(parentName.isEmpty ? contextName : parentName) • \(Int(goal.progress * 100))% complete",
                icon: goal.icon,
                tintHex: goal.colorHex,
                destination: .goals
            )
        }, query: query).prefix(query.isEmpty ? 6 : 10))
    }

    static func habitResults(habits: [Habit], query: String) -> [GlobalSearchResult] {
        Array(rankedResults(habits.compactMap { habit in
            let contextName = habit.context?.name ?? "No context"
            let goalName = habit.goal?.title ?? ""
            guard matches(query: query, fields: [habit.title, contextName, goalName]) else { return nil }
            return GlobalSearchResult(
                id: "habit-\(habit.id.uuidString)",
                category: .habits,
                title: habit.title,
                subtitle: "\(goalName.isEmpty ? contextName : goalName) • \(habit.streakUnit.phrase(habit.currentStreak))",
                icon: habit.icon,
                tintHex: habit.colorHex,
                destination: .habits
            )
        }, query: query).prefix(query.isEmpty ? 6 : 10))
    }

    /// `events` arrives from `searchEvents`, so it is already filtered against the query and
    /// sorted chronologically. What is left to decide is which of them the section shows.
    ///
    /// Truncating *before* ranking — `events.prefix(12)` then `rankedResults` — ranked the twelve
    /// chronologically earliest matches rather than the twelve best, so a query's strongest match
    /// was dropped before scoring ever saw it if twelve weaker ones happened to fall earlier in
    /// the window. Every other section here already ranks first and prefixes second.
    ///
    /// The empty-query branch keeps the truncate-first shape on purpose, and is not the same bug:
    /// `searchEvents` has already answered "what is coming up" in chronological order, so the
    /// first six *are* the answer. Ranking them would be worse, not merely redundant — an empty
    /// query scores everything equally, and `CadenceSearchMatcher.rank` breaks that tie on title,
    /// which would have picked six events alphabetically out of a 365-day window. This is the
    /// shape `iOSSearchView.eventResults` already had: chronological when idle, scored when
    /// searching.
    static func eventResults(from events: [EKEvent], query: String) -> [GlobalSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Closures rather than `map(eventResult(for:))`: a method *reference* is passed as a
            // nonisolated function value and loses this enum's main-actor isolation.
            return events.prefix(6).map { eventResult(for: $0) }
        }
        return Array(rankedResults(events.map { eventResult(for: $0) }, query: query).prefix(12))
    }

    static func eventResult(for event: EKEvent) -> GlobalSearchResult {
        let item = CalendarEventItem(event: event)
        let startDate = event.startDate ?? Date()
        let timeLabel = "\(DateFormatters.dayOfWeek.string(from: startDate)), \(DateFormatters.shortDate.string(from: startDate))"
        // All-day events reach this list now that `searchEvents` stopped dropping them, and
        // `CalendarEventItem` clamps one to 00:00 + 1440 minutes — which reads as
        // "12:00 AM – 12:00 AM". iOS already says "All day" here; so does this.
        let timeRange = event.isAllDay
            ? "All day"
            : TimeFormatters.timeRange(startMin: item.startMin, endMin: item.startMin + item.durationMinutes)
        let subtitle = [
            item.calendarTitle,
            timeLabel,
            timeRange
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")

        return GlobalSearchResult(
            id: "event-\(item.id)",
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
        taskTitles: [UUID: String]
    ) -> [GlobalSearchResult] {
        let sorted = notes.filter { $0.kind == .meeting }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        return Array(rankedResults(sorted.compactMap { note in
            let title = note.displayTitle
            let dateLabel: String
            if let date = DateFormatters.date(from: note.eventDateKey) {
                if note.eventStartMin >= 0, note.eventEndMin >= 0 {
                    dateLabel = "\(DateFormatters.shortDate.string(from: date)) • \(TimeFormatters.timeRange(startMin: note.eventStartMin, endMin: note.eventEndMin))"
                } else {
                    dateLabel = DateFormatters.shortDate.string(from: date)
                }
            } else {
                dateLabel = "Event note"
            }
            let tagText = CadenceSearchTagSupport.text(for: note.sortedTags)
            let content = MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)
            guard matches(query: query, fields: [title, content, dateLabel, tagText]) else { return nil }
            return GlobalSearchResult(
                id: "event-note-\(note.id.uuidString)",
                category: .meetingNotes,
                title: title,
                subtitle: dateLabel,
                icon: "doc.text",
                tintHex: Theme.purpleHex,
                destination: .eventNote(note.id)
            )
        }, query: query).prefix(query.isEmpty ? 8 : 12))
    }

    /// **T-372a: `id` is the tie-break.** `GlobalSearchResult.id` is already the
    /// category-prefixed entity id every row here is built with (`"task-<uuid>"`,
    /// `"event-note-<uuid>"`), so it is both stable across rebuilds of the index and unique
    /// across the categories this list merges. Two tasks called "Admin" in two lists score the
    /// same and title the same, and without this leg `Cmd+K` listed them in whichever order the
    /// `@Query` happened to hand over — so the arrow keys landed on a different one between
    /// keystrokes.
    static func rankedResults(_ results: [GlobalSearchResult], query: String) -> [GlobalSearchResult] {
        CadenceSearchMatcher.rank(
            results,
            query: query,
            title: { $0.title },
            fields: { [$0.title, $0.subtitle] },
            identity: { $0.id }
        )
    }

    static func matches(query: String, fields: [String]) -> Bool {
        CadenceSearchMatcher.matchScore(query: query, fields: fields) != nil
    }
}
#endif
