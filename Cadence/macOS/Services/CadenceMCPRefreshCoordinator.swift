#if os(macOS)
import Darwin
import Foundation

final class CadenceMCPRefreshCoordinator {
    private var monitor: CadenceMCPRefreshMonitor?
    private var lastMarkerDate: Date?

    func start(onChange: @escaping () -> Void) {
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

private final class CadenceMCPRefreshMonitor {
    private let queue = DispatchQueue(label: "com.haoranwei.Cadence.mcp-refresh-monitor")
    private let source: DispatchSourceFileSystemObject
    private var pendingRefresh: DispatchWorkItem?

    init?(onChange: @escaping () -> Void) {
        guard let markerURL = try? CadenceModelContainerFactory.refreshMarkerURL() else { return nil }
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

    private func scheduleRefresh(_ onChange: @escaping () -> Void) {
        pendingRefresh?.cancel()
        let workItem = DispatchWorkItem {
            DispatchQueue.main.async(execute: onChange)
        }
        pendingRefresh = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}
#endif
