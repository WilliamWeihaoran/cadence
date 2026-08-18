import Foundation
import SwiftData

/// Shared fast-path notification reconcile trigger for task/habit create, edit, and delete call
/// sites across macOS and iOS. Kept tiny and side-effect-only so each call site stays a one-liner.
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
