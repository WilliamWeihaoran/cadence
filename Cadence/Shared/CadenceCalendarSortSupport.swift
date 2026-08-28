import EventKit
import Foundation

/// The one order for a list of calendars, on both platforms (T-379).
///
/// macOS sorted with a raw `$0.title < $1.title` and iOS with
/// `localizedCaseInsensitiveCompare`, so calendars differing only by case or by locale-sensitive
/// collation appeared in one order in the Mac's settings and pickers and another on the phone.
/// Worse, *neither* spelling ended on a stable identity: two calendars sharing a title — which
/// EventKit permits, and which happens as soon as the same calendar name exists in two accounts —
/// were unordered within a single platform too, so they could swap places between reads.
///
/// The order is therefore two levels: localized case-insensitive title, then
/// `calendarIdentifier`. The identifier tail is what makes it a total order, so the same set of
/// calendars sorts to the same sequence regardless of the order EventKit handed them over in.
/// This is the same total-order shape as the other shared sorters; do not re-spell it at a call
/// site.
nonisolated enum CadenceCalendarSorting {
    /// The comparator itself, over the two fields it reads, so a test can pin it without an
    /// `EKEventStore`.
    static func isOrderedBefore(
        lhsTitle: String,
        lhsIdentifier: String,
        rhsTitle: String,
        rhsIdentifier: String
    ) -> Bool {
        switch lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return lhsIdentifier < rhsIdentifier
        }
    }

    static func sorted<Element>(
        _ calendars: [Element],
        title: (Element) -> String,
        identifier: (Element) -> String
    ) -> [Element] {
        calendars.sorted {
            isOrderedBefore(
                lhsTitle: title($0),
                lhsIdentifier: identifier($0),
                rhsTitle: title($1),
                rhsIdentifier: identifier($1)
            )
        }
    }

    static func sorted(_ calendars: [EKCalendar]) -> [EKCalendar] {
        sorted(calendars, title: \.title, identifier: \.calendarIdentifier)
    }
}
