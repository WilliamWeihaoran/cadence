#if os(macOS)
// IMPORTANT: Before using CalendarManager, you must:
// 1. In Xcode: Select the Cadence target → Signing & Capabilities → + Capability → Calendars
// 2. In Info.plist: Add NSCalendarsFullAccessUsageDescription with a usage description string

import Foundation
import EventKit
import SwiftData
import Observation

// Two types that used to be declared here have moved out to `Cadence/Shared/`, both because this
// file is one big `#if os(macOS)` and neither of them was ever desktop-only:
//
// - `CalendarWriteFailure` — the typed reason a write did not happen — under T-339, which is the
//   whole reason iOS used to have to answer `Bool`.
// - `CalendarRecurrenceEditScope` — which occurrences a write applies to — under T-549, which
//   deleted the byte-identical private copy `iOSCalendarEventEditSheet` had been keeping.

@Observable
final class CalendarManager {

    static let shared = CalendarManager()

    /// **T-3032. `private(set)`, and the setter is the whole safety argument for this type.**
    ///
    /// This flag is the *only* guard on all six EventKit write paths here — `createStandaloneEvent`,
    /// both `updateEvent` overloads, `updateEventNotes`, `convertAllDayEventToTimed` and
    /// `deleteEvent` each open with `guard isAuthorized else { return record(.notAuthorized) }` and
    /// nothing else stands between the call and `store.save` / `store.remove`. Those writes land in
    /// the user's real Calendar, outside Cadence and not undoable from inside it. So a plain `var`
    /// here let any caller in the module — in practice, a test — mint the one permission the whole
    /// file rests on, and `CalendarManagerScenarioTests` did exactly that on `shared`, which holds a
    /// real `EKEventStore`: safe only because each such test then handed EventKit an event built
    /// from a throwaway store, which EventKit refuses. The call it happened not to make
    /// (`createStandaloneEvent(…, calendarID: "")`) resolves `store.defaultCalendarForNewEvents` and
    /// writes for real.
    ///
    /// `RemindersManager` next door has spelled the same flag `private(set)` all along, so this was
    /// an asymmetry in the tree rather than a matter of taste. Inside the type the value still has
    /// exactly the three writers it always had — `applyAuthorizationStatus`, `requestAccess`'s
    /// refusal branch, and (DEBUG only) the test seam below — and *when* a write happens is
    /// unchanged; T-3032 is about who may set the flag, not about when Cadence may write. What an
    /// agent or UI-test launch may reach is T-3031: nothing — see `isEventKitDisarmed`.
    private(set) var isAuthorized: Bool = false

    /// The most recent write failure, for a surface to present and clear. Views bind an alert to
    /// this rather than each inventing their own error path.
    var lastWriteFailure: CalendarWriteFailure?

    /// Increments whenever the EKEventStore changes — read this in views to subscribe to refreshes.
    var storeVersion: Int = 0

    /// True when the user has explicitly denied access — button should open System Settings instead of re-requesting.
    var isDenied: Bool {
        // [[T-3031]]: a disarmed launch does not ask TCC anything, so it is never "denied" either —
        // which also keeps the Connect button from sending an agent to System Settings.
        guard !isEventKitDisarmed else { return false }
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    private let store: EKEventStore
    private var storeObserver: NSObjectProtocol?

    /// **[[T-3031]]. `true` on an agent (`run-macos-app.sh`) or `CadenceUITests` launch** — see
    /// `CadenceEventKitLaunchGate` for the three variables and why any one is enough.
    ///
    /// Such a launch inherits the owner's Calendar grant through the debug build's bundle id, so
    /// without this `shared` read `.fullAccess`, observed the real store, and every create, update
    /// and delete below landed in the owner's real Calendar. When it is set the manager is inert
    /// at every door EventKit has: authorization is never read and always applies as not granted
    /// (`refreshAuthorizationState`, `requestAccess`, `applyAuthorizationStatus`), no
    /// `EKEventStoreChanged` observer is ever registered (`startObserving`), and the two sinks every
    /// write funnels through (`save`, `deleteEvent`) refuse with `.notAuthorized` even if the flag
    /// were somehow true — so the write gate does not rest on the authorization gate alone.
    ///
    /// Fixed at construction: a launch's environment does not change while it runs.
    private let isEventKitDisarmed: Bool

    private init() {
        self.store = EKEventStore()
        self.isEventKitDisarmed = CadenceEventKitLaunchGate.isDisarmedForThisProcess
        refreshAuthorizationState()
    }

    /// Whether a live `EKEventStoreChanged` observer is registered. Read by the T-3031 tests.
    var isObservingStoreChanges: Bool { storeObserver != nil }

    #if DEBUG
    /// **T-3032 — the only way to obtain an authorized `CalendarManager` from outside the type, and
    /// it does not exist in a release build.**
    ///
    /// A test that needs to run the code *after* the `guard isAuthorized` — the save-rollback paths,
    /// the inverted-range refusal, the all-day conversion — used to force `shared.isAuthorized =
    /// true`, which authorizes the singleton that owns the process's real, granted `EKEventStore`
    /// for as long as the `defer` has not run. This builds a **separate** manager over a store the
    /// caller owns instead, so nothing a test does can leave `shared` authorized, and the seeded
    /// value is fixed at construction rather than settable afterwards.
    ///
    /// Why this shape and not one of the three seams already in the tree. `NotificationManager`'s
    /// static `isTestEnvironment` guard returns early from every side-effecting method — that would
    /// make the save paths unreachable, and the rollback behaviour these tests exist for is exactly
    /// what happens *after* a failed save. `CalendarEventLookup` / `CalendarEventDaySource` (the
    /// protocol seams `CalendarLinkedTaskSupport` and the board already use, with fakes in
    /// `CalendarManagerScenarioTests` and `CalendarBoardEventFetchRateTests`) replace this type
    /// wholesale, so they cannot exercise logic that lives *inside* it.
    /// `CalendarBoardUITestEventSupport` is the same move one surface further out. The injected
    /// dependency is the smallest thing that leaves the behaviour under test untouched.
    ///
    /// `store` has **no default**: a caller must hand over a store it made, so a test cannot reach
    /// the singleton's by omission. Note the residue this does not remove — EventKit grants are
    /// per-process, so *any* `EKEventStore` in an authorized host still resolves the owner's real
    /// calendars. A test built on this seam must keep doing what the existing ones do and operate on
    /// `EKEvent`s from a different store, never on `defaultWritableCalendar`. Callers that start
    /// observing should pair it with `stopObserving()`; nothing here owns a `deinit`, because
    /// `shared` never deallocates and T-3032 does not change production lifetimes.
    init(testStore: EKEventStore, authorizedForTesting: Bool) {
        self.store = testStore
        self.isAuthorized = authorizedForTesting
        self.isEventKitDisarmed = false
    }

    /// **[[T-3031]] — a manager built as an agent or UI-test launch would build `shared`.**
    ///
    /// The disarm decision is taken from `launchEnvironment` through the same
    /// `CadenceEventKitLaunchGate.isDisarmed(in:)` production reads, so a test can hand it the
    /// exact variables `run-macos-app.sh` and the UI suites set without the test host carrying
    /// them. `authorizedForTesting` seeds the flag *past* the gate on purpose: it lets a test prove
    /// the write sinks refuse on their own, independently of `isAuthorized`. Same store rule as the
    /// seam above — the caller hands over a store it made, and writes are driven only with
    /// `EKEvent`s from a foreign store, never through `defaultWritableCalendar`.
    init(gatedTestStore store: EKEventStore, launchEnvironment: [String: String], authorizedForTesting: Bool) {
        self.store = store
        self.isAuthorized = authorizedForTesting
        self.isEventKitDisarmed = CadenceEventKitLaunchGate.isDisarmed(in: launchEnvironment)
    }

    /// Drives `applyAuthorizationStatus` with a status the test chooses, so the disarmed branch is
    /// checked against `.fullAccess` without asking the host's real TCC state.
    func applyAuthorizationStatusForTesting(_ status: EKAuthorizationStatus) {
        applyAuthorizationStatus(status)
    }
    #endif

    // MARK: - Authorization

    func refreshAuthorizationState() {
        // [[T-3031]]: a disarmed launch never reads the grant it inherited.
        guard !isEventKitDisarmed else {
            applyAuthorizationStatus(.notDetermined)
            return
        }
        applyAuthorizationStatus(EKEventStore.authorizationStatus(for: .event))
    }

    private func applyAuthorizationStatus(_ status: EKAuthorizationStatus) {
        if status == .fullAccess, !isEventKitDisarmed {
            isAuthorized = true
            startObserving()
        } else {
            isAuthorized = false
            stopObserving()
        }
    }

    func requestAccess() async -> Bool {
        // [[T-3031]]: no prompt and no grant on a disarmed launch, whatever TCC would say.
        guard !isEventKitDisarmed else {
            await MainActor.run {
                applyAuthorizationStatus(.notDetermined)
            }
            return false
        }
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
        // [[T-3031]]: a disarmed launch never subscribes to the owner's real store.
        guard storeObserver == nil, !isEventKitDisarmed else { return }
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
        return CadenceCalendarSorting.sorted(store.calendars(for: .event))
    }

    var availableCalendars: [EKCalendar] {
        activeCalendars(from: allCalendars)
    }

    /// Calendars the user can write to (excludes read-only subscribed calendars).
    var writableCalendars: [EKCalendar] {
        guard isAuthorized else { return [] }
        return CadenceCalendarSorting.sorted(
            activeCalendars(from: store.calendars(for: .event))
                .filter { $0.allowsContentModifications }
        )
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

    /// Create a standalone event at `startMin` minutes-of-day on `date`.
    ///
    /// **T-3051.** `startMin` is a wall-clock reading, so the start is *set* through
    /// `CadenceCalendarEventTiming.startDate(day:startMin:calendar:)` rather than added to the
    /// day's midnight — the identical defect T-3050 fixed three lines below and at `:383`, spelled
    /// with `addingTimeInterval` instead of `date(byAdding: .minute,)`, which is exactly why two
    /// `rg 'byAdding: .minute'` audits walked past it. This is the macOS drag-to-create path
    /// (`CalendarPageMonthSupportViews` and `SchedulePanel`), so the wrong instant went into the
    /// owner's real Calendar.
    ///
    /// The **end** was anchored at the same midnight (`startMin + max(5, durationMinutes)` from
    /// `startOfDay`), so it carried the start's error instead of being a duration. It is now
    /// `durationMinutes` of **real time** after a correct start — a 30-minute event really is 30
    /// minutes long on a 23-hour day — the shape `convertAllDayEventToTimed` and `updateEvent`
    /// already have, and `CadenceCalendarEventTimingTests` pins it from both directions.
    ///
    /// **It changes no `whether`.** Both production call sites take their minute from
    /// `TimelineMetrics.snappedMinute(fromY:)`, whose `clampStart` bounds it at
    /// `endHour * 60 - duration` and so never reaches the 1440 the helper refuses.
    ///
    /// - Parameter timingCalendar: see `CadenceCalendarEventTiming.startDate`. `.current` in
    ///   production; a test passes an explicit DST-observing zone because the scheme pins the test
    ///   host to `TZ=UTC` ([[T-1116]]). It is not named `calendar` because that name is already the
    ///   resolved `EKCalendar` this event is filed in.
    @discardableResult
    func createStandaloneEvent(
        title: String,
        startMin: Int,
        durationMinutes: Int,
        calendarID: String,
        date: Date,
        notes: String = "",
        timingCalendar: Calendar = .current
    ) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        let selectedCalendar = calendarID.isEmpty ? defaultWritableCalendar : store.calendar(withIdentifier: calendarID)
        guard let calendar = selectedCalendar,
              calendar.allowsContentModifications,
              isActiveCalendar(calendar)
        else { return record(.noWritableCalendar) }
        guard let startDate = CadenceCalendarEventTiming.startDate(
            day: date,
            startMin: startMin,
            calendar: timingCalendar
        ) else { return record(.invalidRange) }
        guard let endDate = timingCalendar.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate) else {
            return record(.invalidRange)
        }
        let event = EKEvent(eventStore: store)
        event.title = CadenceEventTitleSupport.storedTitle(title)
        event.startDate = startDate
        event.endDate = endDate
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

    func event(for note: Note) -> EKEvent? {
        eventForNote(identifier: note.calendarEventID, dateKey: note.eventDateKey)
    }

    private func eventForNote(identifier: String, dateKey: String) -> EKEvent? {
        guard isAuthorized else { return nil }
        return CadenceEventNoteSupport.resolveEvent(
            calendarEventID: identifier,
            eventDateKey: dateKey,
            lookupBaseEvent: { store.event(withIdentifier: $0) },
            eventsForDay: { date in
                let bounds = dayBounds(for: date)
                let predicate = store.predicateForEvents(withStart: bounds.start, end: bounds.end, calendars: nil)
                return store.events(matching: predicate)
            }
        )
    }

    /// Convert an all-day event to a timed event at the specified minute of day on the given date.
    ///
    /// **T-3050.** `startMin` is a wall-clock reading, so the start is *set* through
    /// `CadenceCalendarEventTiming.startDate(dateKey:startMin:calendar:)`, not added to midnight —
    /// that enum records the measurement and the three edge readings. The **end** stays an elapsed
    /// hour after the start, which is the one change of spelling here that is not a bug fix: this
    /// line used to anchor the end at midnight too (`startMin + 60` from `baseDate`), so it carried
    /// the start's error rather than being a clean duration. An hour of real time after a correct
    /// start is what "a one-hour block" means, including on the two days that are 23 and 25 hours
    /// long, and it is the shape `updateEvent`'s timed overload below already has.
    ///
    /// `event.isAllDay` is cleared only once both endpoints exist, so a range this cannot form
    /// leaves the event exactly as it found it rather than half-converted.
    ///
    /// - Parameter calendar: see `CadenceCalendarEventTiming.startDate`. `.current` in production.
    @discardableResult
    func convertAllDayEventToTimed(
        _ event: EKEvent,
        startMin: Int,
        dateKey: String,
        calendar: Calendar = .current
    ) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        guard let startDate = CadenceCalendarEventTiming.startDate(
            dateKey: dateKey,
            startMin: startMin,
            calendar: calendar
        ) else { return record(.invalidRange) }
        guard let endDate = calendar.date(byAdding: .minute, value: 60, to: startDate) else {
            return record(.invalidRange)
        }
        event.isAllDay = false
        event.startDate = startDate
        event.endDate = endDate
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
    ///
    /// **T-3050.** The start is *set* from `startMin` as a wall-clock reading rather than added to
    /// midnight; `CadenceCalendarEventTiming.startDate` records why and what the edge readings do.
    /// The end below is **left exactly as it was** and must stay that way: `durationMinutes` is a
    /// duration added to a start that is already correct, and a 30-minute meeting lasts 30 minutes
    /// of real time on a 23-hour day too. Making the two lines agree in shape would be the bug.
    ///
    /// - Parameter calendar: see `CadenceCalendarEventTiming.startDate`. `.current` in production.
    @discardableResult
    func updateEvent(
        _ event: EKEvent,
        title: String,
        startMin: Int,
        durationMinutes: Int,
        dateKey: String,
        calendarID: String? = nil,
        notes: String? = nil,
        scope: CalendarRecurrenceEditScope = .thisOccurrence,
        calendar: Calendar = .current
    ) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        guard let startDate = CadenceCalendarEventTiming.startDate(
            dateKey: dateKey,
            startMin: startMin,
            calendar: calendar
        ) else { return record(.invalidRange) }
        let endDate = calendar.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate) ?? startDate
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
        event.title = CadenceEventTitleSupport.storedTitle(title)
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

    /// **T-389.** The `guard` used to end in `return nil`, and on this API `nil` is what a
    /// *completed* write returns — the same value the caller gets when Apple Calendar took the
    /// change. So a note whose stored identifier no longer resolves (the event was deleted, or
    /// EventKit reissued its id) reported success, and the desktop editor kept typing into a
    /// mirror that had stopped existing. iOS's overload has always answered `false` here: "an
    /// identifier that resolves to nothing is a sync that did not happen, not a no-op."
    ///
    /// Unlike every other failure on this type, this one is deliberately **not** `record`ed onto
    /// `lastWriteFailure`. The one caller is the event-note editor's debounced content flush,
    /// which fires every few seconds while someone types; routing this there would raise the modal
    /// `calendarWriteFailureAlert` over the editor on a loop. The editor reports it inline
    /// instead, which is also what iOS does.
    @discardableResult
    func updateEventNotes(calendarEventID: String, notes: String) -> CalendarWriteFailure? {
        guard let event = eventForNote(identifier: calendarEventID, dateKey: "") else { return .eventNotFound }
        return updateEventNotes(event, notes: notes)
    }

    // MARK: - Delete Event

    /// Delete an EKEvent directly (used from the event edit popover).
    @discardableResult
    func deleteEvent(_ event: EKEvent, scope: CalendarRecurrenceEditScope = .thisOccurrence) -> CalendarWriteFailure? {
        guard isAuthorized else { return record(.notAuthorized) }
        // [[T-3031]]: the delete sink refuses on a disarmed launch even past the flag.
        guard !isEventKitDisarmed else { return record(.notAuthorized) }
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
        // [[T-3031]]: the save sink refuses on a disarmed launch even past the flag, and puts the
        // in-memory edit back exactly as a failed save does.
        guard !isEventKitDisarmed else {
            event.reset()
            return record(.notAuthorized)
        }
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
