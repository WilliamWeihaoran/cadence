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

    static func eventResults(from events: [EKEvent], query: String) -> [GlobalSearchResult] {
        GlobalSearchIndexSupport.eventResults(from: events, query: query)
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
