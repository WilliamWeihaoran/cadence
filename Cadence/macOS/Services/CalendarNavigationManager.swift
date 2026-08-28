#if os(macOS)
import Foundation
import Observation

@Observable
final class CalendarNavigationManager {
    struct Request: Equatable {
        var dateKey: String
        var preferredHour: Int
        var token: UUID = UUID()
    }

    static let shared = CalendarNavigationManager()

    var request: Request?

    private init() {}

    func open(date: Date) {
        open(dateKey: DateFormatters.dateKey(from: date), now: date)
    }

    /// Jump to a stored `yyyy-MM-dd`.
    ///
    /// `now` only supplies the hour to land on. A day carries no time of its own, and the hour a
    /// user is looking at their own clock at is the least surprising row to arrive on — it is what
    /// `open(date:)` has always resolved to for a date that happens to carry the current time.
    func open(dateKey: String, now: Date = Date()) {
        request = Request(
            dateKey: dateKey,
            preferredHour: Calendar.current.component(.hour, from: now)
        )
    }

    /// Applies a deep link that names a calendar day, reporting whether it was one.
    ///
    /// **T-369.** `cadence://calendar` used to carry no date, so the root selected the Calendar
    /// page and left the timeline wherever it had last been scrolled — which is neither the day
    /// the Calendar widget was showing nor today. The link now names a day, and a bare link means
    /// today; both answers come from `CadenceDeepLink.calendarDateKey(todayKey:)` so the widget's
    /// URL and the app's reading of it cannot disagree.
    @discardableResult
    func openCalendarLink(
        _ deepLink: CadenceDeepLink,
        now: Date = Date(),
        todayKey: String = DateFormatters.todayKey()
    ) -> Bool {
        guard let dateKey = deepLink.calendarDateKey(todayKey: todayKey) else { return false }
        open(dateKey: dateKey, now: now)
        return true
    }

    func clear() {
        request = nil
    }
}
#endif
