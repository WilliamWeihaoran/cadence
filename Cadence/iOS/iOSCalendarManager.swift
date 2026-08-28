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
    ) -> Bool {
        guard isAuthorized, endDate > startDate else { return false }
        guard let calendar = writableCalendar(with: calendarID) ?? writableCalendars.first else { return false }

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
            return true
        } catch {
            // Matches macOS, which resets on the create path too. The instance is local and
            // discarded here, so this is parity rather than an observable fix.
            event.reset()
            print("iOSCalendarManager: failed to create event: \(error)")
            return false
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
    ) -> Bool {
        guard isAuthorized, endDate > startDate, canModify(event) else { return false }
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
            return true
        } catch {
            // `EKEvent` is a reference type and this very instance is held by `CalendarEventItem`
            // and rendered by the timeline. A failed save emits no `EKEventStoreChanged`
            // notification, so nothing bumps `storeVersion` and nothing refetches: without
            // `reset()` the UI keeps showing an event that is not in the store, indefinitely.
            // macOS does this in `CalendarManager.save(_:span:describing:)`.
            event.reset()
            print("iOSCalendarManager: failed to update event: \(error)")
            return false
        }
    }

    @discardableResult
    func deleteEvent(_ event: EKEvent, span: EKSpan = .thisEvent) -> Bool {
        guard isAuthorized, canModify(event) else { return false }
        do {
            try store.remove(event, span: span)
            storeVersion += 1
            return true
        } catch {
            print("iOSCalendarManager: failed to delete event: \(error)")
            return false
        }
    }

    /// Pushes a note's text onto the native event, and says whether it landed.
    ///
    /// **T-325.** This returned `Void`, so its only report of a rejected write was a `print` —
    /// and its one caller, `iOSEventNoteEditorSheet`, called it *after* a `try?` save it had not
    /// checked either. Apple Calendar is not a surface Cadence can roll back, so the caller has
    /// to be able to see this answer. `Bool` rather than a failure enum is deliberate: it is the
    /// vocabulary the other three writes here already speak, and T-324's shared notice strings
    /// exist precisely because a `Bool` cannot name a cause.
    @discardableResult
    func updateEventNotes(_ event: EKEvent, notes: String) -> Bool {
        guard isAuthorized, canModify(event) else { return false }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextNotes = trimmed.isEmpty ? nil : notes
        // Already what the store holds: nothing to write, and nothing failed.
        guard event.notes != nextNotes else { return true }
        event.notes = nextNotes
        do {
            try store.save(event, span: .thisEvent)
            storeVersion += 1
            return true
        } catch {
            // Same hazard as `updateEvent`: the mutated `notes` would otherwise stick in the UI.
            event.reset()
            print("iOSCalendarManager: failed to update event notes: \(error)")
            return false
        }
    }

    @discardableResult
    func updateEventNotes(calendarEventID: String, notes: String) -> Bool {
        // An identifier that resolves to nothing is a sync that did not happen, not a no-op.
        guard let event = event(withIdentifier: calendarEventID) else { return false }
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
