#if os(macOS)
import SwiftUI

enum GlobalSearchInteractionSupport {
    static func handleAppear(
        searchManager: GlobalSearchManager,
        setDraftQuery: (String) -> Void,
        setCommittedQuery: (String) -> Void,
        setFocused: (Bool) -> Void,
        runEventSearch: () -> Void,
        syncHighlight: () -> Void
    ) {
        setDraftQuery(searchManager.query)
        setCommittedQuery(searchManager.query)
        setFocused(true)
        runEventSearch()
        syncHighlight()
    }

    static func clearQuery(
        pendingQueryCommit: inout DispatchWorkItem?,
        searchManager: GlobalSearchManager,
        setDraftQuery: (String) -> Void,
        setCommittedQuery: (String) -> Void,
        setFocused: (Bool) -> Void
    ) {
        pendingQueryCommit?.cancel()
        setDraftQuery("")
        setCommittedQuery("")
        searchManager.query = ""
        setFocused(true)
    }

    static func submitHighlightedResult(
        highlightedResultID: String?,
        flattenedResults: [GlobalSearchResult],
        onSelect: (GlobalSearchResult) -> Void
    ) {
        guard let highlighted = flattenedResults.first(where: { $0.id == highlightedResultID }) else { return }
        onSelect(highlighted)
    }
}
#endif
