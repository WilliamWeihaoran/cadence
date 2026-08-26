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
    /// Shown when an event write was rejected.
    ///
    /// One sentence, not four: `createEvent`/`updateEvent` answer `Bool`, so missing Calendar
    /// access, no writable calendar, a rejected date range and a throwing EventKit save are the
    /// same value by the time a sheet can react. Naming a cause the return type cannot support
    /// would be a guess printed as a fact. Both iOS event sheets read these two strings so the
    /// wording cannot drift into a third variant (T-324).
    static let saveFailureNotice = "Couldn't save this event to Apple Calendar."

    /// The delete half of `saveFailureNotice`, for the same reason.
    static let deleteFailureNotice = "Couldn't delete this event from Apple Calendar."

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
