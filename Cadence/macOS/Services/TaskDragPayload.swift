#if os(macOS)
import Foundation

enum TaskDragPayload {
    private static let listTaskPrefix = "listTask:"
    private static let bundlePrefix = "taskBundle:"

    static func string(for id: UUID) -> String {
        "\(listTaskPrefix)\(id.uuidString)"
    }

    static func bundleString(for id: UUID) -> String {
        "\(bundlePrefix)\(id.uuidString)"
    }

    static func taskID(from payload: String) -> UUID? {
        if payload.hasPrefix(listTaskPrefix) {
            return UUID(uuidString: String(payload.dropFirst(listTaskPrefix.count)))
        }
        if payload.hasPrefix(bundlePrefix) {
            return nil
        }
        return UUID(uuidString: payload)
    }

    static func bundleID(from payload: String) -> UUID? {
        guard payload.hasPrefix(bundlePrefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(bundlePrefix.count)))
    }
}
#endif
