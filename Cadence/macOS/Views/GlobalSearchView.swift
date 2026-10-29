#if os(macOS)
import AppKit
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
    /// [[T-8092]]: keeps a resting pointer from taking the highlight back from the keyboard.
    @State private var hoverGate = GlobalSearchHoverGate()
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
    /// This is the one the overlay passes down and the one `keyboardRows` reads, so the rows,
    /// the continuation sentence and the arrow keys cannot describe three different searches.
    private var sections: [GlobalSearchVisibleSection] {
        GlobalSearchDataSupport.visibleSections(from: indexedSections, expandedCategories: expandedCategories)
    }

    /// Only read when nothing matched — `GlobalSearchEmptyState` draws it, and nothing else — so
    /// the extra pass over the tasks is paid on an empty result set alone ([[T-6971]]).
    private var withheldCompletedTaskCount: Int {
        guard sections.isEmpty else { return 0 }
        return GlobalSearchIndexSupport.withheldCompletedTaskMatchCount(
            tasks: tasks,
            query: query,
            includingCompleted: includesCompletedTasks
        )
    }

    private var keyboardRows: [GlobalSearchKeyboardRow] {
        GlobalSearchOverlayStateSupport.keyboardRows(from: sections)
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
                    withheldCompletedTaskCount: withheldCompletedTaskCount,
                    highlightedResultID: $highlightedResultID,
                    hoverGate: $hoverGate,
                    onSelect: onSelect,
                    onReveal: revealSection
                )
            }
            .onAppear {
                // The palette opens under a pointer that is usually resting over the list, and
                // the first row is the keyboard's until the pointer moves ([[T-8092]]).
                keyboardTookHighlight()
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
                // Typing swaps the rows under a resting pointer, like scrolling does.
                keyboardTookHighlight()
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
                keyboardTookHighlight()
                highlightedResultID = GlobalSearchOverlayStateSupport.moveHighlight(
                    direction: direction,
                    currentID: highlightedResultID,
                    rows: keyboardRows
                )
            }
        }
    }

    private func keyboardTookHighlight() {
        hoverGate.keyboardTookHighlight(pointerAt: NSEvent.mouseLocation)
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
        highlightedResultID = GlobalSearchOverlayStateSupport.syncedHighlightID(
            current: highlightedResultID,
            rows: keyboardRows
        )
    }

    /// Reveals one section in place — from a click on its continuation row or Return on it — and
    /// moves the highlight to the first newly revealed result, the row that now sits where the
    /// continuation row was (T-4320).
    private func revealSection(_ sectionID: String) {
        let before = sections
        expandedCategories.insert(sectionID)
        if let target = GlobalSearchOverlayStateSupport.firstRevealedResultID(
            sectionID: sectionID,
            before: before,
            after: sections
        ) {
            highlightedResultID = target
        } else {
            syncHighlightToAvailableResults()
        }
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
            rows: keyboardRows,
            onSelect: onSelect,
            onReveal: revealSection
        )
    }
}

/// Read selection in the child, so hover does not make the query-owning parent read this state
/// while deriving its sections. Keyboard and submit callbacks still share the same binding.
struct GlobalSearchHighlightList: View {
    let sections: [GlobalSearchVisibleSection]
    let query: String
    var withheldCompletedTaskCount: Int = 0
    @Binding var highlightedResultID: String?
    @Binding var hoverGate: GlobalSearchHoverGate
    let onSelect: (GlobalSearchResult) -> Void
    let onReveal: (String) -> Void

    var body: some View {
        GlobalSearchSectionsList(
            sections: sections,
            query: query,
            withheldCompletedTaskCount: withheldCompletedTaskCount,
            highlightedResultID: highlightedResultID,
            onSelect: onSelect,
            onHover: hover,
            onReveal: onReveal
        )
    }

    /// [[T-8092]]: a hover-enter moves the highlight only once the pointer has moved since the
    /// keyboard last took it — not when the list scrolled a row under a pointer that stayed put.
    /// The gate is written only when its answer changes it, so a plain hover costs no state write.
    private func hover(_ id: String) {
        var gate = hoverGate
        guard gate.admitsHover(pointerAt: NSEvent.mouseLocation) else { return }
        if gate != hoverGate { hoverGate = gate }
        highlightedResultID = id
    }
}
#endif
