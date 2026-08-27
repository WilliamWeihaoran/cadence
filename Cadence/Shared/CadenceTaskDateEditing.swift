import Foundation
import SwiftData

/// The app-side wrapper every user-facing **date or time** edit to a task goes through: it performs
/// the shared mutation and then reconciles OS notifications, in that order, at one place.
///
/// **What it fixes (T-362).** Move a task from 9am to 3pm and the 9am `UNNotificationRequest` stays
/// pending. `NotificationManager.reconcile` is what retires it, and until this existed the only
/// things that ran it were the two root views' `scenePhase` observers — so the reminder fired at the
/// old time unless the user happened to background the app first. The create sheets on both
/// platforms and `iOSTaskDetailSheet.applyDates()` already reconciled immediately; this is that
/// practice given one owner instead of being re-typed at each surface. Same shape as
/// [[T-343]] (status edits, still open) and the same latency class as [[T-306]] / [[T-312]].
///
/// **Why the reconcile is not in `CadenceTaskMutationSupport`.** That enum is the pure mutation
/// layer: it writes model fields and saves, and nothing in it reaches outside SwiftData.
/// `NotificationManager` is a `@MainActor` singleton that reads `notificationsEnabled` out of
/// `UserDefaults.standard` and talks to `UNUserNotificationCenter` — the two things
/// `CadenceStoreSupport` and `CadenceWidgetIntents` document that an extension **must not** do,
/// because the extension does not see the app's suite. Today the widget and MCP targets do not
/// compile `CadenceTaskMutationSupport.swift` at all (they list their `Cadence/` sources
/// explicitly), and folding a notification dependency into it would be the thing that stops them
/// ever being able to. Their own write paths already have their answer: T-306 reconciles MCP writes
/// when the app adopts the external-write marker.
///
/// So the split is: **shared helper mutates, app-side wrapper reconciles.**
///
/// **Every function here is one line plus one reconcile**, and the reconcile is `private`. That is
/// deliberate: eleven surfaces each writing their own `HabitNotificationReconcileSupport` call is
/// the defect shape [[T-374]] names — a correct practice that each new call site has to remember.
/// A surface that needs an edit this vocabulary cannot spell should gain a case here rather than
/// reach past it.
///
/// The reconciler is `CadenceWindDownReconciler` rather than a second identical seam type. It is
/// already "the notification reconcile, injectable, live in the app and inert in a test host" —
/// see its own doc comment for why that default has to exist — and the only thing its name is
/// narrower than is its behaviour. Call sites never name it; they pass `nil` and get `.default`.
@MainActor
enum CadenceTaskDateEditing {

    // MARK: - Do date

    static func setScheduledDate(
        _ dateKey: String,
        for task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.setScheduledDate(dateKey, for: task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func scheduleToday(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.scheduleToday(task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func scheduleTomorrow(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.scheduleTomorrow(task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func scheduleNextWeek(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.scheduleNextWeek(task, modelContext: context)
        reconcile(context, reconciler)
    }

    /// Clearing a do date drops the timeline slot with it — a slot on no day is not a slot. That is
    /// `clearScheduledDate`'s existing contract, and it is why the date pickers that used to write
    /// `task.scheduledDate = ""` by hand now come through here.
    static func clearScheduledDate(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.clearScheduledDate(task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func moveTaskToDate(
        _ task: AppTask,
        dateKey: String,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.moveTaskToDate(task, dateKey: dateKey, modelContext: context)
        reconcile(context, reconciler)
    }

    // MARK: - Do time

    static func setScheduledTime(
        _ startMin: Int,
        for task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.setScheduledTime(startMin, for: task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func clearScheduledTime(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.clearScheduledTime(task, modelContext: context)
        reconcile(context, reconciler)
    }

    /// Day and start minute together, for the surfaces that place a task on a slot in one gesture:
    /// the iPad schedule pane's empty hour, and the two time controls that have to materialise a
    /// day before a time on it can mean anything. One reconcile, not two.
    static func setScheduledSlot(
        dateKey: String,
        startMin: Int,
        for task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.setScheduledDate(dateKey, for: task, modelContext: context)
        CadenceTaskMutationSupport.setScheduledTime(startMin, for: task, modelContext: context)
        reconcile(context, reconciler)
    }

    // MARK: - Due date

    static func setDueDate(
        _ dateKey: String,
        for task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.setDueDate(dateKey, for: task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func dueToday(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.dueToday(task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func dueTomorrow(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.dueTomorrow(task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func dueNextWeek(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.dueNextWeek(task, modelContext: context)
        reconcile(context, reconciler)
    }

    static func clearDueDate(
        _ task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.clearDueDate(task, modelContext: context)
        reconcile(context, reconciler)
    }

    // MARK: - Both at once

    static func setPlanningDates(
        scheduledDate: String?,
        dueDate: String?,
        for task: AppTask,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        CadenceTaskMutationSupport.setPlanningDates(
            scheduledDate: scheduledDate,
            dueDate: dueDate,
            for: task,
            modelContext: context
        )
        reconcile(context, reconciler)
    }

    // MARK: - The one reconcile

    /// `?? .default`, never `?? .live`: `.default` is inert inside a test host, which is what keeps
    /// a scheduling unit test from spawning a store-wide fetch into `NotificationManager` after its
    /// body has returned. A test that wants to watch the reconcile injects its own recorder.
    private static func reconcile(_ context: ModelContext, _ reconciler: CadenceWindDownReconciler?) {
        (reconciler ?? .default).run(in: context)
    }
}
