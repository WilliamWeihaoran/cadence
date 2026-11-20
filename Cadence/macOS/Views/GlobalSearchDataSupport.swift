#if os(macOS)
import SwiftUI
import EventKit

/// **One Events fetch: the query it ran for, the events it matched, and the rows built from them**
/// ([[T-18658]]).
///
/// The fetch runs behind a 40 ms commit debounce plus an 80 ms delay, so for that window the
/// palette's query is newer than its event rows. Keeping the matched `EKEvent`s beside the rows is
/// what lets `GlobalSearchDataSupport.buildSections` re-gate them against the CURRENT query, the
/// way iOS Search re-scores its cached events on every render, instead of drawing -- and letting
/// Return open -- rows the field no longer matches.
struct GlobalSearchEventFetch {
    let query: String
    let events: [EKEvent]
    let results: [GlobalSearchResult]

    static let empty = GlobalSearchEventFetch(query: "", events: [], results: [])

    init(query: String, events: [EKEvent], results: [GlobalSearchResult]) {
        self.query = query
        self.events = events
        self.results = results
    }

    init(query: String, events: [EKEvent]) {
        self.init(query: query, events: events, results: GlobalSearchDataSupport.eventResults(from: events, query: query))
    }

    /// The Events rows for `currentQuery`: the fetch's own rows when it ran for this query, and
    /// otherwise its events re-scored against it -- a non-refining query keeps none of them, so no
    /// event row is drawn under a query it does not match while the re-fetch is pending.
    func results(for currentQuery: String) -> [GlobalSearchResult] {
        guard currentQuery != query else { return results }
        return GlobalSearchDataSupport.eventResults(from: events, query: currentQuery)
    }
}

enum GlobalSearchDataSupport {
    static func buildSections(
        query: String,
        hiddenTabs: Set<SidebarStaticDestination>,
        areas: [Area],
        projects: [Project],
        tasks: [AppTask],
        notes: [Note],
        eventFetch: GlobalSearchEventFetch,
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
            eventResults: eventFetch.results(for: query),
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
}
#endif
