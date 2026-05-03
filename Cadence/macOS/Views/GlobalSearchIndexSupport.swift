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
        pursuits: [Pursuit],
        goals: [Goal],
        habits: [Habit],
        eventResults: [GlobalSearchResult]
    ) -> GlobalSearchIndexedSource {
        var sections: [GlobalSearchSection] = []

        appendSection(.commands, results: commandResults(query: query), into: &sections)
        appendSection(.pages, results: pageResults(query: query, hiddenTabs: hiddenTabs), into: &sections)
        appendSection(.areas, results: areaResults(areas: areas, query: query), into: &sections)
        appendSection(.projects, results: projectResults(projects: projects, query: query), into: &sections)
        appendSection(.tasks, results: taskResults(tasks: tasks, query: query), into: &sections)
        appendSection(.events, results: eventResults, into: &sections)
        appendSection(.meetingNotes, results: eventNoteResults(notes: notes, query: query), into: &sections)
        appendSection(.pursuits, results: pursuitResults(pursuits: pursuits, query: query), into: &sections)
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

    static func commandResults(query: String) -> [GlobalSearchResult] {
        rankedResults(
            GlobalSearchCommandDefinition.all.compactMap { definition in
                guard matches(query: query, fields: [definition.title, definition.subtitle, definition.aliases]) else { return nil }
                return GlobalSearchResult(
                    id: "command-\(definition.command.rawValue)",
                    category: .commands,
                    title: definition.title,
                    subtitle: definition.subtitle,
                    icon: definition.icon,
                    tintHex: definition.tintHex,
                    destination: .command(definition.command)
                )
            },
            query: query
        )
    }

    static func pageResults(query: String, hiddenTabs: Set<SidebarStaticDestination>) -> [GlobalSearchResult] {
        rankedResults(GlobalSearchPageDefinition.all.compactMap { page in
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
                tintHex: page.tintHex,
                destination: .sidebar(page.item)
            )
        }, query: query)
    }

    static func areaResults(areas: [Area], query: String) -> [GlobalSearchResult] {
        rankedResults(areas.compactMap { area in
            let contextName = area.context?.name ?? "No context"
            let lifecycle = area.isArchived ? "archived" : (area.isDone ? "completed done" : "active")
            guard matches(query: query, fields: [area.name, area.desc, contextName, lifecycle]) else { return nil }
            return GlobalSearchResult(
                id: "area-\(area.id.uuidString)",
                category: .areas,
                title: area.name,
                subtitle: "\(contextName) • \(area.tasks?.filter { !$0.isDone }.count ?? 0) active tasks • \(area.isArchived ? "Archived" : (area.isDone ? "Completed" : "Active"))",
                icon: area.icon,
                tintHex: area.colorHex,
                destination: .area(area.id)
            )
        }, query: query)
    }

    static func projectResults(projects: [Project], query: String) -> [GlobalSearchResult] {
        rankedResults(projects.compactMap { project in
            let contextName = project.context?.name ?? "No context"
            let areaName = project.area?.name
            let summary = [contextName, areaName].compactMap { $0 }.joined(separator: " • ")
            let lifecycle = project.isArchived ? "archived" : (project.isDone ? "completed done" : "active")
            guard matches(query: query, fields: [project.name, project.desc, summary, lifecycle]) else { return nil }
            return GlobalSearchResult(
                id: "project-\(project.id.uuidString)",
                category: .projects,
                title: project.name,
                subtitle: "\(summary) • \(project.tasks?.filter { !$0.isDone }.count ?? 0) active tasks • \(project.isArchived ? "Archived" : (project.isDone ? "Completed" : "Active"))",
                icon: project.icon,
                tintHex: project.colorHex,
                destination: .project(project.id)
            )
        }, query: query)
    }

    static func taskResults(tasks: [AppTask], query: String) -> [GlobalSearchResult] {
        let base = tasks
            .filter { !$0.isCancelled }
            .sorted {
                if $0.isDone != $1.isDone { return !$0.isDone && $1.isDone }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt > $1.createdAt
            }

        return Array(rankedResults(base.compactMap { task in
            let container = task.project?.name ?? task.area?.name ?? "Inbox"
            let contextName = task.context?.name ?? ""
            let notesSnippet = task.notes.isEmpty ? "" : task.notes
            let tagText = task.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
            let statusAliases = [
                task.isDone ? "completed done" : "active todo",
                task.priority.label,
                task.resolvedSectionName,
                tagText
            ].joined(separator: " ")
            guard matches(query: query, fields: [task.title, container, contextName, notesSnippet, statusAliases]) else { return nil }

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
                icon: task.scheduledStartMin >= 0 ? "calendar.badge.clock" : "checkmark.circle",
                tintHex: task.containerColor,
                destination: .task(task.id)
            )
        }, query: query).prefix(query.isEmpty ? 10 : 14))
    }

    static func pursuitResults(pursuits: [Pursuit], query: String) -> [GlobalSearchResult] {
        Array(rankedResults(pursuits.compactMap { pursuit in
            let contextName = pursuit.context?.name ?? "No context"
            let goalCount = pursuit.goals?.count ?? 0
            let habitCount = pursuit.habits?.count ?? 0
            guard matches(query: query, fields: [pursuit.title, pursuit.desc, contextName, pursuit.status.label]) else { return nil }
            return GlobalSearchResult(
                id: "pursuit-\(pursuit.id.uuidString)",
                category: .pursuits,
                title: pursuit.title,
                subtitle: "\(contextName) • \(goalCount) goals • \(habitCount) habits",
                icon: pursuit.icon,
                tintHex: pursuit.colorHex,
                destination: .pursuits
            )
        }, query: query).prefix(query.isEmpty ? 6 : 10))
    }

    static func goalResults(goals: [Goal], query: String) -> [GlobalSearchResult] {
        Array(rankedResults(goals.compactMap { goal in
            let contextName = goal.context?.name ?? "No context"
            let pursuitName = goal.pursuit?.title ?? ""
            guard matches(query: query, fields: [goal.title, goal.desc, contextName, pursuitName]) else { return nil }
            return GlobalSearchResult(
                id: "goal-\(goal.id.uuidString)",
                category: .goals,
                title: goal.title,
                subtitle: "\(pursuitName.isEmpty ? contextName : pursuitName) • \(Int(goal.progress * 100))% complete",
                icon: "target",
                tintHex: goal.colorHex,
                destination: .goals
            )
        }, query: query).prefix(query.isEmpty ? 6 : 10))
    }

    static func habitResults(habits: [Habit], query: String) -> [GlobalSearchResult] {
        Array(rankedResults(habits.compactMap { habit in
            let contextName = habit.context?.name ?? "No context"
            let pursuitName = habit.pursuit?.title ?? ""
            guard matches(query: query, fields: [habit.title, contextName, pursuitName]) else { return nil }
            return GlobalSearchResult(
                id: "habit-\(habit.id.uuidString)",
                category: .habits,
                title: habit.title,
                subtitle: "\(pursuitName.isEmpty ? contextName : pursuitName) • \(habit.currentStreak) day streak",
                icon: habit.icon,
                tintHex: habit.colorHex,
                destination: .habits
            )
        }, query: query).prefix(query.isEmpty ? 6 : 10))
    }

    static func eventResults(from events: [EKEvent], query: String) -> [GlobalSearchResult] {
        let mapped = Array(events.prefix(query.isEmpty ? 6 : 12)).map { event in
            let item = CalendarEventItem(event: event)
            let startDate = event.startDate ?? Date()
            let timeLabel = "\(DateFormatters.dayOfWeek.string(from: startDate)), \(DateFormatters.shortDate.string(from: startDate))"
            let subtitle = [
                item.calendarTitle,
                timeLabel,
                TimeFormatters.timeRange(startMin: item.startMin, endMin: item.startMin + item.durationMinutes)
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

            return GlobalSearchResult(
                id: "event-\(item.id)",
                category: .events,
                title: item.title,
                subtitle: subtitle,
                icon: "calendar",
                tintHex: item.calendarColor.globalSearchHexString() ?? (Theme.purple.globalSearchHexString() ?? "#9E8CFF"),
                destination: .event(item.id)
            )
        }
        return rankedResults(mapped, query: query)
    }

    static func eventNoteResults(notes: [Note], query: String) -> [GlobalSearchResult] {
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
                dateLabel = "Meeting note"
            }
            let tagText = note.sortedTags.flatMap { [$0.name, $0.slug] }.joined(separator: " ")
            guard matches(query: query, fields: [title, note.content, dateLabel, tagText]) else { return nil }
            return GlobalSearchResult(
                id: "event-note-\(note.id.uuidString)",
                category: .meetingNotes,
                title: title,
                subtitle: dateLabel,
                icon: "doc.text",
                tintHex: Theme.purple.globalSearchHexString() ?? "#9E8CFF",
                destination: .eventNote(note.id)
            )
        }, query: query).prefix(query.isEmpty ? 8 : 12))
    }

    static func rankedResults(_ results: [GlobalSearchResult], query: String) -> [GlobalSearchResult] {
        GlobalSearchMatcher.rankResults(results, query: query)
    }

    static func matches(query: String, fields: [String]) -> Bool {
        GlobalSearchMatcher.matchScore(query: query, fields: fields) != nil
    }
}
#endif
