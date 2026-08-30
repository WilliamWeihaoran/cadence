import Foundation
import Testing
@testable import Cadence

/// **T-306 and T-312: two out-of-process write surfaces, one answer.**
///
/// Cadence's store has three writers. The app is one. The MCP server is a second process, and the
/// widget extension running an App Intent is a third. Both of the others saved and stopped:
/// `CadenceWriteService.saveNotifyAndAudit` posted the refresh marker and recorded the audit
/// entry, and the App Intents forced a widget reload — and neither reconciled OS notifications.
/// So a task an agent completed kept its pending "due today" reminder, and one it just scheduled
/// had none, until some unrelated scene-phase checkpoint happened to sweep.
///
/// **The naive fix is wrong in a specific way.** `NotificationManager.reconcile` reads
/// `notificationsEnabled` out of `UserDefaults.standard`, which is per-process. The widget
/// extension does not share the app's, so reconciling there would read empty defaults, conclude
/// notifications are off, and cancel every reminder the app had scheduled. The writers therefore
/// post an **app-group marker** and the app — the one process that can see the setting —
/// reconciles when it adopts the write. `CadenceStoreSupport.postExternalWrite` is that marker,
/// and it is the seam that already existed: `CadenceModelContainerFactory.notifyExternalWrite`
/// now goes through it rather than spelling the file write out again.
@MainActor
struct CadenceExternalWriteReconcileTests {

    // MARK: - The marker

    @Test func theMarkerSitsBesideTheStoreItDescribes() {
        let storeURL = URL(fileURLWithPath: "/tmp/cadence-fixture/Cadence/default.store")
        let markerURL = CadenceStoreSupport.externalWriteMarkerURL(besideStoreAt: storeURL)

        #expect(markerURL.lastPathComponent == ".cadence-mcp-refresh")
        #expect(markerURL.deletingLastPathComponent() == storeURL.deletingLastPathComponent())
    }

    /// The second post must **truncate and rewrite**, never replace.
    ///
    /// `CadenceMCPRefreshCoordinator` watches this path through a `DispatchSource` holding an open
    /// descriptor. Unlink the file and write a new one and that descriptor points at a dead inode:
    /// the app stops noticing external writes entirely, with nothing to say so. The inode check is
    /// the only assertion that can tell those two implementations apart.
    @Test func postingTwiceRewritesTheMarkerInPlace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let markerURL = CadenceStoreSupport.externalWriteMarkerURL(besideStoreAt: storeURL)

        #expect(!FileManager.default.fileExists(atPath: markerURL.path))

        let first = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(CadenceStoreSupport.postExternalWrite(besideStoreAt: storeURL, now: first))
        let firstInode = try inode(of: markerURL)
        let firstContents = try String(contentsOf: markerURL, encoding: .utf8)
        #expect(firstContents == iso(first))

        let second = Date(timeIntervalSince1970: 1_700_000_600)
        #expect(CadenceStoreSupport.postExternalWrite(besideStoreAt: storeURL, now: second))

        let secondContents = try String(contentsOf: markerURL, encoding: .utf8)
        let secondInode = try inode(of: markerURL)
        #expect(secondContents == iso(second))
        #expect(
            secondInode == firstInode,
            "the marker was replaced rather than rewritten, so the app's file watcher is now holding a dead descriptor"
        )
    }

    // MARK: - What an App Intent write publishes

    /// All three of `CompleteTaskIntent`, `CaptureTaskIntent` and `ToggleHabitCompletionIntent`
    /// end in this call, so the tail cannot drift between them.
    @Test func aCompletionFromAWidgetPublishesTheOverrideTheReloadAndTheMarker() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let markerURL = CadenceStoreSupport.externalWriteMarkerURL(besideStoreAt: storeURL)
        try withTemporaryDefaults("cadence.tests.external-write") { defaults in
            let taskID = UUID()
            let now = Date(timeIntervalSince1970: 1_700_000_000)

            CadenceWidgetIntentWriteSupport.publish(
                completedTaskID: taskID,
                storeURL: storeURL,
                userDefaults: defaults,
                now: now
            )

            // The optimistic override the tapped row reads back.
            #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(now: now, userDefaults: defaults) == [taskID])
            // The forced reload, which the 15-second throttle would otherwise swallow.
            #expect(CadenceWidgetRefreshCenter.lastReloadDate(userDefaults: defaults) == now)
            // And the marker that gets the app to reconcile the reminder this completion invalidated.
            let posted = try String(contentsOf: markerURL, encoding: .utf8)
            #expect(
                posted == iso(now),
                "a widget completion no longer tells the app its store changed (T-312)"
            )
        }
    }

    @Test func aHabitToggleFromAWidgetPublishesTheSameWay() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let markerURL = CadenceStoreSupport.externalWriteMarkerURL(besideStoreAt: storeURL)
        try withTemporaryDefaults("cadence.tests.external-write") { defaults in
            let habitID = UUID()
            let now = Date(timeIntervalSince1970: 1_700_000_000)

            CadenceWidgetIntentWriteSupport.publish(
                habitCompletion: (habitID, true),
                storeURL: storeURL,
                userDefaults: defaults,
                now: now
            )

            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now, userDefaults: defaults) == [habitID: true])
            #expect(CadenceWidgetRefreshCenter.lastReloadDate(userDefaults: defaults) == now)
            let posted = try String(contentsOf: markerURL, encoding: .utf8)
            #expect(posted == iso(now))
        }
    }

    /// A capture has no optimistic override to write — but it is still a write, and the reminder
    /// for a task captured "for today" is exactly the notification that was never scheduled.
    @Test func aCaptureWithNoOptimisticOverrideStillPostsTheMarker() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let markerURL = CadenceStoreSupport.externalWriteMarkerURL(besideStoreAt: storeURL)
        try withTemporaryDefaults("cadence.tests.external-write") { defaults in
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            CadenceWidgetIntentWriteSupport.publish(storeURL: storeURL, userDefaults: defaults, now: now)

            #expect(CadenceWidgetRefreshCenter.suppressedTaskIDs(now: now, userDefaults: defaults).isEmpty)
            #expect(CadenceWidgetRefreshCenter.lastReloadDate(userDefaults: defaults) == now)
            let posted = try String(contentsOf: markerURL, encoding: .utf8)
            #expect(posted == iso(now))
        }
    }

    // MARK: - The wiring, where the value is out of reach

    /// Each intent's `perform()` opens the real app-group container, so the three call sites
    /// cannot be driven from here — but a call site that stops publishing is the whole bug, and
    /// exact counts are what catch one of three reverting (`CadenceSharedBoardChromeTests`'
    /// lesson).
    @Test func everyWritingAppIntentEndsInTheSharedPublish() throws {
        let source = strippingComments(try sourceFile("Cadence/Services/CadenceWidgetIntents.swift"))
        let raw = try sourceFile("Cadence/Services/CadenceWidgetIntents.swift")

        #expect(source != raw, "the comment stripper did nothing")
        #expect(source.count == raw.count, "the comment stripper changed the string's length")

        #expect(
            source.components(separatedBy: "CadenceWidgetIntentWriteSupport.publish(").count - 1 == 3,
            "one of the three writing App Intents stopped publishing its write"
        )
        // And none of them went back to spelling the tail out for themselves.
        #expect(
            source.components(separatedBy: "CadenceWidgetRefreshCenter.reloadAllWidgets(").count - 1 == 1,
            "an App Intent reloads widgets outside the shared publish again"
        )
        // The trap: the extension must not reconcile, because it cannot see the app's setting.
        #expect(!source.contains("NotificationManager"))
        #expect(!source.contains("scheduleReconcile"))
    }

    /// The MCP server's marker post and the widget extension's are the same implementation, not
    /// two file writes that agree today.
    @Test func theMCPWritePathPostsThroughTheSharedMarker() throws {
        let factory = strippingComments(
            try sourceFile("Cadence/Services/MCPReadOnly/CadenceModelContainerFactory.swift")
        )
        let body = try cadenceFunctionBody("static func notifyExternalWrite()", in: factory)

        #expect(body.contains("CadenceStoreSupport.postExternalWrite"))
        #expect(!body.contains("createFile"), "the marker write was spelled out here a second time")
        #expect(!body.contains("FileHandle"), "the marker write was spelled out here a second time")

        // The write service still reaches it, which is what makes an MCP save announce itself.
        let writeService = strippingComments(
            try sourceFile("Cadence/Services/MCPReadOnly/CadenceWriteService.swift")
        )
        #expect(writeService.contains("CadenceModelContainerFactory.notifyExternalWrite()"))
    }

    /// **The app side of the contract.** `refreshAppData()` is a private method on a SwiftUI view,
    /// so the reconcile it now runs has no symbol a test can call; scoping the scan to that one
    /// function body is what keeps it from passing on an unrelated line elsewhere in a 300-line
    /// root view.
    @Test func macOSReconcilesNotificationsWhenItAdoptsAnExternalWrite() throws {
        let source = strippingComments(try sourceFile("Cadence/macOS/macOSRootView.swift"))
        let body = try cadenceFunctionBody("private func refreshAppData()", in: source)

        #expect(
            body.contains("HabitNotificationReconcileSupport.scheduleReconcile"),
            "adopting an out-of-process write no longer reconciles notifications (T-306)"
        )
        // After the swap, not before: a reconcile against the outgoing context diffs against rows
        // the other process never reached.
        let swap = try #require(body.range(of: "CadenceModelContextRefresh.replacement"))
        let reconcile = try #require(body.range(of: "HabitNotificationReconcileSupport.scheduleReconcile"))
        #expect(swap.lowerBound < reconcile.lowerBound)
    }

    /// iOS has no marker watcher, so becoming active is its only checkpoint for a write the widget
    /// extension made while the app was away. `Cadence/iOS/` is inside `#if os(iOS)` and invisible
    /// to this macOS-built target, which is what leaves a scan as the only tool here.
    @Test func iOSReconcilesNotificationsOnEveryScenePhaseChange() throws {
        let raw = try sourceFile("Cadence/iOS/iOSRootView.swift")
        let source = strippingComments(raw)

        #expect(source != raw, "the comment stripper did nothing")
        #expect(source.count == raw.count, "the comment stripper changed the string's length")

        let body = try cadenceFunctionBody(".onChange(of: scenePhase)", in: source)

        #expect(body.contains("NotificationManager.shared.reconcile"))
        // The reconcile must sit outside the leaving-active branch. It used to be the only thing
        // in it, which is why a widget write while the app was backgrounded was never swept.
        let guardRange = try #require(body.range(of: "if phase != .active {"))
        let branch = try cadenceFunctionBody("if phase != .active", in: String(body[guardRange.lowerBound...]))
        #expect(
            !branch.contains("NotificationManager.shared.reconcile"),
            "the reconcile is back inside the leaving-active branch, so an App Intent write is swept only on the way out (T-312)"
        )
        #expect(branch.contains("CadenceWidgetRefreshCenter.reloadAllWidgets"))
    }

    // MARK: - The scan itself

    /// The absence assertions above are worth nothing if the reads are failing. A scan that reads
    /// no files passes every one of them.
    @Test func theSourceScanReachesTheFilesItClaimsTo() throws {
        for path in [
            "Cadence/Services/CadenceWidgetIntents.swift",
            "Cadence/Services/CadenceStoreSupport.swift",
            "Cadence/Services/MCPReadOnly/CadenceModelContainerFactory.swift",
            "Cadence/macOS/macOSRootView.swift",
            "Cadence/iOS/iOSRootView.swift",
        ] {
            let characters = try sourceFile(path).count
            #expect(characters > 500, "\(path) read as \(characters) characters")
        }

        // `cadenceFunctionBody` throws on a miss rather than returning "", and this proves it here.
        #expect(throws: SourceBodyScanError.self) {
            try cadenceFunctionBody(
                "private func aFunctionThatDoesNotExist()",
                in: try sourceFile("Cadence/macOS/macOSRootView.swift")
            )
        }
    }

    // MARK: - Fixtures

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cadence-external-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func inode(of url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try CadenceSourceScan.sourceFile(relativePath)
    }

    private func strippingComments(_ source: String) -> String {
        CadenceSourceScan.strippingComments(source)
    }
}
