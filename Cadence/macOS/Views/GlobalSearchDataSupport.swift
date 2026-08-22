#if os(macOS)
import SwiftUI
import EventKit

enum GlobalSearchDataSupport {
    static func buildSections(
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
    ) -> [GlobalSearchSection] {
        GlobalSearchIndexSupport.buildIndexedSource(
            query: query,
            hiddenTabs: hiddenTabs,
            areas: areas,
            projects: projects,
            tasks: tasks,
            notes: notes,
            goals: goals,
            habits: habits,
            eventResults: eventResults,
            sidebarTabColorsRaw: sidebarTabColorsRaw
        ).sections
    }

    static func commandResults(query: String, sidebarTabColorsRaw: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.commandResults(query: query, sidebarTabColorsRaw: sidebarTabColorsRaw)
    }

    static func pageResults(
        query: String,
        hiddenTabs: Set<SidebarStaticDestination>,
        sidebarTabColorsRaw: String
    ) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.pageResults(
            query: query,
            hiddenTabs: hiddenTabs,
            sidebarTabColorsRaw: sidebarTabColorsRaw
        )
    }

    static func areaResults(areas: [Area], query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.areaResults(areas: areas, query: query)
    }

    static func projectResults(projects: [Project], query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.projectResults(projects: projects, query: query)
    }

    static func taskResults(tasks: [AppTask], query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.taskResults(tasks: tasks, query: query)
    }

    static func goalResults(goals: [Goal], query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.goalResults(goals: goals, query: query)
    }

    static func habitResults(habits: [Habit], query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.habitResults(habits: habits, query: query)
    }

    static func eventResults(from events: [EKEvent], query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.eventResults(from: events, query: query)
    }

    static func eventNoteResults(
        notes: [Note],
        query: String,
        taskTitles: [UUID: String]
    ) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.eventNoteResults(notes: notes, query: query, taskTitles: taskTitles)
    }

    static func syncedHighlightID(current: String?, availableResults: [GlobalSearchResult]) -> String? {
        guard !availableResults.isEmpty else { return nil }
        if let current, availableResults.contains(where: { $0.id == current }) {
            return current
        }
        return availableResults.first?.id
    }
}
#endif
