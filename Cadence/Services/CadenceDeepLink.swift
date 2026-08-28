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

        let segments = Self.segments(of: url)
        guard let route = segments.first?.lowercased() else { return nil }
        let payload = Array(segments.dropFirst())

        switch route {
        case "today":
            self = .today
        case "task":
            guard let rawID = payload.first, let id = UUID(uuidString: rawID) else { return nil }
            self = .task(id)
        case "habits":
            self = .habits
        case "goals", "milestones":
            self = .goals
        case "calendar":
            self = .calendar(dateKey: Self.calendarDateKey(fromPath: payload))
        default:
            return nil
        }
    }

    /// The route name and its payload, in order, from **either** URL shape.
    ///
    /// **T-370: this is the lenient reading, and it is T-369's rule applied one level up.** The
    /// parser used to switch on `url.host` alone, which made two arbitrary distinctions. It
    /// rejected `cadence:///today` — an empty authority puts `today` in the *path*, so the host is
    /// `nil` and a URL naming a route the app has landed in the `default` branch and did nothing.
    /// And it silently ignored trailing components on singleton routes, so `cadence://today/junk`
    /// was accepted while `cadence:///today` was not: the same slack, granted in one place and
    /// refused in the other.
    ///
    /// Strict was the alternative and it loses on the same argument T-369 settled: a URL that
    /// names a route the app has is a request to open that route, and refusing it leaves the tap
    /// doing nothing at all — the worst outcome available, because there is no error surface
    /// behind a deep link. T-369 chose to degrade a mangled `cadence://calendar/not-a-date` to the
    /// bare calendar link rather than reject it; rejecting `cadence:///today` is that decision
    /// made the other way for no reason. So both shapes parse, and extra components stay ignored
    /// **by every** singleton route rather than by whichever ones happened to.
    ///
    /// A payload that is *required* is still required: `cadence://task` with no id is `nil`, and a
    /// non-UUID id is `nil`, because there is no task to open and no bare "task" screen to degrade
    /// to. `url` still emits the canonical `cadence://<route>` form — leniency is a property of
    /// what the app accepts, not of what it produces.
    private static func segments(of url: URL) -> [String] {
        let host = url.host.map { [$0] } ?? []
        return host + url.pathComponents.filter { $0 != "/" }
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

    /// A finished task whose surface must open its collapsed Completed section before the row the
    /// link names exists on the page (T-375). Written by
    /// `resolvedDestination(for:modelContext:)`, which is the only thing that knows whether the
    /// task is finished; see `CadenceDeepLinkResolutionSupport.TaskLinkResolution` for why this is
    /// a reveal rather than a second `pendingTaskID`.
    ///
    /// Its lifetime is the route's. `handle(_:)` clears it for **every** link, so a singleton
    /// route — which never reaches the resolver's task branch — cannot leave the previous link's
    /// logbook standing open.
    var revealedCompletedTaskID: UUID?

    private init() {}

    func handle(_ url: URL) {
        guard let deepLink = CadenceDeepLink(url: url) else { return }
        route = Route(deepLink: deepLink)
        revealedCompletedTaskID = nil
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
