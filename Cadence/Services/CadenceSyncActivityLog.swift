import CoreData
import Foundation
import Observation

/// Where `CadenceSyncActivityEvent`s come from.
///
/// The seam exists because the thing on the other side of it **cannot be produced on demand**.
/// `NSPersistentCloudKitContainer` posts a mirroring event when it has decided to mirror; there is
/// no public call that makes one happen, and the two things that look like one are not. Faking a
/// trigger is how this ticket fails, so the trigger is not faked here or anywhere else — what is
/// injectable is the *reading*, which is the part with logic in it.
///
/// **Implementations must deliver on the main thread.** The live one asks `NotificationCenter` for
/// `OperationQueue.main`; a test calls the handler directly from a `@MainActor` context. That
/// contract is what lets `start`'s handler be `@MainActor`-isolated, which in turn is what lets a
/// test drive the whole log synchronously, with no expectation, no sleep and no clock.
@MainActor
protocol CadenceSyncActivityEventStream: AnyObject {
    func start(_ handler: @escaping @MainActor (CadenceSyncActivityEvent) -> Void)
    func stop()
}

/// The launch-scoped record of what CloudKit mirroring has done, and the only thing any view reads
/// about it.
///
/// A singleton with an injectable stream, for the same reason `CadencePushRegistrationMonitor` is
/// a singleton while `CadenceCloudAccountProbe` is not: this is one fact about the process that
/// arrives asynchronously from a notification with no view anywhere near it, so a second instance
/// would be a second instance that never hears anything. The `stream:` parameter is the test seam
/// and nothing in the app passes it.
///
/// **Launch-scoped, and the copy says so.** The history starts empty at every launch, because
/// nothing persists these events and reconstructing them from the CloudKit metadata tables is not
/// something this app should be doing. `statusLine`'s empty sentence names the launch for exactly
/// that reason — "since it launched" is a promise this type can keep.
@MainActor
@Observable
final class CadenceSyncActivityLog {
    static let shared = CadenceSyncActivityLog(stream: CadenceCloudKitMirroringEventStream())

    private(set) var summary: CadenceSyncActivitySummary = .empty

    @ObservationIgnored private let stream: CadenceSyncActivityEventStream
    @ObservationIgnored private var hasStarted = false

    init(stream: CadenceSyncActivityEventStream) {
        self.stream = stream
    }

    /// Called from both app delegates' launch, beside
    /// `CadenceRemoteNotificationRegistrar.registerIfNeeded()`. Idempotent, because the only thing
    /// worse than missing the events is counting each of them twice.
    ///
    /// It starts at **launch** rather than when a settings screen appears, and that is the whole
    /// point: mirroring happens while nobody is looking at Settings, and a surface that only
    /// begins listening when it is opened can never say anything except "nothing yet".
    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        stream.start { [weak self] event in
            self?.record(event)
        }
    }

    /// The fold. `internal` rather than private so a test can drive the reader without a stream at
    /// all, which is the shape most of `CadenceSyncActivityTests` takes.
    func record(_ event: CadenceSyncActivityEvent) {
        summary = summary.applying(event)
    }
}

/// The live stream: `NSPersistentCloudKitContainer.eventChangedNotification`, translated once.
///
/// SwiftData's CloudKit mirroring is `NSPersistentCloudKitContainer` underneath — the app opens its
/// store with `cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")` and never names the
/// Core Data class — so this observes the notification by name without holding a container. That
/// also means it is listening to *every* mirrored store in the process, which is correct: there is
/// one, and if a second ever appears its events are still this app's events.
///
/// **What is NOT here, by instruction (T-2000).** There is no resync. `NSPersistentCloudKitContainer`
/// exposes no public API to trigger a sync pass, and the two things that could be dressed up as one
/// are both dishonest: touching a record schedules an *export* and pulls nothing down, and deleting
/// the local store metadata to force a re-import is destructive. Neither is a button. If one is
/// ever added it must be named for what it does.
///
/// **What `center:` and `decode:` buy, and what they do not ([[T-2010]]).** The notification source
/// is injected so a test can read back *how this subscribes* — the name it asks for, that it asks
/// with no `object:` filter, and that it asks for the main queue. The decoder is injected so a test
/// can drive the subscription rather than only inspect it: with both substituted, a real `post`
/// into a real `NotificationCenter` travels the real main-queue delivery into the real
/// `handler(event)`, and `CadenceSyncActivityLog`'s summary moves. **It does not prove the other
/// end.** That Core Data actually posts this notification for a SwiftData store opened with
/// `cloudKitDatabase:`, and that the real decoder reads its payload, is still taken from the
/// platform, not measured: `NSPersistentCloudKitContainer.Event` declares `init` as
/// `NS_UNAVAILABLE` and the only public way to obtain one is a real mirrored store. The seam moves
/// the untested part from "the whole subscription" down to "whether anything ever arrives", and
/// that last step is [[T-2010]]'s own two-minute check on a debug build.
@MainActor
final class CadenceCloudKitMirroringEventStream: CadenceSyncActivityEventStream {
    /// How a notification becomes one of this app's events. Defaults to the real decoder and
    /// nothing in the app passes anything else.
    typealias Decoder = @Sendable (Notification) -> CadenceSyncActivityEvent?

    private let center: NotificationCenter
    private let decode: Decoder
    private var observer: NSObjectProtocol?

    /// `center` and `decode` are the test seams and nothing in the app passes either — the same
    /// shape as `CadenceSyncActivityLog`'s `stream:`.
    ///
    /// **`decode` exists because the real one cannot be driven, not to make the real one
    /// optional** ([[T-2010]]). `NSPersistentCloudKitContainerEvent` declares `+new` and `-init`
    /// `NS_UNAVAILABLE`, so no test can build a notification this stream's real decoder returns
    /// anything but `nil` for — which left the *delivering* half of `start` unreachable: with both
    /// `center` and `decode` real, `handler(event)` could be deleted outright and every test in
    /// the tree stayed green, because the only assertion over the handler was a count of zero.
    /// Substituting the decoder alongside the centre makes the path live end to end — real
    /// `addObserver`, real `post`, real main-queue delivery, real `MainActor.assumeIsolated`, real
    /// `handler(event)` — with exactly one link still taken from the platform: that Core Data
    /// posts the notification, and that its payload decodes. That link is [[T-2010]]'s two-minute
    /// owner check and nothing here claims it.
    init(
        center: NotificationCenter = .default,
        decode: @escaping Decoder = { CadenceSyncActivityEvent(notification: $0) }
    ) {
        self.center = center
        self.decode = decode
    }

    func start(_ handler: @escaping @MainActor (CadenceSyncActivityEvent) -> Void) {
        guard observer == nil else { return }
        let decode = self.decode
        observer = center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            // `.main` is the contract `CadenceSyncActivityEventStream` states. Core Data does not
            // promise which queue it posts on, and the `MainActor.assumeIsolated` below is only
            // sound because this block is scheduled onto the main queue rather than run inline.
            queue: .main
        ) { notification in
            guard let event = decode(notification) else { return }
            MainActor.assumeIsolated {
                handler(event)
            }
        }
    }

    func stop() {
        guard let observer else { return }
        center.removeObserver(observer)
        self.observer = nil
    }
}

extension CadenceSyncActivityEvent {
    /// The one translation from Core Data's event to this app's, and the only place in the tree
    /// that names `NSPersistentCloudKitContainer`.
    ///
    /// `error?.localizedDescription` is read here rather than stored as an `Error`, so the value
    /// type stays `Sendable` and `Equatable` and every test over the summary is a test over
    /// strings and dates.
    ///
    /// `nonisolated` because it is a pure translation that touches no actor state, and because the
    /// target's default actor isolation is `MainActor`: left implicit, naming this initializer
    /// from any nonisolated `@Sendable` context — which is exactly what a `NotificationCenter`
    /// observer block is — is an `#ActorIsolatedCall` warning against a zero-warning baseline.
    nonisolated init?(notification: Notification) {
        guard let raw = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else { return nil }
        guard let phase = CadenceSyncActivityPhase(eventType: raw.type) else { return nil }
        self.init(
            identifier: raw.identifier,
            phase: phase,
            startDate: raw.startDate,
            endDate: raw.endDate,
            succeeded: raw.succeeded,
            errorDescription: raw.error?.localizedDescription
        )
    }
}

extension CadenceSyncActivityPhase {
    /// `nil` on an event type a future OS adds. An unrecognised phase is dropped rather than
    /// folded into one of the three, because mapping it onto `.import` would put an unknown pass's
    /// failure under a heading that names the wrong thing.
    nonisolated init?(eventType: NSPersistentCloudKitContainer.EventType) {
        switch eventType {
        case .setup: self = .setup
        case .import: self = .import
        case .export: self = .export
        @unknown default: return nil
        }
    }
}
