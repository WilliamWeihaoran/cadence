import SwiftUI

/// One past-due summary line, split so that colour can be applied to the part that earns it.
///
/// Today's past-due list and section cards each render a single caption that mixes a deadline
/// with something that is not one — `"46 days ago • 3 active tasks"`, `"Documents • 9 days ago"`.
/// The whole caption used to be drawn in `Theme.red`, which put the same red on a count and a
/// parent list name as on the date that is actually late. Splitting the line is what lets the
/// view tint the deadline and leave the rest neutral without either card inventing its own rule.
struct CadenceOverdueSummaryLine: Equatable {
    /// Text that comes before the deadline — a parent list name. Always neutral.
    let leadingDetail: String?
    /// The deadline itself, already humanised ("46 days ago"). The **only** fragment allowed red.
    let dateText: String
    /// Text that comes after the deadline — an active/open count. Always neutral.
    let trailingDetail: String?
    /// Whether the deadline has actually passed, via `CadenceDueUrgency` rather than a second
    /// hand-rolled `<` comparison against today.
    let isLate: Bool

    static let separator = " • "

    /// The line as one string, for accessibility and for tests that care about wording rather
    /// than colour.
    var plainText: String {
        ([leadingDetail, dateText, trailingDetail].compactMap { $0 })
            .filter { !$0.isEmpty }
            .joined(separator: Self.separator)
    }

    /// Red only when the deadline has passed. A summary card that somehow renders a future date
    /// says so in the neutral ramp instead of borrowing the urgency of the section it sits in.
    var dateTint: Color { isLate ? Theme.red : Theme.dim }
}

enum CadenceOverdueSummaryPresentation {
    /// Builds the split line for a past-due card.
    ///
    /// `dueDateKey` is a `yyyy-MM-dd` storage key; an unparseable or empty one degrades to the
    /// raw string through `DateFormatters.relativeDate` and is reported as not late, so a bad
    /// value can never light up red.
    static func line(
        dueDateKey: String,
        leadingDetail: String? = nil,
        trailingDetail: String? = nil,
        todayKey: String = DateFormatters.todayKey()
    ) -> CadenceOverdueSummaryLine {
        CadenceOverdueSummaryLine(
            leadingDetail: normalized(leadingDetail),
            dateText: DateFormatters.relativeDate(from: dueDateKey),
            trailingDetail: normalized(trailingDetail),
            isLate: CadenceDueUrgency.evaluate(dueDateKey: dueDateKey, todayKey: todayKey) == .overdue
        )
    }

    /// `"3 active tasks"` / `"1 active task"` — the count Today's past-due list card carries.
    static func activeTaskDetail(count: Int) -> String {
        "\(count) active task\(count == 1 ? "" : "s")"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }
}
