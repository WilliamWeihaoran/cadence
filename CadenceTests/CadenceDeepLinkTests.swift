import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct CadenceDeepLinkTests {
    @Test func deepLinkParsesTodayAndTaskURLs() throws {
        let taskID = UUID()
        let todayURL = try #require(URL(string: "cadence://today"))
        let taskURL = try #require(URL(string: "CADENCE://task/\(taskID.uuidString)"))

        let todayLink = try #require(CadenceDeepLink(url: todayURL))
        let taskLink = try #require(CadenceDeepLink(url: taskURL))

        #expect(todayLink == .today)
        #expect(taskLink == .task(taskID))
    }

    @Test func deepLinkRejectsWrongSchemeUnknownRoutesAndBadTaskIDs() throws {
        #expect(CadenceDeepLink(url: try #require(URL(string: "https://today"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence://unknown"))) == nil)
        #expect(CadenceDeepLink(url: try #require(URL(string: "cadence://task/not-a-uuid"))) == nil)
    }

    @Test func deepLinkBuildsCanonicalURLs() {
        let taskID = UUID(uuidString: "B8C8927A-6AB3-4B25-8F8A-EA4E849C770B")!

        #expect(CadenceDeepLink.today.url.absoluteString == "cadence://today")
        #expect(CadenceDeepLink.task(taskID).url.absoluteString == "cadence://task/\(taskID.uuidString)")
    }

    @Test func managerTracksPendingTaskAndClearsOnlyMatchingTask() throws {
        let manager = CadenceDeepLinkManager.shared
        let taskID = UUID()
        let otherTaskID = UUID()

        manager.route = nil
        manager.pendingTaskID = nil

        manager.handle(try #require(URL(string: "cadence://task/\(taskID.uuidString)")))
        #expect(manager.route?.deepLink == .task(taskID))
        #expect(manager.pendingTaskID == taskID)

        manager.clearPendingTask(otherTaskID)
        #expect(manager.pendingTaskID == taskID)

        manager.clearPendingTask(taskID)
        #expect(manager.pendingTaskID == nil)

        manager.handle(try #require(URL(string: "cadence://today")))
        #expect(manager.route?.deepLink == .today)
        #expect(manager.pendingTaskID == nil)
    }

    // MARK: - T-368: a task link is resolved against the store, not applied blind

    /// Builds a context and returns it with today's key, so every test below asks the same
    /// question of the same day.
    private func makeStore() throws -> (ModelContext, String) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (ModelContext(container), DateFormatters.todayKey())
    }

    private func resetManager() -> CadenceDeepLinkManager {
        let manager = CadenceDeepLinkManager.shared
        manager.route = nil
        manager.pendingTaskID = nil
        return manager
    }

    /// The link that motivated T-368: an id for a row that is not there any more. It used to arm
    /// `pendingTaskID` and leave it armed forever, so the next screen that happened to draw that
    /// row opened a task the user had not asked for.
    @Test func taskDeepLinkForMissingTaskDisarmsPendingIDAndKeepsToday() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()
        let missingID = UUID()

        manager.handle(try #require(URL(string: "cadence://task/\(missingID.uuidString)")))
        #expect(manager.pendingTaskID == missingID)

        let destination = manager.resolvedDestination(
            for: .task(missingID),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .today)
        #expect(manager.pendingTaskID == nil)

        let resolution = CadenceDeepLinkResolutionSupport.resolveTaskLink(
            id: missingID,
            task: nil,
            todayKey: todayKey
        )
        #expect(resolution.outcome == .missing)
        #expect(resolution.destination == .today)
        #expect(resolution.pendingTaskID == nil)
    }

    /// A widget link for work that was finished elsewhere. Today drops done tasks, so the row that
    /// would disarm the id never renders: the link routes to All Tasks and disarms here instead.
    @Test func completedTaskDeepLinkRoutesToAllTasksAndDoesNotStayArmed() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let task = AppTask(title: "Finished this morning")
        task.scheduledDate = todayKey
        task.status = .done
        task.completedAt = Date()
        modelContext.insert(task)
        try modelContext.save()

        manager.handle(try #require(URL(string: "cadence://task/\(task.id.uuidString)")))
        #expect(manager.pendingTaskID == task.id)

        let destination = manager.resolvedDestination(
            for: .task(task.id),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .allTasks)
        #expect(manager.pendingTaskID == nil)
        #expect(CadenceDeepLinkResolutionSupport.todayShows(task, todayKey: todayKey) == false)
    }

    /// Cancelled work takes the same route as done work, and a task dated for another day takes it
    /// too — the gate is Today's whole scope predicate, not an `isDone` check.
    @Test func cancelledAndOffDayTaskDeepLinksAlsoRouteToAllTasksDisarmed() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let cancelled = AppTask(title: "Dropped it")
        cancelled.scheduledDate = todayKey
        cancelled.status = .cancelled
        let laterTask = AppTask(title: "Next week")
        laterTask.scheduledDate = "9999-01-01"
        modelContext.insert(cancelled)
        modelContext.insert(laterTask)
        try modelContext.save()

        for task in [cancelled, laterTask] {
            manager.pendingTaskID = task.id
            let destination = manager.resolvedDestination(
                for: .task(task.id),
                modelContext: modelContext,
                todayKey: todayKey
            )
            #expect(destination == .allTasks)
            #expect(manager.pendingTaskID == nil)
        }

        let resolution = CadenceDeepLinkResolutionSupport.resolveTaskLink(
            id: laterTask.id,
            task: laterTask,
            todayKey: todayKey
        )
        #expect(resolution.outcome == .outsideToday)
        #expect(resolution.pendingTaskID == nil)
    }

    /// The case that must keep working: a live task Today lists. Resolution routes to Today, the
    /// id stays armed for the row, and the row's `clearPendingTask` still disarms it.
    @Test func liveTodayTaskDeepLinkStaysArmedForItsRowAndTheRowStillClearsIt() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        let task = AppTask(title: "Due today")
        task.dueDate = todayKey
        modelContext.insert(task)
        try modelContext.save()

        manager.handle(try #require(URL(string: "cadence://task/\(task.id.uuidString)")))

        let destination = manager.resolvedDestination(
            for: .task(task.id),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .today)
        #expect(manager.pendingTaskID == task.id)
        #expect(CadenceDeepLinkResolutionSupport.todayShows(task, todayKey: todayKey))

        // The row-level clear, unchanged and still the thing that ends a successful link.
        manager.clearPendingTask(task.id)
        #expect(manager.pendingTaskID == nil)
    }

    /// Resolution never disarms an id it does not own. A second link landing between `handle(_:)`
    /// and the root's resolve pass owns `pendingTaskID`; clearing it there would be this same bug
    /// pointed the other way.
    @Test func resolvingAStaleTaskLinkLeavesANewerPendingTaskAlone() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()
        let newerID = UUID()

        manager.pendingTaskID = newerID
        let destination = manager.resolvedDestination(
            for: .task(UUID()),
            modelContext: modelContext,
            todayKey: todayKey
        )

        #expect(destination == .today)
        #expect(manager.pendingTaskID == newerID)
        manager.pendingTaskID = nil
    }

    /// Singleton routes are untouched by resolution and never read the store.
    @Test func nonTaskDeepLinksResolveToTheirOwnDestinations() throws {
        let (modelContext, todayKey) = try makeStore()
        let manager = resetManager()

        for (link, expected) in [
            (CadenceDeepLink.today, CadenceFeatureDestination.today),
            (.habits, .habits),
            (.goals, .goals),
            (.calendar, .calendar)
        ] {
            #expect(
                manager.resolvedDestination(for: link, modelContext: modelContext, todayKey: todayKey) == expected
            )
        }
    }
}
