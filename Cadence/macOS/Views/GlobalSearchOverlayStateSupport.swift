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

    static func flattenedResults(from sections: [GlobalSearchSection]) -> [GlobalSearchResult] {
        sections.flatMap(\.results)
    }

    static func moveHighlight(
        direction: MoveCommandDirection,
        currentID: String?,
        results: [GlobalSearchResult]
    ) -> String? {
        guard !results.isEmpty else { return nil }
        let currentIndex = results.firstIndex(where: { $0.id == currentID }) ?? 0
        switch direction {
        case .down:
            return results[min(currentIndex + 1, results.count - 1)].id
        case .up:
            return results[max(currentIndex - 1, 0)].id
        default:
            return currentID
        }
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
#endif
