import Foundation
import Observation
import OSLog
import SwiftData
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

    /// **[[T-15486]].** The last complete read of the store a reconcile was handed, so the next one
    /// can tell a deleted task from one that is merely missing. Within one process; the first read
    /// after a launch falls back to the durable record below.
    @ObservationIgnored
    private var lastCompleteStoreRead: NotificationCompleteStoreRead?

    /// **[[T-15516]].** Where `reconcile` stores the last complete read across a relaunch.
    static let lastCompleteStoreReadDefaultsKey = "cadence.notifications.lastCompleteStoreRead"

    /// **[[T-15516]].** The durable identity of the store a complete read came from, or `nil` when
    /// it has none worth trusting across a launch. For `shared` that is the app's one container's
    /// store file (`NotificationStoreFileIdentity`), and nothing for any other container; a test
    /// manager answers `nil` unless the test hands it a resolver over its own temp store.
    @ObservationIgnored
    private let durableStoreIdentity: @MainActor (ObjectIdentifier) -> String?

    private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "Notifications")

    // `lazy` is deliberate: a plain stored-property initializer runs before `super.init()`,
    // which would touch `UNUserNotificationCenter.current()` unconditionally on every
    // construction — bypassing the `isTestEnvironment`/Preview guard below entirely, since
    // that guard only runs once the `init()` body executes. `lazy` defers the actual touch
    // until `center` is first read, which only happens after the guard has already returned.
    @ObservationIgnored
    private lazy var center: UNUserNotificationCenter = .current()

    /// **[[T-3113]].** The calls every side-effecting entry point below makes, behind one seam.
    ///
    /// For `shared` this is `CadenceSystemNotificationCentre`, which reads
    /// `UNUserNotificationCenter.current()` inside each call — so constructing it touches nothing,
    /// and every entry point's `isTestEnvironment` guard still runs before the OS is reached. A
    /// test builds its own manager with `init(centre:defaults:)` and a fake; that is the only way
    /// these bodies execute in a test host, and it never reaches the OS because the system centre
    /// is `private` to this file and cannot be handed in.
    private let centre: any CadenceNotificationCentre

    /// True only for a manager built by `init(centre:defaults:)`. Each entry point's guard reads
    /// `centreIsInjected || !Self.isTestEnvironment`, so for `shared` — where this is `false` —
    /// the guard is exactly the `!Self.isTestEnvironment` it always was.
    private let centreIsInjected: Bool

    /// Where `reconcile` reads `notificationsEnabledDefaultsKey`. `CadenceDefaults.store` for
    /// `shared`; a private suite for a test.
    private let defaults: UserDefaults

    private override init() {
        centre = CadenceSystemNotificationCentre()
        centreIsInjected = false
        defaults = CadenceDefaults.store
        durableStoreIdentity = { identity in
            guard let container = PersistenceController.shared.container,
                  ObjectIdentifier(container) == identity else { return nil }
            return NotificationStoreFileIdentity.of(container)
        }
        super.init()
        guard !Self.isTestEnvironment else { return }
        center.delegate = self
        Task { await refreshAuthorizationState() }
    }

    /// **[[T-3113]].** A manager that talks to `centre` instead of the OS, for tests.
    ///
    /// It sets no delegate and starts no initial authorization read, so nothing runs that the test
    /// did not call. Not for production: the app has exactly one manager, `shared`.
    init(
        centre: any CadenceNotificationCentre,
        defaults: UserDefaults,
        durableStoreIdentity: @escaping @MainActor (ObjectIdentifier) -> String? = { _ in nil }
    ) {
        self.centre = centre
        centreIsInjected = true
        self.defaults = defaults
        self.durableStoreIdentity = durableStoreIdentity
        super.init()
    }

    // MARK: - Authorization

    func refreshAuthorizationState() async {
        guard centreIsInjected || !Self.isTestEnvironment else { return }
        let status = await centre.authorizationStatus()
        isAuthorized = status == .authorized || status == .provisional
        isDenied = status == .denied
    }

    /// The ONLY place in the app that should call `UNUserNotificationCenter.requestAuthorization`.
    /// Must stay gated behind an explicit Settings button — never called from app launch — so
    /// there's no jarring cold-launch permission prompt.
    ///
    /// **[[T-6000]]: a granted answer turns reminders on.** The only callers are the two
    /// "Enable Notifications" buttons, so a `true` here is someone who asked for notifications and
    /// said yes to the OS. The stored switch defaults to `false` and nothing else writes it `true`,
    /// so the pane used to flip to an "Enable reminders" row with its switch still off and
    /// `reconcile` went on cancelling everything. The write goes to `defaults` — for `shared`, the
    /// `CadenceDefaults.store` both panes' `@AppStorage` reads — so each pane's
    /// `.onChange(of: notificationsEnabled)` sees it and reconciles. A refusal writes nothing, and
    /// nobody who never pressed the button is touched: the default stays `false`.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard centreIsInjected || !Self.isTestEnvironment else { return false }
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorizationState()
        if granted {
            defaults.set(true, forKey: Self.notificationsEnabledDefaultsKey)
        }
        return granted
    }

    /// **[[T-6000]]: what the "Enable Notifications" button does, for both platforms.** Returns
    /// `true` when the caller should open the system Settings app.
    ///
    /// Settings opens only when the status was ALREADY `.denied` before the tap: the OS will not
    /// prompt twice, so Settings is the only place that answer can be changed. Any other status
    /// asks the OS, and its answer stands — a "Don't Allow" given just now is the user's choice,
    /// not a cue to send them to Settings unasked, which is what both panes used to do. The status
    /// is re-read before `isDenied` is consulted, because the cached flag is only as fresh as the
    /// pane's last appearance or foreground.
    func requestAuthorizationOrOpenSettings() async -> Bool {
        await refreshAuthorizationState()
        if isDenied { return true }
        await requestAuthorization()
        return false
    }

    // MARK: - Reconciliation

    /// Diffs the desired notification set (computed from current SwiftData state) against
    /// `UNUserNotificationCenter`'s currently pending requests and converges. Idempotent — safe to
    /// call repeatedly from multiple trigger points (scenePhase checkpoints, task/habit
    /// create/complete/cancel/delete fast paths).
    ///
    /// The diffing rules live in `NotificationReconcileDiff.make`; keep any new decision-making there
    /// rather than inline here. `shared` early-returns under test, so the body itself is driven only
    /// through a fake-backed manager (`init(centre:defaults:)`, [[T-3113]]).
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
    ///
    /// **`completeStore` ([[T-15486]])** is passed only by a pass whose `tasks` is a complete read
    /// of the store (`CadenceForegroundNotificationSnapshot.completeStore`). Against the previous
    /// such read of the same store it proves which tasks were deleted -- including a delete
    /// CloudKit synced from another device, where no `cancel(taskIDs:)` runs here -- and their
    /// already-delivered reminders are withdrawn. Every other pass leaves `nil` and withdraws
    /// nothing for a missing task. Since [[T-15516]] the first such read of a launch is compared
    /// with the one an earlier launch stored, when both name the same store file.
    func reconcile(
        tasks: [AppTask],
        completeStore: NotificationCompleteStoreRead? = nil,
        dueReminderHour: Int = 9,
        dueReminderMinute: Int = 0
    ) async {
        guard centreIsInjected || !Self.isTestEnvironment else { return }

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

        let notificationsEnabled = defaults.bool(forKey: Self.notificationsEnabledDefaultsKey)
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

        let pendingIdentifiers = await centre.pendingIdentifiers()
        let diff = NotificationReconcileDiff.make(
            desired: plan.all,
            pendingIdentifiers: pendingIdentifiers
        )

        if !diff.identifiersToRemove.isEmpty {
            centre.removePending(withIdentifiers: diff.identifiersToRemove)
        }

        // [[T-15464]]: a reminder that already FIRED is not pending, so the diff above never sees
        // it; withdraw the delivered ones whose task is now done or cancelled -- or, [[T-15486]],
        // proved deleted by two complete reads of the same store. A partial pass neither proves
        // nor replaces the last complete read.
        //
        // [[T-15516]]: the first complete read of a launch has no in-memory predecessor, so it is
        // compared with the one an earlier launch stored -- and only when both name the same store
        // file. The current read replaces the stored one whenever it has a file identity.
        let durableRead = completeStore.flatMap { read in
            durableStoreIdentity(read.storeIdentity).map {
                NotificationDurableCompleteStoreRead(storeFileIdentity: $0, taskIDs: read.taskIDs)
            }
        }
        let provenDeleted = lastCompleteStoreRead == nil
            ? NotificationReconcileDiff.provenDeletedTaskIDs(
                previous: Self.storedCompleteStoreRead(defaults: defaults),
                current: durableRead
            )
            : NotificationReconcileDiff.provenDeletedTaskIDs(
                previous: lastCompleteStoreRead,
                current: completeStore
            )
        if let completeStore { lastCompleteStoreRead = completeStore }
        if let durableRead { Self.store(durableRead, defaults: defaults) }
        let settledTaskIDs = Set(tasks.filter { $0.status == .done || $0.status == .cancelled }.map(\.id))
            .union(provenDeleted)
        if !settledTaskIDs.isEmpty {
            let deliveredToRemove = NotificationReconcileDiff.deliveredIdentifiersToRemove(
                delivered: await centre.deliveredIdentifiers(),
                settledTaskIDs: settledTaskIDs
            )
            if !deliveredToRemove.isEmpty {
                centre.removeDelivered(withIdentifiers: deliveredToRemove)
            }
        }

        lastReconcileRegistrationFailures = await Self.register(diff.requestsToAdd) { osRequest in
            try await self.centre.add(osRequest)
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
    ///
    /// **[[T-15464]]: the delivered copies go too.** A reminder that already fired would otherwise
    /// sit in Notification Center naming a task that no longer exists. The same identifiers, so
    /// nothing outside these tasks' two reminders is touched.
    func cancel(taskIDs: [UUID]) async {
        guard centreIsInjected || !Self.isTestEnvironment, !taskIDs.isEmpty else { return }
        let identifiers = taskIDs.flatMap {
            [NotificationIdentifiers.taskStart(taskID: $0), NotificationIdentifiers.taskDue(taskID: $0)]
        }
        centre.removePending(withIdentifiers: identifiers)
        centre.removeDelivered(withIdentifiers: identifiers)
    }

    /// Cancels a specific set of habits' pending reminder notifications directly.
    func cancel(habitIDs: [UUID]) async {
        guard centreIsInjected || !Self.isTestEnvironment, !habitIDs.isEmpty else { return }
        let identifiers = habitIDs.map { NotificationIdentifiers.habitReminder(habitID: $0) }
        centre.removePending(withIdentifiers: identifiers)
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
        guard centreIsInjected || !Self.isTestEnvironment else { return }
        let pendingIdentifiers = await centre.pendingIdentifiers()
        let managedIDs = pendingIdentifiers.filter(NotificationIdentifiers.isManaged)
        guard !managedIDs.isEmpty else { return }
        centre.removePending(withIdentifiers: managedIDs)
    }

    // MARK: - [[T-15516]]: the complete read, across a relaunch

    static func storedCompleteStoreRead(defaults: UserDefaults) -> NotificationDurableCompleteStoreRead? {
        defaults.data(forKey: lastCompleteStoreReadDefaultsKey).flatMap(NotificationDurableCompleteStoreRead.init(encoded:))
    }

    private static func store(_ read: NotificationDurableCompleteStoreRead, defaults: UserDefaults) {
        guard let data = read.encoded, defaults.data(forKey: lastCompleteStoreReadDefaultsKey) != data else { return }
        defaults.set(data, forKey: lastCompleteStoreReadDefaultsKey)
    }

    /// The privacy data reset's step ([[T-1404]]): which task ids a deleted store held is still a
    /// record of it. Clears the stored read only; the next complete read writes a fresh one.
    static func clearStoredCompleteStoreRead(defaults: UserDefaults = CadenceDefaults.store) {
        defaults.removeObject(forKey: lastCompleteStoreReadDefaultsKey)
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

/// **[[T-3113]].** The notification-centre calls `NotificationManager`'s side-effecting entry points
/// make — the purge's two, plus the authorization read, the authorization request, `add`, and the
/// delivered-reminder read and removal ([[T-15464]]).
///
/// Narrow on purpose, like the purge protocol it extends: it names exactly what the manager calls
/// so a fake can record each call, and nothing the manager does not.
@MainActor
protocol CadenceNotificationCentre: CadencePendingNotificationPurgeCentre {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    /// [[T-15464]]: the identifiers of the reminders already shown in Notification Center.
    func deliveredIdentifiers() async -> [String]
    /// [[T-15464]]: withdraws already-shown reminders from Notification Center.
    func removeDelivered(withIdentifiers identifiers: [String])
}

/// The real centre behind `NotificationManager.shared` ([[T-3113]]).
///
/// `private` so that no test can hand it to `init(centre:defaults:)`: the only manager that holds
/// it is `shared`, whose entry points all guard on `isTestEnvironment`. `current()` is read inside
/// each call, as in `CadenceLiveNotificationPurgeCentre`, so constructing this touches nothing.
@MainActor
private struct CadenceSystemNotificationCentre: CadenceNotificationCentre {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func removePending(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func deliveredIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().deliveredNotifications().map(\.request.identifier)
    }

    func removeDelivered(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// One request the OS refused during a reconcile ([[T-3049]] (2)). `reason` is the error's own
/// description, kept for a reader of `lastReconcileRegistrationFailures`, not for display.
nonisolated struct NotificationRegistrationFailure: Equatable, Sendable {
    let identifier: String
    let reason: String
}

/// **[[T-15516]].** The identity of the one store FILE a container opened, for a complete read that
/// has to be recognised on a later launch.
///
/// The path, the file number and the creation date of the store file: equal across relaunches of
/// the same file, and different for anything that replaces it -- a restore moves a staged copy into
/// the store directory (`StoreBackupManager.performPendingRestoreIfNeeded`), a reset store
/// directory is recreated, the recovery store is another file. `nil` -- so nothing is proved or
/// stored -- for an in-memory store (no store file on disk), for anything that is not a regular
/// file, for a container with more than one store, or when the file cannot be read.
nonisolated enum NotificationStoreFileIdentity {
    static func of(_ container: ModelContainer) -> String? {
        let urls = container.configurations.map(\.url)
        guard urls.count == 1, let url = urls.first else { return nil }
        return of(storeURL: url)
    }

    static func of(storeURL url: URL, fileManager: FileManager = .default) -> String? {
        guard url.isFileURL,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let created = attributes[.creationDate] as? Date else { return nil }
        return "\(url.standardizedFileURL.path)|\(fileNumber)|\(created.timeIntervalSince1970)"
    }
}
