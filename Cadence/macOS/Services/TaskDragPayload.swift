#if os(macOS)
import Foundation

enum TaskDragPayload {
    private static let listTaskPrefix = "listTask:"

    static func string(for id: UUID) -> String {
        "\(listTaskPrefix)\(id.uuidString)"
    }

    static func taskID(from payload: String) -> UUID? {
        if payload.hasPrefix(listTaskPrefix) {
            return UUID(uuidString: String(payload.dropFirst(listTaskPrefix.count)))
        }
        return UUID(uuidString: payload)
    }
}
#endif
