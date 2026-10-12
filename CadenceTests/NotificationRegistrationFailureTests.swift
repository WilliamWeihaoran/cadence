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

    // That `reconcile` routes its adds through this seam, keeps its own pass's refusals, and clears
    // them on the cancel branch is held behaviourally since [[T-3113]], by
    // `NotificationManagerCentreSeamTests.reconcileRecordsTheRefusalsOfItsOwnPassAndTheCancelBranchClearsThem`;
    // the grep of the reconcile body that stood in while it could not run under test is gone.
}
