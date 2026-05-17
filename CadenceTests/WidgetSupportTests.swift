import Foundation
import SwiftData
import Testing
@testable import Cadence

struct WidgetSupportTests {

    @Test func widgetRefreshCenterSuppressesRecentlyCompletedTasksTemporarily() {
        let suiteName = "cadence.widget.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let taskID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)

        CadenceWidgetRefreshCenter.markTaskCompleted(taskID, now: now, userDefaults: defaults)

        #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(now: now, userDefaults: defaults).contains(taskID))
        #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(now: now.addingTimeInterval(120), userDefaults: defaults).isEmpty)
    }

    @Test func legacyStoreCandidateDirectoriesCoverSandboxedAndUnsandboxedLocations() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let directories = CadenceStoreSupport.legacyStoreCandidateDirectories(homeDirectoryURL: home)

        #expect(directories.count == 2)
        #expect(directories[0].path == "/Users/tester/Library/Containers/com.haoranwei.Cadence/Data/Library/Application Support")
        #expect(directories[1].path == "/Users/tester/Library/Application Support")
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
}
