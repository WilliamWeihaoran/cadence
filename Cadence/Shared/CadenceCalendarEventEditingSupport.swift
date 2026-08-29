import Foundation

/// The rules for editing an Apple Calendar event, with EventKit factored out so they can be
/// asserted on.
///
/// Cadence shows every *visible* calendar's events, but only some calendars accept writes —
/// Birthdays, Holidays and any subscribed feed are read-only. The event editor previously
/// assumed every event it was handed was editable: it rewrote the sheet's calendar selection to
/// the first writable calendar on appear, so a birthday claimed to live in "Personal", and left
/// Save and Delete enabled on an event EventKit would refuse. Both then failed silently — the
/// save threw, the sheet stayed open, and nothing said why.
enum CadenceCalendarEventEditingSupport {
    /// Shown when an event write was rejected, and says only what the *operation* was.
    ///
    /// One sentence, because when T-324 wrote it `createEvent`/`updateEvent` answered `Bool`:
    /// missing Calendar access, no writable calendar, a rejected date range and a throwing
    /// EventKit save were the same value by the time a sheet could react, and naming a cause the
    /// return type could not support would have been a guess printed as a fact.
    ///
    /// **T-339 gave iOS a return type that can.** This stays as the sentence a caller with no
    /// typed failure in hand still needs — and as the lead of `saveFailureNotice(for:)`, which is
    /// what the sheets now show. Both iOS event sheets read these so the wording cannot drift
    /// into a third variant.
    static let saveFailureNotice = "Couldn't save this event to Apple Calendar."

    /// The delete half of `saveFailureNotice`, for the same reason.
    static let deleteFailureNotice = "Couldn't delete this event from Apple Calendar."

    /// What a sheet shows when a save was refused: the operation, then the cause.
    ///
    /// Two sentences rather than one, and the cause is `CalendarWriteFailure.message` rather than
    /// a second wording of it — that is the same string the desktop alert has always shown, which
    /// is the point of the port. `failure` is optional because a sheet can still fail before it
    /// reaches EventKit at all (an unparseable date key), and inventing a cause for that would be
    /// the exact mistake T-324 refused to make.
    static func saveFailureNotice(for failure: CalendarWriteFailure?) -> String {
        notice(operation: saveFailureNotice, failure: failure)
    }

    /// The delete half of `saveFailureNotice(for:)`.
    static func deleteFailureNotice(for failure: CalendarWriteFailure?) -> String {
        notice(operation: deleteFailureNotice, failure: failure)
    }

    private static func notice(operation: String, failure: CalendarWriteFailure?) -> String {
        guard let failure else { return operation }
        return "\(operation) \(failure.message)"
    }

    /// Shown in place of the calendar picker and the delete button when the event cannot be
    /// written. It names the calendar so the sentence is about *this* event rather than a
    /// general disclaimer.
    static func readOnlyNotice(calendarName: String) -> String {
        let name = calendarName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "This event is on a read-only calendar, so it can only be viewed here. Edit it in Apple Calendar."
        }
        return "\(name) is a read-only calendar, so this event can only be viewed here. Edit it in Apple Calendar."
    }

    /// Which calendar the sheet should show as selected.
    ///
    /// A writable event keeps its own calendar when that calendar is still selectable, and
    /// otherwise falls back to the first writable one so the picker is never empty. A **read-only**
    /// event always keeps its own identifier: substituting a writable calendar there told the user
    /// the event lived somewhere it does not.
    static func resolvedCalendarID(
        eventCalendarID: String,
        isEventEditable: Bool,
        writableCalendarIDs: [String]
    ) -> String {
        guard isEventEditable else { return eventCalendarID }
        if writableCalendarIDs.contains(eventCalendarID) { return eventCalendarID }
        return writableCalendarIDs.first ?? ""
    }

    /// Whether the Save button should be enabled. A read-only event can never be saved, however
    /// complete the form is.
    static func canSave(
        title: String,
        isEventEditable: Bool,
        selectedCalendarID: String,
        writableCalendarIDs: [String]
    ) -> Bool {
        guard isEventEditable else { return false }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return writableCalendarIDs.contains(selectedCalendarID)
    }
}
