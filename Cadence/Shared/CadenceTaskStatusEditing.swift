import Foundation
import SwiftData

/// The app-side wrapper every user-facing **status** change to a task goes through: it performs the
/// shared mutation and then reconciles OS notifications, in that order, at one place.
///
/// **What it fixes (T-343).** Complete a task on iOS and its pending "starting now" / "due today"
/// `UNNotificationRequest` stayed scheduled. `NotificationManager.reconcile` is what retires it, and
/// on iOS the only thing that ran it was `iOSRootView`'s `scenePhase` observer — so a reminder could
/// fire for work already done, right up until the next lifecycle checkpoint. macOS never had the
/// gap: `TaskWorkflowService.markDone` / `markCancelled` / `markTodo` have always reconciled after
/// the transition. This is that practice given an owner on the other platform instead of six
/// surfaces each remembering it.
///
/// It is a **latency** bug rather than a correctness one — the scene-phase pass is still the safety
/// net, and `75e36c4` widened it to every phase change — which is why the ticket is P2 and why the
/// fix is a routing change rather than new machinery.
///
/// **Why the reconcile is not in `CadenceTaskMutationSupport`.** Same answer as
/// `CadenceTaskDateEditing`, and T-343 states it as a constraint rather than a preference: widgets
/// and MCP complete tasks through the very same shared helpers, and they **must not** schedule
/// app-side notifications. `NotificationManager` reads `notificationsEnabled` from
/// `UserDefaults.standard` and talks to `UNUserNotificationCenter`, neither of which an extension
/// sees the app's version of. The out-of-process writers already have their own answer: T-306 and
/// T-312 reconcile when the app adopts the external-write marker.
///
/// So the split is the same one: **shared helper mutates, app-side wrapper reconciles.**
///
/// **Where this sits relative to `CadenceTaskDateEditing`.** Deliberately beside it and not inside
/// it. They share the seam type and the `?? .default` rule; they do not share a vocabulary, and a
/// single enum spanning "which day is this on" and "is this finished" would be one name over two
/// unrelated sets of call sites. T-362's file is the template this one follows, not the file this
/// one extends.
///
/// **Not a second seam type.** The reconciler is `CadenceWindDownReconciler`, which is already "the
/// notification reconcile, injectable, live in the app and inert in a test host". Call sites never
/// name it; they pass nothing and get `.default`.
///
/// **What is deliberately not routed here.** `iOSTaskDetailSheet` was the seventh surface, left as
/// residue on T-343 because the file was owned by another change in flight; **T-407** routed its
/// two real transitions — the status well and the completion circle — through `setStatus` and
/// `toggleCompletion` below, which is what those entry points were shaped for.
///
/// Its `CadenceTaskMutationSupport.normalizeCompletionState` stays outside. That is not a user's
/// status change but the repair every field observer on the sheet fires through, including the
/// ones that run when the sheet merely opens — so routing it would reconcile the whole store on
/// every appearance and every keystroke in a title, for a status that did not move.
/// `IOSTaskDetailSheetResidueTests` pins the carve-out from both ends.
@MainActor
enum CadenceTaskStatusEditing {

    /// The completion circle and every swipe / card / row that flips one task between done and
    /// todo.
    static func toggleCompletion(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)
        reconcile(context, reconciler)
    }

    /// An explicit status, including `.cancelled` — the one transition `toggleCompletion` cannot
    /// spell.
    static func setStatus(
        _ status: TaskStatus,
        for task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.setStatus(status, for: task, modelContext: context)
        reconcile(context, reconciler)
    }

    /// Finishing a task from the focus timer: log the elapsed minutes and mark it done, then
    /// reconcile once.
    ///
    /// A case of its own rather than "log, then call `toggleCompletion`", because
    /// `CadenceFocusSupport.complete` is a single save and splitting it would either reconcile
    /// twice or leave the logged minutes outside the transition.
    static func completeFocusSession(
        _ task: AppTask,
        elapsedSeconds: Int,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceFocusSupport.complete(task, elapsedSeconds: elapsedSeconds, modelContext: context)
        reconcile(context, reconciler)
    }

    // MARK: - The one reconcile

    /// `?? .default`, never `?? .live`: `.default` is inert inside a test host, which is what keeps
    /// a status unit test from spawning a store-wide fetch into `NotificationManager` after its body
    /// has returned. A test that wants to watch the reconcile injects its own recorder.
    private static func reconcile(_ context: ModelContext, _ reconciler: CadenceWindDownReconciler?) {
        (reconciler ?? .default).run(in: context)
    }
}
