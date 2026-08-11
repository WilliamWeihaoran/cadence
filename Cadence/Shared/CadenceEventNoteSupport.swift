#if os(iOS) || os(macOS)
import EventKit
import Foundation

enum CadenceEventNoteSupport {
    private static let occurrenceSeparator = "#occurrence="

    static func rawIdentifier(for event: EKEvent) -> String {
        if let eventIdentifier = event.eventIdentifier, !eventIdentifier.isEmpty {
            return eventIdentifier
        }
        let itemIdentifier = event.calendarItemIdentifier
        return itemIdentifier.isEmpty ? fallbackIdentifier(for: event) : itemIdentifier
    }

    static func identifier(for event: EKEvent) -> String {
        let baseIdentifier = rawIdentifier(for: event)
        guard let occurrenceDate = recurringOccurrenceDate(for: event) else {
            return baseIdentifier
        }
        return occurrenceIdentifier(baseIdentifier: baseIdentifier, occurrenceDate: occurrenceDate)
    }

    static func occurrenceIdentifier(
        baseIdentifier: String,
        occurrenceDate: Date,
        calendar: Calendar = .current
    ) -> String {
        let occurrenceMinute = startMinute(for: occurrenceDate, calendar: calendar)
        return "\(baseIdentifier)\(occurrenceSeparator)\(DateFormatters.dateKey(from: occurrenceDate)):\(occurrenceMinute)"
    }

    static func lookupIdentifier(from identifier: String) -> String {
        identifier.components(separatedBy: occurrenceSeparator).first ?? identifier
    }

    static func matches(_ event: EKEvent, identifier: String) -> Bool {
        identifier == self.identifier(for: event) || identifier == rawIdentifier(for: event)
    }

    /// The single definition of "this event belongs to a repeating series". `CalendarEventIdentity`
    /// and the iOS event editor both route here — three copies of this predicate existed before,
    /// and the wrong one shipped in all three.
    ///
    /// `occurrenceDate` is deliberately **not** part of the test. EventKit declares it
    /// `null_unspecified` and documents it as "nil for new events until you set startDate", so it
    /// is non-nil for every event that has ever been given a start date — recurring or not.
    /// Including it made the predicate unconditionally true, which is why a freshly created
    /// one-off event came back wearing a repeat glyph and raising a "Change recurring event?"
    /// scope dialog on every edit.
    ///
    /// `isDetached` stays: a detached occurrence is an instance whose attributes diverged from the
    /// series, and it is not guaranteed to carry the series' rules on its own copy.
    static func isRecurringSeriesMember(hasRecurrenceRules: Bool, isDetached: Bool) -> Bool {
        hasRecurrenceRules || isDetached
    }

    static func isRecurringSeriesMember(_ event: EKEvent) -> Bool {
        isRecurringSeriesMember(hasRecurrenceRules: event.hasRecurrenceRules, isDetached: event.isDetached)
    }

    static func note(for calendarEventID: String, in notes: [Note]) -> Note? {
        guard !calendarEventID.isEmpty else { return nil }
        if let exact = notes.first(where: { $0.kind == .meeting && $0.calendarEventID == calendarEventID }) {
            return exact
        }
        return legacyOccurrenceScopedNote(for: calendarEventID, in: notes)
    }

    /// Adopts a note written before `isRecurringSeriesMember` was fixed.
    ///
    /// While the predicate was always true, `identifier(for:)` appended `#occurrence=<day>:<min>`
    /// to **every** event — including one-off ones. Those notes are on disk. Now that a one-off
    /// event resolves to its bare identifier, the exact-ID lookup above would miss them and a
    /// second note would be created beside the user's existing one.
    ///
    /// This only fires when the caller asked with a *base* identifier, which after the fix happens
    /// only for events that are not series members — so a genuine series' per-occurrence notes are
    /// never collapsed onto one another. An ambiguous base (more than one candidate) is left to
    /// the date/title fallback rather than guessed at.
    private static func legacyOccurrenceScopedNote(for baseIdentifier: String, in notes: [Note]) -> Note? {
        guard baseIdentifier == lookupIdentifier(from: baseIdentifier) else { return nil }
        let candidates = notes.filter { note in
            note.kind == .meeting
                && note.calendarEventID != baseIdentifier
                && lookupIdentifier(from: note.calendarEventID) == baseIdentifier
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    static func note(
        for calendarEventID: String,
        eventTitle: String,
        calendarID: String,
        eventDateKey: String,
        eventStartMin: Int,
        eventEndMin: Int,
        in notes: [Note]
    ) -> Note? {
        if let exact = note(for: calendarEventID, in: notes) {
            return exact
        }

        let normalizedTitle = normalizedEventTitle(eventTitle)
        guard !calendarID.isEmpty,
              !eventDateKey.isEmpty,
              eventStartMin >= 0,
              eventEndMin >= 0,
              !normalizedTitle.isEmpty else {
            return nil
        }

        return notes.first { note in
            guard note.kind == .meeting,
                  note.calendarID == calendarID,
                  note.eventDateKey == eventDateKey,
                  note.eventStartMin == eventStartMin,
                  note.eventEndMin == eventEndMin else {
                return false
            }
            return normalizedEventTitle(note.title) == normalizedTitle
        }
    }

    /// Finds the note for an event, or creates one.
    ///
    /// `calendarID` / `eventDateKey` / `eventStartMin` / `eventEndMin` are **required**, and used
    /// to be defaulted to `""` / `""` / `-1` / `-1`. Every one of those defaults fails the guard
    /// in `note(for:eventTitle:calendarID:…)` above, so accepting them did not degrade the
    /// date/title fallback — it switched it off entirely and fell straight through to `insert()`.
    /// That fallback exists precisely because EventKit hands out a new identifier for the same
    /// event, so the short call spelling was the one that produced a duplicate note every time the
    /// user reopened an event. No caller ever used the defaults; only the failure mode survived.
    @discardableResult
    static func noteForEditing(
        calendarEventID: String,
        eventTitle: String,
        calendarID: String,
        eventDateKey: String,
        eventStartMin: Int,
        eventEndMin: Int,
        nativeNotes: String? = nil,
        notes: [Note],
        insert: (Note) -> Void
    ) -> Note? {
        guard !calendarEventID.isEmpty else { return nil }
        if let existing = note(
            for: calendarEventID,
            eventTitle: eventTitle,
            calendarID: calendarID,
            eventDateKey: eventDateKey,
            eventStartMin: eventStartMin,
            eventEndMin: eventEndMin,
            in: notes
        ) {
            if existing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Event Note" : eventTitle
            }
            if existing.calendarEventID.isEmpty || existing.calendarEventID != calendarEventID {
                existing.calendarEventID = calendarEventID
            }
            updateMetadata(
                existing,
                calendarID: calendarID,
                eventDateKey: eventDateKey,
                eventStartMin: eventStartMin,
                eventEndMin: eventEndMin
            )
            return existing
        }

        let resolvedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Event Note" : eventTitle
        let created = Note(
            kind: .meeting,
            title: resolvedTitle,
            content: initialContent(eventTitle: resolvedTitle, nativeNotes: nativeNotes),
            calendarEventID: calendarEventID,
            calendarID: calendarID,
            eventDateKey: eventDateKey,
            eventStartMin: eventStartMin,
            eventEndMin: eventEndMin
        )
        insert(created)
        return created
    }

    static func initialContent(eventTitle: String, nativeNotes: String?) -> String {
        let trimmedNativeNotes = (nativeNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNativeNotes.isEmpty {
            return nativeNotes ?? trimmedNativeNotes
        }
        let resolvedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Event Note" : eventTitle
        return "# \(resolvedTitle)\n\n"
    }

    static func eventDateMetadata(from event: EKEvent) -> (dateKey: String, startMin: Int, endMin: Int) {
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start
        return (
            DateFormatters.dateKey(from: start),
            startMinute(for: start),
            startMinute(for: end)
        )
    }

    static func updateMetadata(
        _ note: Note,
        calendarID: String,
        eventDateKey: String,
        eventStartMin: Int,
        eventEndMin: Int
    ) {
        var changed = false
        if !calendarID.isEmpty, note.calendarID != calendarID {
            note.calendarID = calendarID
            changed = true
        }
        if !eventDateKey.isEmpty, note.eventDateKey != eventDateKey {
            note.eventDateKey = eventDateKey
            changed = true
        }
        if eventStartMin >= 0, note.eventStartMin != eventStartMin {
            note.eventStartMin = eventStartMin
            changed = true
        }
        if eventEndMin >= 0, note.eventEndMin != eventEndMin {
            note.eventEndMin = eventEndMin
            changed = true
        }
        if changed {
            note.updatedAt = Date()
        }
    }

    static func meetingNotes(forLinkedCalendarID calendarID: String, in notes: [Note]) -> [Note] {
        let trimmed = calendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return notes
            .filter { $0.kind == .meeting && $0.calendarID == trimmed }
            .sorted {
                if $0.eventDateKey != $1.eventDateKey { return $0.eventDateKey > $1.eventDateKey }
                if $0.eventStartMin != $1.eventStartMin { return $0.eventStartMin > $1.eventStartMin }
                return $0.updatedAt > $1.updatedAt
            }
    }

    static func startMinute(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }

    private static func recurringOccurrenceDate(for event: EKEvent) -> Date? {
        guard isRecurringSeriesMember(event) else { return nil }
        return event.occurrenceDate
    }

    private static func fallbackIdentifier(for event: EKEvent) -> String {
        let start = event.startDate ?? event.occurrenceDate ?? Date.distantPast
        let startMinute = startMinute(for: start)
        let calendarID = event.calendar?.calendarIdentifier ?? "calendar"
        let title = (event.title ?? "untitled")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "|", with: "-")
        return "event-fallback|\(calendarID)|\(DateFormatters.dateKey(from: start))|\(startMinute)|\(title)"
    }

    private static func normalizedEventTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}
#endif
