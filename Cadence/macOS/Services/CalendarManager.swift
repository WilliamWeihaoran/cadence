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

    private let store = EKEventStore()

    private init() {}

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            isAuthorized = true
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
        return granted
    }

    // MARK: - Available Calendars

    var availableCalendars: [EKCalendar] {
        store.calendars(for: .event).sorted { $0.title < $1.title }
    }

    // MARK: - Create or Update Event

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

        // Build start date from scheduledDate + scheduledStartMin
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

    // MARK: - Delete Event

    func deleteEvent(calendarEventID: String) {
        guard !calendarEventID.isEmpty,
              let event = store.event(withIdentifier: calendarEventID) else { return }
        do {
            try store.remove(event, span: .thisEvent)
        } catch {
            print("CalendarManager: failed to delete event: \(error)")
        }
    }

    // MARK: - Handle Store Changes

    /// Call this when EKEventStoreChanged fires to reconcile tasks whose calendar events were deleted externally.
    func handleStoreChange(tasks: [AppTask], context: ModelContext) {
        for task in tasks where !task.calendarEventID.isEmpty {
            if store.event(withIdentifier: task.calendarEventID) == nil {
                task.scheduledStartMin = -1
                task.calendarEventID = ""
            }
        }
        try? context.save()
    }

    // MARK: - Observe Changes

    private var storeObserver: NSObjectProtocol?

    func observeChanges(tasks: [AppTask], context: ModelContext) {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.handleStoreChange(tasks: tasks, context: context)
        }
    }
}
#endif
