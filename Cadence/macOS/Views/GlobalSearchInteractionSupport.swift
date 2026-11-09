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

    /// **[[T-14014]] — Return resolves against the query in the field, not the last committed one.**
    ///
    /// The typed query reaches the rows only after `scheduleQueryCommit`'s 40 ms debounce, so a
    /// Return pressed inside that window used to read the PREVIOUS query's rows and highlight and
    /// open a result the user had just typed past. This commits a still-pending draft first —
    /// cancelling the scheduled commit so it cannot land a second time — and only then reads the
    /// highlight and the rows, which is why both are closures: they must be read after the commit.
    /// `commit` is expected to leave the highlight where the debounce would have left it, so Return
    /// acts exactly as it would have 40 ms later. iOS Search has no debounce — its rows derive from
    /// the field's text directly — so this is the Mac catching up to it ([[T-8201]]).
    static func submitHighlightedResult(
        draftQuery: String,
        committedQuery: String,
        pendingQueryCommit: inout DispatchWorkItem?,
        commit: (String) -> Void,
        highlightedResultID: () -> String?,
        rows: () -> [GlobalSearchKeyboardRow],
        onSelect: (GlobalSearchResult) -> Void,
        onReveal: (String) -> Void
    ) {
        pendingQueryCommit?.cancel()
        pendingQueryCommit = nil
        if draftQuery != committedQuery {
            commit(draftQuery)
        }
        submitHighlightedResult(
            highlightedResultID: highlightedResultID(),
            rows: rows(),
            onSelect: onSelect,
            onReveal: onReveal
        )
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
