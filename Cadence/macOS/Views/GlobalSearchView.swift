#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct GlobalSearchOverlay: View {
    let onSelect: (GlobalSearchResult) -> Void
    let onDismiss: () -> Void

    @Environment(GlobalSearchManager.self) private var searchManager
    @Environment(CalendarManager.self) private var calendarManager
    @AppStorage("sidebarHiddenTabs") private var sidebarHiddenTabsRaw = ""

    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var tasks: [AppTask]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Pursuit.order) private var pursuits: [Pursuit]
    @Query(sort: \Goal.order) private var goals: [Goal]
    @Query(sort: \Habit.order) private var habits: [Habit]

    @State private var eventResults: [GlobalSearchResult] = []
    @State private var highlightedResultID: String?
    @State private var pendingEventSearch: DispatchWorkItem?
    @State private var pendingQueryCommit: DispatchWorkItem?
    @State private var draftQuery: String = ""
    @State private var committedQuery: String = ""
    @FocusState private var isSearchFocused: Bool

    private var query: String { committedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hiddenTabs: Set<SidebarStaticDestination> {
        GlobalSearchOverlayStateSupport.hiddenTabs(from: sidebarHiddenTabsRaw)
    }

    private var sections: [GlobalSearchSection] {
        GlobalSearchDataSupport.buildSections(
            query: query,
            hiddenTabs: hiddenTabs,
            areas: areas,
            projects: projects,
            tasks: tasks,
            notes: notes,
            pursuits: pursuits,
            goals: goals,
            habits: habits,
            eventResults: eventResults
        )
    }

    private var flattenedResults: [GlobalSearchResult] {
        GlobalSearchOverlayStateSupport.flattenedResults(from: sections)
    }

    var body: some View {
        GlobalSearchOverlayShell(onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 0) {
                GlobalSearchHeader(
                    draftQuery: $draftQuery,
                    clear: clearQuery,
                    submit: submitHighlightedResult,
                    isSearchFocused: $isSearchFocused
                )

                Divider()
                    .background(Theme.borderSubtle)

                GlobalSearchSectionsList(
                    sections: sections,
                    query: query,
                    highlightedResultID: highlightedResultID,
                    onSelect: onSelect,
                    onHover: { highlightedResultID = $0 }
                )
            }
            .onAppear {
                GlobalSearchInteractionSupport.handleAppear(
                    searchManager: searchManager,
                    setDraftQuery: { draftQuery = $0 },
                    setCommittedQuery: { committedQuery = $0 },
                    setFocused: { isSearchFocused = $0 },
                    runEventSearch: runEventSearch,
                    syncHighlight: syncHighlightToAvailableResults
                )
            }
            .onChange(of: draftQuery) { _, newValue in
                scheduleQueryCommit(newValue)
            }
            .onChange(of: committedQuery) { _, _ in
                runEventSearch()
                syncHighlightToAvailableResults()
            }
            .onMoveCommand { direction in
                highlightedResultID = GlobalSearchOverlayStateSupport.moveHighlight(
                    direction: direction,
                    currentID: highlightedResultID,
                    results: flattenedResults
                )
            }
        }
    }

    private func runEventSearch() {
        GlobalSearchOverlayStateSupport.scheduleEventSearch(
            query: query,
            calendarManager: calendarManager,
            cancelPending: { pendingEventSearch?.cancel() },
            storePending: { pendingEventSearch = $0 }
        ) { results in
            eventResults = results
            syncHighlightToAvailableResults()
        }
    }

    private func syncHighlightToAvailableResults() {
        highlightedResultID = GlobalSearchDataSupport.syncedHighlightID(
            current: highlightedResultID,
            availableResults: flattenedResults
        )
    }

    private func scheduleQueryCommit(_ value: String) {
        GlobalSearchOverlayStateSupport.scheduleQueryCommit(
            value: value,
            cancelPending: { pendingQueryCommit?.cancel() },
            storePending: { pendingQueryCommit = $0 }
        ) { committed in
            committedQuery = committed
            searchManager.query = committed
        }
    }

    private func clearQuery() {
        GlobalSearchInteractionSupport.clearQuery(
            pendingQueryCommit: &pendingQueryCommit,
            searchManager: searchManager,
            setDraftQuery: { draftQuery = $0 },
            setCommittedQuery: { committedQuery = $0 },
            setFocused: { isSearchFocused = $0 }
        )
    }

    private func submitHighlightedResult() {
        GlobalSearchInteractionSupport.submitHighlightedResult(
            highlightedResultID: highlightedResultID,
            flattenedResults: flattenedResults,
            onSelect: onSelect
        )
    }
}
#endif
