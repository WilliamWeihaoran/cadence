import Foundation
import SwiftData
import Testing
@testable import Cadence

// NOTE: This file only tests the pure planning logic in `NotificationScheduling.swift`
// (TaskNotificationPlanner, HabitNotificationPlanner, NotificationPlan.build). It deliberately
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

    // MARK: - HabitNotificationPlanner.reminder

    @Test func habitReminderNilWhenNoReminderTimeSet() {
        let habit = Habit(title: "Read")
        habit.reminderMinuteOfDay = nil
        let now = date("2026-06-09", hour: 8)

        #expect(HabitNotificationPlanner.reminder(for: habit, now: now) == nil)
    }

    @Test func habitReminderResolvesLaterTodayWhenStillUpcoming() throws {
        let habit = Habit(title: "Stretch")
        habit.reminderMinuteOfDay = 20 * 60 // 8:00 PM
        let now = date("2026-06-09", hour: 8) // 8:00 AM — reminder is later today

        let request = try #require(HabitNotificationPlanner.reminder(for: habit, now: now))
        #expect(request.identifier == NotificationIdentifiers.habitReminder(habitID: habit.id))
        #expect(request.kind == .habitReminder)
        #expect(request.fireDate == date("2026-06-09", hour: 20))
    }

    @Test func habitReminderResolvesTomorrowWhenTimeAlreadyPassedToday() throws {
        let habit = Habit(title: "Journal")
        habit.reminderMinuteOfDay = 7 * 60 // 7:00 AM
        let now = date("2026-06-09", hour: 8) // 8:00 AM — 7 AM already passed today

        let request = try #require(HabitNotificationPlanner.reminder(for: habit, now: now))
        #expect(request.fireDate == date("2026-06-10", hour: 7))
    }

    /// **An out-of-range reminder time schedules nothing (T-363).**
    ///
    /// `Calendar.date(bySettingHour:minute:second:of:)` returns `nil` for every one of these, and
    /// the planner used to end that expression in `?? now` — so a habit carrying a junk minute got
    /// a *standing daily* reminder at whatever o'clock reconcile happened to run. The assertion is
    /// `== nil` rather than "not at `now`" on purpose: the values below are not times, and the
    /// planner has no business inventing one for them.
    ///
    /// `Habit.reminderMinuteOfDay` is an unvalidated `Int?` by design — see
    /// `HabitStreakTests.reminderMinuteOfDayHasNoRangeValidationTodayByDesignGap` — so these
    /// values are reachable from imported, synced or hand-edited data even though no picker emits
    /// them.
    @Test func habitReminderSchedulesNothingForAnOutOfRangeMinute() {
        let now = date("2026-06-09", hour: 8)

        for minuteOfDay in [-1500, -15, -1, 1440, 1500, 100_000] {
            let habit = Habit(title: "Corrupt reminder \(minuteOfDay)")
            habit.reminderMinuteOfDay = minuteOfDay

            // Non-vacuity: the fallback these used to take was `now` itself, so a planner that
            // still fell back would return a request rather than nil here.
            #expect(
                HabitNotificationPlanner.reminder(for: habit, now: now) == nil,
                "minuteOfDay \(minuteOfDay) still schedules a daily reminder"
            )
        }
    }

    /// The guard is a range, and both of its ends are inclusive: 00:00 and 23:59 are real reminder
    /// times and a fix that clipped either would silently drop a user's actual setting.
    @Test func habitReminderAcceptsBothEndsOfTheValidMinuteRange() throws {
        #expect(HabitNotificationPlanner.reminderMinuteRange == 0...1439)

        let midnight = Habit(title: "Midnight")
        midnight.reminderMinuteOfDay = 0
        let beforeMidnight = date("2026-06-09", hour: 0) // 00:00 exactly — today's slot has passed
        let midnightRequest = try #require(HabitNotificationPlanner.reminder(for: midnight, now: beforeMidnight))
        #expect(midnightRequest.fireDate == date("2026-06-10", hour: 0))

        let lastMinute = Habit(title: "23:59")
        lastMinute.reminderMinuteOfDay = 1439
        let now = date("2026-06-09", hour: 8)
        let lastMinuteRequest = try #require(HabitNotificationPlanner.reminder(for: lastMinute, now: now))
        #expect(lastMinuteRequest.fireDate == date("2026-06-09", hour: 23, minute: 59))
    }

    /// The plan a reconcile actually installs contains no request for the corrupt habit — the level
    /// the bug was observed at, rather than the planner call in isolation.
    @Test func planBuildOmitsHabitsWithAnOutOfRangeReminderMinute() {
        let now = date("2026-06-09", hour: 8)

        let validHabit = Habit(title: "Meditate")
        validHabit.reminderMinuteOfDay = 6 * 60

        let corruptHabit = Habit(title: "Imported junk")
        corruptHabit.reminderMinuteOfDay = 1440

        let plan = NotificationPlan.build(
            tasks: [],
            habits: [validHabit, corruptHabit],
            now: now,
            dueReminderHour: 9,
            dueReminderMinute: 0
        )

        #expect(plan.habitReminders.map(\.identifier) == [NotificationIdentifiers.habitReminder(habitID: validHabit.id)])
        #expect(plan.habitReminders.contains { $0.identifier == NotificationIdentifiers.habitReminder(habitID: corruptHabit.id) } == false)
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

        let remindingHabit = Habit(title: "Meditate")
        remindingHabit.reminderMinuteOfDay = 6 * 60

        let silentHabit = Habit(title: "No reminder set")

        let plan = NotificationPlan.build(
            tasks: [scheduledTask, dueTask, doneTask],
            habits: [remindingHabit, silentHabit],
            now: now,
            dueReminderHour: 9,
            dueReminderMinute: 0
        )

        #expect(Set(plan.taskStarts.map(\.identifier)) == Set([NotificationIdentifiers.taskStart(taskID: scheduledTask.id)]))
        #expect(Set(plan.taskDues.map(\.identifier)) == Set([NotificationIdentifiers.taskDue(taskID: dueTask.id)]))
        #expect(Set(plan.habitReminders.map(\.identifier)) == Set([NotificationIdentifiers.habitReminder(habitID: remindingHabit.id)]))
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

    // MARK: - HabitNotificationReconcileSupport.reconcileInput

    @Test func reconcileInputIsNilWhenEitherFetchFailed() {
        #expect(HabitNotificationReconcileSupport.reconcileInput(tasks: nil, habits: []) == nil)
        #expect(HabitNotificationReconcileSupport.reconcileInput(tasks: [], habits: nil) == nil)
        #expect(HabitNotificationReconcileSupport.reconcileInput(tasks: nil, habits: nil) == nil)
    }

    @Test func reconcileInputPassesThroughAGenuinelyEmptyStore() {
        let input = HabitNotificationReconcileSupport.reconcileInput(tasks: [], habits: [])

        #expect(input != nil)
        #expect(input?.tasks.isEmpty == true)
        #expect(input?.habits.isEmpty == true)
    }

    @Test func reconcileInputPassesThroughFetchedEntities() {
        let task = AppTask(title: "Standup")
        let habit = Habit(title: "Meditate")

        let input = HabitNotificationReconcileSupport.reconcileInput(tasks: [task], habits: [habit])

        #expect(input?.tasks.map(\.id) == [task.id])
        #expect(input?.habits.map(\.id) == [habit.id])
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
