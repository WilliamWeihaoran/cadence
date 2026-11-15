import EventKit
import Foundation

/// **Which fetched events Cadence draws, and which it draws as cancelled — one rule, both
/// platforms** ([[T-18007]], under [[T-8201]]).
///
/// No fetch used to read an event's participation or status, so a meeting the owner declined and
/// one its organizer cancelled were drawn exactly like a meeting they were going to: full-weight
/// blocks taking their column in the overlap layout, and the day read busier in Cadence than in
/// the app the events came from.
///
/// - **Declined** (the current user's attendee answered `.declined`) is **hidden**, matching
///   Apple Calendar's default ("Show Declined Events" off). Applied in both managers' day fetches
///   and search windows, so every surface downstream — Day/Week, Board, Today, Search — agrees.
/// - **Cancelled** (`status == .canceled`, which Exchange and Google leave on the calendar) is
///   kept and drawn struck through and dimmed, with "cancelled" spoken, so the slot reads as free
///   without the event silently vanishing.
///
/// The rule is decided over plain values (`Attendee`, `EKEventStatus`) so the suite can pin it
/// without an `EKEventStore`; the `EKEvent` overloads only read those values off the event.
/// An account whose server does not mark the current user (`isCurrentUser` false for every
/// attendee, which some CalDAV servers do) has no declined answer to read, so its events stay shown.
nonisolated enum CadenceCalendarEventVisibility {
    /// The two facts about one attendee the rule reads.
    struct Attendee: Equatable {
        let isCurrentUser: Bool
        let status: EKParticipantStatus
    }

    /// Whether an event with these attendees is drawn at all.
    static func isShown(attendees: [Attendee]) -> Bool {
        guard let me = attendees.first(where: { $0.isCurrentUser }) else { return true }
        return me.status != .declined
    }

    /// Whether an event with this status is drawn as cancelled.
    static func isCancelled(status: EKEventStatus) -> Bool {
        status == .canceled
    }

    /// How much a cancelled block is dimmed: the whole block, plate and labels together, so no
    /// label tier moves against the plate it was solved on.
    static let cancelledOpacity: Double = 0.5

    // MARK: - EKEvent adapters

    static func attendees(of event: EKEvent) -> [Attendee] {
        (event.attendees ?? []).map {
            Attendee(isCurrentUser: $0.isCurrentUser, status: $0.participantStatus)
        }
    }

    static func isShown(_ event: EKEvent) -> Bool {
        isShown(attendees: attendees(of: event))
    }

    static func isCancelled(_ event: EKEvent) -> Bool {
        isCancelled(status: event.status)
    }

    /// The filter both managers apply to every `store.events(matching:)` they hand out.
    static func shown(_ events: [EKEvent]) -> [EKEvent] {
        events.filter(isShown)
    }
}
