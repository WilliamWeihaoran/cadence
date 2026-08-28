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

    /// The start this file orders on: `startDate`, or the occurrence's own date when EventKit hands
    /// back a series member with no start of its own.
    static func startInstant(of event: EKEvent) -> Date {
        event.startDate ?? event.occurrenceDate ?? Date.distantFuture
    }

    /// The identity leg of `precedes`, and the reason it is spelled here rather than borrowed.
    ///
    /// `CadenceEventNoteSupport` owns what an event identifier *is*, and `event(from:identifier:)`
    /// below pays main-actor isolation to use it. `precedes` cannot: it is handed to `sorted(by:)`
    /// from `iOSCalendarManager.fetchEvents` as a plain function value, so it has to stay
    /// `nonisolated`. What it reads is the same pair of EventKit fields
    /// `CadenceEventNoteSupport.rawIdentifier` reads, in the same order, and it deliberately does
    /// **not** reach for that function's `#occurrence=` suffix: occurrences of one series differ in
    /// `startInstant`, which is compared first, so the suffix could never break a tie this leg is
    /// asked to break.
    ///
    /// Measured rather than assumed: EventKit gives even a never-saved `EKEvent` a distinct
    /// `calendarItemIdentifier`, so this leg separates two such events too. The comparator is still
    /// exposed field-by-field below, so the leg can be pinned against chosen identities rather than
    /// against whatever EventKit happens to mint.
    static func identity(of event: EKEvent) -> String {
        if let eventIdentifier = event.eventIdentifier, !eventIdentifier.isEmpty {
            return eventIdentifier
        }
        return event.calendarItemIdentifier
    }

    /// **T-373.** A **total** order: start, then title, then identity.
    ///
    /// It was called total while it stopped at title. Two events sharing a start *and* a title are
    /// not the exotic case the name implied they were — a recurring meeting fetched across a window
    /// gives one per occurrence, an all-day event starts at midnight like every other all-day
    /// event, and a calendar subscribed to twice yields the same meeting twice. Tied, `sorted` was
    /// free to return either arrangement, so the Mac's Cmd+K results and the iPhone's event list
    /// could reorder themselves between two identical reads.
    ///
    /// Deliberately not a `Comparable` conformance on some wrapper, for the reason
    /// `CadenceMCPOrdering.precedes` gives: the title leg is case-insensitive while a synthesized
    /// `==` would not be, which would leave `"standup"` and `"Standup"` neither ordered nor equal.
    static func precedes(_ lhs: EKEvent, _ rhs: EKEvent) -> Bool {
        isOrderedBefore(
            lhsStart: startInstant(of: lhs),
            lhsTitle: lhs.title ?? "",
            lhsIdentity: identity(of: lhs),
            rhsStart: startInstant(of: rhs),
            rhsTitle: rhs.title ?? "",
            rhsIdentity: identity(of: rhs)
        )
    }

    /// The comparator over the three fields it reads, so a test can pin every leg — the identity
    /// one included — without an `EKEventStore` that has saved anything. The same shape
    /// `CadenceCalendarSorting.isOrderedBefore` uses, and for the same reason.
    static func isOrderedBefore(
        lhsStart: Date,
        lhsTitle: String,
        lhsIdentity: String,
        rhsStart: Date,
        rhsTitle: String,
        rhsIdentity: String
    ) -> Bool {
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        let titles = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
        if titles != .orderedSame { return titles == .orderedAscending }
        return lhsIdentity < rhsIdentity
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
