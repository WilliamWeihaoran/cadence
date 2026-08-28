import Foundation
import Observation

nonisolated enum CadenceDeepLink: Equatable {
    case today
    case task(UUID)
    case habits
    case goals
    /// The calendar, optionally on a named `yyyy-MM-dd`.
    ///
    /// **T-369.** The link was payload-free, so a tap on the Calendar widget opened the calendar
    /// on whichever date it had last been scrolled to — the widget showed a fortnight from *its*
    /// date and the app answered with a remembered one. `nil` no longer means "wherever it was":
    /// see `calendarDateKey(todayKey:)`.
    case calendar(dateKey: String?)

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
            self = .calendar(dateKey: Self.calendarDateKey(fromPath: pathComponents))
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
        case .calendar(let dateKey):
            guard let dateKey else { return URL(string: "cadence://calendar")! }
            return URL(string: "cadence://calendar/\(dateKey)")!
        }
    }

    /// The day a calendar link opens, or `nil` for a link that is not about the calendar.
    ///
    /// **A bare `cadence://calendar` means today, explicitly.** Landing on a remembered date is
    /// the one answer nobody asked for: it is not where the widget was pointing and not where a
    /// user who typed the bare URL meant either. Callers that have no date of their own get one
    /// here rather than leaving the calendar wherever it was parked (T-369).
    func calendarDateKey(todayKey: String = DateFormatters.todayKey()) -> String? {
        guard case .calendar(let dateKey) = self else { return nil }
        return dateKey ?? todayKey
    }

    /// A `yyyy-MM-dd` first path component, or `nil`.
    ///
    /// An unparseable payload degrades to the bare link — which means today — rather than
    /// rejecting the URL outright. A calendar link with a mangled date is still a request to open
    /// the calendar, and refusing it would leave the tap doing nothing at all.
    private static func calendarDateKey(fromPath pathComponents: [String]) -> String? {
        guard let raw = pathComponents.first, DateFormatters.date(from: raw) != nil else { return nil }
        return raw
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
