import Foundation
import Observation
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
    ///
    /// **It catches rather than rethrows, and records the refusal (T-636).** The mutation under it
    /// throws now, but the six surfaces that reach this are three cards, two sheets and a
    /// `[CadenceSwipeAction]` built by a `static func` with no view state at all — so "let the
    /// caller name the failure where the user is already looking" cannot mean six copies of an
    /// alert, and for the swipe it cannot mean anything. macOS answered the identical question the
    /// identical way in T-628: `TaskCompletionAnimationManager.settleFailed` is read by
    /// `macOSRootView`, once, because a notice owned by any one surface is missing from the rest.
    ///
    /// **Nothing is reconciled on the failure path.** `commitSettle` has already put the status,
    /// the timestamp and the successor back, so there is no transition for the notification
    /// reconcile to act on — and reconciling anyway would retire a reminder for work that is still
    /// open.
    static func toggleCompletion(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        do {
            try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context)
        } catch {
            CadenceTaskSettleFailureCenter.shared.record()
            return
        }
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
    ///
    /// **It answers whether the change is in the store (T-636(c)).** `toggleCompletion` above
    /// catches and records because its six surfaces cannot each own a notice; this one has exactly
    /// one caller, `iOSFocusView.complete(_:)`, and that caller has something to do with the answer
    /// the shared alert cannot do for it — the elapsed clock. Resetting it over a refused commit
    /// discards the minutes for good, since the timer is the only place they existed. So the
    /// refusal is recorded on `CadenceTaskSettleFailureCenter` for the sentence, *and* returned for
    /// the clock.
    ///
    /// Nothing is reconciled on the failure path, for the reason `toggleCompletion` records:
    /// `commitSettle` has already put the transition back, so there is none to reconcile.
    @discardableResult
    static func completeFocusSession(
        _ task: AppTask,
        elapsedSeconds: Int,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) -> Bool {
        do {
            try CadenceFocusSupport.complete(task, elapsedSeconds: elapsedSeconds, modelContext: context)
        } catch {
            CadenceTaskSettleFailureCenter.shared.record()
            return false
        }
        reconcile(context, reconciler)
        return true
    }

    // MARK: - The one reconcile

    /// `?? .default`, never `?? .live`: `.default` is inert inside a test host, which is what keeps
    /// a status unit test from spawning a store-wide fetch into `NotificationManager` after its body
    /// has returned. A test that wants to watch the reconcile injects its own recorder.
    private static func reconcile(_ context: ModelContext, _ reconciler: CadenceWindDownReconciler?) {
        (reconciler ?? .default).run(in: context)
    }
}

/// Where a refused **settle** is recorded so one surface can name it (T-636).
///
/// iOS's answer to macOS's `TaskCompletionAnimationManager.settleFailed`, and beside
/// `CadenceTaskStatusEditing` rather than in a file of its own because the wrapper above is the
/// only party that may write it: a second writer would be a second answer to "did that tick land".
///
/// It carries a flag rather than an error, and that is a claim about what there is to say. Every
/// refusal it can hold has already been undone by `CadenceTaskMutationSupport.commitSettle`, so the
/// circle the user is looking at has re-drawn open on its own and the only thing left to add is the
/// sentence `CadencePendingChangePersistence.editFailureNotice` already spells, under the title
/// `CadenceTaskMutationSupport.settleFailureAlertTitle` macOS already shows.
@MainActor
@Observable
final class CadenceTaskSettleFailureCenter {
    static let shared = CadenceTaskSettleFailureCenter()

    private(set) var settleFailed = false

    private init() {}

    func record() { settleFailed = true }

    func clear() { settleFailed = false }
}
