// EventKit reminders, shared by both platforms. This lived in `macOS/Services/` inside an
// `#if os(macOS)` guard, which read as a platform constraint and was only an accident of
// where it was written: nothing here touches AppKit, and `NSRemindersFullAccessUsageDescription`
// ships on iOS as well as macOS. iOS Settings > Reminders needs it.
//
// The *file* carries the `Cadence` prefix and the *type* does not — the same mismatch
// `Shared/CadenceCalendarVisibilityPreferences.swift` has, and for the same reason: the old
// path keeps a tombstone comment under its original name, and two `RemindersManager.swift`
// files in one target collide on `.stringsdata`. Grep for the declaration, not the filename.
import EventKit
import Foundation
import Observation

struct AppleReminderItem: Identifiable {
    let id: String
    let title: String
    let notes: String
    let listTitle: String
    let dueDate: Date?
    let priority: Int
    let allowsCompletion: Bool
}

@Observable
final class RemindersManager {
    static let shared = RemindersManager()

    private(set) var reminders: [AppleReminderItem] = []
    private(set) var isAuthorized = false
    private(set) var isLoading = false

    /// Set when a request that started from `.notDetermined` came back refused. See
    /// `RemindersConnectionState.isDenied(status:deniedInThisSession:)` for why the cached status
    /// is not enough on its own. Stored rather than computed so `@Observable` re-renders the
    /// surfaces the moment it flips.
    private(set) var deniedInThisSession = false

    var isDenied: Bool {
        RemindersConnectionState.isDenied(
            status: EKEventStore.authorizationStatus(for: .reminder),
            deniedInThisSession: deniedInThisSession
        )
    }

    /// **T-256.** Read live, exactly like `isDenied`, and with no session fold: a restriction is
    /// imposed by whoever manages the device, not by a choice made at the in-app prompt, so there
    /// is no refusal for a launch to remember here the way `deniedInThisSession` remembers one for
    /// `.denied`. `isDenied` above still folds `.restricted` into its own `true` too — that flag
    /// answers "will a request button do anything", and the answer is no either way — so callers
    /// that need to tell the two apart check `isRestricted` first.
    var isRestricted: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .restricted
    }

    /// **T-268's observable seam.** A running count of the two reconciles this manager performs on
    /// its own view of the world. EventKit cannot be driven from a unit test, so the reconcile that
    /// follows a refused completion had no effect any test could watch: on a host without a
    /// Reminders grant, `refreshAuthorizationState()` re-derives `isAuthorized = false` from
    /// `isAuthorized == false` and changes nothing observable. Deleting it passed the whole suite.
    ///
    /// Counting the call is the smallest honest fix. It records that the work happened rather than
    /// that it was intended — the increments live inside the two methods themselves, not beside the
    /// `switch` that chooses between them, so a dispatcher that decides correctly and then does
    /// nothing still fails.
    ///
    /// `@ObservationIgnored` on purpose: no view reads this, and a counter that bumps on every
    /// reload has no business invalidating anything.
    @ObservationIgnored private(set) var reconcileLedger = RemindersReconcileLedger()

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    private init() {
        refreshAuthorizationState()
    }

    /// `.authorized` is the pre-macOS-14 spelling of `.fullAccess` — the same enum case with
    /// the same raw value, not a second state — so matching `.fullAccess` alone still accepts
    /// every status that used to pass here. This also matches `CalendarManager`.
    func refreshAuthorizationState() {
        reconcileLedger.authorizationRefreshes += 1
        let status = EKEventStore.authorizationStatus(for: .reminder)
        isAuthorized = status == .fullAccess

        if isAuthorized {
            // A real grant retires the session record — it can only ever add a denial the cached
            // status has not caught up with, never contradict one it has.
            deniedInThisSession = false
            startObserving()
            reload()
        } else {
            stopObserving()
            reminders = []
            isLoading = false
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess {
            refreshAuthorizationState()
            return true
        }
        guard status == .notDetermined else {
            refreshAuthorizationState()
            return false
        }

        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else {
            // Trust the request's own `false` for exactly the reason the `true` below is trusted:
            // `authorizationStatus` is cached per process and keeps answering `.notDetermined`
            // after the user taps Don't Allow, which left both surfaces offering an "Allow Access"
            // button that can never prompt again. Record it before re-deriving, so the re-derive
            // reads the denial rather than the stale cache.
            deniedInThisSession = true
            refreshAuthorizationState()
            return false
        }

        // Trust the request's own answer instead of re-reading `authorizationStatus`.
        // That class method is cached per process and, on iOS, still reports `.notDetermined`
        // for the rest of the launch after the user taps Allow — measured on the iOS 26
        // simulator, where the Settings card kept offering "Allow Access" until the app was
        // relaunched even though TCC had already recorded the grant. Re-reading it here made
        // connecting from iOS Settings look like it had failed. `granted == true` *is* the
        // authorization; nothing else needs to confirm it.
        //
        // `reset()` because this store was created before the grant and would otherwise keep
        // serving its pre-authorization view of the database.
        store.reset()
        isAuthorized = true
        deniedInThisSession = false
        startObserving()
        reload()
        return true
    }

    func reload() {
        reconcileLedger.reloadRequests += 1
        guard isAuthorized else {
            reminders = []
            isLoading = false
            return
        }

        isLoading = true
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? []).map(Self.makeItem).sorted(by: Self.sortItems)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reminders = items
                self.isLoading = false
            }
        }
    }

    /// **T-255.** This returned `Void` and had four ways to do nothing — not authorized, the
    /// identifier no longer resolving, a list that refuses content modifications, and a `save`
    /// throw that only `print`ed — while both Inbox rows had already animated themselves to
    /// completed. The row could not tell success from any of the four, so it stayed ticked over a
    /// reminder Apple Reminders still had open until the next relaunch un-ticked it.
    ///
    /// The refusal ordering is `AppleReminderCompletionOutcome.refusal(...)` rather than a `guard`
    /// chain, so it is a value the test target can exercise without an EventKit grant, and the
    /// rows turn whatever comes back into `AppleReminderCompletionResolution` — one policy for
    /// both platforms.
    ///
    /// Two outcomes also reconcile the *manager's* own view of the world before returning, because
    /// in both the row is being shown something that is no longer true: a lost grant re-derives
    /// authorization (which replaces every row with the access card, and is why that outcome's
    /// resolution says nothing itself), and an unresolvable identifier refetches.
    @discardableResult
    func completeReminder(id: String) -> AppleReminderCompletionOutcome {
        // Not queried at all while unauthorized — `refusal` answers `.notAuthorized` first
        // regardless, and an unauthorized store has nothing to say about an identifier.
        let reminder = isAuthorized ? store.calendarItem(withIdentifier: id) as? EKReminder : nil

        if let refusal = AppleReminderCompletionOutcome.refusal(
            isAuthorized: isAuthorized,
            reminderResolves: reminder != nil,
            allowsContentModifications: reminder?.calendar.allowsContentModifications ?? false
        ) {
            reconcile(after: refusal)
            return refusal
        }

        guard let reminder else { return .reminderUnavailable }

        reminder.isCompleted = true
        reminder.completionDate = Date()
        do {
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == id }
            return .completed
        } catch {
            print("RemindersManager: failed to complete reminder: \(error)")
            reconcile(after: .saveFailed)
            return .saveFailed
        }
    }

    /// Bring the manager's own picture back in line with what a completion just discovered, and
    /// report which reconcile that was.
    ///
    /// The choice is `AppleReminderCompletionReconcile.forOutcome(_:)` — a value in `Shared/`, so
    /// "a lost grant re-derives authorization, an unresolvable identifier refetches" is a thing a
    /// test can state — and the doing is here, counted in `reconcileLedger`, so a test can also
    /// watch it happen without an EventKit grant. **T-268:** this was an inline `switch` in
    /// `completeReminder(id:)` and either arm could be deleted with the suite still green.
    @discardableResult
    func reconcile(after outcome: AppleReminderCompletionOutcome) -> AppleReminderCompletionReconcile {
        let reconcile = AppleReminderCompletionReconcile.forOutcome(outcome)
        switch reconcile {
        case .refreshAuthorization:
            refreshAuthorizationState()
        case .reload:
            reload()
        case .none:
            break
        }
        return reconcile
    }

    private func startObserving() {
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    private func stopObserving() {
        guard let storeObserver else { return }
        NotificationCenter.default.removeObserver(storeObserver)
        self.storeObserver = nil
    }

    /// `nonisolated` because `fetchReminders` already calls this from EventKit's background
    /// completion queue — the annotation states where the work actually happens rather than
    /// moving it. Both helpers are pure functions over their arguments.
    nonisolated private static func makeItem(from reminder: EKReminder) -> AppleReminderItem {
        AppleReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            notes: reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            listTitle: reminder.calendar.title,
            dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
            priority: reminder.priority,
            allowsCompletion: reminder.calendar.allowsContentModifications
        )
    }

    nonisolated private static func sortItems(_ lhs: AppleReminderItem, _ rhs: AppleReminderItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
