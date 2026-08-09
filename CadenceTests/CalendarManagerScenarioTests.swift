import Foundation
import Testing
#if os(macOS)
import EventKit
import SwiftData
#endif
@testable import Cadence

// Deep regression coverage for Cadence/macOS/Services/CalendarManager.swift (EventKit
// authorization, event CRUD, all-day-event fetch/convert) and
// Cadence/macOS/Views/CalendarLinkedTaskSupport.swift (reconciling a task's stale
// `calendarEventID` against the live store). AGENTS.md flags CalendarManager as a risk area
// ("can trigger permission prompts and external calendar side effects"), so these tests avoid
// ever touching a real, authorized EventKit store — the test machine has no Calendar access
// grant, so `CalendarManager.shared.isAuthorized` starts (and normally stays) `false`, which is
// itself exactly the "denied / not yet determined" scenario these tests exercise.
//
// Where a test needs to simulate a *previously authorized* state (to prove stale-state recovery
// or to exercise the parts of a method that run after the authorization guard), it force-sets
// `CalendarManager.shared.isAuthorized` directly via `@testable import` and always restores it
// in a `defer` so no state leaks into other tests in the suite.
#if os(macOS)
@Suite(.serialized)
@MainActor
struct CalendarManagerScenarioTests {

    // MARK: - 1. Denied / not-yet-determined authorization never crashes and no-ops safely

    @Test func unauthorizedStateShortCircuitsEveryCalendarOperationWithoutTouchingEventKit() {
        let manager = CalendarManager.shared
        let originalAuthorized = manager.isAuthorized
        manager.isAuthorized = false
        defer { manager.isAuthorized = originalAuthorized }

        // Read-only surface.
        #expect(manager.allCalendars.isEmpty)
        #expect(manager.availableCalendars.isEmpty)
        #expect(manager.writableCalendars.isEmpty)
        #expect(manager.defaultWritableCalendar == nil)
        #expect(manager.fetchEvents(for: Date()).isEmpty)
        #expect(manager.fetchAllDayEvents(for: Date()).isEmpty)
        #expect(manager.event(withIdentifier: "some-id") == nil)
        #expect(manager.event(withIdentifier: "") == nil)
        #expect(manager.searchEvents(matching: "standup").isEmpty)

        // Mutating surface: none of these should crash even though nothing is authorized.
        manager.createStandaloneEvent(title: "Test", startMin: 60, durationMinutes: 30, calendarID: "", date: Date())

        let scratchEvent = EKEvent(eventStore: EKEventStore())
        scratchEvent.title = "Untouched"
        manager.updateEvent(scratchEvent, title: "Should not apply", startMin: 60, durationMinutes: 30, dateKey: "2026-06-01")
        manager.updateEvent(scratchEvent, title: "Should not apply either", startDate: Date(), endDate: Date().addingTimeInterval(3600))
        manager.updateEventNotes(scratchEvent, notes: "Should not apply")
        manager.updateEventNotes(calendarEventID: "some-id", notes: "Should not apply")
        manager.convertAllDayEventToTimed(scratchEvent, startMin: 120, dateKey: "2026-06-01")
        manager.deleteEvent(scratchEvent)

        // Guarded methods must never mutate the object when unauthorized.
        #expect(scratchEvent.title == "Untouched")
    }

    // MARK: - 2. Authorization revoked mid-session is detected instead of staying stale

    /// Whether this machine has actually granted Calendar access.
    ///
    /// These two tests used to hardcode `false`, on the stated assumption that no test machine
    /// would have a live grant. That is not true of a developer's own Mac, where the app is
    /// installed and authorized, and it made both fail there for a reason unrelated to the
    /// behavior under test. Seeding the *opposite* of the live value keeps the assertion sharp on
    /// either kind of machine: a handler that failed to re-derive would leave the seeded value in
    /// place and still be caught.
    private var liveAuthorization: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    @Test func staleCachedAuthorizationIsCorrectedWhenTheStoreChangeHandlerRuns() {
        let manager = CalendarManager.shared
        let originalAuthorized = manager.isAuthorized
        let originalVersion = manager.storeVersion
        let live = liveAuthorization
        // Simulate a previous session whose cached grant no longer matches reality.
        manager.isAuthorized = !live
        defer { manager.isAuthorized = originalAuthorized }

        // The EKEventStoreChanged handler must re-derive authorization (not just bump the
        // refresh counter), so a revocation made outside the app while it keeps running is
        // eventually reflected instead of caching the old answer until the next relaunch.
        manager.handleStoreChangeNotification()

        #expect(manager.storeVersion == originalVersion + 1)
        #expect(manager.isAuthorized == live)
    }

    @Test func refreshAuthorizationStateNeverThrowsAndReflectsLiveStatus() {
        let manager = CalendarManager.shared
        let originalAuthorized = manager.isAuthorized
        defer { manager.isAuthorized = originalAuthorized }
        let live = liveAuthorization

        // Converges from either direction, so neither a stuck `true` nor a stuck `false` passes.
        manager.isAuthorized = true
        manager.refreshAuthorizationState()
        #expect(manager.isAuthorized == live)

        manager.isAuthorized = false
        manager.refreshAuthorizationState()
        #expect(manager.isAuthorized == live)
    }

    // MARK: - 3. Moving an event to a missing/read-only calendar doesn't crash or corrupt the event

    @Test func updateEventSkipsCalendarReassignmentWhenTargetCalendarCannotBeResolvedButStillAppliesOtherFields() {
        let manager = CalendarManager.shared
        let originalAuthorized = manager.isAuthorized
        manager.isAuthorized = true
        defer { manager.isAuthorized = originalAuthorized }

        // Constructed against a throwaway store (not CalendarManager's own), so `store.save`
        // internally fails with an EventKit error rather than persisting anywhere real — this
        // keeps the test isolated from any live calendar while still exercising the exact guard
        // logic used for an unresolvable/read-only destination calendar.
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Original title"
        let originalCalendar = event.calendar

        // EKEvent rounds stored dates to whole seconds, so start from a whole-second `Date` —
        // otherwise reading `event.startDate` back after the round-trip through EventKit would
        // fail an exact-equality check purely due to a dropped fractional second, not a real bug.
        let start = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down))
        let end = start.addingTimeInterval(1800)
        manager.updateEvent(
            event,
            title: "Moved event",
            startDate: start,
            endDate: end,
            calendarID: "definitely-not-a-real-calendar-identifier"
        )

        // No crash reaching here is itself part of the assertion. The unresolved calendarID must
        // not have corrupted the event's calendar assignment...
        #expect(event.calendar === originalCalendar)
        // ...while the rest of the requested edit (title/time) still applies, since only the
        // calendar-move portion was invalid.
        #expect(event.title == "Moved event")
        #expect(event.startDate == start)
        #expect(event.endDate == end)
    }

    @Test func updateEventRejectsInvertedTimeRangeWithoutMutatingTheEvent() {
        let manager = CalendarManager.shared
        let originalAuthorized = manager.isAuthorized
        manager.isAuthorized = true
        defer { manager.isAuthorized = originalAuthorized }

        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Untouched"
        let start = Date()
        let end = start.addingTimeInterval(-60) // end before start: invalid range

        manager.updateEvent(event, title: "Should not apply", startDate: start, endDate: end)

        #expect(event.title == "Untouched")
    }

    // MARK: - 4. fetchAllDayEvents day-boundary math is correct across DST transitions

    @Test func dayBoundsSpanExactlyOneCalendarDayAcrossSpringForwardAndFallBackTransitions() throws {
        let tz = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        let anchor = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let springForward = try #require(tz.nextDaylightSavingTimeTransition(after: anchor))
        let fallBack = try #require(tz.nextDaylightSavingTimeTransition(after: springForward))

        let springBounds = CalendarManager.shared.dayBounds(for: springForward, calendar: calendar)
        let fallBounds = CalendarManager.shared.dayBounds(for: fallBack, calendar: calendar)

        // A day that loses an hour to DST is 23 wall-clock hours long; a day that gains an hour
        // back is 25. Both must still resolve to exactly one calendar day (no off-by-one that
        // would clip real events near midnight or bleed into the neighboring day).
        #expect(springBounds.end.timeIntervalSince(springBounds.start) == 23 * 3600)
        #expect(fallBounds.end.timeIntervalSince(fallBounds.start) == 25 * 3600)

        // Bounds must land exactly on local midnight, not on some UTC-shifted approximation.
        #expect(calendar.component(.hour, from: springBounds.start) == 0)
        #expect(calendar.component(.hour, from: springBounds.end) == 0)
        #expect(calendar.component(.hour, from: fallBounds.start) == 0)
        #expect(calendar.component(.hour, from: fallBounds.end) == 0)

        let springNextDay = try #require(calendar.date(byAdding: .day, value: 1, to: springBounds.start))
        let fallNextDay = try #require(calendar.date(byAdding: .day, value: 1, to: fallBounds.start))
        #expect(calendar.isDate(springBounds.end, inSameDayAs: springNextDay))
        #expect(calendar.isDate(fallBounds.end, inSameDayAs: fallNextDay))
    }

    // MARK: - 5. Converting an all-day event to timed produces a sane range and never bleeds into other events

    @Test func convertAllDayEventToTimedSetsExactRangeAndNeverMutatesAnUnrelatedEvent() throws {
        let manager = CalendarManager.shared
        let originalAuthorized = manager.isAuthorized
        manager.isAuthorized = true
        defer { manager.isAuthorized = originalAuthorized }

        let dateKey = "2026-06-15"
        let baseDate = try #require(DateFormatters.date(from: dateKey))

        let allDayEvent = EKEvent(eventStore: EKEventStore())
        allDayEvent.title = "All-day errand"
        allDayEvent.isAllDay = true

        // A second, unrelated event already occupying the exact same slot on the same day —
        // overlapping calendar events are normal (Apple Calendar itself allows this), so
        // conversion must not attempt to move/clear it.
        let existingTimedEvent = EKEvent(eventStore: EKEventStore())
        existingTimedEvent.title = "Existing meeting"
        existingTimedEvent.isAllDay = false
        let existingStart = try #require(Calendar.current.date(byAdding: .minute, value: 9 * 60, to: baseDate))
        let existingEnd = try #require(Calendar.current.date(byAdding: .minute, value: 10 * 60, to: baseDate))
        existingTimedEvent.startDate = existingStart
        existingTimedEvent.endDate = existingEnd

        manager.convertAllDayEventToTimed(allDayEvent, startMin: 9 * 60, dateKey: dateKey)

        #expect(!allDayEvent.isAllDay)
        #expect(allDayEvent.startDate == existingStart)
        #expect(allDayEvent.endDate == existingEnd)

        // The unrelated event must be completely untouched by converting a different event.
        #expect(existingTimedEvent.isAllDay == false)
        #expect(existingTimedEvent.title == "Existing meeting")
        #expect(existingTimedEvent.startDate == existingStart)
        #expect(existingTimedEvent.endDate == existingEnd)
    }

    // MARK: - 6. Looking up an externally-deleted event self-heals a task's stale calendarEventID

    private struct FakeCalendarEventLookup: CalendarEventLookup {
        var isAuthorized: Bool
        var eventsByLookupID: [String: EKEvent] = [:]

        func event(withIdentifier identifier: String) -> EKEvent? {
            eventsByLookupID[identifier]
        }
    }

    @Test func clearMissingEventLinksDoesNothingWhileAuthorizationIsUnknownOrDenied() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Standup")
        task.calendarEventID = "some-external-event-id"
        modelContext.insert(task)
        try modelContext.save()

        let fake = FakeCalendarEventLookup(isAuthorized: false, eventsByLookupID: [:])
        CalendarLinkedTaskSupport.clearMissingEventLinks(in: [task], modelContext: modelContext, calendarManager: fake)

        // Must not treat "we don't currently know" as "the event is gone" — that would silently
        // sever a perfectly valid link the moment authorization drops out from under the app.
        #expect(task.calendarEventID == "some-external-event-id")
    }

    @Test func clearMissingEventLinksClearsReferenceWhenEventWasDeletedExternally() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "1:1 with manager")
        task.calendarEventID = "deleted-elsewhere-id"
        modelContext.insert(task)
        try modelContext.save()

        let fake = FakeCalendarEventLookup(isAuthorized: true, eventsByLookupID: [:])
        CalendarLinkedTaskSupport.clearMissingEventLinks(in: [task], modelContext: modelContext, calendarManager: fake)

        #expect(task.calendarEventID.isEmpty)
    }

    @Test func clearMissingEventLinksPreservesReferenceWhenEventStillExists() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Still scheduled")
        task.calendarEventID = "still-exists-id"
        modelContext.insert(task)
        try modelContext.save()

        let liveEvent = EKEvent(eventStore: EKEventStore())
        liveEvent.title = "Still exists"
        let fake = FakeCalendarEventLookup(isAuthorized: true, eventsByLookupID: ["still-exists-id": liveEvent])
        CalendarLinkedTaskSupport.clearMissingEventLinks(in: [task], modelContext: modelContext, calendarManager: fake)

        #expect(task.calendarEventID == "still-exists-id")
    }

    @Test func clearMissingEventLinksNeverClearsSyntheticFallbackIdentifiersRegardlessOfLookupResult() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "No native identifier")
        task.calendarEventID = "event-fallback|cal-123|2026-06-15|540|Team Sync"
        modelContext.insert(task)
        try modelContext.save()

        // Even an "always miss" lookup must not clear a fallback-identified task — fallback IDs
        // are synthesized locally (for events EventKit gave no real identifier) and can never be
        // resolved via `event(withIdentifier:)`, so treating a lookup miss as "deleted" here would
        // wipe every such link on the very first reconciliation pass.
        let fake = FakeCalendarEventLookup(isAuthorized: true, eventsByLookupID: [:])
        CalendarLinkedTaskSupport.clearMissingEventLinks(in: [task], modelContext: modelContext, calendarManager: fake)

        #expect(task.calendarEventID == "event-fallback|cal-123|2026-06-15|540|Team Sync")
    }

    // MARK: - 7. Reconciling many tasks together evaluates each independently (no cross-task misattribution)

    @Test func clearMissingEventLinksEvaluatesEachTaskAgainstItsOwnIdentifierOnly() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let stillLinkedTask = AppTask(title: "Recently attached")
        stillLinkedTask.calendarEventID = "exists-A"
        let missingLinkTask = AppTask(title: "Deleted externally")
        missingLinkTask.calendarEventID = "missing-B"
        let anotherStillLinkedTask = AppTask(title: "Another live link")
        anotherStillLinkedTask.calendarEventID = "exists-C"

        for task in [stillLinkedTask, missingLinkTask, anotherStillLinkedTask] {
            modelContext.insert(task)
        }
        try modelContext.save()

        let liveEventA = EKEvent(eventStore: EKEventStore())
        liveEventA.title = "A"
        let liveEventC = EKEvent(eventStore: EKEventStore())
        liveEventC.title = "C"

        // A single reconciliation pass (as triggered once per `storeVersion` bump, regardless of
        // how many unrelated external changes coalesced into that one notification) must resolve
        // every task strictly against its own stored identifier.
        let fake = FakeCalendarEventLookup(
            isAuthorized: true,
            eventsByLookupID: ["exists-A": liveEventA, "exists-C": liveEventC]
        )
        CalendarLinkedTaskSupport.clearMissingEventLinks(
            in: [stillLinkedTask, missingLinkTask, anotherStillLinkedTask],
            modelContext: modelContext,
            calendarManager: fake
        )

        #expect(stillLinkedTask.calendarEventID == "exists-A")
        #expect(anotherStillLinkedTask.calendarEventID == "exists-C")
        #expect(missingLinkTask.calendarEventID.isEmpty)
    }

    // MARK: - 8. Rapid create/delete of calendar-linked tasks leaves no orphans and never crashes

    @Test func rapidCreateAndDeleteOfCalendarLinkedTasksNeverCrashesAndClearsEveryReference() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        for round in 0..<5 {
            var taskIDs: Set<UUID> = []
            var tasks: [AppTask] = []
            for index in 0..<10 {
                let task = AppTask(title: "Round \(round) task \(index)")
                task.calendarEventID = "external-event-\(round)-\(index)"
                modelContext.insert(task)
                tasks.append(task)
                taskIDs.insert(task.id)
            }
            try modelContext.save()

            // Deleting immediately after creating, in a tight loop, must not crash or leave any
            // task rows behind — `removeFromCalendar` only ever clears the local field (Cadence
            // never owns/creates the underlying EKEvent for a scheduled task), so there is nothing
            // in EventKit for a rapid create/delete cycle to orphan.
            modelContext.deleteTasks(withIDs: taskIDs)
            try modelContext.save()

            #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        }
    }
}
#endif
