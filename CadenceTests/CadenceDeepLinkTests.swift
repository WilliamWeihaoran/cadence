import Foundation
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
}
