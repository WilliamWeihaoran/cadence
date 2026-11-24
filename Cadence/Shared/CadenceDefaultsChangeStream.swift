import Combine
import Foundation

/// The `UserDefaults.didChangeNotification` signal the two preference-sync hosts observe, delivered
/// on the main thread ([[T-19903]]).
///
/// `UserDefaults.didChangeNotification` is posted on whatever thread did the write, and it fires
/// for **every** defaults write in the process -- a framework writing its own keys on its own queue
/// included. `CadenceLookPreferenceSyncHost` and `CadenceNoteTemplatePreferenceSyncHost` each fed
/// `NotificationCenter.default.publisher(for:)` straight into `.onReceive`, so such a write ran the
/// host's `publish` (a `@MainActor` sync, a `ModelContext` write) off the main thread, and SwiftUI
/// raised "Publishing changes from background threads is not allowed". It was sighted on the iPad
/// on exactly the runs that opened Settings, whose `onAppear` is the app's one CloudKit
/// `accountStatus` call.
///
/// A main-thread post is still delivered **inline**, exactly as before; only an off-main post is
/// hopped to the main queue. One stored instance, for the reason `CadenceDayChangeStream` records:
/// `onReceive` keeps its subscription only when handed the same publisher.
@MainActor
final class CadenceDefaultsChangeStream {
    /// The stream both hosts observe, over `NotificationCenter.default`.
    static let main = CadenceDefaultsChangeStream(center: .default)

    let publisher: AnyPublisher<Void, Never>

    init(center: NotificationCenter) {
        publisher = center.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in () }
            .receive(on: CadenceMainThreadScheduler())
            .eraseToAnyPublisher()
    }
}

/// Runs an action inline when already on the main thread, and on the main queue otherwise.
///
/// `receive(on: DispatchQueue.main)` would also be correct, but it defers every delivery -- a
/// main-thread defaults write included -- to a later turn of the run loop, which is a timing
/// change the fix does not need to make.
nonisolated struct CadenceMainThreadScheduler: Scheduler {
    typealias SchedulerTimeType = DispatchQueue.SchedulerTimeType
    typealias SchedulerOptions = DispatchQueue.SchedulerOptions

    var now: SchedulerTimeType { DispatchQueue.main.now }
    var minimumTolerance: SchedulerTimeType.Stride { DispatchQueue.main.minimumTolerance }

    func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.schedule(options: options, action)
        }
    }

    func schedule(
        after date: SchedulerTimeType,
        tolerance: SchedulerTimeType.Stride,
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) {
        DispatchQueue.main.schedule(after: date, tolerance: tolerance, options: options, action)
    }

    func schedule(
        after date: SchedulerTimeType,
        interval: SchedulerTimeType.Stride,
        tolerance: SchedulerTimeType.Stride,
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) -> Cancellable {
        DispatchQueue.main.schedule(after: date, interval: interval, tolerance: tolerance, options: options, action)
    }
}
