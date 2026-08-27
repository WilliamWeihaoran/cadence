import Foundation
import SwiftData

/// Shared fast-path notification reconcile trigger for task/habit create, edit, and delete call
/// sites across macOS and iOS, plus the shared reaction to Settings' "Enable reminders" toggle.
/// Kept tiny and side-effect-only so each call site stays a one-liner.
nonisolated enum HabitNotificationReconcileSupport {
    /// Main-actor by requirement, not by convenience.
    ///
    /// This was `nonisolated` taking a `ModelContext` into a `Task { @MainActor in … }`, which
    /// Swift 6 rejects: *"sending 'context' risks causing data races."* `ModelContext` is not
    /// `Sendable`, and the old signature advertised that it could be called from anywhere and would
    /// carry the context across to the main actor — which is exactly the unsafe thing.
    ///
    /// It was never actually called from anywhere else. Every one of the thirteen call sites is a
    /// SwiftUI view body or a service that is main-actor isolated by the project's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default, and each passes the context it got from
    /// `@Environment(\.modelContext)`. So the fix is to state the isolation the callers already
    /// have rather than to hop: with the function on the main actor the `Task` inherits that
    /// isolation, the context stays in one domain, and nothing is sent anywhere.
    ///
    /// The tempting alternative — keeping it `nonisolated` and silencing the diagnostic — would
    /// leave a function whose signature invites an off-main caller that would genuinely race.
    @MainActor
    static func scheduleReconcile(in context: ModelContext) {
        Task {
            guard let input = reconcileInput(
                tasks: try? context.fetch(FetchDescriptor<AppTask>()),
                habits: try? context.fetch(FetchDescriptor<Habit>())
            ) else { return }
            await NotificationManager.shared.reconcile(tasks: input.tasks, habits: input.habits)
        }
    }

    /// `nil` when either fetch failed, which callers must treat as "skip this pass".
    ///
    /// Coercing a failed fetch to `[]` is not inert: `reconcile` reads an empty desired set as
    /// "nothing should be pending" and cancels every managed notification the app has scheduled.
    /// A genuinely empty store still returns a (empty, empty) pair — that one really does mean
    /// there is nothing to notify about.
    static func reconcileInput(
        tasks: [AppTask]?,
        habits: [Habit]?
    ) -> (tasks: [AppTask], habits: [Habit])? {
        guard let tasks, let habits else { return nil }
        return (tasks, habits)
    }
}

/// The two side effects flipping Settings → "Enable reminders" can have, as injectable values.
///
/// Injectable for the same reason `CadenceNotificationCanceller` is: both branches bottom out in
/// `NotificationManager`, which early-returns inside a test host, so from the outside a branch
/// that ran and a branch that did not look identical — and this toggle has two branches that are
/// each other's inverse, which is exactly the shape where a swapped pair stays green forever.
///
/// The cancel half delegates to `CadenceNotificationCanceller.live` rather than restating
/// `NotificationManager.shared.cancelAll()`, so "how the app cancels pending notifications" keeps
/// one owner.
@MainActor
struct CadenceNotificationsEnabledEffects {
    private let cancel: () async -> Void
    private let reconcile: (ModelContext) -> Void

    init(
        cancel: @escaping () async -> Void,
        reconcile: @escaping (ModelContext) -> Void
    ) {
        self.cancel = cancel
        self.reconcile = reconcile
    }

    func cancelPendingNotifications() async {
        await cancel()
    }

    func reconcileNotifications(in context: ModelContext) {
        reconcile(context)
    }

    static var live: Self {
        Self(
            cancel: { await CadenceNotificationCanceller.live.run() },
            reconcile: { HabitNotificationReconcileSupport.scheduleReconcile(in: $0) }
        )
    }
}

extension HabitNotificationReconcileSupport {
    /// The one reaction to Settings → "Enable reminders" changing, shared by both platforms.
    ///
    /// **T-361.** `reconcile` has always done the right thing when the setting is off — it calls
    /// `cancelAll()` — but nothing observed the setting *changing*. The toggle wrote
    /// `UserDefaults` and stopped, so pending OS notifications survived until the app next hit a
    /// scene-phase checkpoint and a reminder could fire moments after the user switched reminders
    /// off. The symmetric half matters just as much: switching reminders back on scheduled
    /// nothing until the app backgrounded, which reads as the setting doing nothing at all.
    ///
    /// Off does **not** route through `scheduleReconcile`. That path fetches first and skips the
    /// pass when either fetch fails (see `reconcileInput`), which would make "the reminders you
    /// just turned off go away" conditional on a store read succeeding. Cancelling is
    /// unconditional; it needs no state to be correct.
    @MainActor
    static func applyNotificationsEnabledChange(
        _ enabled: Bool,
        in context: ModelContext,
        effects: CadenceNotificationsEnabledEffects? = nil
    ) async {
        // `? = nil` rather than `= .live`, and for a compiler reason rather than a style one: a
        // default argument expression is evaluated in a *nonisolated* context, so naming a
        // main-actor-isolated `.live` there does not compile. Same shape as the wind-down entry
        // points, which take `reconciler: CadenceWindDownReconciler? = nil` for the same reason.
        let effects = effects ?? .live
        if enabled {
            effects.reconcileNotifications(in: context)
        } else {
            await effects.cancelPendingNotifications()
        }
    }

    /// The call-site spelling: a SwiftUI `.onChange` body is synchronous, and both settings owners
    /// should stay a single line that names the shared entry point rather than growing a local
    /// branch each that can drift apart.
    @MainActor
    static func notificationsEnabledDidChange(to enabled: Bool, in context: ModelContext) {
        Task { await applyNotificationsEnabledChange(enabled, in: context) }
    }
}
