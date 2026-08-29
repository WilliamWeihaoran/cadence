#if os(iOS)
import EventKit
import Foundation
import Observation

@Observable
final class iOSCalendarManager {
    static let shared = iOSCalendarManager()

    var isAuthorized = false
    var storeVersion = 0

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    private init() {
        refreshAuthorizationState()
    }

    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    var allCalendars: [EKCalendar] {
        guard isAuthorized else { return [] }
        return CadenceCalendarSorting.sorted(store.calendars(for: .event))
    }

    var availableCalendars: [EKCalendar] {
        allCalendars.filter { CalendarVisibilityPreferences.isActive($0.calendarIdentifier) }
    }

    var writableCalendars: [EKCalendar] {
        availableCalendars.filter(\.allowsContentModifications)
    }

    /// Whether EventKit will accept writes to this event. Birthdays, Holidays and subscribed
    /// feeds are visible but read-only, and `fetchEvents` deliberately returns them, so every
    /// mutation below has to ask before it tries.
    func canModify(_ event: EKEvent) -> Bool {
        event.calendar?.allowsContentModifications ?? false
    }

    func refreshAuthorizationState() {
        applyAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
    }

    @discardableResult
    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            await MainActor.run {
                applyAuthorizationStatus(status)
            }
            return true
        case .notDetermined, .writeOnly:
            break
        default:
            await MainActor.run {
                applyAuthorizationStatus(status)
            }
            return false
        }

        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        await MainActor.run {
            if granted {
                applyAuthorizationStatus(.fullAccess)
            } else {
                isAuthorized = false
                stopObserving()
            }
        }
        return granted
    }

    func fetchEvents(for date: Date) -> [EKEvent] {
        guard isAuthorized, !availableCalendars.isEmpty else { return [] }
        let bounds = dayBounds(for: date)
        let predicate = store.predicateForEvents(withStart: bounds.start, end: bounds.end, calendars: availableCalendars)
        return store.events(matching: predicate)
            .sorted(by: CadenceCalendarEventSearchSupport.precedes)
    }

    func event(withIdentifier identifier: String) -> EKEvent? {
        guard isAuthorized, !identifier.isEmpty else { return nil }
        return store.event(withIdentifier: CadenceEventNoteSupport.lookupIdentifier(from: identifier))
    }

    /// Every event in the window, all-day included. The window and the filter are the *same* on
    /// both platforms — see `CadenceCalendarEventSearchSupport`, which owns the matching rule.
    func searchEvents(matching query: String, pastDays: Int = 60, futureDays: Int = 365) -> [EKEvent] {
        guard isAuthorized, !availableCalendars.isEmpty else { return [] }

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -max(0, pastDays), to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: max(0, futureDays), to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: availableCalendars)

        return CadenceCalendarEventSearchSupport.results(
            from: store.events(matching: predicate),
            query: query,
            now: now
        )
    }

    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        calendarID: String?,
        notes: String? = nil,
        isAllDay: Bool = false
    ) -> CalendarWriteFailure? {
        guard isAuthorized else { return .notAuthorized }
        guard endDate > startDate else { return .invalidRange }
        guard let calendar = writableCalendar(with: calendarID) ?? writableCalendars.first else {
            return .noWritableCalendar
        }

        let event = EKEvent(eventStore: store)
        event.title = CadenceEventTitleSupport.storedTitle(title)
        event.isAllDay = isAllDay
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        event.notes = trimmedNotes.isEmpty ? nil : notes
        do {
            try store.save(event, span: .thisEvent)
            storeVersion += 1
            return nil
        } catch {
            // Matches macOS, which resets on the create path too. The instance is local and
            // discarded here, so this is parity rather than an observable fix.
            event.reset()
            print("iOSCalendarManager: failed to create event: \(error)")
            return .saveFailed(error.localizedDescription)
        }
    }

    @discardableResult
    func updateEvent(
        _ event: EKEvent,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarID: String?,
        notes: String? = nil,
        span: EKSpan = .thisEvent,
        isAllDay: Bool = false
    ) -> CalendarWriteFailure? {
        guard isAuthorized else { return .notAuthorized }
        guard endDate > startDate else { return .invalidRange }
        // A read-only calendar is the "no calendar available to write to" case, one event at a
        // time: EventKit will refuse the save, and the notice already names that possibility.
        guard canModify(event) else { return .noWritableCalendar }
        event.title = CadenceEventTitleSupport.storedTitle(title)
        event.isAllDay = isAllDay
        event.startDate = startDate
        event.endDate = endDate
        if let calendar = writableCalendar(with: calendarID) {
            event.calendar = calendar
        }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        event.notes = trimmedNotes.isEmpty ? nil : notes
        do {
            try store.save(event, span: span)
            storeVersion += 1
            return nil
        } catch {
            // `EKEvent` is a reference type and this very instance is held by `CalendarEventItem`
            // and rendered by the timeline. A failed save emits no `EKEventStoreChanged`
            // notification, so nothing bumps `storeVersion` and nothing refetches: without
            // `reset()` the UI keeps showing an event that is not in the store, indefinitely.
            // macOS does this in `CalendarManager.save(_:span:describing:)`.
            event.reset()
            print("iOSCalendarManager: failed to update event: \(error)")
            return .saveFailed(error.localizedDescription)
        }
    }

    @discardableResult
    func deleteEvent(_ event: EKEvent, span: EKSpan = .thisEvent) -> CalendarWriteFailure? {
        guard isAuthorized else { return .notAuthorized }
        guard canModify(event) else { return .noWritableCalendar }
        do {
            try store.remove(event, span: span)
            storeVersion += 1
            return nil
        } catch {
            print("iOSCalendarManager: failed to delete event: \(error)")
            return .saveFailed(error.localizedDescription)
        }
    }

    /// Pushes a note's text onto the native event, and says whether it landed.
    ///
    /// **T-325.** This returned `Void`, so its only report of a rejected write was a `print` —
    /// and its one caller, `iOSEventNoteEditorSheet`, called it *after* a `try?` save it had not
    /// checked either. Apple Calendar is not a surface Cadence can roll back, so the caller has
    /// to be able to see this answer.
    ///
    /// It answered `Bool`, matching the other three writes here, and T-324's shared notice
    /// strings exist precisely because a `Bool` cannot name a cause. **T-339** removed the reason
    /// for that: `CalendarWriteFailure` is shared now, so all five writes name one.
    @discardableResult
    func updateEventNotes(_ event: EKEvent, notes: String) -> CalendarWriteFailure? {
        guard isAuthorized else { return .notAuthorized }
        guard canModify(event) else { return .noWritableCalendar }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextNotes = trimmed.isEmpty ? nil : notes
        // Already what the store holds: nothing to write, and nothing failed.
        guard event.notes != nextNotes else { return nil }
        event.notes = nextNotes
        do {
            try store.save(event, span: .thisEvent)
            storeVersion += 1
            return nil
        } catch {
            // Same hazard as `updateEvent`: the mutated `notes` would otherwise stick in the UI.
            event.reset()
            print("iOSCalendarManager: failed to update event notes: \(error)")
            return .saveFailed(error.localizedDescription)
        }
    }

    @discardableResult
    func updateEventNotes(calendarEventID: String, notes: String) -> CalendarWriteFailure? {
        // An identifier that resolves to nothing is a sync that did not happen, not a no-op. That
        // sentence is what `.eventNotFound` was named for on the desktop side (T-389); until
        // T-339 this overload could only assert it in a comment.
        guard let event = event(withIdentifier: calendarEventID) else { return .eventNotFound }
        return updateEventNotes(event, notes: notes)
    }

    private func applyAuthorizationStatus(_ status: EKAuthorizationStatus) {
        if status == .fullAccess {
            isAuthorized = true
            startObserving()
        } else {
            isAuthorized = false
            stopObserving()
        }
    }

    private func startObserving() {
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.handleStoreChangeNotification()
        }
    }

    /// Handles an `EKEventStoreChanged` notification: bump the version *and* re-derive
    /// authorization.
    ///
    /// **T-323.** This used to be `storeVersion += 1` inline in the observer, which is only half
    /// of what the notification means — see `CadenceCalendarStoreChangeSupport`, which owns the
    /// pair so macOS and iOS cannot answer it differently again. Revoking Calendar access from
    /// Settings while Cadence kept running left `isAuthorized` true until the next launch, so
    /// every read guarded on it went on believing it had access it no longer had.
    func handleStoreChangeNotification() {
        CadenceCalendarStoreChangeSupport.apply(
            bumpVersion: { storeVersion += 1 },
            refreshAuthorization: { refreshAuthorizationState() }
        )
    }

    private func stopObserving() {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
            self.storeObserver = nil
        }
    }

    private func writableCalendar(with id: String?) -> EKCalendar? {
        guard let id else { return nil }
        return writableCalendars.first { $0.calendarIdentifier == id }
    }

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }
}
#endif
