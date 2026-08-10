import Foundation
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

    @Test func startNotificationFiresAtCorrectTimeForFutureScheduledTask() {
        let task = AppTask(title: "Standup")
        task.scheduledDate = "2026-06-10"
        task.scheduledStartMin = 540 // 9:00 AM
        let now = date("2026-06-09")

        let request = try? #require(TaskNotificationPlanner.startNotification(for: task, now: now))
        #expect(request?.identifier == NotificationIdentifiers.taskStart(taskID: task.id))
        #expect(request?.kind == .taskStart)
        #expect(request?.title == "Standup")
        #expect(request?.body == "Starting now")
        #expect(request?.fireDate == date("2026-06-10", hour: 9))
    }

    @Test func startNotificationHandlesEndOfDayMinutesWithoutRollingToWrongDay() {
        let task = AppTask(title: "Late night wrap-up")
        task.scheduledDate = "2026-06-10"
        task.scheduledStartMin = 1435 // 11:55 PM
        let now = date("2026-06-10", hour: 9)

        let request = try? #require(TaskNotificationPlanner.startNotification(for: task, now: now))
        #expect(request?.fireDate == date("2026-06-10", hour: 23, minute: 55))
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

    @Test func dueNotificationFiresAtFixedTimeOfDay() {
        let task = AppTask(title: "Submit report")
        task.dueDate = "2026-06-10"
        let now = date("2026-06-09")

        let request = try? #require(TaskNotificationPlanner.dueNotification(for: task, now: now, reminderHour: 9, reminderMinute: 0))
        #expect(request?.identifier == NotificationIdentifiers.taskDue(taskID: task.id))
        #expect(request?.kind == .taskDue)
        #expect(request?.title == "Submit report")
        #expect(request?.body == "Due today")
        #expect(request?.fireDate == date("2026-06-10", hour: 9))
    }

    // MARK: - HabitNotificationPlanner.reminder

    @Test func habitReminderNilWhenNoReminderTimeSet() {
        let habit = Habit(title: "Read")
        habit.reminderMinuteOfDay = nil
        let now = date("2026-06-09", hour: 8)

        #expect(HabitNotificationPlanner.reminder(for: habit, now: now) == nil)
    }

    @Test func habitReminderResolvesLaterTodayWhenStillUpcoming() {
        let habit = Habit(title: "Stretch")
        habit.reminderMinuteOfDay = 20 * 60 // 8:00 PM
        let now = date("2026-06-09", hour: 8) // 8:00 AM — reminder is later today

        let request = try? #require(HabitNotificationPlanner.reminder(for: habit, now: now))
        #expect(request?.identifier == NotificationIdentifiers.habitReminder(habitID: habit.id))
        #expect(request?.kind == .habitReminder)
        #expect(request?.fireDate == date("2026-06-09", hour: 20))
    }

    @Test func habitReminderResolvesTomorrowWhenTimeAlreadyPassedToday() {
        let habit = Habit(title: "Journal")
        habit.reminderMinuteOfDay = 7 * 60 // 7:00 AM
        let now = date("2026-06-09", hour: 8) // 8:00 AM — 7 AM already passed today

        let request = try? #require(HabitNotificationPlanner.reminder(for: habit, now: now))
        #expect(request?.fireDate == date("2026-06-10", hour: 7))
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
