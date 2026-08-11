import Foundation
import Observation
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
    /// An empty `tasks`/`habits` pair means "cancel everything", so callers must pass real fetched
    /// state — never a failed fetch coerced to an empty array. See `HabitNotificationReconcileSupport`.
    func reconcile(
        tasks: [AppTask],
        habits: [Habit],
        dueReminderHour: Int = 9,
        dueReminderMinute: Int = 0
    ) async {
        guard !Self.isTestEnvironment else { return }

        let notificationsEnabled = UserDefaults.standard.bool(forKey: Self.notificationsEnabledDefaultsKey)
        guard notificationsEnabled, isAuthorized else {
            await cancelAll()
            return
        }

        let plan = NotificationPlan.build(
            tasks: tasks,
            habits: habits,
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

        for request in diff.requestsToAdd {
            let content = Self.makeContent(for: request)
            let osRequest = UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: Self.makeTrigger(for: request)
            )
            try? await center.add(osRequest)
        }
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

    func cancelAll() async {
        guard !Self.isTestEnvironment else { return }
        let pending = await center.pendingNotificationRequests()
        let managedIDs = pending.map(\.identifier).filter(NotificationIdentifiers.isManaged)
        guard !managedIDs.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: managedIDs)
    }

    // MARK: - Helpers

    private static func makeContent(for request: CadenceNotificationRequest) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
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
}
