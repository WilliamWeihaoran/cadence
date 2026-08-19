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

    /// Resolve a picked search result back to its `EKEvent`.
    ///
    /// This is the *inverse* of `results(from:query:now:)`, not a use of it. The identifier already
    /// names exactly one event, so every filter search applies is wrong here — and one of them was
    /// actively harmful: `macOSRootCommandActionSupport` resolved a Cmd+K event result by calling
    /// `searchEvents(matching: "")` and scanning the answer, which took the `isUpcoming` branch
    /// above. Search reaches 60 days into the past, so a finished event could be *found* and then
    /// not *opened* — picking it navigated nowhere and silently dropped you on today's calendar.
    ///
    /// Recurrence is why this scans the fetched window rather than asking `EKEventStore` for the
    /// identifier: a search result carries an *occurrence* identifier, and
    /// `EKEventStore.event(withIdentifier:)` hands back the series' base event, whose `startDate`
    /// is the first occurrence rather than the one that was picked.
    ///
    /// `@MainActor` inside an otherwise `nonisolated` enum because `CadenceEventNoteSupport` — the
    /// single owner of what an event identifier *is* — is main-actor isolated under the app's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Borrowing the identity rule and paying for the
    /// isolation is the trade this file already argues for elsewhere; re-spelling `identifier ==`
    /// here to stay nonisolated would be a fourth copy of a predicate that has shipped wrong three
    /// times. The only caller is a main-actor command handler, so nothing is given up.
    @MainActor
    static func event(from events: [EKEvent], identifier: String) -> EKEvent? {
        guard !identifier.isEmpty else { return nil }
        return events.first { CadenceEventNoteSupport.matches($0, identifier: identifier) }
    }

    static func results(from events: [EKEvent], query: String, now: Date = Date()) -> [EKEvent] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? events.filter { isUpcoming($0, now: now) }
            : events.filter { matches(query: trimmed, event: $0) }
        return filtered.sorted(by: precedes)
    }
}
