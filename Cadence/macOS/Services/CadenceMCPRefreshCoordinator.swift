#if os(macOS)
import Darwin
import Foundation

final class CadenceMCPRefreshCoordinator {
    private var monitor: CadenceMCPRefreshMonitor?
    private var lastMarkerDate: Date?

    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard monitor == nil else { return }
        monitor = CadenceMCPRefreshMonitor { [weak self] in
            self?.lastMarkerDate = Self.currentMarkerDate() ?? Date()
            onChange()
        }
        lastMarkerDate = Self.currentMarkerDate()
    }

    func shouldRefreshForCurrentMarker() -> Bool {
        guard let markerDate = Self.currentMarkerDate(),
              markerDate != lastMarkerDate else { return false }
        lastMarkerDate = markerDate
        return true
    }

    private static func currentMarkerDate() -> Date? {
        guard let markerURL = try? CadenceModelContainerFactory.refreshMarkerURL(),
              let values = try? markerURL.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }
}

/// **[[T-18622]]: the reminder half of adopting an out-of-process write, held for the app's life.**
///
/// The only reconcile for an MCP or widget write used to be the last line of
/// `macOSRootView.refreshAppData()`, and that swap waits for `NSApp.isActive` -- while Claude
/// Desktop, the surface the owner drives MCP from, is frontmost. So a task an agent completed,
/// deleted or moved kept its old "Due today" / "Starting now" until Cadence was next clicked. The
/// watch was also `@State` on the root view, so with the window closed (the app still running)
/// nothing heard the marker at all. This watch is owned by `CadenceAppDelegate`, needs no window,
/// and reconciles from a fresh read whatever the activation state; the UI swap stays deferred
/// exactly as it was ([[T-18162]]). The [[T-3046]] half-imported-store caution does not apply: a
/// local SQLite write is complete before its marker is posted.
@MainActor
final class CadenceExternalWriteReminderWatch {
    static let shared = CadenceExternalWriteReminderWatch(
        reconcile: { CadenceExternalWriteReminderWatch.reconcileFromStore() }
    )

    private var monitor: CadenceMCPRefreshMonitor?
    private let reconcile: @MainActor () -> Void

    init(reconcile: @escaping @MainActor () -> Void) {
        self.reconcile = reconcile
    }

    var isWatching: Bool { monitor != nil }

    /// `markerURL` is injectable for the tests; the app passes nothing and watches the real
    /// marker. Never in a test host for `shared`: that marker sits beside the app's store.
    func start(markerURL: URL? = nil) {
        guard monitor == nil,
              let url = markerURL ?? (try? CadenceModelContainerFactory.refreshMarkerURL()) else { return }
        monitor = CadenceMCPRefreshMonitor(markerURL: url) { [weak self] in
            self?.reconcile()
        }
    }

    func stop() {
        monitor = nil
    }

    /// The becoming-active arm's own input (`NotificationReconcileObserver`): a fresh context over
    /// the store, so no registered row predates the write. A failed read reconciles nothing.
    static func reconcileFromStore() {
        guard !NotificationManager.isTestEnvironment,
              let container = PersistenceController.shared.container else { return }
        Task {
            guard let snapshot = try? CadenceForegroundNotificationSnapshot(container: container) else { return }
            await NotificationManager.shared.reconcile(tasks: snapshot.tasks, completeStore: snapshot.completeStore)
            withExtendedLifetime(snapshot) {}
        }
    }
}

final class CadenceMCPRefreshMonitor {
    private let queue = DispatchQueue(label: "com.haoranwei.Cadence.mcp-refresh-monitor")
    private let source: DispatchSourceFileSystemObject
    private var pendingRefresh: DispatchWorkItem?

    convenience init?(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard let markerURL = try? CadenceModelContainerFactory.refreshMarkerURL() else { return nil }
        self.init(markerURL: markerURL, onChange: onChange)
    }

    init?(markerURL: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: markerURL.path) {
            FileManager.default.createFile(atPath: markerURL.path, contents: Data())
        }

        let descriptor = open(markerURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleRefresh(onChange)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    private func scheduleRefresh(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        pendingRefresh?.cancel()
        let workItem = DispatchWorkItem {
            DispatchQueue.main.async(execute: onChange)
        }
        pendingRefresh = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}
#endif
