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

    /// **"Open this event's editor once its day is drawn"** ([[T-11196]] (1)).
    ///
    /// Cmd+K picking an event used to stop at the jump, so the reader still had to find the block
    /// and click it, where iOS Search opens the event's editor. The Mac's editor is a popover
    /// anchored to the event's block, and the block does not exist until the calendar has laid
    /// the day out -- so the jump carries this beside it, and the block (or all-day chip) whose
    /// `CalendarEventItem.id` it names takes it when it appears and opens its own popover.
    ///
    /// Kept apart from `request` because the page clears that the moment it has scrolled, which
    /// is before the day's blocks are drawn. It lapses after `editorRequestLifetime`, so an event
    /// whose block never appears -- its calendar hidden, its day off the rendered window -- cannot
    /// spring its editor open on some later visit.
    struct EventEditorRequest: Equatable {
        var eventID: String
        var expiresAt: Date
        var token: UUID = UUID()
    }

    static let editorRequestLifetime: TimeInterval = 5

    static let shared = CalendarNavigationManager()

    var request: Request?
    private(set) var eventEditorRequest: EventEditorRequest?

    /// Internal rather than private so a test can drive its own instance; the app uses `shared`.
    init() {}

    func open(date: Date) {
        open(dateKey: DateFormatters.dateKey(from: date), now: date)
    }

    /// Jump to the event's day and ask the block carrying `eventID` to open its editor.
    func open(date: Date, editingEventID eventID: String, now: Date = Date()) {
        open(date: date)
        eventEditorRequest = EventEditorRequest(
            eventID: eventID,
            expiresAt: now.addingTimeInterval(Self.editorRequestLifetime)
        )
    }

    /// Whether the block or chip for `eventID` should open its editor now. Answers `true` once:
    /// the request is consumed, so the next segment of a multi-day event -- which shares the id
    /// -- does not open a second popover. A lapsed request is dropped and answers `false`.
    func takeEventEditorRequest(for eventID: String, now: Date = Date()) -> Bool {
        guard let pending = eventEditorRequest else { return false }
        guard pending.expiresAt > now else {
            eventEditorRequest = nil
            return false
        }
        guard pending.eventID == eventID else { return false }
        eventEditorRequest = nil
        return true
    }

    /// Jump to a stored `yyyy-MM-dd`.
    ///
    /// `now` only supplies the hour to land on. A day carries no time of its own, and the hour a
    /// user is looking at their own clock at is the least surprising row to arrive on — it is what
    /// `open(date:)` has always resolved to for a date that happens to carry the current time.
    func open(dateKey: String, now: Date = Date()) {
        // A plain jump is not about any event, so it retires one a previous jump left pending.
        eventEditorRequest = nil
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
