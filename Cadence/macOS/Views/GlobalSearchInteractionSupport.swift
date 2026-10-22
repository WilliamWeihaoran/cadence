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

    /// Return on the highlighted row (T-4320): a result is selected, a continuation row reveals its
    /// section in place and selects nothing.
    static func submitHighlightedResult(
        highlightedResultID: String?,
        rows: [GlobalSearchKeyboardRow],
        onSelect: (GlobalSearchResult) -> Void,
        onReveal: (String) -> Void
    ) {
        guard let highlighted = rows.first(where: { $0.id == highlightedResultID }) else { return }
        switch highlighted {
        case .result(let result):
            onSelect(result)
        case .moreResults(let sectionID):
            onReveal(sectionID)
        }
    }
}
#endif
