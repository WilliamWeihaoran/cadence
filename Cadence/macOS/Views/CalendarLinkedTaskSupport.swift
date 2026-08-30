#if os(macOS)
import EventKit
import SwiftData

/// Minimal seam over `CalendarManager` so calendar-link reconciliation (deciding whether a task's
/// stale `calendarEventID` should be cleared) can be regression-tested with a fake implementation
/// instead of requiring live EventKit authorization/data.
protocol CalendarEventLookup {
    var isAuthorized: Bool { get }

    /// Whether the store has actually produced its calendars yet.
    ///
    /// **T-529.** `isAuthorized` answers "may we ask", not "has an answer arrived". It is derived
    /// from `EKEventStore.authorizationStatus`, which flips the instant access is granted and stays
    /// true across every account refresh afterwards — while `event(withIdentifier:)` returns `nil`
    /// both for an event that is gone *and* for one whose source EventKit has not loaded. Those are
    /// the same value with opposite meanings, and the sweep below turns one of them into a delete.
    ///
    /// This is the cheap discriminator for the loudest case: a store with no calendars at all.
    /// `CadenceCalendarLinkHealth` needs the same evidence for the same reason and takes it as
    /// `isCalendarAccessAuthorized` because an unauthorized store reports `allCalendars` empty and
    /// so makes every link in the app look dead at once; here the empty set arrives through the
    /// front door as well, during the `EKEventStoreChanged` that a grant or an account reload
    /// posts.
    var hasLoadedCalendars: Bool { get }

    func event(withIdentifier identifier: String) -> EKEvent?
}

extension CalendarManager: CalendarEventLookup {
    var hasLoadedCalendars: Bool { !allCalendars.isEmpty }
}

enum CalendarLinkedTaskSupport {

    /// The tasks whose stored link the live store cannot resolve. **Reports; writes nothing.**
    ///
    /// Split out in T-529 so the question and the destructive answer to it are two calls. Its
    /// sibling `CadenceCalendarLinkHealth.missingLinks` — the same question about a *list*'s
    /// `linkedCalendarID` — reports and lets the user re-pick, and reads as the more defensible
    /// posture precisely because a nil lookup is not proof.
    static func missingEventLinks(
        in tasks: [AppTask],
        calendarManager: CalendarEventLookup
    ) -> [AppTask] {
        guard canTrustLookupMisses(calendarManager) else { return [] }
        return tasks.filter { shouldClearCalendarLink(for: $0, calendarManager: calendarManager) }
    }

    /// Clears the links `missingEventLinks` reports, and only those.
    ///
    /// **Unattended, on every `EKEventStoreChanged`** — `macOSRootView` and `SchedulePanel` both
    /// fire it off a `storeVersion` bump, with no user looking and nothing said afterwards. That is
    /// why the evidence guard is where the whole of T-529 is: the write itself is fine, but a store
    /// that has told us nothing yet must not be read as a store that has told us the event is gone.
    ///
    /// **Known residue (see the ticket delta).** `hasLoadedCalendars` catches the store-wide case.
    /// One account still syncing while the others have loaded leaves `allCalendars` non-empty, so a
    /// link into that account is still clearable on a miss. Narrowing that needs per-source
    /// evidence EventKit does not offer cheaply, and no current writer produces a non-empty
    /// `AppTask.calendarEventID` at all — every assignment in the tree is `= ""` — so the residue
    /// is reachable only from a store written by an earlier build.
    static func clearMissingEventLinks(
        in tasks: [AppTask],
        modelContext: ModelContext,
        calendarManager: CalendarEventLookup
    ) {
        let missing = missingEventLinks(in: tasks, calendarManager: calendarManager)
        guard !missing.isEmpty else { return }

        for task in missing {
            task.calendarEventID = ""
        }
        try? modelContext.save()
    }

    /// The store-level overload. **The evidence guard is asked before the fetch, not after it
    /// (T-537).** Both callers fire this off an `EKEventStoreChanged` bump, and EventKit posts that
    /// while an account reloads as well as when something actually changed — so the state T-529
    /// exists to make inert is also the state this runs in most often, and it used to build a
    /// whole-store `FetchDescriptor<AppTask>` before finding out it had nothing to decide.
    ///
    /// The array overload guards too, so the check below is not the only one: it is the early one.
    static func clearMissingEventLinks(
        modelContext: ModelContext,
        calendarManager: CalendarEventLookup
    ) {
        guard canTrustLookupMisses(calendarManager) else { return }
        let descriptor = FetchDescriptor<AppTask>()
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        clearMissingEventLinks(in: tasks, modelContext: modelContext, calendarManager: calendarManager)
    }

    /// Whether a `nil` from `event(withIdentifier:)` may be read as "this event is gone" rather
    /// than "this store has not answered yet".
    static func canTrustLookupMisses(_ calendarManager: CalendarEventLookup) -> Bool {
        calendarManager.isAuthorized && calendarManager.hasLoadedCalendars
    }

    static func shouldClearCalendarLink(
        for task: AppTask,
        calendarManager: CalendarEventLookup
    ) -> Bool {
        guard !task.calendarEventID.isEmpty else { return false }

        let lookupID = CalendarEventIdentity.lookupIdentifier(from: task.calendarEventID)
        guard !lookupID.hasPrefix("event-fallback|") else { return false }

        return calendarManager.event(withIdentifier: lookupID) == nil
    }
}
#endif
