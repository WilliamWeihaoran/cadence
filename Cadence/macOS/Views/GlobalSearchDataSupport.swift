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
        sidebarTabColorsRaw: String,
        includesCompletedTasks: Bool
    ) -> [GlobalSearchSection] {
        GlobalSearchIndexSupport.buildIndexedSource(
            query: query,
            hiddenTabs: hiddenTabs,
            areas: areas,
            projects: projects,
            tasks: tasks,
            notes: notes,
            eventResults: eventResults,
            sidebarTabColorsRaw: sidebarTabColorsRaw,
            includesCompletedTasks: includesCompletedTasks
        ).sections
    }

    /// What the palette draws, derived from the full match sets plus which sections the reader has
    /// expanded (T-1473).
    ///
    /// **One function, because the rows and the sentence under them have to come off the same
    /// list.** `CadenceSearchResultCap` records why its three numbers are derived in one place:
    /// a section drawing N rows under a count of M is the failure mode, and the only way to be
    /// sure of it is that nothing else ever computes either number.
    static func visibleSections(
        from sections: [GlobalSearchSection],
        expandedCategories: Set<String>
    ) -> [GlobalSearchVisibleSection] {
        sections.map { section in
            let isExpanded = expandedCategories.contains(section.id)
            let visible = CadenceSearchResultCap.visibleCount(
                total: section.results.count,
                cap: section.cap,
                isExpanded: isExpanded
            )
            return GlobalSearchVisibleSection(
                category: section.category,
                results: Array(section.results.prefix(visible)),
                hidden: CadenceSearchResultCap.hiddenCount(
                    total: section.results.count,
                    cap: section.cap,
                    isExpanded: isExpanded
                )
            )
        }
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
