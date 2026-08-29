import Foundation

/// Why an EventKit write did not happen.
///
/// Every write used to end in a bare `return` or a swallowed `print`, so a drag-to-create against
/// a read-only calendar, a hidden-away last writable calendar, or access revoked mid-session all
/// looked identical to success: the gesture completed, the popover dismissed, the ghost cleared,
/// and nothing appeared.
///
/// **T-339 moved this out of `CalendarManager.swift` and into `Shared/`.** That file is one large
/// `#if os(macOS)`, so the only platform that could name a cause was the one that already had a
/// shared alert to show it in. iOS answered `Bool` from all five of its writes and reached for
/// `CadenceCalendarEventEditingSupport`'s one-sentence notices, which exist *because* a `Bool`
/// cannot say why — three vocabularies for one question. Nothing here was ever desktop-only: it
/// is a bare value type over `String`s with no EventKit in it.
///
/// `nonisolated` for the reason `Cadence/Models/AGENTS.md` records for the data enums: the project
/// sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which hands a bare value type a main-actor
/// *synthesized* `Equatable`. Comparing two of these from a nonisolated context — which is what a
/// `#expect` macro expansion is — then warns "main actor-isolated conformance ... cannot be used in
/// nonisolated context; this is an error in the Swift 6 language mode". `CadenceEventNoteCommitOutcome`
/// is spelled the same way. Nothing on this type is actor-affine.
nonisolated enum CalendarWriteFailure: Equatable {
    case notAuthorized
    case noWritableCalendar
    case invalidRange
    /// The stored EventKit identifier no longer resolves to an event, so there was nothing to
    /// write to. Distinct from `saveFailed`: the store never refused anything, it was never asked.
    case eventNotFound
    case saveFailed(String)

    var title: String {
        switch self {
        case .notAuthorized:      return "No Calendar Access"
        case .noWritableCalendar: return "No Writable Calendar"
        case .invalidRange:       return "Invalid Event Time"
        case .eventNotFound:      return "Event Not in Apple Calendar"
        case .saveFailed:         return "Calendar Change Not Saved"
        }
    }

    var message: String {
        switch self {
        case .notAuthorized:
            return "Cadence can't reach your calendars. Grant Calendar access in Settings → Calendar to create and edit events."
        case .noWritableCalendar:
            return "No calendar is available to write to. The calendar may be read-only, or hidden in Settings → Calendar."
        case .invalidRange:
            return "The event needs to end after it starts."
        case .eventNotFound:
            return "The event this note is linked to is no longer in Apple Calendar, so the change stayed in Cadence."
        case .saveFailed(let reason):
            return "Your calendar rejected the change, so it was undone.\n\n\(reason)"
        }
    }
}
