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
        eventResults: [GlobalSearchResult]
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
            eventResults: eventResults
        ).sections
    }

    static func commandResults(query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.commandResults(query: query)
    }

    static func pageResults(query: String, hiddenTabs: Set<SidebarStaticDestination>) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.pageResults(query: query, hiddenTabs: hiddenTabs)
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

    static func eventNoteResults(notes: [Note], query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.eventNoteResults(notes: notes, query: query)
    }

    static func rankResults(_ results: [GlobalSearchResult], query: String) -> [GlobalSearchResult] {
        GlobalSearchMatcher.rankResults(results, query: query)
    }

    static func matchScore(query: String, _ fields: String...) -> Int? {
        GlobalSearchMatcher.matchScore(query: query, fields: fields)
    }

    static func matchScore(query: String, fields: [String]) -> Int? {
        GlobalSearchMatcher.matchScore(query: query, fields: fields)
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
