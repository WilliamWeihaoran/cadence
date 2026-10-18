#if os(macOS)
import SwiftUI
import SwiftData
import EventKit

struct GlobalSearchOverlay: View {
    let onSelect: (GlobalSearchResult) -> Void
    let onDismiss: () -> Void

    @Environment(GlobalSearchManager.self) private var searchManager
    @Environment(CalendarManager.self) private var calendarManager
    /// The device-local hidden set the synced layout replaced (T-1274), read only as the fallback
    /// for a store with no synced row yet.
    @AppStorage(CadencePreferenceKeys.sidebarHiddenTabs) private var sidebarHiddenTabsRaw = ""
    /// The palette draws every command and page row in the tint the *sidebar* draws that
    /// destination in, override included — so retinting Today in Settings → Sidebar retints it
    /// here too. Before T-244 this preference was never read on this screen.
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = CadencePreferenceKeys.emptySidebarPreference
    /// Whether the Tasks section lists completed work (T-1476). Persisted, and `false` by default:
    /// the palette used to include completed tasks unconditionally and offer no way to say
    /// otherwise, so the same query answered differently here and on iOS.
    @AppStorage(CadencePreferenceKeys.searchIncludesCompletedTasks) private var includesCompletedTasks = false

    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var tasks: [AppTask]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    /// The palette must not offer a page the sidebar is hiding, and since T-1274 what the sidebar
    /// hides is an account-wide record rather than this Mac's preference.
    @Query private var sidebarLayoutPreferences: [SidebarLayoutPreference]

    @State private var eventResults: [GlobalSearchResult] = []
    @State private var highlightedResultID: String?
    @State private var pendingEventSearch: DispatchWorkItem?
    @State private var pendingQueryCommit: DispatchWorkItem?
    @State private var draftQuery: String = ""
    @State private var committedQuery: String = ""
    /// Which sections the reader has expanded past their cap, keyed by
    /// `GlobalSearchVisibleSection.id` (T-1473).
    ///
    /// Scoped to one result set and cleared whenever the query or the Completed filter changes:
    /// the 38 matches a section was withholding are a fact about *this* search, and a section
    /// left expanded would hand the next one an uncapped list nobody asked for. iOS keys the same
    /// reset off `resultSetIdentity`.
    @State private var expandedCategories: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    private var query: String { committedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hiddenTabs: Set<SidebarStaticDestination> {
        GlobalSearchOverlayStateSupport.hiddenTabs(
            of: CadenceSidebarLayoutPreferenceStore.layout(
                from: sidebarLayoutPreferences,
                legacyHiddenRaw: sidebarHiddenTabsRaw
            )
        )
    }

    /// Everything each category matched, uncapped. Nothing is drawn from this directly — see
    /// `sections` below, which is what the palette shows.
    private var indexedSections: [GlobalSearchSection] {
        GlobalSearchDataSupport.buildSections(
            query: query,
            hiddenTabs: hiddenTabs,
            areas: areas,
            projects: projects,
            tasks: tasks,
            notes: notes,
            eventResults: eventResults,
            sidebarTabColorsRaw: sidebarTabColorsRaw,
            includesCompletedTasks: includesCompletedTasks
        )
    }

    /// **The sections as drawn** — capped, minus whatever the reader has expanded, each carrying
    /// the count of what it is still holding back.
    ///
    /// This is the one the overlay passes down and the one `flattenedResults` reads, so the rows,
    /// the continuation sentence and the arrow keys cannot describe three different searches.
    private var sections: [GlobalSearchVisibleSection] {
        GlobalSearchDataSupport.visibleSections(from: indexedSections, expandedCategories: expandedCategories)
    }

    private var flattenedResults: [GlobalSearchResult] {
        GlobalSearchOverlayStateSupport.flattenedResults(from: sections)
    }

    var body: some View {
        GlobalSearchOverlayShell(onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 0) {
                GlobalSearchHeader(
                    draftQuery: $draftQuery,
                    includesCompletedTasks: $includesCompletedTasks,
                    clear: clearQuery,
                    submit: submitHighlightedResult,
                    isSearchFocused: $isSearchFocused
                )

                Divider()
                    .background(Theme.borderSubtle)

                GlobalSearchHighlightList(
                    sections: sections,
                    query: query,
                    highlightedResultID: $highlightedResultID,
                    onSelect: onSelect,
                    onReveal: { expandedCategories.insert($0) }
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
                expandedCategories.removeAll()
                runEventSearch()
                syncHighlightToAvailableResults()
            }
            .onChange(of: includesCompletedTasks) { _, _ in
                // A different result set, so the expansions belong to the previous one. The
                // highlight is re-synced because the row it was on may have just been filtered
                // out from under it.
                expandedCategories.removeAll()
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

/// Read selection in the child, so hover does not make the query-owning parent read this state
/// while deriving its sections. Keyboard and submit callbacks still share the same binding.
struct GlobalSearchHighlightList: View {
    let sections: [GlobalSearchVisibleSection]
    let query: String
    @Binding var highlightedResultID: String?
    let onSelect: (GlobalSearchResult) -> Void
    let onReveal: (String) -> Void

    var body: some View {
        GlobalSearchSectionsList(
            sections: sections,
            query: query,
            highlightedResultID: highlightedResultID,
            onSelect: onSelect,
            onHover: { highlightedResultID = $0 },
            onReveal: onReveal
        )
    }
}
#endif
