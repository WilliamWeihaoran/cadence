import Foundation
import SwiftData
import Testing
@testable import Cadence

// NOTE: This file only tests the pure planning logic in `NotificationScheduling.swift`
// (TaskNotificationPlanner, NotificationPlan, NotificationReconcileDiff). It deliberately
// does NOT test `UNUserNotificationCenter` itself — real authorization prompts, actual
// notification delivery, or diffing against `pendingNotificationRequests()` are inherently
// manual/simulator-only. A future agent should not try to write a flaky test against the real
// notification center; `NotificationManager` is a thin adapter over the plan this file verifies.

@MainActor
struct NotificationSchedulingTests {
    private func date(_ key: String, hour: Int = 0, minute: Int = 0) -> Date {
        let base = DateFormatters.date(from: key)!
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    // MARK: - TaskNotificationPlanner.startNotification

    @Test func startNotificationNilWhenUnscheduled() {
        let task = AppTask(title: "Unscheduled")
        task.scheduledDate = "2026-06-10"
        task.scheduledStartMin = -1
        let now = date("2026-06-09")

        #expect(TaskNotificationPlanner.startNotification(for: task, now: now) == nil)
    }

    @Test func startNotificationNilWhenDone() {
        let task = AppTask(title: "Done task")
        task.scheduledDate = "2026-06-10"
        task.scheduledStartMin = 540
        task.status = .done
        let now = date("2026-06-09")

        #expect(TaskNotificationPlanner.startNotification(for: task, now: now) == nil)
    }

    @Test func startNotificationNilWhenCancelled() {
        let task = AppTask(title: "Cancelled task")
        task.scheduledDate = "2026-06-10"
        task.scheduledStartMin = 540
        task.status = .cancelled
        let now = date("2026-06-09")

        #expect(TaskNotificationPlanner.startNotification(for: task, now: now) == nil)
    }

    @Test func startNotificationNilWhenFireTimeAlreadyPast() {
        let task = AppTask(title: "Already started")
        task.scheduledDate = "2026-06-10"
        task.scheduledStartMin = 540 // 9:00 AM
        let now = date("2026-06-10", hour: 10) // 10:00 AM same day — already past

        #expect(TaskNotificationPlanner.startNotification(for: task, now: now) == nil)
    }

    @Test func startNotificationFiresAtCorrectTimeForFutureScheduledTask() throws {
        let task = AppTask(title: "Standup")
        task.scheduledDate = "2026-06-10"
        task.scheduledStartMin = 540 // 9:00 AM
        let now = date("2026-06-09")

        let request = try #require(TaskNotificationPlanner.startNotification(for: task, now: now))
        #expect(request.identifier == NotificationIdentifiers.taskStart(taskID: task.id))
        #expect(request.kind == .taskStart)
        #expect(request.title == "Standup")
        #expect(request.body == "Starting now")
        #expect(request.fireDate == date("2026-06-10", hour: 9))
    }

    @Test func startNotificationHandlesEndOfDayMinutesWithoutRollingToWrongDay() throws {
        let task = AppTask(title: "Late night wrap-up")
        task.scheduledDate = "2026-06-10"
        task.scheduledStartMin = 1435 // 11:55 PM
        let now = date("2026-06-10", hour: 9)

        let request = try #require(TaskNotificationPlanner.startNotification(for: task, now: now))
        #expect(request.fireDate == date("2026-06-10", hour: 23, minute: 55))
    }

    // MARK: - TaskNotificationPlanner.dueNotification

    @Test func dueNotificationNilWhenNoDueDate() {
        let task = AppTask(title: "No due date")
        let now = date("2026-06-09")

        #expect(TaskNotificationPlanner.dueNotification(for: task, now: now, reminderHour: 9, reminderMinute: 0) == nil)
    }

    @Test func dueNotificationNilWhenDone() {
        let task = AppTask(title: "Done task")
        task.dueDate = "2026-06-10"
        task.status = .done
        let now = date("2026-06-09")

        #expect(TaskNotificationPlanner.dueNotification(for: task, now: now, reminderHour: 9, reminderMinute: 0) == nil)
    }

    @Test func dueNotificationNilWhenCancelled() {
        let task = AppTask(title: "Cancelled task")
        task.dueDate = "2026-06-10"
        task.status = .cancelled
        let now = date("2026-06-09")

        #expect(TaskNotificationPlanner.dueNotification(for: task, now: now, reminderHour: 9, reminderMinute: 0) == nil)
    }

    @Test func dueNotificationNilWhenAlreadyPast() {
        let task = AppTask(title: "Due earlier today")
        task.dueDate = "2026-06-10"
        let now = date("2026-06-10", hour: 10) // reminder is 9 AM, already past

        #expect(TaskNotificationPlanner.dueNotification(for: task, now: now, reminderHour: 9, reminderMinute: 0) == nil)
    }

    @Test func dueNotificationFiresAtFixedTimeOfDay() throws {
        let task = AppTask(title: "Submit report")
        task.dueDate = "2026-06-10"
        let now = date("2026-06-09")

        let request = try #require(TaskNotificationPlanner.dueNotification(for: task, now: now, reminderHour: 9, reminderMinute: 0))
        #expect(request.identifier == NotificationIdentifiers.taskDue(taskID: task.id))
        #expect(request.kind == .taskDue)
        #expect(request.title == "Submit report")
        #expect(request.body == "Due today")
        #expect(request.fireDate == date("2026-06-10", hour: 9))
    }

    // MARK: - Habit reminders are retired ([[T-2081]])

    /// **The inversion of the five habit-reminder planner tests that stood here.**
    ///
    /// They pinned *when* a habit got a reminder: later today vs. tomorrow, both ends of the valid
    /// minute range, and (T-363) nothing at all for a junk minute. The planner is gone, so the
    /// question they answered no longer has a wrong answer — and the replacement is strictly
    /// stronger than any of them. It is not "a corrupt reminder time schedules nothing", it is
    /// **no habit schedules anything, whatever its reminder time**, including the in-range values
    /// the old tests used as their non-vacuity control.
    ///
    /// Asserted on `plan.all` rather than on the absence of a symbol, because the plan is what
    /// `NotificationManager.reconcile` installs. `NotificationPlan.build` no longer accepts a
    /// `habits:` argument at all, so the habits below cannot even be offered to it — this test
    /// states what that compile-time fact buys at runtime.
    @Test func noHabitReachesTheInstalledPlanWhateverItsReminderTime() {
        let now = date("2026-06-09", hour: 8)

        // Every shape the retired planner distinguished: later today, already passed, both ends of
        // the valid range, unset, and the out-of-range values T-363 was about.
        for minuteOfDay in [nil, 0, 7 * 60, 20 * 60, 1439, -15, 1440, 100_000] as [Int?] {
            let habit = Habit(title: "Retired \(String(describing: minuteOfDay))")
            habit.reminderMinuteOfDay = minuteOfDay

            let task = AppTask(title: "Still scheduled")
            task.scheduledDate = "2026-06-10"
            task.scheduledStartMin = 540

            let plan = NotificationPlan.build(
                tasks: [task],
                now: now,
                dueReminderHour: 9,
                dueReminderMinute: 0
            )

            #expect(
                plan.all.contains { $0.identifier == NotificationIdentifiers.habitReminder(habitID: habit.id) } == false,
                "minuteOfDay \(String(describing: minuteOfDay)) still reached the plan"
            )
            #expect(plan.all.contains { $0.kind == .habitReminder } == false)
            // Non-vacuity: the plan is not simply empty. The task alongside each habit is still
            // planned, so the absences above are about habits rather than about `build` returning
            // nothing.
            #expect(plan.all.map(\.identifier) == [NotificationIdentifiers.taskStart(taskID: task.id)])
        }
    }

    /// The minute range outlived the planner, and on purpose.
    ///
    /// `HabitNotificationPlanner` is now validation-only: `CadenceHabitReminderEditing` still asks
    /// it whether a stored value is a real time of day, for rows the schema deliberately keeps.
    /// Pinned so "the planner is gone" is not mistaken for "the range went with it".
    @Test func theRetiredPlannerKeepsOnlyItsMinuteRange() {
        #expect(HabitNotificationPlanner.reminderMinuteRange == 0...1439)
        #expect(HabitNotificationPlanner.reminderMinuteRange == HabitReminderTime.minuteRange)
    }

    // MARK: - NotificationPlan.build

    @Test func planBuildContainsExactlyExpectedIdentifiers() {
        let now = date("2026-06-09", hour: 8)

        let scheduledTask = AppTask(title: "Scheduled")
        scheduledTask.scheduledDate = "2026-06-10"
        scheduledTask.scheduledStartMin = 540

        let dueTask = AppTask(title: "Due")
        dueTask.dueDate = "2026-06-10"

        let doneTask = AppTask(title: "Done, should not appear")
        doneTask.scheduledDate = "2026-06-10"
        doneTask.scheduledStartMin = 600
        doneTask.dueDate = "2026-06-10"
        doneTask.status = .done

        let plan = NotificationPlan.build(
            tasks: [scheduledTask, dueTask, doneTask],
            now: now,
            dueReminderHour: 9,
            dueReminderMinute: 0
        )

        #expect(Set(plan.taskStarts.map(\.identifier)) == Set([NotificationIdentifiers.taskStart(taskID: scheduledTask.id)]))
        #expect(Set(plan.taskDues.map(\.identifier)) == Set([NotificationIdentifiers.taskDue(taskID: dueTask.id)]))
        // `taskStarts + taskDues` is the whole of `all` now — [[T-2081]] removed the third channel
        // rather than leaving it empty, so there is no `plan.habitReminders` to assert about.
        #expect(Set(plan.all.map(\.identifier)) == Set(plan.taskStarts.map(\.identifier) + plan.taskDues.map(\.identifier)))
    }

    // MARK: - NotificationReconcileDiff

    private func request(_ identifier: String, title: String = "Standup", hour: Int = 9) -> CadenceNotificationRequest {
        CadenceNotificationRequest(
            identifier: identifier,
            kind: .taskStart,
            title: title,
            body: "Starting now",
            fireDate: date("2026-06-10", hour: hour)
        )
    }

    @Test func reconcileDiffReAddsAlreadyPendingRequestsSoRescheduledTimesTakeEffect() {
        let taskID = UUID()
        let identifier = NotificationIdentifiers.taskStart(taskID: taskID)
        // The identifier only encodes the task's UUID — the fire date and title live in the pending
        // request. Skipping IDs that are already pending leaves the stale 09:00 request in place.
        let desired = [request(identifier, title: "Standup", hour: 15)]

        let diff = NotificationReconcileDiff.make(desired: desired, pendingIdentifiers: [identifier])

        #expect(diff.identifiersToRemove.isEmpty)
        #expect(diff.requestsToAdd == desired)
    }

    @Test func reconcileDiffRemovesManagedPendingIdentifiersThatAreNoLongerDesired() {
        let staleID = NotificationIdentifiers.taskDue(taskID: UUID())
        let liveID = NotificationIdentifiers.taskStart(taskID: UUID())

        let diff = NotificationReconcileDiff.make(
            desired: [request(liveID)],
            pendingIdentifiers: [staleID, liveID]
        )

        #expect(diff.identifiersToRemove == [staleID])
        #expect(diff.requestsToAdd.map(\.identifier) == [liveID])
    }

    @Test func reconcileDiffLeavesUnmanagedPendingIdentifiersAlone() {
        let foreignID = "some-other-feature-\(UUID().uuidString)"

        let diff = NotificationReconcileDiff.make(desired: [], pendingIdentifiers: [foreignID])

        #expect(diff.identifiersToRemove.isEmpty)
        #expect(diff.requestsToAdd.isEmpty)
    }

    @Test func reconcileDiffWithEmptyDesiredSetClearsEveryManagedPendingIdentifier() {
        let first = NotificationIdentifiers.taskStart(taskID: UUID())
        let second = NotificationIdentifiers.habitReminder(habitID: UUID())

        let diff = NotificationReconcileDiff.make(desired: [], pendingIdentifiers: [first, second])

        // An empty desired set is destructive by design, which is exactly why callers must never
        // hand `reconcile` an empty list that actually means "the fetch failed".
        #expect(Set(diff.identifiersToRemove) == Set([first, second]))
    }

    @Test func reconcileDiffKeepsOnlyAsManyRequestsAsThePlatformWillHold() {
        // iOS holds 64 pending requests per app and silently drops the overflow, so the cap has
        // to be ours and it has to keep the ones that fire first.
        let base = date("2026-06-10", hour: 9)
        let desired = (0..<80).map { offset in
            CadenceNotificationRequest(
                identifier: NotificationIdentifiers.taskStart(taskID: UUID()),
                kind: .taskStart,
                title: "Task \(offset)",
                body: "Starting now",
                fireDate: base.addingTimeInterval(TimeInterval(offset) * 3600)
            )
        }

        let diff = NotificationReconcileDiff.make(
            desired: desired.shuffled(),
            pendingIdentifiers: desired.map(\.identifier)
        )

        #expect(diff.requestsToAdd.count == 64)
        #expect(Set(diff.requestsToAdd.map(\.identifier)) == Set(desired.prefix(64).map(\.identifier)))
        // The overflow has to be removed rather than left pending, or the requests the OS kept
        // last time survive as a stale, arbitrary subset.
        #expect(Set(diff.identifiersToRemove) == Set(desired.suffix(16).map(\.identifier)))
    }

    // MARK: - HabitNotificationReconcileSupport

    /// **[[T-2081]] retired the paired-fetch helper, and these three tests with it.**
    ///
    /// Its job was to pair two optional fetches so neither could be coerced to `[]` — because
    /// `reconcile` reads an empty desired set as "cancel everything", a failed fetch silently
    /// cancelling every pending reminder was the bug it existed to prevent. With the habit fetch
    /// gone there is one optional left and the helper would be the identity function, so the rule
    /// moved into `scheduleReconcile`'s own `guard let`.
    ///
    /// The rule still has to hold, so it is pinned where it now lives rather than dropped: the
    /// fetch is `try?`-and-`guard`, never `?? []`. A source assertion is the weak form, and it is
    /// the only form available — `scheduleReconcile` spawns a `Task` into a `@MainActor`
    /// singleton that early-returns under test, which is why the helper was extracted in the first
    /// place.
    @Test func scheduleReconcileStillSkipsThePassWhenTheFetchFails() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Shared/HabitNotificationReconcileSupport.swift")

        #expect(source.contains("guard let tasks = try? context.fetch(FetchDescriptor<AppTask>()) else { return }"))
        #expect(
            source.contains("?? []") == false,
            "a failed fetch coerced to an empty array would cancel every pending reminder"
        )
        #expect(
            source.contains("FetchDescriptor<Habit>") == false,
            "the reconcile fetches habits again"
        )
        #expect(
            source.contains("reconcile(tasks: tasks)"),
            "the reconcile call no longer matches the habit-free signature"
        )
    }
}

/// T-241: a bulk container wind-down settled its tasks and never reconciled notifications, so
/// completing or archiving a list left every one of its tasks' pending "starting now" / "due today"
/// nudges live until the next `scenePhase` checkpoint swept them. The single-task transitions
/// (`TaskWorkflowService.markDone` / `markCancelled` / `markTodo`) have always reconciled; the bulk
/// path never did.
///
/// **These tests are about the seam, not about notifications.** `scheduleReconcile` spawns an
/// unstructured `Task` that fetches the whole store and calls into the `@MainActor`
/// `NotificationManager` singleton, which is why the fix was deferred twice rather than added as a
/// one-liner: an unconditional call would have left every existing wind-down test doing async store
/// work after its body returned. `CadenceWindDownReconciler` is the answer — its `default` is inert
/// inside a test host, so nothing here reaches `NotificationManager` or `UNUserNotificationCenter`
/// at all, and a test that wants to prove the wiring injects its own and watches it fire.
@MainActor
struct ContainerWindDownReconcileTests {

    /// Records one entry per `run(in:)`, and records it as *what the reconciler could see* — the
    /// number of settled tasks visible in the context it was handed. A reconciler invoked before
    /// the settle loop would record zero, so this pins the ordering as well as the call.
    ///
    /// `@MainActor` explicitly: a nested type does not inherit the enclosing suite's isolation, and
    /// `CadenceWindDownReconciler` is main-actor isolated.
    @MainActor
    private final class Recorder {
        var settledCountsSeen: [Int] = []

        func reconciler() -> CadenceWindDownReconciler {
            CadenceWindDownReconciler { context in
                let tasks = (try? context.fetch(FetchDescriptor<AppTask>())) ?? []
                self.settledCountsSeen.append(tasks.filter { $0.isDone || $0.isCancelled }.count)
            }
        }
    }

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    private func openTask(_ title: String) -> AppTask {
        AppTask(title: title)
    }

    // MARK: - The default is inert in a test host

    /// The whole reason the fix could be a one-liner and still was not. If `default` is ever
    /// "simplified" back to an unconditional `.live`, the eighteen wind-down tests in
    /// `CadenceListWindDownSurfaceTests` and `CadenceCancelledTaskReachabilityTests` quietly start
    /// spawning store fetches into the notification layer, and nothing else goes red.
    @Test func theDefaultReconcilerIsInertInsideATestHost() {
        #expect(NotificationManager.isTestEnvironment)
        #expect(CadenceWindDownReconciler.default.isLive == false)
        #expect(CadenceWindDownReconciler.live.isLive)
        #expect(CadenceWindDownReconciler.inert.isLive == false)
    }

    // MARK: - Every entry point reconciles

    @Test func archivingAnAreaReconcilesAfterSettlingItsTasks() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let child = Project(name: "Kitchen", area: area)
        let own = openTask("own")
        own.area = area
        let inChild = openTask("in child")
        inChild.project = child
        for model in [own, inChild] { modelContext.insert(model) }
        modelContext.insert(area)
        modelContext.insert(child)
        area.tasks = [own]
        area.projects = [child]
        child.tasks = [inChild]
        try modelContext.save()

        let recorder = Recorder()
        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: modelContext,
            reconciler: recorder.reconciler()
        )

        #expect(own.isCancelled)
        #expect(inChild.isCancelled)
        // One reconcile for the batch, and it saw both cancellations already written.
        #expect(recorder.settledCountsSeen == [2])
    }

    @Test func completingAnAreaReconciles() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let task = openTask("open")
        task.area = area
        modelContext.insert(task)
        modelContext.insert(area)
        area.tasks = [task]
        try modelContext.save()

        let recorder = Recorder()
        TaskContainerLifecycleService.completeRemainingActiveTasks(
            in: area,
            includingChildProjects: false,
            in: modelContext,
            reconciler: recorder.reconciler()
        )

        #expect(task.isDone)
        #expect(recorder.settledCountsSeen == [1])
    }

    @Test func windingAProjectDownReconcilesInBothDirections() throws {
        let modelContext = ModelContext(try container())
        let cancelProject = Project(name: "Cancel")
        let completeProject = Project(name: "Complete")
        let toCancel = openTask("to cancel")
        toCancel.project = cancelProject
        let toComplete = openTask("to complete")
        toComplete.project = completeProject
        for model in [toCancel, toComplete] { modelContext.insert(model) }
        modelContext.insert(cancelProject)
        modelContext.insert(completeProject)
        cancelProject.tasks = [toCancel]
        completeProject.tasks = [toComplete]
        try modelContext.save()

        let recorder = Recorder()
        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: cancelProject,
            in: modelContext,
            reconciler: recorder.reconciler()
        )
        TaskContainerLifecycleService.completeRemainingActiveTasks(
            in: completeProject,
            in: modelContext,
            reconciler: recorder.reconciler()
        )

        #expect(toCancel.isCancelled)
        #expect(toComplete.isDone)
        #expect(recorder.settledCountsSeen == [1, 2])
    }

    @Test func windingAKanbanColumnDownReconcilesInBothDirections() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Board")
        let doing = TaskSectionConfig(name: "Doing")
        let review = TaskSectionConfig(name: "Review")
        let inDoing = openTask("in doing")
        inDoing.project = project
        inDoing.sectionName = "Doing"
        let inReview = openTask("in review")
        inReview.project = project
        inReview.sectionName = "Review"
        for model in [inDoing, inReview] { modelContext.insert(model) }
        modelContext.insert(project)
        project.tasks = [inDoing, inReview]
        try modelContext.save()

        let recorder = Recorder()
        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: doing,
            area: nil,
            project: project,
            in: modelContext,
            reconciler: recorder.reconciler()
        )
        TaskContainerLifecycleService.completeRemainingActiveTasks(
            in: review,
            area: nil,
            project: project,
            in: modelContext,
            reconciler: recorder.reconciler()
        )

        #expect(inDoing.isCancelled)
        #expect(inReview.isDone)
        #expect(recorder.settledCountsSeen == [1, 2])
    }

    // MARK: - Nothing settled, nothing to reconcile

    /// The reconcile diffs a desired set derived from the store against what is pending, so an
    /// unchanged store diffs to a no-op. Archiving an already-empty list should not pay for two
    /// full-store fetches to discover that.
    @Test func aWindDownThatSettlesNothingDoesNotReconcile() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Empty")
        let alreadyDone = openTask("done")
        alreadyDone.status = .done
        alreadyDone.area = area
        modelContext.insert(alreadyDone)
        modelContext.insert(area)
        area.tasks = [alreadyDone]
        try modelContext.save()

        let recorder = Recorder()
        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: modelContext,
            reconciler: recorder.reconciler()
        )

        #expect(recorder.settledCountsSeen.isEmpty)
    }
}
