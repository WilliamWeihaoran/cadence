import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct WidgetSupportTests {

    @Test func legacyStoreCandidateDirectoriesCoverSandboxedAndUnsandboxedLocations() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let directories = CadenceStoreSupport.legacyStoreCandidateDirectories(homeDirectoryURL: home)

        #expect(directories.map(\.path) == [
            "/Users/tester/Library/Containers/com.haoranwei.Cadence/Data/Library/Application Support/Cadence",
            "/Users/tester/Library/Application Support/Cadence",
        ])
    }

    @Test func widgetRefreshCenterSuppressesRecentlyCompletedTasksTemporarily() throws {
        try withTemporaryDefaults("cadence.widget.tests") { defaults in
            let taskID = UUID()
            let now = Date(timeIntervalSince1970: 1_000)

            CadenceWidgetRefreshCenter.markTaskCompleted(taskID, now: now, userDefaults: defaults)

            #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(now: now, userDefaults: defaults).contains(taskID))
            #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(now: now.addingTimeInterval(120), userDefaults: defaults).isEmpty)
        }
    }

    @Test func widgetRefreshCenterStoresRecentHabitCompletionStateTemporarily() throws {
        try withTemporaryDefaults("cadence.widget.tests") { defaults in
            let habitID = UUID()
            let now = Date(timeIntervalSince1970: 1_000)

            CadenceWidgetRefreshCenter.markHabitCompletion(
                habitID,
                isDoneToday: true,
                now: now,
                userDefaults: defaults
            )

            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now, userDefaults: defaults)[habitID] == true)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now.addingTimeInterval(120), userDefaults: defaults).isEmpty)
        }
    }

    @Test func migrateLegacyStoreCopiesManagedItemsIntoAppGroupDirectory() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("cadence-widget-tests-\(UUID().uuidString)", isDirectory: true)
        let legacyDirectory = tempRoot.appendingPathComponent("legacy", isDirectory: true)
        let appGroupDirectory = tempRoot.appendingPathComponent("group", isDirectory: true)

        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: legacyDirectory.appendingPathComponent("default.store"))
        try Data("wal".utf8).write(to: legacyDirectory.appendingPathComponent("default.store-wal"))
        try fileManager.createDirectory(at: legacyDirectory.appendingPathComponent(".default_SUPPORT"), withIntermediateDirectories: true)

        var backedUpDirectory: URL?
        let migratedFrom = try CadenceStoreSupport.migrateLegacyStoreIfNeeded(
            appGroupDirectoryURL: appGroupDirectory,
            candidateLegacyDirectories: [legacyDirectory],
            backupHandler: { directory in
                backedUpDirectory = directory
            }
        )

        #expect(migratedFrom == legacyDirectory)
        #expect(backedUpDirectory == legacyDirectory)
        #expect(fileManager.fileExists(atPath: appGroupDirectory.appendingPathComponent("default.store").path))
        #expect(fileManager.fileExists(atPath: appGroupDirectory.appendingPathComponent("default.store-wal").path))
        #expect(fileManager.fileExists(atPath: appGroupDirectory.appendingPathComponent(".default_SUPPORT").path))
    }

    @Test func widgetRefreshCenterClearsStoredStateForAccountDeletion() throws {
        try withTemporaryDefaults("cadence.widget.tests") { defaults in
            let taskID = UUID()
            let habitID = UUID()
            let now = Date(timeIntervalSince1970: 1_000)

            CadenceWidgetRefreshCenter.reloadAllWidgets(force: true, now: now, userDefaults: defaults)
            CadenceWidgetRefreshCenter.markTaskCompleted(taskID, now: now, userDefaults: defaults)
            CadenceWidgetRefreshCenter.markHabitCompletion(
                habitID,
                isDoneToday: true,
                now: now,
                userDefaults: defaults
            )
            CadenceWidgetRefreshCenter.clearStoredState(userDefaults: defaults)

            #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(now: now, userDefaults: defaults).isEmpty)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now, userDefaults: defaults).isEmpty)
        }
    }

    @Test func todayWidgetSupportSortsTasksLikeTodayView() {
        let todayKey = "2026-05-11"

        let scheduledHigh = AppTask(title: "scheduled-high")
        scheduledHigh.scheduledDate = todayKey
        scheduledHigh.priority = .high
        scheduledHigh.order = 5

        let overdueLow = AppTask(title: "overdue-low")
        overdueLow.dueDate = "2026-05-09"
        overdueLow.priority = .low
        overdueLow.order = 50

        let dueTodayMedium = AppTask(title: "due-today-medium")
        dueTodayMedium.dueDate = todayKey
        dueTodayMedium.priority = .medium
        dueTodayMedium.order = 30

        let dueTodayHigh = AppTask(title: "due-today-high")
        dueTodayHigh.dueDate = todayKey
        dueTodayHigh.priority = .high
        dueTodayHigh.order = 40

        let tomorrow = AppTask(title: "tomorrow")
        tomorrow.dueDate = "2026-05-12"
        tomorrow.priority = .high
        tomorrow.order = 1

        let sorted = CadenceTodayWidgetSupport.todayTasks(
            from: [scheduledHigh, overdueLow, dueTodayMedium, dueTodayHigh, tomorrow],
            todayKey: todayKey
        )

        #expect(sorted.map(\.title) == [
            "overdue-low",
            "due-today-high",
            "due-today-medium",
            "scheduled-high",
        ])
    }

    @Test func todayWidgetSnapshotCapsTasksAndComputesCounts() {
        let todayKey = "2026-05-11"

        func task(title: String, dueDate: String = "", scheduledDate: String = "", priority: TaskPriority = .none, order: Int) -> AppTask {
            let task = AppTask(title: title)
            task.dueDate = dueDate
            task.scheduledDate = scheduledDate
            task.priority = priority
            task.order = order
            return task
        }

        let snapshot = CadenceTodayWidgetSupport.snapshot(
            from: [
                task(title: "overdue", dueDate: "2026-05-10", priority: .medium, order: 10),
                task(title: "due", dueDate: todayKey, priority: .high, order: 20),
                task(title: "scheduled-1", scheduledDate: todayKey, priority: .low, order: 30),
                task(title: "scheduled-2", scheduledDate: todayKey, priority: .none, order: 40),
            ],
            todayKey: todayKey,
            limit: 3
        )

        #expect(snapshot.totalCount == 4)
        #expect(snapshot.overdueCount == 1)
        #expect(snapshot.dueTodayCount == 1)
        #expect(snapshot.scheduledTodayCount == 2)
        #expect(snapshot.tasks.map(\.title) == ["overdue", "due", "scheduled-1"])
        #expect(snapshot.state == .ready)
    }

    @Test func todayWidgetSnapshotHidesSuppressedTasksAndFallsBackToEmptyState() {
        let todayKey = "2026-05-11"
        let task = AppTask(title: "complete me")
        task.dueDate = todayKey

        let snapshot = CadenceTodayWidgetSupport.snapshot(
            from: [task],
            todayKey: todayKey,
            limit: 3,
            suppressedTaskIDs: [task.id]
        )

        #expect(snapshot.totalCount == 0)
        #expect(snapshot.tasks.isEmpty)
        #expect(snapshot.state == .empty)
    }

    @Test func unavailableSnapshotUsesUnavailableStateAndRetryPolicy() {
        let referenceDate = Date(timeIntervalSince1970: 2_000)
        let snapshot = CadenceTodayWidgetSupport.unavailableSnapshot(todayKey: "2026-05-11", message: "Needs setup")
        let reloadDate = CadenceTodayWidgetSupport.recommendedReloadDate(for: snapshot, referenceDate: referenceDate)

        #expect(snapshot.state == .unavailable)
        #expect(snapshot.statusMessage == "Needs setup")
        #expect(reloadDate == referenceDate.addingTimeInterval(5 * 60))
    }

    @Test func completeTaskIntentMarksActiveTasksDoneAndLeavesOthersUntouched() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let active = AppTask(title: "active")
        let cancelled = AppTask(title: "cancelled")
        cancelled.status = .cancelled
        let done = AppTask(title: "done")
        done.status = .done
        done.completedAt = Date(timeIntervalSince1970: 100)

        modelContext.insert(active)
        modelContext.insert(cancelled)
        modelContext.insert(done)
        try modelContext.save()

        let changed = try CompleteTaskIntent.completeTask(taskID: active.id.uuidString, in: modelContext)
        let changedAgain = try CompleteTaskIntent.completeTask(taskID: active.id.uuidString, in: modelContext)
        let cancelledChanged = try CompleteTaskIntent.completeTask(taskID: cancelled.id.uuidString, in: modelContext)
        let missingChanged = try CompleteTaskIntent.completeTask(taskID: UUID().uuidString, in: modelContext)

        #expect(changed)
        #expect(changedAgain == false)
        #expect(cancelledChanged == false)
        #expect(missingChanged == false)
        #expect(active.isDone)
        #expect(active.completedAt != nil)
        #expect(done.completedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func completeTaskIntentSpawnsNextOccurrenceForRecurringTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        // Long-stale do date so the successor's expected date is "tomorrow" under any wall clock.
        let recurring = AppTask(title: "Daily standup")
        recurring.recurrenceRule = .daily
        recurring.scheduledDate = "2020-01-01"
        modelContext.insert(recurring)
        try modelContext.save()

        let changed = try CompleteTaskIntent.completeTask(taskID: recurring.id.uuidString, in: modelContext)

        #expect(changed)
        #expect(recurring.isDone)

        guard let spawnedID = recurring.recurrenceSpawnedTaskID else {
            Issue.record("Completing a recurring task from the widget/App Intent must still advance the series")
            return
        }
        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        guard let next = tasks.first(where: { $0.id == spawnedID }) else {
            Issue.record("Expected the spawned next occurrence to be persisted")
            return
        }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        #expect(next.scheduledDate == DateFormatters.dateKey(from: tomorrow))
        #expect(next.recurrenceRule == .daily)
        #expect(next.recurrenceSeriesID == recurring.recurrenceSeriesID)
    }

    @Test func captureTaskIntentCreatesInboxAndTodayTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let existing = AppTask(title: "existing")
        existing.order = 4
        modelContext.insert(existing)
        try modelContext.save()

        try CaptureTaskIntent.captureTask(title: "inbox", planForToday: false, in: modelContext)
        try CaptureTaskIntent.captureTask(title: "today", planForToday: true, in: modelContext)

        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        let inbox = tasks.first { $0.title == "inbox" }
        let today = tasks.first { $0.title == "today" }

        #expect(inbox?.scheduledDate == "")
        #expect(inbox?.estimatedMinutes == 30)
        #expect(inbox?.order == 5)
        #expect(today?.scheduledDate == DateFormatters.todayKey())
        #expect(today?.estimatedMinutes == 30)
        #expect(today?.order == 6)
    }

    /// Drives the same call `perform()` makes, and then the override write `perform()` makes with
    /// its result — the two halves have to agree or a widget tap shows the old state until the
    /// next full timeline reload.
    @Test func toggleHabitCompletionIntentLogsAndRemovesTodayCheckIn() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        try withTemporaryDefaults("cadence.widget.tests") { defaults in
            let now = Date(timeIntervalSince1970: 1_000)

            let habit = Habit(title: "Read")
            modelContext.insert(habit)
            try modelContext.save()

            func toggle() throws -> ToggleHabitCompletionIntent.HabitToggleResult {
                let result = try ToggleHabitCompletionIntent.toggleHabitCompletionResult(
                    habitID: habit.id.uuidString,
                    on: "2026-05-11",
                    in: modelContext
                )
                if result.changed, let habitID = result.habitID {
                    CadenceWidgetRefreshCenter.markHabitCompletion(
                        habitID,
                        isDoneToday: result.isDoneToday,
                        now: now,
                        userDefaults: defaults
                    )
                }
                return result
            }

            let firstToggle = try toggle()
            #expect(firstToggle.changed)
            #expect(firstToggle.habitID == habit.id)
            #expect(firstToggle.isDoneToday)
            #expect(habit.isDone(on: "2026-05-11"))
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now, userDefaults: defaults)[habit.id] == true)

            let secondToggle = try toggle()
            #expect(secondToggle.changed)
            #expect(secondToggle.habitID == habit.id)
            #expect(secondToggle.isDoneToday == false)
            #expect(habit.isDone(on: "2026-05-11") == false)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now, userDefaults: defaults)[habit.id] == false)

            // An unknown habit id must report "nothing changed" so `perform()` writes no override.
            let missing = try ToggleHabitCompletionIntent.toggleHabitCompletionResult(
                habitID: UUID().uuidString,
                on: "2026-05-11",
                in: modelContext
            )
            #expect(missing.changed == false)
            #expect(missing.habitID == nil)
        }
    }

    @Test func habitWidgetSnapshotPrefersOpenHabitsAndComputesCounts() {
        let today = DateFormatters.date(from: "2026-05-11")!

        let open = Habit(title: "Walk")
        open.order = 3

        let done = Habit(title: "Journal")
        done.order = 1
        done.completions = [HabitCompletion(date: "2026-05-11", habit: done)]

        let later = Habit(title: "Read")
        later.order = 2

        let snapshot = CadenceHabitWidgetSupport.snapshot(
            from: [done, later, open],
            today: today,
            limit: 3
        )

        #expect(snapshot.totalDueCount == 3)
        #expect(snapshot.doneCount == 1)
        #expect(snapshot.habits.map(\.title) == ["Read", "Walk", "Journal"])
    }

    /// The widget renders from `CadenceHabitWidgetHabit` and never sees the `Habit`, so if the unit
    /// does not cross that boundary the view has nothing to print but a hardcoded "d" — which is
    /// what made a `.timesPerWeek` habit kept for eight weeks read "8d" on the home screen.
    @Test func habitWidgetSnapshotCarriesTheStreakUnitFromTheFrequency() {
        let today = DateFormatters.date(from: "2026-05-11")!

        let weekly = Habit(title: "Long run")
        weekly.frequencyType = .timesPerWeek
        weekly.targetCount = 3
        weekly.order = 1

        let daily = Habit(title: "Read")
        daily.frequencyType = .daily
        daily.order = 2

        let snapshot = CadenceHabitWidgetSupport.snapshot(
            from: [weekly, daily],
            today: today,
            limit: 2,
            recentCompletionStates: [:]
        )

        let units = Dictionary(
            uniqueKeysWithValues: snapshot.habits.map { ($0.title, $0.streakUnit) }
        )
        #expect(units["Long run"] == .weeks)
        #expect(units["Read"] == .days)
        #expect(HabitStreakUnit.weeks.shortLabel(8) == "8w")
    }

    @Test func habitWidgetSnapshotPrefersRecentCompletionOverride() {
        let today = DateFormatters.date(from: "2026-05-11")!
        let habit = Habit(title: "Read")
        habit.order = 1

        let snapshot = CadenceHabitWidgetSupport.snapshot(
            from: [habit],
            today: today,
            limit: 1,
            recentCompletionStates: [habit.id: true]
        )

        #expect(snapshot.doneCount == 1)
        #expect(snapshot.habits.first?.isDoneToday == true)
    }

    @Test func milestoneWidgetPrioritizesOverdueGoalsFirst() {
        let overdueGoal = Goal(title: "Overdue launch")
        let overdueTask = AppTask(title: "Fix blocking task")
        overdueTask.dueDate = "2026-05-10"
        overdueGoal.tasks = [overdueTask]

        let routineGoal = Goal(title: "Routine upkeep")
        let routineTask = AppTask(title: "Follow up")
        routineTask.dueDate = "2026-05-14"
        routineGoal.tasks = [routineTask]

        let goals = CadenceMilestoneWidgetSupport.prioritizedGoals(
            from: [routineGoal, overdueGoal],
            now: DateFormatters.date(from: "2026-05-11")!
        )

        #expect(goals.map(\.title) == ["Overdue launch", "Routine upkeep"])
    }

    @Test func milestoneWidgetCountsEachOverdueTaskOnceAcrossNestedGoals() {
        let now = DateFormatters.date(from: "2026-05-11")!

        let area = Area(name: "Launch")
        let first = AppTask(title: "Fix blocker")
        first.dueDate = "2026-05-08"
        let second = AppTask(title: "Ship changelog")
        second.dueDate = "2026-05-09"
        area.tasks = [first, second]

        // A direction and its one milestone. `contributingTasks` walks sub-goals, so the direction's
        // summary already contains the milestone's tasks — summing both summaries double-counts.
        let direction = Goal(title: "Ship v2")
        let milestone = Goal(title: "Beta cut")
        direction.subGoals = [milestone]
        milestone.parentGoal = direction
        milestone.listLinks = [GoalListLink(goal: milestone, area: area)]

        let snapshot = CadenceMilestoneWidgetSupport.snapshot(
            from: [direction, milestone],
            now: now,
            limit: 4
        )

        #expect(snapshot.totalOverdueTaskCount == 2)
    }

    @Test func calendarWidgetSnapshotSeparatesDueAndScheduledCounts() {
        let today = DateFormatters.date(from: "2026-05-11")!

        let due = AppTask(title: "Due")
        due.dueDate = "2026-05-11"

        let scheduled = AppTask(title: "Scheduled")
        scheduled.scheduledDate = "2026-05-11"

        let future = AppTask(title: "Future")
        future.scheduledDate = "2026-05-12"

        let snapshot = CadenceCalendarWidgetSupport.snapshot(
            from: [due, scheduled, future],
            today: today,
            dayCount: 3
        )

        #expect(snapshot.state == .ready)
        #expect(snapshot.days.first?.dueCount == 1)
        #expect(snapshot.days.first?.scheduledCount == 1)
        #expect(snapshot.days.dropFirst().first?.scheduledCount == 1)
    }
}
