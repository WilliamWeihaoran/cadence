import Foundation
import Testing
import UserNotifications
@testable import Cadence

/// **[[T-3049]] (1): tapping a task reminder opens that task.**
///
/// Nothing here schedules, delivers or taps a notification, and nothing reaches the OS
/// notification centre: building a `UNMutableNotificationContent` touches none, and
/// `UNNotificationResponse` cannot be constructed, so the delegate's unpacking is held by a source
/// scan while every decision it forwards to is driven directly.
@MainActor
struct NotificationTapRoutingTests {
    private let fireDate = Date(timeIntervalSinceReferenceDate: 900_000_000)

    private func request(identifier: String, kind: NotificationKind) -> CadenceNotificationRequest {
        CadenceNotificationRequest(identifier: identifier, kind: kind, title: "Title", body: "Body", fireDate: fireDate)
    }

    private func linkInContent(of request: CadenceNotificationRequest) -> String? {
        NotificationManager.makeContent(for: request).userInfo[NotificationTapRoute.deepLinkUserInfoKey] as? String
    }

    // MARK: - What a reminder carries

    @Test func bothTaskReminderKindsCarryTheirTasksDeepLink() throws {
        let taskID = UUID()
        let requests = [
            request(identifier: NotificationIdentifiers.taskStart(taskID: taskID), kind: .taskStart),
            request(identifier: NotificationIdentifiers.taskDue(taskID: taskID), kind: .taskDue),
        ]
        for request in requests {
            let raw = try #require(linkInContent(of: request), "\(request.identifier) carries no link (T-3049)")
            #expect(raw == CadenceDeepLink.task(taskID).url.absoluteString)
            let url = try #require(URL(string: raw))
            #expect(CadenceDeepLink(url: url) == .task(taskID), "the carried link does not parse back to its task")
        }
    }

    @Test func aHabitReminderCarriesNoLink() {
        let content = NotificationManager.makeContent(
            for: request(identifier: NotificationIdentifiers.habitReminder(habitID: UUID()), kind: .habitReminder)
        )
        #expect(content.userInfo.isEmpty, "a habit reminder carries \(content.userInfo), but there is no task to open")
    }

    @Test func theIdentifierParserRoundTripsBothTaskFormatsAndRefusesEverythingElse() {
        let taskID = UUID()
        #expect(NotificationIdentifiers.taskID(fromIdentifier: NotificationIdentifiers.taskStart(taskID: taskID)) == taskID)
        #expect(NotificationIdentifiers.taskID(fromIdentifier: NotificationIdentifiers.taskDue(taskID: taskID)) == taskID)
        for foreign in [
            NotificationIdentifiers.habitReminder(habitID: taskID),
            "task-due-not-a-uuid",
            "task-due-",
            "someone-elses-\(taskID.uuidString)",
            "",
        ] {
            #expect(NotificationIdentifiers.taskID(fromIdentifier: foreign) == nil, "\(foreign) parsed as a task")
        }
    }

    // MARK: - What a tap opens

    /// The content the OS is handed and the URL a tap derives are the same link, end to end. The
    /// response's identifier is deliberately foreign, so the link can only have come from `userInfo`.
    @Test func aTapOnATaskRemindersContentOpensThatTask() {
        let taskID = UUID()
        let content = NotificationManager.makeContent(
            for: request(identifier: NotificationIdentifiers.taskDue(taskID: taskID), kind: .taskDue)
        )
        let url = NotificationTapRoute.deepLinkURL(
            isDefaultAction: true,
            userInfo: content.userInfo,
            identifier: "foreign-identifier"
        )
        #expect(url == CadenceDeepLink.task(taskID).url, "a tap no longer opens the task its reminder is about (T-3049)")
    }

    @Test func onlyTheTapItselfRoutes() {
        let taskID = UUID()
        let url = NotificationTapRoute.deepLinkURL(
            isDefaultAction: false,
            userInfo: [NotificationTapRoute.deepLinkUserInfoKey: CadenceDeepLink.task(taskID).url.absoluteString],
            identifier: NotificationIdentifiers.taskDue(taskID: taskID)
        )
        #expect(url == nil, "a dismissal or custom action opened the app onto a task")
    }

    /// A reminder an older build registered carries no `userInfo`; its identifier still names the
    /// task, so the tap still opens it.
    @Test func aReminderWithoutUserInfoFallsBackToTheTaskItsIdentifierNames() {
        let taskID = UUID()
        let url = NotificationTapRoute.deepLinkURL(
            isDefaultAction: true,
            userInfo: [:],
            identifier: NotificationIdentifiers.taskStart(taskID: taskID)
        )
        #expect(url == CadenceDeepLink.task(taskID).url)
    }

    @Test func aLinkInUserInfoWinsOverTheIdentifier() {
        let carried = UUID()
        let named = UUID()
        let url = NotificationTapRoute.deepLinkURL(
            isDefaultAction: true,
            userInfo: [NotificationTapRoute.deepLinkUserInfoKey: CadenceDeepLink.task(carried).url.absoluteString],
            identifier: NotificationIdentifiers.taskDue(taskID: named)
        )
        #expect(url == CadenceDeepLink.task(carried).url)
    }

    /// Missing or garbage `userInfo` on a notification that names no task opens nothing — and a
    /// garbage value on one that does falls back to the identifier rather than being trusted.
    @Test func garbageUserInfoNeitherCrashesNorMisroutes() {
        let garbage: [[AnyHashable: Any]] = [
            [:],
            [NotificationTapRoute.deepLinkUserInfoKey: 42],
            [NotificationTapRoute.deepLinkUserInfoKey: ""],
            [NotificationTapRoute.deepLinkUserInfoKey: "not a url at all %%"],
            [NotificationTapRoute.deepLinkUserInfoKey: "cadence://today"],
            [NotificationTapRoute.deepLinkUserInfoKey: "cadence://task/not-a-uuid"],
            [NotificationTapRoute.deepLinkUserInfoKey: "https://example.com/task/\(UUID().uuidString)"],
            ["unrelated": "cadence://task/\(UUID().uuidString)"],
        ]
        #expect(garbage.count == 8)

        let habit = NotificationIdentifiers.habitReminder(habitID: UUID())
        let opened = garbage.compactMap {
            NotificationTapRoute.deepLinkURL(isDefaultAction: true, userInfo: $0, identifier: habit)
        }
        #expect(opened.isEmpty, "garbage userInfo on a non-task reminder opened \(opened)")

        let taskID = UUID()
        let fallbacks = garbage.map {
            NotificationTapRoute.deepLinkURL(
                isDefaultAction: true,
                userInfo: $0,
                identifier: NotificationIdentifiers.taskDue(taskID: taskID)
            )
        }
        #expect(
            fallbacks.allSatisfy { $0 == CadenceDeepLink.task(taskID).url },
            "garbage userInfo was trusted over the identifier: \(fallbacks)"
        )
    }

    // MARK: - The delegate forwards to the existing route

    @Test func theDelegateHandsTheTapToTheSameHandlerAsOpenURL() throws {
        let manager = try CadenceCommitSurfaceScan.scanned("Cadence/Services/NotificationManager.swift")
        let body = try cadenceFunctionBody("didReceive response: UNNotificationResponse", in: manager)

        #expect(
            body.contains("NotificationTapRoute.deepLinkURL("),
            "didReceive no longer derives its link through NotificationTapRoute (T-3049)"
        )
        #expect(
            body.contains("isDefaultAction: response.actionIdentifier == UNNotificationDefaultActionIdentifier"),
            "didReceive no longer limits routing to the tap itself"
        )
        #expect(
            body.contains("CadenceDeepLinkManager.shared.handle(url)"),
            "didReceive no longer hands the link to the deep-link manager, so a tap goes nowhere (T-3049)"
        )
        #expect(body.contains("completionHandler()"), "didReceive never completes")

        let makeContent = try cadenceFunctionBody("static func makeContent(for request:", in: manager)
        #expect(
            makeContent.contains("content.userInfo = NotificationTapRoute.userInfo(for: request)"),
            "the scheduled content no longer carries its link"
        )

        for root in ["Cadence/macOS/macOSRootView.swift", "Cadence/iOS/iOSRootView.swift"] {
            let source = try CadenceCommitSurfaceScan.scanned(root)
            #expect(
                source.contains(".onOpenURL { url in\n            CadenceDeepLinkManager.shared.handle(url)"),
                "\(root)'s .onOpenURL no longer calls the handler a reminder tap shares with it"
            )
        }
    }

    // MARK: - T-3049, the residue: a tap that COLD-LAUNCHES the app

    /// A root watches `route?.token` with `.onChange`, and `.onChange` does not fire for a value
    /// that is already set when the view first renders. A reminder tap that launches the app runs
    /// `handle(_:)` before any root exists, so without an appear-time read the route is recorded
    /// and never applied. `takeUnappliedRoute()` is the appear-time read.
    @Test func aRouteStandingBeforeTheRootRendersIsStillClaimedByIt() throws {
        let manager = CadenceDeepLinkManager.shared
        manager.route = nil
        _ = manager.takeUnappliedRoute()

        let taskID = UUID()
        manager.handle(try #require(URL(string: "cadence://task/\(taskID.uuidString)")))

        #expect(
            manager.takeUnappliedRoute() == .task(taskID),
            "a route recorded before the root appeared is not offered to it, so a cold-launch tap goes nowhere (T-3049)"
        )
    }

    /// The other half of the same guard, and the reason the appear-time read is not just a second
    /// call site: `.onAppear` fires again on every re-appearance — a re-opened macOS window — and
    /// re-applying a route the user navigated away from half an hour ago is its own defect.
    @Test func anAlreadyClaimedRouteIsNotAppliedASecondTimeWhenTheRootAppearsAgain() throws {
        let manager = CadenceDeepLinkManager.shared
        manager.route = nil
        _ = manager.takeUnappliedRoute()

        manager.handle(try #require(URL(string: "cadence://habits")))
        #expect(manager.takeUnappliedRoute() == .habits)

        #expect(
            manager.takeUnappliedRoute() == nil,
            "the standing route was handed out twice, so re-opening the window re-navigates (T-3049)"
        )
        #expect(
            manager.route?.deepLink == .habits,
            "claiming the route cleared it, which strands iOSCalendarView.standingCalendarDeepLinkDateKey (T-369)"
        )
    }

    /// Claiming is per-token, not per-link: `handle(_:)` mints a fresh token for every URL it
    /// accepts, so tapping the *same* reminder twice is two routes and routes twice.
    @Test func aRepeatTapOnTheSameReminderIsANewRouteAndRoutesAgain() throws {
        let manager = CadenceDeepLinkManager.shared
        manager.route = nil
        _ = manager.takeUnappliedRoute()

        let url = try #require(URL(string: "cadence://today"))
        manager.handle(url)
        #expect(manager.takeUnappliedRoute() == .today)
        #expect(manager.takeUnappliedRoute() == nil)

        manager.handle(url)
        #expect(
            manager.takeUnappliedRoute() == .today,
            "a second tap on the same reminder was swallowed as already-applied (T-3049)"
        )
    }

    /// The macOS wiring, which `CadenceTests` cannot drive: the appear-time call exists, and the
    /// handler reads through the claim rather than through `route` directly.
    @Test func theMacRootReadsAStandingDeepLinkRouteWhenItAppears() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/macOSRootView.swift")
        let onAppear = try cadenceFunctionBody(".onAppear", in: source)

        #expect(
            onAppear.contains("macOSRootLifecycleSupport.handleAppear("),
            "the reader did not return macOSRootView's .onAppear block"
        )
        #expect(
            onAppear.contains("handleDeepLinkRoute()"),
            "macOSRootView's .onAppear no longer applies a route that was standing before it rendered (T-3049)"
        )

        let handler = try cadenceFunctionBody("private func handleDeepLinkRoute()", in: source)
        #expect(
            handler.contains("deepLinkManager.takeUnappliedRoute()"),
            "handleDeepLinkRoute no longer claims the route, so .onAppear and .onChange both apply it (T-3049)"
        )
        #expect(
            !handler.contains("deepLinkManager.route?.deepLink"),
            "handleDeepLinkRoute still reads the route directly, which re-navigates on every re-appearance (T-3049)"
        )
    }
}
