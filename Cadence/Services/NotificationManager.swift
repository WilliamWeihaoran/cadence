import Foundation
import Observation
import OSLog
import UserNotifications

/// Thin adapter over `UNUserNotificationCenter`, modeled on `CalendarManager`'s shape:
/// an `@Observable` singleton exposing authorization state plus a handful of imperative
/// actions, with all the actual scheduling *logic* living in the pure `NotificationScheduling.swift`
/// planner so it stays unit-testable.
///
/// Local notifications require no Info.plist usage-description key (unlike EventKit's
/// `NSCalendarsFullAccessUsageDescription`) — only runtime authorization via `requestAuthorization()`.
/// Do not add an Info.plist key for this.
@MainActor
@Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    static let notificationsEnabledDefaultsKey = "notificationsEnabled"

    var isAuthorized: Bool = false

    /// **T-694.** True once the user has explicitly declined — the access card's title reads as a
    /// demand only where that is warranted, mirroring `CalendarManager.isDenied`. `.notDetermined`
    /// (never asked) reads `false` here, same as `.authorized`; only the not-authorized *and*
    /// already-asked state is a fault the reader has to go and fix.
    var isDenied: Bool = false

    /// **[[T-3049]] (2).** Every request the most recent reconcile handed the OS and had refused,
    /// in the order they were added. Replaced, not appended, on every pass that reaches a decision —
    /// a pass that takes the `cancelAll()` branch adds nothing and so clears it — so this always
    /// answers "what did the last reconcile fail to schedule", never a running history. Nothing
    /// renders it; it exists so "scheduled" and "the OS refused it" stop being the same silence.
    private(set) var lastReconcileRegistrationFailures: [NotificationRegistrationFailure] = []

    private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "Notifications")

    // `lazy` is deliberate: a plain stored-property initializer runs before `super.init()`,
    // which would touch `UNUserNotificationCenter.current()` unconditionally on every
    // construction — bypassing the `isTestEnvironment`/Preview guard below entirely, since
    // that guard only runs once the `init()` body executes. `lazy` defers the actual touch
    // until `center` is first read, which only happens after the guard has already returned.
    @ObservationIgnored
    private lazy var center: UNUserNotificationCenter = .current()

    private override init() {
        super.init()
        guard !Self.isTestEnvironment else { return }
        center.delegate = self
        Task { await refreshAuthorizationState() }
    }

    // MARK: - Authorization

    func refreshAuthorizationState() async {
        guard !Self.isTestEnvironment else { return }
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        isDenied = settings.authorizationStatus == .denied
    }

    /// The ONLY place in the app that should call `UNUserNotificationCenter.requestAuthorization`.
    /// Must stay gated behind an explicit Settings button — never called from app launch — so
    /// there's no jarring cold-launch permission prompt.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard !Self.isTestEnvironment else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorizationState()
        return granted
    }

    // MARK: - Reconciliation

    /// Diffs the desired notification set (computed from current SwiftData state) against
    /// `UNUserNotificationCenter`'s currently pending requests and converges. Idempotent — safe to
    /// call repeatedly from multiple trigger points (scenePhase checkpoints, task/habit
    /// create/complete/cancel/delete fast paths).
    ///
    /// The diffing rules live in `NotificationReconcileDiff.make` because this method early-returns
    /// under test; keep any new decision-making there rather than inline here.
    ///
    /// An empty `tasks` array means "cancel everything", so callers must pass real fetched state —
    /// never a failed fetch coerced to an empty array. See `HabitNotificationReconcileSupport`.
    ///
    /// **`habits:` is gone ([[T-2081]]), not emptied.** Habit reminders are retired, and the two
    /// ways to say so differ: a `habits: []` every caller must remember to pass is a parameter
    /// whose only correct value is invisible at the call site, while no parameter at all is a
    /// statement the compiler enforces. Removing it also means a pending `habit-reminder-…` is now
    /// permanently absent from `plan.all` while still being `isManaged`, so this diff removes one
    /// on every pass — which is the sweep `CadenceRetiredHabitReminderPurge` exists to not have to
    /// wait for.
    func reconcile(
        tasks: [AppTask],
        dueReminderHour: Int = 9,
        dueReminderMinute: Int = 0
    ) async {
        guard !Self.isTestEnvironment else { return }

        // **[[T-3047]]: re-derive the permission before reading it.** `isAuthorized` used to move
        // in exactly three places — `init()`, `requestAuthorization()`, and the
        // `.notificationsAuthorizationLifecycle` hook, which is attached on exactly two surfaces,
        // both of them the Settings → Notifications pane. Everywhere else it was a cached answer to
        // a question the OS lets the user change at any moment: iOS offers "Turn Off Notifications"
        // straight off a delivered banner, and both platforms have System Settings. Stale-`true`,
        // the guard below passes, `center.add` is refused and the `try?` swallows it, and the app
        // goes on holding out a guarantee the OS has withdrawn. Stale-`false`, every pass takes the
        // `cancelAll()` branch, so the user who just granted permission watches the app answer by
        // removing everything.
        //
        // **Here rather than in the scene-phase observers, and ahead of the guard rather than
        // beside it.** Order is the whole of the bug, and in this position it is structural: there
        // is no arrangement of callers in which the guard below reads a flag this pass did not just
        // derive. Wiring the refresh into `macOSRootView`'s `NotificationReconcileObserver` and
        // `iOSRootView`'s `.onChange(of: scenePhase)` would cover the foreground transition and
        // leave every mutation fast path reading the cached answer, in two places that then have to
        // be kept in step — and `reconcile` is the only reader of `isAuthorized` outside the two
        // panes that already carry the hook.
        //
        // **This adds no new reconcile.** Both root observers already reconcile on *becoming*
        // active ([[T-312]], [[T-3046]]), so the set of moments this function runs is unchanged;
        // only the branch a run takes changes, and only towards what the OS actually says. The
        // mid-import hazard [[T-3046]] weighed does not reach either new direction: a corrected
        // `true -> false` lands in `cancelAll()`, which reads no tasks at all, and a corrected
        // `false -> true` replaces a `cancelAll()` with a plan diff that removes strictly less. The
        // cost is one `notificationSettings()` read per pass, beside the
        // `pendingNotificationRequests()` read already below.
        await refreshAuthorizationState()

        let notificationsEnabled = CadenceDefaults.store.bool(forKey: Self.notificationsEnabledDefaultsKey)
        guard notificationsEnabled, isAuthorized else {
            lastReconcileRegistrationFailures = []
            await cancelAll()
            return
        }

        let plan = NotificationPlan.build(
            tasks: tasks,
            now: Date(),
            dueReminderHour: dueReminderHour,
            dueReminderMinute: dueReminderMinute
        )

        let pending = await center.pendingNotificationRequests()
        let diff = NotificationReconcileDiff.make(
            desired: plan.all,
            pendingIdentifiers: pending.map(\.identifier)
        )

        if !diff.identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.identifiersToRemove)
        }

        lastReconcileRegistrationFailures = await Self.register(diff.requestsToAdd) { osRequest in
            try await self.center.add(osRequest)
        }
    }

    /// Hands each request to `add` and returns the ones it refused, logging each refusal.
    ///
    /// **[[T-3049]] (2).** This loop used to be `try? await center.add(osRequest)` inline in
    /// `reconcile`, which swallowed the error — so nothing in the app or in any log could tell a
    /// scheduled reminder from one the OS refused, and [[T-3047]]'s stale-authorization case was
    /// silent for exactly that reason. It is a standalone function, with the OS call injected,
    /// because `reconcile` early-returns under test: this is the one seam where a refusal can be
    /// driven and the record of it read back. A refusal does not stop the pass — every later
    /// request is still attempted.
    static func register(
        _ requests: [CadenceNotificationRequest],
        adding add: (UNNotificationRequest) async throws -> Void
    ) async -> [NotificationRegistrationFailure] {
        var failures: [NotificationRegistrationFailure] = []
        for request in requests {
            let osRequest = UNNotificationRequest(
                identifier: request.identifier,
                content: makeContent(for: request),
                trigger: makeTrigger(for: request)
            )
            do {
                try await add(osRequest)
            } catch {
                let reason = String(describing: error)
                logger.error(
                    "Notification registration refused for \(request.identifier, privacy: .public): \(reason, privacy: .public)"
                )
                failures.append(NotificationRegistrationFailure(identifier: request.identifier, reason: reason))
            }
        }
        return failures
    }

    /// The exact trigger `reconcile` schedules, as a standalone function.
    ///
    /// `reconcile` early-returns under test, so anything built inline inside it is unverifiable:
    /// asserting `NotificationKind.repeatsDaily` proved only that the enum agreed with itself,
    /// and reverting this construction to a hardcoded one-shot left the suite green while the OS
    /// still received a habit reminder that fired once and expired. Constructing a trigger touches
    /// no notification centre, so pulling it out here makes the one line that carries the repeat
    /// semantics to the OS directly testable.
    static func makeTrigger(for request: CadenceNotificationRequest) -> UNCalendarNotificationTrigger {
        let spec = request.triggerSpec()
        return UNCalendarNotificationTrigger(dateMatching: spec.components, repeats: spec.repeats)
    }

    /// Cancels a specific set of tasks' pending notifications directly — cheaper than a full
    /// reconcile when the caller already knows exactly which tasks were removed (e.g. deletion).
    func cancel(taskIDs: [UUID]) async {
        guard !Self.isTestEnvironment, !taskIDs.isEmpty else { return }
        let identifiers = taskIDs.flatMap {
            [NotificationIdentifiers.taskStart(taskID: $0), NotificationIdentifiers.taskDue(taskID: $0)]
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Cancels a specific set of habits' pending reminder notifications directly.
    func cancel(habitIDs: [UUID]) async {
        guard !Self.isTestEnvironment, !habitIDs.isEmpty else { return }
        let identifiers = habitIDs.map { NotificationIdentifiers.habitReminder(habitID: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Cancels these reminders **now**, from a delete that has already committed.
    ///
    /// The one spelling of `Task { await NotificationManager.shared.cancel(…) }` a delete path
    /// should use, so the deferred spelling below is its visible opposite rather than a variant
    /// nobody notices is missing.
    nonisolated static func cancelReminders(taskIDs: [UUID] = [], habitIDs: [UUID] = []) {
        guard let cancel = reminderCancellation(taskIDs: taskIDs, habitIDs: habitIDs) else { return }
        cancel()
    }

    /// Hands these reminders to the enclosing `commitCascade`, which releases them if — and only
    /// if — its commit lands ([[T-1348]]).
    ///
    /// For the delete that **does not commit itself**: a list cascade is one pending change owned
    /// by the surface that asked for it, so cancelling here would be a change made by a delete
    /// that may yet promise it made none. With no cascade in scope the cancellation is dropped;
    /// `CadenceDeferredDeleteEffects` argues why that is the recoverable direction.
    nonisolated static func deferReminderCancellation(taskIDs: [UUID] = [], habitIDs: [UUID] = []) {
        guard let cancel = reminderCancellation(taskIDs: taskIDs, habitIDs: habitIDs) else { return }
        CadenceDeferredDeleteEffects.current?.hold(
            taskIDs: taskIDs,
            habitIDs: habitIDs,
            effect: cancel
        )
    }

    /// `nil` when there is nothing to cancel, so neither entry point above queues an empty effect.
    private nonisolated static func reminderCancellation(
        taskIDs: [UUID],
        habitIDs: [UUID]
    ) -> (@Sendable () -> Void)? {
        guard !taskIDs.isEmpty || !habitIDs.isEmpty else { return nil }
        return {
            Task {
                await NotificationManager.shared.cancel(taskIDs: taskIDs)
                await NotificationManager.shared.cancel(habitIDs: habitIDs)
            }
        }
    }

    func cancelAll() async {
        guard !Self.isTestEnvironment else { return }
        let pending = await center.pendingNotificationRequests()
        let managedIDs = pending.map(\.identifier).filter(NotificationIdentifiers.isManaged)
        guard !managedIDs.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: managedIDs)
    }

    // MARK: - Helpers

    /// Internal rather than private so a test can read the `userInfo` the OS is actually handed;
    /// building content touches no notification centre.
    static func makeContent(for request: CadenceNotificationRequest) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        // [[T-3049]] (1): the link a tap opens. See `NotificationTapRoute`.
        content.userInfo = NotificationTapRoute.userInfo(for: request)
        return content
    }

    /// Reuses the same test-mode detection as `CadenceUITestSupport`/`CadenceAppDelegate` so unit
    /// and UI tests never trigger a real OS permission prompt or schedule real notifications.
    /// Also skips Xcode's SwiftUI Preview host process — `UNUserNotificationCenter.current()` is a
    /// well-known source of crashes there since preview hosts lack a normal app bundle identity.
    static var isTestEnvironment: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
        if CadenceUITestSupport.isEnabled { return true }
        return false
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Shows notifications while the app is foregrounded (banner + sound), matching normal
    /// background-delivery behavior instead of silently swallowing them.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// **[[T-3049]] (1).** A tap on a task reminder opens that task.
    ///
    /// The URL comes from `NotificationTapRoute.deepLinkURL`, and it goes to
    /// `CadenceDeepLinkManager.shared.handle(_:)` — the same call both root views' `.onOpenURL`
    /// make — rather than back out through `NSWorkspace`/`UIApplication.open`: on macOS an
    /// external URL can open a second `WindowGroup` window, and on either platform the `cadence`
    /// scheme could resolve to another installed copy of the app. A response that names no task
    /// routes nowhere, as every tap did before.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let url = NotificationTapRoute.deepLinkURL(
            isDefaultAction: response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            userInfo: request.content.userInfo,
            identifier: request.identifier
        )
        if let url {
            Task { @MainActor in CadenceDeepLinkManager.shared.handle(url) }
        }
        completionHandler()
    }
}

/// The real notification centre, as the two-call view `CadenceRetiredHabitReminderPurge` asks for.
///
/// **It lives in this file because this file is the app's one door to the OS notification centre**
/// — the rule `CadenceAgentOperatingRuleTests.theOnlyFileInTheAppThatReachesTheNotificationCentreIsTheGuardedManager`
/// states as an equality. The purge declares the protocol and owns the decision about *which*
/// identifiers go; it does not get its own door.
///
/// `current()` is read inside each call rather than stored, for the same reason `center` above is
/// `lazy`: touching it eagerly crashes a SwiftUI preview host, which lacks a normal app bundle
/// identity. `CadenceRetiredHabitReminderPurge.run()` checks `isTestEnvironment` before it
/// constructs this, so no test host reaches either line.
@MainActor
struct CadenceLiveNotificationPurgeCentre: CadencePendingNotificationPurgeCentre {
    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func removePending(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// One request the OS refused during a reconcile ([[T-3049]] (2)). `reason` is the error's own
/// description, kept for a reader of `lastReconcileRegistrationFailures`, not for display.
nonisolated struct NotificationRegistrationFailure: Equatable, Sendable {
    let identifier: String
    let reason: String
}
