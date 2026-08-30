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

        // Mutating surface: none of these should crash even though nothing is authorized — and
        // none of them may fail in silence. Every one used to end in a bare `return`, so
        // drag-to-create with access revoked mid-session completed the gesture, dismissed the
        // popover, cleared the ghost, and produced nothing the user could see.
        manager.lastWriteFailure = nil
        #expect(manager.createStandaloneEvent(title: "Test", startMin: 60, durationMinutes: 30, calendarID: "", date: Date()) == .notAuthorized)
        #expect(manager.lastWriteFailure == .notAuthorized)

        let scratchEvent = EKEvent(eventStore: EKEventStore())
        scratchEvent.title = "Untouched"
        #expect(manager.updateEvent(scratchEvent, title: "Should not apply", startMin: 60, durationMinutes: 30, dateKey: "2026-06-01") == .notAuthorized)
        #expect(manager.updateEvent(scratchEvent, title: "Should not apply either", startDate: Date(), endDate: Date().addingTimeInterval(3600)) == .notAuthorized)
        #expect(manager.updateEventNotes(scratchEvent, notes: "Should not apply") == .notAuthorized)
        // T-389: an id that resolves to nothing is a failure, not the success value. This line
        // read `== nil` — which on this API is what a completed write returns — against a
        // comment three lines up saying none of these may fail in silence.
        #expect(manager.updateEventNotes(calendarEventID: "some-id", notes: "Should not apply") == .eventNotFound)
        #expect(manager.convertAllDayEventToTimed(scratchEvent, startMin: 120, dateKey: "2026-06-01") == .notAuthorized)
        #expect(manager.deleteEvent(scratchEvent) == .notAuthorized)

        // Guarded methods must never mutate the object when unauthorized.
        #expect(scratchEvent.title == "Untouched")
        manager.lastWriteFailure = nil
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

    @Test func aFailedSaveIsReportedAndRollsTheEventBackInsteadOfLeavingAPhantomEdit() {
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
        let failure = manager.updateEvent(
            event,
            title: "Moved event",
            startDate: start,
            endDate: end,
            calendarID: "definitely-not-a-real-calendar-identifier"
        )

        // No crash reaching here is itself part of the assertion. The unresolved calendarID must
        // not have corrupted the event's calendar assignment...
        #expect(event.calendar === originalCalendar)

        // ...and the save against a throwaway store cannot succeed, which is now reported rather
        // than swallowed by a `print`.
        guard case .saveFailed = failure else {
            Issue.record("expected a save failure, got \(String(describing: failure))")
            return
        }
        #expect(manager.lastWriteFailure == failure)

        // The requested edit must NOT survive a failed save. `EKEvent` is a reference type and
        // this same instance is what `CalendarEventItem` hands the timeline to draw, so keeping
        // the mutation left a block rendering an event that does not exist in the store — with
        // no `EKEventStoreChanged` notification to bump `storeVersion` and refetch it away.
        #expect(event.title != "Moved event")
        #expect(event.startDate == nil)
        #expect(event.endDate == nil)
        manager.lastWriteFailure = nil
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

    @Test func convertAllDayEventToTimedRollsBackOnFailureAndNeverMutatesAnUnrelatedEvent() throws {
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

        let failure = manager.convertAllDayEventToTimed(allDayEvent, startMin: 9 * 60, dateKey: dateKey)

        // The conversion computes the right range — 09:00–10:00 on the given day, matching the
        // range built independently above — but the save against a throwaway store fails, so the
        // event is put back rather than left half-converted on screen.
        guard case .saveFailed = failure else {
            Issue.record("expected a save failure, got \(String(describing: failure))")
            return
        }
        #expect(allDayEvent.startDate == nil)
        #expect(allDayEvent.endDate == nil)

        // The unrelated event must be completely untouched by converting a different event.
        #expect(existingTimedEvent.isAllDay == false)
        #expect(existingTimedEvent.title == "Existing meeting")
        #expect(existingTimedEvent.startDate == existingStart)
        #expect(existingTimedEvent.endDate == existingEnd)
        manager.lastWriteFailure = nil
    }

    // MARK: - 6. Looking up an externally-deleted event self-heals a task's stale calendarEventID

    private struct FakeCalendarEventLookup: CalendarEventLookup {
        var isAuthorized: Bool
        /// Defaulted `true` so every test written before T-529 keeps asking the question it was
        /// written to ask. The tests that vary it are the ones about the guard itself.
        var hasLoadedCalendars: Bool = true
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

    // MARK: - 6b. T-529: an authorized store that has answered nothing is not a store saying "gone"

    /// **The whole of T-529.** `event(withIdentifier:)` returns `nil` for an event that was deleted
    /// *and* for one whose source EventKit has not produced yet, and this sweep runs unattended on
    /// every `EKEventStoreChanged` — including the one posted when access is first granted and the
    /// ones posted while an account reloads. `isAuthorized` alone cannot tell those apart: it is
    /// `authorizationStatus`, which says the app may ask, not that an answer has arrived.
    ///
    /// Its sibling `CadenceCalendarLinkHealth` takes the opposite posture on the same question for
    /// a *list*'s `linkedCalendarID` — it reports the break and lets the user re-pick — and it
    /// guards on exactly this evidence for exactly this reason.
    @Test func clearMissingEventLinksTreatsAStoreWithNoCalendarsAsUnansweredRatherThanAsProofOfDeletion() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Sprint review")
        task.calendarEventID = "still-syncing-id"
        modelContext.insert(task)
        try modelContext.save()

        let fake = FakeCalendarEventLookup(
            isAuthorized: true,
            hasLoadedCalendars: false,
            eventsByLookupID: [:]
        )
        CalendarLinkedTaskSupport.clearMissingEventLinks(in: [task], modelContext: modelContext, calendarManager: fake)

        #expect(task.calendarEventID == "still-syncing-id")
    }

    /// The question, asked without the destructive answer attached. Split out in T-529 so the
    /// reporting posture the sibling takes is reachable here at all — and so a caller that wants to
    /// know cannot only find out by having the links cleared.
    @Test func missingEventLinksReportsTheSameSetItWouldHaveClearedAndWritesNothing() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let deleted = AppTask(title: "Deleted externally")
        deleted.calendarEventID = "missing-id"
        let live = AppTask(title: "Still scheduled")
        live.calendarEventID = "live-id"
        for task in [deleted, live] { modelContext.insert(task) }
        try modelContext.save()

        let liveEvent = EKEvent(eventStore: EKEventStore())
        liveEvent.title = "Live"
        let fake = FakeCalendarEventLookup(
            isAuthorized: true,
            eventsByLookupID: ["live-id": liveEvent]
        )

        let reported = CalendarLinkedTaskSupport.missingEventLinks(in: [deleted, live], calendarManager: fake)

        #expect(reported.map(\.id) == [deleted.id])
        // Reporting is not clearing: both identifiers survive the call untouched.
        #expect(deleted.calendarEventID == "missing-id")
        #expect(live.calendarEventID == "live-id")
    }

    /// The reporter honours the same evidence guard, so the two postures cannot disagree about
    /// which links are dead.
    @Test func missingEventLinksReportsNothingWhileTheStoreHasProducedNoCalendars() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Sprint review")
        task.calendarEventID = "still-syncing-id"
        modelContext.insert(task)
        try modelContext.save()

        let unanswered = FakeCalendarEventLookup(isAuthorized: true, hasLoadedCalendars: false)
        #expect(CalendarLinkedTaskSupport.missingEventLinks(in: [task], calendarManager: unanswered).isEmpty)

        let answered = FakeCalendarEventLookup(isAuthorized: true, hasLoadedCalendars: true)
        #expect(CalendarLinkedTaskSupport.missingEventLinks(in: [task], calendarManager: answered).map(\.id) == [task.id])
    }

    /// The guard is a conjunction, and each half is load-bearing: authorization without loaded
    /// calendars is the T-529 case, loaded calendars without authorization cannot happen through
    /// `CalendarManager` but must not become the way the guard is satisfied if it ever does.
    @Test func lookupMissesAreOnlyTrustedWhenTheStoreIsBothAuthorizedAndLoaded() {
        #expect(CalendarLinkedTaskSupport.canTrustLookupMisses(
            FakeCalendarEventLookup(isAuthorized: true, hasLoadedCalendars: true)
        ))
        #expect(!CalendarLinkedTaskSupport.canTrustLookupMisses(
            FakeCalendarEventLookup(isAuthorized: true, hasLoadedCalendars: false)
        ))
        #expect(!CalendarLinkedTaskSupport.canTrustLookupMisses(
            FakeCalendarEventLookup(isAuthorized: false, hasLoadedCalendars: true)
        ))
        #expect(!CalendarLinkedTaskSupport.canTrustLookupMisses(
            FakeCalendarEventLookup(isAuthorized: false, hasLoadedCalendars: false)
        ))
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

    // MARK: - 6c. T-537: the evidence question is asked before every task is fetched

    /// **T-537.** The store-level overload built a full `FetchDescriptor<AppTask>` and only then
    /// reached `canTrustLookupMisses`, inside the array overload below it. That runs on **every**
    /// `EKEventStoreChanged` — a notification EventKit posts while an account reloads, not only when
    /// the user changed something — so the launch state T-529 exists to make inert (authorized, no
    /// calendars produced yet) still paid a whole-store fetch in order to decide to do nothing.
    ///
    /// It is an ordering fact inside a static function with no seam: the fetch is
    /// `modelContext.fetch`, which no fake can count. So it is pinned as source order, scoped to
    /// that overload's own body rather than to the file — the array overload above it is a
    /// different function and already guards in the right place. What must **not** change is the
    /// neighbouring behaviour: guarding earlier may not clear a link that survived before, nor
    /// spare one that did not, and those tests are the ones that say so.
    @Test func clearMissingEventLinksAnswersTheEvidenceQuestionBeforeItFetchesEveryTask() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarLinkedTaskSupport.swift")
        let source = CadenceSourceScan.strippingComments(raw)
        // Non-vacuity: the file really was read, and the stripper really did blank something.
        #expect(source.contains("enum CalendarLinkedTaskSupport"))
        #expect(source != raw)

        // The store-level overload is the *last* `clearMissingEventLinks` in the file.
        let tail = try #require(
            source.range(of: "func clearMissingEventLinks(", options: .backwards),
            "the overload this test is about is not declared here any more"
        )
        let body = try #require(
            CadenceSourceScan.functionBody(
                named: "clearMissingEventLinks",
                in: String(source[tail.lowerBound...])
            ),
            "the store-level overload's braces do not balance"
        )
        let evidenceGuard = try #require(
            body.range(of: "guard canTrustLookupMisses("),
            "the store-level overload fetches every task before asking whether a miss means anything"
        )
        let fetch = try #require(
            body.range(of: "FetchDescriptor<AppTask>"),
            "the overload no longer fetches, so this test is pinning nothing"
        )
        #expect(evidenceGuard.upperBound < fetch.lowerBound)
    }
}
#endif
