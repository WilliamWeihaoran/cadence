import Combine
import Foundation
import Testing
@testable import Cadence

/// [[T-19903]]: the defaults-change signal the two preference-sync hosts observe reaches them on
/// the main thread, whichever thread wrote the default.
///
/// Each test builds its own stream over a private `NotificationCenter`, so nothing here observes
/// or posts on `NotificationCenter.default`.
@MainActor
struct CadenceDefaultsChangeStreamTests {
    /// The bug: a defaults write on a background queue posts the notification there, and the host's
    /// `onReceive` ran `publish` on that queue.
    @Test func aDefaultsChangePostedOffTheMainThreadIsDeliveredOnTheMainThread() async {
        let center = NotificationCenter()
        let stream = CadenceDefaultsChangeStream(center: center)
        var cancellable: AnyCancellable?

        let deliveredOnMain: Bool = await withCheckedContinuation { continuation in
            cancellable = stream.publisher.sink { _ in
                continuation.resume(returning: Thread.isMainThread)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                // Precondition of the scenario, not of the fix: the post really is off-main.
                precondition(!Thread.isMainThread)
                center.post(name: UserDefaults.didChangeNotification, object: nil)
            }
        }

        #expect(deliveredOnMain)
        cancellable?.cancel()
    }

    /// The fix must not defer a main-thread write: before it, `publish` ran inside the `post`
    /// call, and it still does.
    @Test func aDefaultsChangePostedOnTheMainThreadIsDeliveredInline() {
        let center = NotificationCenter()
        let stream = CadenceDefaultsChangeStream(center: center)
        var deliveries = 0
        let cancellable = stream.publisher.sink { _ in deliveries += 1 }

        center.post(name: UserDefaults.didChangeNotification, object: nil)

        #expect(deliveries == 1)
        cancellable.cancel()
    }
}
