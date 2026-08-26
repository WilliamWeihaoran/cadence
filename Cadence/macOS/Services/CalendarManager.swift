#if os(macOS)
// IMPORTANT: Before using CalendarManager, you must:
// 1. In Xcode: Select the Cadence target → Signing & Capabilities → + Capability → Calendars
// 2. In Info.plist: Add NSCalendarsFullAccessUsageDescription with a usage description string

import Foundation
import EventKit
import SwiftData
import Observation

enum CalendarRecurrenceEditScope: String, CaseIterable, Hashable {
    case thisOccurrence
    case futureOccurrences

    var label: String {
        switch self {
        case .thisOccurrence: return "Only This Event"
        case .futureOccurrences: return "This And Future Events"
        }
    }

    var eventSpan: EKSpan {
        switch self {
        case .thisOccurrence: return .thisEvent
        case .futureOccurrences: return .futureEvents
        }
    }
}

/// Why an EventKit write did not happen.
///
/// Every write used to end in a bare `return` or a swallowed `print`, so a drag-to-create against
/// a read-only calendar, a hidden-away last writable calendar, or access revoked mid-session all
/// looked identical to success: the gesture completed, the popover dismissed, the ghost cleared,
/// and nothing appeared.
enum CalendarWriteFailure: Equatable {
    case notAuthorized
    case noWritableCalendar
    case invalidRange
    case saveFailed(String)

    var title: String {
        switch self {
        case .notAuthorized:      return "No Calendar Access"
        case .noWritableCalendar: return "No Writable Calendar"
        case .invalidRange:       return "Invalid Event Time"
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
        case .saveFailed(let reason):
            return "Your calendar rejected the change, so it was undone.\n\n\(reason)"
        }
    }
}

@Observable
final class CalendarManager {

    static let shared = CalendarManager()

    var isAuthorized: Bool = false

    /// The most recent write failure, for a surface to present and clear. Views bind an alert to
    /// this rather than each inventing their own error path.
    var lastWriteFailure: CalendarWriteFailure?

    /// Increments whenever the EKEventStore changes — read this in views to subscribe to refreshes.
    var storeVersion: Int = 0

    /// True when the user has explicitly denied access — button should open System Settings instead of re-requesting.
    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    private init() {
        refreshAuthorizationState()
    }

    // MARK: - Authorization

    func refreshAuthorizationState() {
        applyAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
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

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            await MainActor.run {
                applyAuthorizationStatus(status)
            }
            return true
        case .notDetermined:
            break
        default:
            await MainActor.run {
                applyAuthorizationStatus(status)
            }
            return false
        }

        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { ok, _ in
                    continuation.resume(returning: ok)
                }
            }
        }
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

    // MARK: - Observing Store Changes

    /// Start listening for EKEventStoreChanged notifications. Call once; safe to call repeatedly.
    func startObserving() {
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.handleStoreChangeNotification()
        }
    }

    /// Handles an `EKEventStoreChanged` notification. EventKit posts this notification both for
    /// ordinary data changes (create/update/delete elsewhere) and when the user grants or revokes
    /// Calendar access from System Settings while Cadence keeps running. Re-deriving authorization
    /// here — not just bumping `storeVersion` — prevents `isAuthorized` from staying stale-true
    /// indefinitely after a mid-session revocation (previously only `refreshAuthorizationState()`
    /// at app-foreground caught that, so a revocation could go undetected until relaunch).
    ///
    /// The pair itself lives in `CadenceCalendarStoreChangeSupport` since T-323, when iOS was
    /// found still doing the version half only.
    func handleStoreChangeNotification() {
        CadenceCalendarStoreChangeSupport.apply(
            bumpVersion: { storeVersion += 1 },
            refreshAuthorization: { refreshAuthorizationState() }
        )
    }

    func stopObserving() {
        if let obs = storeObserver {
            NotificationCenter.default.removeObserver(obs)
            storeObserver = nil
        }
    }

    // MARK: - Available Calendars

    var allCalendars: [EKCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    var availableCalendars: [EKCalendar] {
        activeCalendars(from: allCalendars)
    }

    /// Calendars the user can write to (excludes read-only subscribed calendars).
    var writableCalendars: [EKCalendar] {
        guard isAuthorized else { return [] }
        return activeCalendars(from: store.calendars(for: .event))
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
    }

    var defaultWritableCalendar: EKCalendar? {
        guard isAuthorized else { return nil }
        if let calendar = store.defaultCalendarForNewEvents,
           calendar.allowsContentModifications,
           isActiveCalendar(calendar) {
            return calendar
        }
        return writableCalendars.first
    }

    // MARK: - Create Standalone Event (direct iCal event, not linked to a task)

    @discardableResult
    func createStandaloneEvent(title: String, startMin: Int, durationMinutes: Int, calendarID: String, date: Date, notes: String = "") -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        let selectedCalendar = calendarID.isEmpty ? defaultWritableCalendar : store.calendar(withIdentifier: calendarID)
        guard let calendar = selectedCalendar,
              calendar.allowsContentModifications,
              isActiveCalendar(calendar)
        else { return record(.noWritableCalendar) }
        let event = EKEvent(eventStore: store)
        event.title = title.isEmpty ? "New Event" : title
        let startOfDay = Calendar.current.startOfDay(for: date)
        event.startDate = startOfDay.addingTimeInterval(TimeInterval(startMin * 60))
        event.endDate = startOfDay.addingTimeInterval(TimeInterval((startMin + max(5, durationMinutes)) * 60))
        event.isAllDay = false
        event.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        event.calendar = calendar
        return save(event, span: .thisEvent, describing: "create standalone event")
    }

    // MARK: - Fetching Events

    /// Fetch all non-all-day events for a specific day.
    func fetchEvents(for date: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let calendars = availableCalendars
        guard !calendars.isEmpty else { return [] }
        let bounds = dayBounds(for: date)
        let predicate = store.predicateForEvents(withStart: bounds.start, end: bounds.end, calendars: calendars)
        return store.events(matching: predicate).filter { !$0.isAllDay }
    }

    /// Fetch all all-day events for a specific day.
    func fetchAllDayEvents(for date: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let calendars = availableCalendars
        guard !calendars.isEmpty else { return [] }
        let bounds = dayBounds(for: date)
        let predicate = store.predicateForEvents(withStart: bounds.start, end: bounds.end, calendars: calendars)
        return store.events(matching: predicate).filter { $0.isAllDay }
    }

    /// Returns an EKEvent from the store by its identifier.
    func event(withIdentifier identifier: String) -> EKEvent? {
        guard isAuthorized, !identifier.isEmpty else { return nil }
        return store.event(withIdentifier: identifier)
    }

    /// Convert an all-day event to a timed event at the specified minute offset on the given date.
    @discardableResult
    func convertAllDayEventToTimed(_ event: EKEvent, startMin: Int, dateKey: String) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        guard let baseDate = DateFormatters.date(from: dateKey) else { return record(.invalidRange) }
        let cal = Calendar.current
        event.isAllDay = false
        event.startDate = cal.date(byAdding: .minute, value: startMin, to: baseDate) ?? baseDate
        event.endDate = cal.date(byAdding: .minute, value: startMin + 60, to: baseDate) ?? baseDate
        return save(event, span: .thisEvent, describing: "convert all-day event")
    }

    /// Every event in the window, all-day included. The window and the filter are the *same* on
    /// both platforms — see `CadenceCalendarEventSearchSupport`, which owns the matching rule and
    /// records why the all-day exclusion that used to live here was a bug rather than an intent.
    func searchEvents(matching query: String, pastDays: Int = 60, futureDays: Int = 365) -> [EKEvent] {
        CadenceCalendarEventSearchSupport.results(
            from: windowEvents(pastDays: pastDays, futureDays: futureDays),
            query: query
        )
    }

    /// The same window `searchEvents` reads, with no query filter applied at all.
    ///
    /// Split out for the one caller that resolves a picked Cmd+K result back to an `EKEvent`.
    /// It used to ask for the window by searching it with an empty query, which is the branch
    /// that keeps only what has not ended yet — so a past event was findable and not openable.
    /// See `CadenceCalendarEventSearchSupport.event(from:identifier:)`.
    func windowEvents(pastDays: Int = 60, futureDays: Int = 365) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let calendars = availableCalendars
        guard !calendars.isEmpty else { return [] }

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -max(0, pastDays), to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: max(0, futureDays), to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
    }

    // MARK: - Update External Event (iCal event edited in Cadence)

    /// Update an EKEvent's title and time, then save back to iCal.
    @discardableResult
    func updateEvent(
        _ event: EKEvent,
        title: String,
        startMin: Int,
        durationMinutes: Int,
        dateKey: String,
        calendarID: String? = nil,
        notes: String? = nil,
        scope: CalendarRecurrenceEditScope = .thisOccurrence
    ) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        guard let baseDate = DateFormatters.date(from: dateKey) else { return record(.invalidRange) }
        let cal = Calendar.current
        let startDate = cal.date(byAdding: .minute, value: startMin, to: baseDate) ?? baseDate
        let endDate = cal.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate) ?? startDate
        return updateEvent(
            event,
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendarID: calendarID,
            notes: notes,
            scope: scope
        )
    }

    @discardableResult
    func updateEvent(
        _ event: EKEvent,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarID: String? = nil,
        notes: String? = nil,
        scope: CalendarRecurrenceEditScope = .thisOccurrence
    ) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        guard endDate > startDate else { return record(.invalidRange) }
        event.title = title.isEmpty ? "Untitled" : title
        event.startDate = startDate
        event.endDate = endDate
        if let notes {
            event.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        }
        if let calendarID,
           let targetCalendar = store.calendar(withIdentifier: calendarID),
           targetCalendar.allowsContentModifications {
            event.calendar = targetCalendar
        }
        return save(event, span: scope.eventSpan, describing: "update event")
    }

    @discardableResult
    func updateEventNotes(_ event: EKEvent, notes: String) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextNotes = trimmed.isEmpty ? nil : notes
        guard event.notes != nextNotes else { return nil }
        event.notes = nextNotes
        return save(event, span: .thisEvent, describing: "update event notes")
    }

    @discardableResult
    func updateEventNotes(calendarEventID: String, notes: String) -> CalendarWriteFailure? {
        let lookupID = CalendarEventIdentity.lookupIdentifier(from: calendarEventID)
        guard let event = event(withIdentifier: lookupID) else { return nil }
        return updateEventNotes(event, notes: notes)
    }

    // MARK: - Delete Event

    /// Delete an EKEvent directly (used from the event edit popover).
    @discardableResult
    func deleteEvent(_ event: EKEvent, scope: CalendarRecurrenceEditScope = .thisOccurrence) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        do {
            try store.remove(event, span: scope.eventSpan)
            return nil
        } catch {
            return record(.saveFailed(error.localizedDescription))
        }
    }

    // MARK: - Write plumbing

    /// Saves an `EKEvent` that has already been mutated in memory, and puts it back if the save
    /// fails.
    ///
    /// `EKEvent` is a reference type and the very same instance is held by `CalendarEventItem`
    /// and rendered by the timeline. Mutating it and then swallowing a `save` error — a read-only
    /// calendar, access revoked mid-session, an iCloud conflict — left the UI showing an event
    /// that does not exist in the store, with nothing to clear it: no `EKEventStoreChanged`
    /// notification means no `storeVersion` bump and no refetch. `reset()` returns the object to
    /// its last saved state so the next render shows what is really there.
    private func save(_ event: EKEvent, span: EKSpan, describing operation: String) -> CalendarWriteFailure? {
        do {
            try store.save(event, span: span)
            return nil
        } catch {
            event.reset()
            print("CalendarManager: failed to \(operation): \(error)")
            return record(.saveFailed(error.localizedDescription))
        }
    }

    @discardableResult
    private func record(_ failure: CalendarWriteFailure) -> CalendarWriteFailure {
        lastWriteFailure = failure
        return failure
    }

    /// Internal (not private) and calendar-injectable so day-boundary correctness — including
    /// across DST transitions — is directly testable without touching live EventKit. Uses
    /// `Calendar`'s wall-clock-aware day arithmetic (not a fixed 24-hour offset), so a day that is
    /// actually 23 or 25 hours long around a DST transition still resolves to exactly one calendar
    /// day rather than drifting into the wrong day.
    func dayBounds(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    private func activeCalendars(from calendars: [EKCalendar]) -> [EKCalendar] {
        calendars.filter(isActiveCalendar)
    }

    private func isActiveCalendar(_ calendar: EKCalendar) -> Bool {
        CalendarVisibilityPreferences.isActive(calendar.calendarIdentifier)
    }
}
#endif
