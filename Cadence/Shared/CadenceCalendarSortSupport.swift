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

    /// Calendars grouped under their account, for the Mac calendar picker popover ([[T-14701]]).
    ///
    /// The accounts are in the same localized, case-insensitive order the calendars are, and each
    /// account's calendars are in `sorted(_:title:identifier:)`'s order. The popover used to re-sort
    /// both with a raw `<` -- the spelling T-379 retired everywhere else -- and a raw `<` puts every
    /// capitalised name ahead of every lowercase one, so the usual Mac accounts read "Other",
    /// "Subscribed Calendars", "iCloud": the iCloud account, where most people's calendars live,
    /// came last, and a calendar named "gym" sat below "Work" while the iPhone's list and Settings
    /// put it above. A raw `<` also left two same-titled calendars in one account free to swap.
    static func groupedBySource<Element>(
        _ calendars: [Element],
        source: (Element) -> String,
        title: (Element) -> String,
        identifier: (Element) -> String
    ) -> [(source: String, calendars: [Element])] {
        var bySource: [String: [Element]] = [:]
        for calendar in calendars {
            bySource[source(calendar), default: []].append(calendar)
        }
        return bySource
            .sorted { lhs, rhs in
                switch lhs.key.localizedCaseInsensitiveCompare(rhs.key) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return lhs.key < rhs.key
                }
            }
            .map { (source: $0.key, calendars: sorted($0.value, title: title, identifier: identifier)) }
    }

    /// The calendar a new event goes to when the person has not picked one, on both platforms
    /// ([[T-8552]]): the system's default calendar for new events when Cadence may write to it,
    /// otherwise the first writable calendar in the shared order.
    ///
    /// macOS always asked EventKit's `defaultCalendarForNewEvents` first, while every iOS creation
    /// surface took `writableCalendars.first` -- the alphabetically first calendar -- so the same
    /// "new event" landed in the person's default calendar on the Mac and in whichever of their
    /// calendars sorted first on the phone. Nothing about a touchscreen forces that.
    ///
    /// Over identifiers rather than `EKCalendar`, so a test can pin it without an `EKEventStore`.
    static func defaultWritableID(writableIDs: [String], systemDefaultID: String?) -> String? {
        if let systemDefaultID, writableIDs.contains(systemDefaultID) { return systemDefaultID }
        return writableIDs.first
    }
}
