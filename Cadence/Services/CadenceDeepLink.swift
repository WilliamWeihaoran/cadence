import Foundation
import Observation

nonisolated enum CadenceDeepLink: Equatable {
    case today
    case task(UUID)
    case habits
    case goals
    case calendar

    init?(url: URL) {
        guard url.scheme?.caseInsensitiveCompare("cadence") == .orderedSame else { return nil }

        let host = (url.host ?? "").lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "today":
            self = .today
        case "task":
            guard let rawID = pathComponents.first, let id = UUID(uuidString: rawID) else { return nil }
            self = .task(id)
        case "habits":
            self = .habits
        case "goals", "milestones":
            self = .goals
        case "calendar":
            self = .calendar
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case .today:
            return URL(string: "cadence://today")!
        case .task(let id):
            return URL(string: "cadence://task/\(id.uuidString)")!
        case .habits:
            return URL(string: "cadence://habits")!
        case .goals:
            return URL(string: "cadence://goals")!
        case .calendar:
            return URL(string: "cadence://calendar")!
        }
    }
}

@Observable
final class CadenceDeepLinkManager {
    struct Route: Equatable {
        var deepLink: CadenceDeepLink
        var token: UUID = UUID()
    }

    static let shared = CadenceDeepLinkManager()

    var route: Route?
    var pendingTaskID: UUID?

    private init() {}

    func handle(_ url: URL) {
        guard let deepLink = CadenceDeepLink(url: url) else { return }
        route = Route(deepLink: deepLink)
        switch deepLink {
        case .today:
            pendingTaskID = nil
        case .task(let id):
            pendingTaskID = id
        case .habits, .goals, .calendar:
            pendingTaskID = nil
        }
    }

    func clearPendingTask(_ taskID: UUID) {
        guard pendingTaskID == taskID else { return }
        pendingTaskID = nil
    }
}
