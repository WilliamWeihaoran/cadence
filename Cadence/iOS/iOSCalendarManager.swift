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
        return store.calendars(for: .event).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Event" : title
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
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Event" : title
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

    func updateEventNotes(_ event: EKEvent, notes: String) {
        guard isAuthorized, canModify(event) else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextNotes = trimmed.isEmpty ? nil : notes
        guard event.notes != nextNotes else { return }
        event.notes = nextNotes
        do {
            try store.save(event, span: .thisEvent)
            storeVersion += 1
        } catch {
            print("iOSCalendarManager: failed to update event notes: \(error)")
        }
    }

    func updateEventNotes(calendarEventID: String, notes: String) {
        guard let event = event(withIdentifier: calendarEventID) else { return }
        updateEventNotes(event, notes: notes)
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
            self?.storeVersion += 1
        }
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
