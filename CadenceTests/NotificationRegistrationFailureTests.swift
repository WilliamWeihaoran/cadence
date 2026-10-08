import Foundation
import Testing
import UserNotifications
@testable import Cadence

/// **[[T-3049]] (2): a registration the OS refuses is observable, not swallowed.**
///
/// `reconcile` early-returns under test by design, so these drive `NotificationManager.register`
/// — the loop `reconcile` hands its adds to — with a fake `add` that refuses chosen identifiers.
/// Nothing here constructs or reaches the OS notification centre; building a
/// `UNNotificationRequest` value touches none.
@MainActor
struct NotificationRegistrationFailureTests {
    private struct Refusal: Error {}

    private func requests(_ count: Int) -> [CadenceNotificationRequest] {
        let fireDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
        return (0..<count).map { index in
            CadenceNotificationRequest(
                identifier: NotificationIdentifiers.taskDue(taskID: UUID()),
                kind: .taskDue,
                title: "Task \(index)",
                body: "Due today",
                fireDate: fireDate.addingTimeInterval(Double(index) * 60)
            )
        }
    }

    @Test func everyRefusedAddIsRecordedAndEveryLaterAddIsStillAttempted() async {
        let planned = requests(5)
        let refused: Set<String> = [planned[1].identifier, planned[3].identifier]
        var attempted: [String] = []

        let failures = await NotificationManager.register(planned) { osRequest in
            attempted.append(osRequest.identifier)
            if refused.contains(osRequest.identifier) { throw Refusal() }
        }

        #expect(attempted == planned.map(\.identifier), "a refusal stopped the pass early")
        #expect(
            failures.map(\.identifier) == planned.map(\.identifier).filter(refused.contains),
            "the record of refused adds does not match what the OS refused (T-3049)"
        )
        #expect(failures.allSatisfy { !$0.reason.isEmpty }, "a refusal was recorded without its reason")
    }

    @Test func aPassTheOSAcceptsRecordsNoFailure() async {
        let planned = requests(3)
        var attempted = 0

        let failures = await NotificationManager.register(planned) { _ in attempted += 1 }

        #expect(attempted == planned.count)
        #expect(failures.isEmpty)
    }

    /// The seam above is only the fix if `reconcile` actually routes its adds through it and keeps
    /// the result, and if the cancel branch clears what an earlier pass left there.
    @Test func theReconcileKeepsTheRefusalsOfItsOwnPassRatherThanSwallowingThem() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/Services/NotificationManager.swift")
        let body = try cadenceFunctionBody("func reconcile(", in: source)

        #expect(body.contains("let plan = NotificationPlan.build("), "non-vacuity: not reading the reconcile body")
        #expect(
            !body.contains("try? await center.add"),
            "reconcile swallows the OS's refusal again, so a failed registration is unobservable (T-3049)"
        )
        #expect(
            body.contains("lastReconcileRegistrationFailures = await Self.register(diff.requestsToAdd)"),
            "reconcile no longer records the refusals of its own pass (T-3049)"
        )

        let clear = try #require(body.range(of: "lastReconcileRegistrationFailures = []"))
        let cancel = try #require(body.range(of: "await cancelAll()"))
        #expect(
            clear.upperBound <= cancel.lowerBound,
            "the cancel branch no longer clears the previous pass's refusals before it returns (T-3049)"
        )
    }
}
