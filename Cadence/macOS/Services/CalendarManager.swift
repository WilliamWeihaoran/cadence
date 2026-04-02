#if os(macOS)
// IMPORTANT: Before using CalendarManager, you must:
// 1. In Xcode: Select the Cadence target → Signing & Capabilities → + Capability → Calendars
// 2. In Info.plist: Add NSCalendarsFullAccessUsageDescription with a usage description string

import Foundation
import EventKit
import SwiftData
import Observation

@Observable
final class CalendarManager {

    static let shared = CalendarManager()

    var isAuthorized: Bool = false

    /// Increments whenever the EKEventStore changes — read this in views to subscribe to refreshes.
    var storeVersion: Int = 0

    /// True when the user has explicitly denied access — button should open System Settings instead of re-requesting.
    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            isAuthorized = true
            startObserving()
            return true
        case .notDetermined:
            break
        default:
            isAuthorized = false
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
        isAuthorized = granted
        if granted { startObserving() }
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
            self?.storeVersion += 1
        }
    }

    func stopObserving() {
        if let obs = storeObserver {
            NotificationCenter.default.removeObserver(obs)
            storeObserver = nil
        }
    }

    // MARK: - Available Calendars

    var availableCalendars: [EKCalendar] {
        store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    /// Calendars the user can write to (excludes read-only subscribed calendars).
    var writableCalendars: [EKCalendar] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
    }

    // MARK: - Create Standalone Event (direct iCal event, not linked to a task)

    func createStandaloneEvent(title: String, startMin: Int, durationMinutes: Int, calendarID: String, date: Date, notes: String = "") {
        guard isAuthorized else { return }
        guard let calendar = store.calendar(withIdentifier: calendarID) else { return }
        let event = EKEvent(eventStore: store)
        event.title = title.isEmpty ? "New Event" : title
        let startOfDay = Calendar.current.startOfDay(for: date)
        event.startDate = startOfDay.addingTimeInterval(TimeInterval(startMin * 60))
        event.endDate = startOfDay.addingTimeInterval(TimeInterval((startMin + max(5, durationMinutes)) * 60))
        event.isAllDay = false
        event.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            print("CalendarManager: failed to create standalone event: \(error)")
        }
    }

    // MARK: - Fetching Events

    /// Fetch all non-all-day events for a specific day.
    func fetchEvents(for date: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).filter { !$0.isAllDay }
    }

    func searchEvents(matching query: String, pastDays: Int = 60, futureDays: Int = 365) -> [EKEvent] {
        guard isAuthorized else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -pastDays, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: futureDays, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)

        let events = store.events(matching: predicate).filter { !$0.isAllDay }
        guard !trimmed.isEmpty else {
            return events
                .filter { ($0.endDate ?? now) >= now }
                .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
        }

        let needle = trimmed.localizedLowercase
        return events
            .filter { event in
                let fields = [
                    event.title ?? "",
                    event.notes ?? "",
                    event.calendar?.title ?? ""
                ]
                return fields.contains { $0.localizedLowercase.contains(needle) }
            }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
    }

    // MARK: - Create or Update Event (Cadence task → iCal)

    func createOrUpdateEvent(for task: AppTask, calendarID: String) {
        guard !task.scheduledDate.isEmpty, task.scheduledStartMin >= 0 else { return }
        guard let calendar = store.calendar(withIdentifier: calendarID) else { return }

        let event: EKEvent
        if !task.calendarEventID.isEmpty,
           let existing = store.event(withIdentifier: task.calendarEventID) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = calendar
        }

        event.title = task.title.isEmpty ? "Untitled Task" : task.title

        guard let baseDate = DateFormatters.date(from: task.scheduledDate) else { return }

        let cal = Calendar.current
        let startDate = cal.date(byAdding: .minute, value: task.scheduledStartMin, to: baseDate) ?? baseDate
        let durationMinutes = max(task.estimatedMinutes, 60)
        let endDate = cal.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate

        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = false

        do {
            try store.save(event, span: .thisEvent)
            task.calendarEventID = event.eventIdentifier
        } catch {
            print("CalendarManager: failed to save event: \(error)")
        }
    }

    // MARK: - Update External Event (iCal event edited in Cadence)

    /// Update an EKEvent's title and time, then save back to iCal.
    func updateEvent(_ event: EKEvent, title: String, startMin: Int, durationMinutes: Int, dateKey: String, calendarID: String? = nil, notes: String? = nil) {
        guard let baseDate = DateFormatters.date(from: dateKey) else { return }
        let cal = Calendar.current
        let startDate = cal.date(byAdding: .minute, value: startMin, to: baseDate) ?? baseDate
        let endDate = cal.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate) ?? startDate
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
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            print("CalendarManager: failed to update event: \(error)")
        }
    }

    // MARK: - Delete Event

    /// Delete a calendar event by its stored identifier string (used when unscheduling a task).
    func deleteEvent(calendarEventID: String) {
        guard !calendarEventID.isEmpty,
              let event = store.event(withIdentifier: calendarEventID) else { return }
        do {
            try store.remove(event, span: .thisEvent)
        } catch {
            print("CalendarManager: failed to delete event: \(error)")
        }
    }

    /// Delete an EKEvent directly (used from the event edit popover).
    func deleteEvent(_ event: EKEvent) {
        do {
            try store.remove(event, span: .thisEvent)
        } catch {
            print("CalendarManager: failed to delete event: \(error)")
        }
    }

    // MARK: - iCal → Cadence Task Sync

    /// Sync a task's scheduled time from its linked EKEvent.
    /// If the event was deleted externally, clears the task's schedule.
    func syncTaskFromLinkedEvent(_ task: AppTask) {
        guard !task.calendarEventID.isEmpty else { return }
        if let event = store.event(withIdentifier: task.calendarEventID) {
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: event.startDate)
            let newStartMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            let newDuration = max(5, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
            let newDateKey = DateFormatters.dateKey(from: event.startDate)
            task.scheduledStartMin = newStartMin
            task.estimatedMinutes = newDuration
            task.scheduledDate = newDateKey
        } else {
            // Event was deleted externally — unschedule the task
            task.scheduledStartMin = -1
            task.scheduledDate = ""
            task.calendarEventID = ""
        }
    }
}
#endif
