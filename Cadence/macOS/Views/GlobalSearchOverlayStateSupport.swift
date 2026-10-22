#if os(macOS)
import SwiftUI

enum GlobalSearchOverlayStateSupport {
    /// The rows the palette must not offer, read off the resolved sidebar layout rather than off a
    /// string (T-1274). The layout is one synced record now, so "hidden" is an account-wide answer
    /// and the palette has to ask the same helper both sidebars ask.
    static func hiddenTabs(
        of layout: CadenceSidebarLayoutPreferenceStore.Layout
    ) -> Set<SidebarStaticDestination> {
        Set(layout.hidden.compactMap(\.sidebarStaticDestination))
    }

    /// **The VISIBLE rows, in draw order** (T-1473), continuation rows included (T-4320). This
    /// drives arrow-key movement, the highlight sync and Return, so it has to walk what is on
    /// screen: walking the uncapped `GlobalSearchSection.results` would let Down-arrow move the
    /// highlight onto a row the list is not drawing, and Return would then open something the user
    /// could not see.
    ///
    /// **A capped section contributes its "N more results" row after its last result**, exactly
    /// where `GlobalSearchSectionsList` draws it. Before T-4320 this was `flatMap(\.results)`, so
    /// the row was visible but unreachable from the keys and the reveal was mouse-only.
    static func keyboardRows(from sections: [GlobalSearchVisibleSection]) -> [GlobalSearchKeyboardRow] {
        sections.flatMap { section -> [GlobalSearchKeyboardRow] in
            let results = section.results.map(GlobalSearchKeyboardRow.result)
            guard let hidden = section.hidden,
                  CadenceSearchResultCap.continuationLabel(hidden: hidden) != nil else { return results }
            return results + [.moreResults(sectionID: section.id)]
        }
    }

    static func moveHighlight(
        direction: MoveCommandDirection,
        currentID: String?,
        rows: [GlobalSearchKeyboardRow]
    ) -> String? {
        guard !rows.isEmpty else { return nil }
        let currentIndex = rows.firstIndex(where: { $0.id == currentID }) ?? 0
        switch direction {
        case .down:
            return rows[min(currentIndex + 1, rows.count - 1)].id
        case .up:
            return rows[max(currentIndex - 1, 0)].id
        default:
            return currentID
        }
    }

    /// Keeps the highlight on a row that still exists, else the first row. Read over the keyboard
    /// rows rather than the results (T-4320), so a highlight resting on a continuation row is not
    /// thrown back to the top by a re-sync.
    static func syncedHighlightID(current: String?, rows: [GlobalSearchKeyboardRow]) -> String? {
        guard !rows.isEmpty else { return nil }
        if let current, rows.contains(where: { $0.id == current }) {
            return current
        }
        return rows.first?.id
    }

    /// **Where the highlight lands after a reveal: the first newly revealed result** (T-4320) —
    /// the row that now sits where the continuation row was, so the keyboard user's next Down
    /// continues through the remainder instead of jumping back to the top. `nil` when the section
    /// revealed nothing (it was not capped), and the caller then leaves the highlight to the sync.
    static func firstRevealedResultID(
        sectionID: String,
        before: [GlobalSearchVisibleSection],
        after: [GlobalSearchVisibleSection]
    ) -> String? {
        guard let collapsed = before.first(where: { $0.id == sectionID }),
              let expanded = after.first(where: { $0.id == sectionID }),
              expanded.results.count > collapsed.results.count else { return nil }
        return expanded.results[collapsed.results.count].id
    }

    static func scheduleEventSearch(
        query: String,
        calendarManager: CalendarManager,
        cancelPending: () -> Void,
        storePending: @escaping (DispatchWorkItem?) -> Void,
        updateResults: @escaping ([GlobalSearchResult]) -> Void
    ) {
        cancelPending()
        guard calendarManager.isAuthorized else {
            updateResults([])
            return
        }

        let workItem = DispatchWorkItem {
            let matchedEvents = calendarManager.searchEvents(matching: query)
            DispatchQueue.main.async {
                updateResults(GlobalSearchDataSupport.eventResults(from: matchedEvents, query: query))
            }
        }

        storePending(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    static func scheduleQueryCommit(
        value: String,
        cancelPending: () -> Void,
        storePending: @escaping (DispatchWorkItem?) -> Void,
        commit: @escaping (String) -> Void
    ) {
        cancelPending()

        let workItem = DispatchWorkItem {
            commit(value)
            storePending(nil)
        }

        storePending(workItem)

        if value.isEmpty {
            workItem.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
        }
    }
}
/// One stop on the palette's arrow-key path (T-4320): a result, or a capped section's
/// "N more results" row. Return on the first selects; on the second it reveals.
///
/// The highlight stays a `String` so hover and the row views keep their existing contract; a
/// continuation row's id is namespaced `continuation-<section id>`, a prefix no
/// `CadenceSearchIdentity` kind uses, so it cannot collide with a result's.
enum GlobalSearchKeyboardRow: Identifiable, Equatable {
    case result(GlobalSearchResult)
    case moreResults(sectionID: String)

    static func continuationID(forSection sectionID: String) -> String {
        "continuation-\(sectionID)"
    }

    var id: String {
        switch self {
        case .result(let result): result.id
        case .moreResults(let sectionID): Self.continuationID(forSection: sectionID)
        }
    }
}
#endif
