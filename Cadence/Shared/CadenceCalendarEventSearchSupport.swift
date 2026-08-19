import EventKit
import Foundation

/// The one filter behind `searchEvents` on both platforms.
///
/// `CalendarManager.searchEvents` (macOS) and `iOSCalendarManager.searchEvents` (iOS) carried the
/// same name and the same default arguments (60 past days / 365 future days) and disagreed twice:
/// macOS dropped every all-day event with `filter { !$0.isAllDay }` and matched with a naive
/// `localizedLowercase.contains`, while iOS kept all-day events and matched with
/// `CadenceSearchMatcher`. So Cmd+K on the Mac could not find an all-day event at all, and the
/// events it *did* find were selected by a different rule than the iPhone's.
///
/// The all-day exclusion was not deliberate. macOS's `fetchEvents` / `fetchAllDayEvents` pair
/// genuinely does split on `isAllDay`, because the timeline day canvas and the all-day banner are
/// two surfaces that must not draw each other's events — but neither of them goes through search,
/// and search has one result list with nothing to double-count. The one macOS caller that resolves
/// a picked search result back to an `EKEvent`, `macOSRootCommandActionSupport`, went through this
/// same function, so an all-day event could not be *opened* either.
///
/// Both platforms now call `results(from:query:now:)`. Keep it that way: two `searchEvents` bodies
/// spelling the same intent is exactly how the divergence above happened.
nonisolated enum CadenceCalendarEventSearchSupport {
    /// Title first: `CadenceSearchMatcher` scores the first field as the title and weights a
    /// prefix hit there far above one in the body.
    static func searchFields(for event: EKEvent) -> [String] {
        [
            event.title ?? "",
            event.notes ?? "",
            event.calendar?.title ?? ""
        ]
    }

    static func matches(query: String, event: EKEvent) -> Bool {
        CadenceSearchMatcher.matchScore(query: query, fields: searchFields(for: event)) != nil
    }

    /// An empty query means "what is coming up", not "everything in the window" — the window
    /// reaches 60 days into the past, which is not a useful thing to list unprompted.
    static func isUpcoming(_ event: EKEvent, now: Date) -> Bool {
        (event.endDate ?? now) >= now
    }

    /// Total, including the title tie-break. macOS sorted on `startDate` alone, which leaves the
    /// order of two events starting at the same minute undefined — and an all-day event starts at
    /// midnight, so the tie is the common case on the results this fix newly admits.
    static func precedes(_ lhs: EKEvent, _ rhs: EKEvent) -> Bool {
        let lhsStart = lhs.startDate ?? lhs.occurrenceDate ?? Date.distantFuture
        let rhsStart = rhs.startDate ?? rhs.occurrenceDate ?? Date.distantFuture
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "") == .orderedAscending
    }

    static func results(from events: [EKEvent], query: String, now: Date = Date()) -> [EKEvent] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? events.filter { isUpcoming($0, now: now) }
            : events.filter { matches(query: trimmed, event: $0) }
        return filtered.sorted(by: precedes)
    }
}
