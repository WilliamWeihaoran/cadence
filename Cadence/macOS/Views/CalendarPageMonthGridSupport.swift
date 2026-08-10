#if os(macOS)
import SwiftUI
import Foundation

func monthStart(for date: Date, calendar: Calendar) -> Date {
    let comps = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: comps) ?? date
}

/// Index of the block that **renders** `date`.
///
/// Distinct from the calendar month `date` falls in: the grid tiles months without repeating a
/// day — a block starts on its month's first Sunday and carries the days before it as trailing
/// fill on the previous block — so for roughly three days a month the two answers differ by one.
///
/// Every date -> scroll mapping wants *this* one. `CalendarMonthGridIdentifiers.day` is tagged
/// with the rendering block, so a day id assembled from a calendar-month index simply does not
/// exist in the grid, and `ScrollViewProxy.scrollTo` ignores an unknown id without complaint.
///
/// The block rule itself is not restated here: it is read from
/// `CalendarMonthGridSupport.blockMonthStart(for:)`, the same helper `weeks(for:)` is built on,
/// so this cannot drift away from the layout it is describing.
///
/// **Known gap at the very bottom of the window.** The result is clamped into
/// `[0, totalMonths - 1]` by `monthIndex(for:)`. For a date in the leading 1–6 days of the
/// *earliest* month in the window the rendering block is the month before it — index `-1` — and
/// the clamp returns block `0`, which knowingly does **not** draw that date. There is no honest
/// answer available: no block in the window renders that day at all. The invariant "the returned
/// index names a block that actually draws this date" therefore holds everywhere except this one
/// boundary, and the clamped value is deliberately a non-drawing block rather than a correction.
/// Practically unreachable — the window is 120 months wide and centred on today — but pinned by
/// `blockIndexClampsBelowTheWindowToAKnowinglyNonDrawingBlock` so it cannot change unnoticed.
func blockIndex(for date: Date, currentMonthStart: Date, todayMonthIdx: Int, calendar: Calendar) -> Int {
    monthIndex(
        for: CalendarMonthGridSupport.blockMonthStart(for: date, calendar: calendar),
        currentMonthStart: currentMonthStart,
        todayMonthIdx: todayMonthIdx,
        calendar: calendar
    )
}

/// Month-start -> window index arithmetic, plus the window clamp.
///
/// In production this is reached only through `blockIndex(for:)`, which hands it a *block's*
/// month start; it is not a second, "name the calendar month" entry point for callers to choose
/// between. It stays a separate function because tests exercise the index arithmetic and the
/// clamp directly, and because keeping the clamp in one place is what makes the boundary note on
/// `blockIndex(for:)` true of every path.
func monthIndex(for date: Date, currentMonthStart: Date, todayMonthIdx: Int, calendar: Calendar) -> Int {
    let targetMonthStart = monthStart(for: date, calendar: calendar)
    let delta = calendar.dateComponents([.month], from: currentMonthStart, to: targetMonthStart).month ?? 0
    let rawIndex = todayMonthIdx + delta
    let clampedIndex = min(max(rawIndex, 0), CalendarMonthGridMetrics.totalMonths - 1)
    #if DEBUG
    // Dev-only diagnostic (never traps, never changes the return value): surfaces window-
    // boundary mismatches — e.g. the timeline's day buffer and the month grid's window use
    // different spans — that would otherwise silently clamp with no signal anything was off.
    // Named for `blockIndex(for:)` because that is the only production path in; naming this
    // function would send the reader looking for a call site that does not exist.
    if rawIndex != clampedIndex {
        print("[CalendarMonthGrid] blockIndex(for:) resolved an out-of-window index (\(rawIndex)); the anchor date fell outside the month grid's \(CalendarMonthGridMetrics.totalMonths)-month buffer and was silently clamped to \(clampedIndex), a block that does not draw it.")
    }
    #endif
    return clampedIndex
}

func monthIndexForOffset(y: CGFloat, offsets: [CGFloat], totalMonths: Int) -> Int {
    let monthCount = min(offsets.count, max(totalMonths, 0))
    guard monthCount > 0 else { return 0 }

    var lo = 0
    var hi = monthCount - 1
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if offsets[mid] <= y { lo = mid } else { hi = mid - 1 }
    }
    return lo
}

/// The month that actually occupies most of the viewport, not merely the one that owns its
/// top pixel.
///
/// `monthIndexForOffset` answers "which month band contains this y", which is the right
/// question for a scroll position but the wrong one for a header: one pixel past a boundary
/// the top row belongs to the next month while the remaining ~95% of the screen is still the
/// previous one, and the header would rename the whole page after a nudge. Measuring overlap
/// makes the label flip when the screen actually changes hands.
///
/// A `viewportHeight` of zero (unmeasured geometry) degrades to the top-anchored answer.
func dominantMonthIndex(
    topY: CGFloat,
    viewportHeight: CGFloat,
    offsets: [CGFloat],
    totalMonths: Int
) -> Int {
    let monthCount = min(offsets.count, max(totalMonths, 0))
    guard monthCount > 0 else { return 0 }

    let top = max(topY, 0)
    guard viewportHeight > 0 else {
        return monthIndexForOffset(y: top, offsets: offsets, totalMonths: totalMonths)
    }

    let bottom = top + viewportHeight
    let first = monthIndexForOffset(y: top, offsets: offsets, totalMonths: totalMonths)
    let last = monthIndexForOffset(y: bottom, offsets: offsets, totalMonths: totalMonths)

    var best = first
    var bestOverlap = -CGFloat.greatestFiniteMagnitude
    for idx in first...last {
        let start = offsets[idx]
        let end = idx + 1 < monthCount ? offsets[idx + 1] : CGFloat.greatestFiniteMagnitude
        let overlap = min(bottom, end) - max(top, start)
        // Strictly greater, so an exact tie keeps the earlier month rather than jittering
        // between two equal halves.
        if overlap > bestOverlap {
            bestOverlap = overlap
            best = idx
        }
    }
    return best
}

enum CalendarMonthGridIdentifiers {
    static func month(_ index: Int) -> String {
        "month_\(index)"
    }

    static func day(monthIndex: Int, dateKey: String) -> String {
        "month_day_\(monthIndex)_\(dateKey)"
    }
}

/// Single source of truth for the month grid's window size and cell sizing.
/// Previously `totalMonths` (120), `todayMonthIdx`/`todayMonthIndex` (60), and
/// `cellHeight` (130) were each declared independently in `CalendarPageComponents.swift`,
/// `CalendarPageStateSupport.swift`, and `CalendarPageView.swift` — any future edit to one
/// without the others would silently desync the offset table from actual scroll position.
enum CalendarMonthGridMetrics {
    static let totalMonths = 120
    static let todayMonthIndex = 60

    /// Fallback row height, used only before the grid's viewport has been measured (the first
    /// layout pass reports a zero height). Real rows are sized by `rowHeight(weeksInMonth:_:)`.
    static let cellHeight: CGFloat = 130

    /// Floor for a week row. Below this a cell cannot show its day number plus a single chip,
    /// so a very short window scrolls instead of shrinking rows into illegibility.
    static let minimumRowHeight: CGFloat = 72

    /// Row height that divides the viewport evenly across *this* month's own week rows, so a
    /// month is exactly one screen tall: no dead band under a short month, no scrolling
    /// within a month.
    ///
    /// The grid tiles months without repeating days (a month block starts on its first Sunday
    /// and the days before it belong to the previous block), so a block is 4, 5, or 6 rows.
    /// Dividing by that count — rather than a fixed 6 — is what makes every month fill the
    /// window exactly.
    static func rowHeight(weeksInMonth: Int, viewportHeight: CGFloat) -> CGFloat {
        let weeks = CGFloat(max(1, weeksInMonth))
        guard viewportHeight > 0 else { return cellHeight }
        return max(minimumRowHeight, viewportHeight / weeks)
    }

    /// Rendered height of a whole month block. This is the *single* source of truth shared by
    /// the rendered rows and the scroll-offset table — see `CalendarMonthGridSupport
    /// .cumulativeOffsets`. Keeping one function on both sides is what prevents the two from
    /// drifting apart and mislabelling the header.
    static func monthHeight(weeksInMonth: Int, viewportHeight: CGFloat) -> CGFloat {
        let weeks = max(1, weeksInMonth)
        return CGFloat(weeks) * rowHeight(weeksInMonth: weeks, viewportHeight: viewportHeight)
    }
}

/// Vertical budget inside one month day cell.
///
/// The cell is now a fixed height (see `CalendarMonthGridMetrics.rowHeight`), so the chip cap
/// can no longer be a hardcoded `prefix(5)`: it has to be derived from the height the row was
/// actually given, or a short window would clip chips and a tall one would waste the space.
enum CalendarMonthCellLayout {
    /// 6pt top padding + the 24pt day-number circle.
    static let headerHeight: CGFloat = 30
    static let headerChipSpacing: CGFloat = 3
    static let chipHeight: CGFloat = 15
    static let chipSpacing: CGFloat = 2
    static let bottomPadding: CGFloat = 4
    /// Hollow completion circle on a task chip. Matches the task-row glyph elsewhere in the app.
    static let completionGlyphSize: CGFloat = 9

    /// How many chips fit in a row of `rowHeight`, ignoring any overflow label.
    static func chipCapacity(rowHeight: CGFloat) -> Int {
        let available = rowHeight - headerHeight - headerChipSpacing - bottomPadding
        guard available >= chipHeight else { return 0 }
        return max(0, Int((available + chipSpacing) / (chipHeight + chipSpacing)))
    }

    /// Splits a day's items into drawn chips and a "+N more" remainder.
    ///
    /// When there is overflow the label takes one chip slot (it is shorter than a chip, so it
    /// always fits where a chip would have), which keeps the cell inside its fixed height.
    static func chipLayout(totalItems: Int, rowHeight: CGFloat) -> (visible: Int, overflow: Int) {
        let capacity = chipCapacity(rowHeight: rowHeight)
        guard totalItems > capacity else { return (max(0, totalItems), 0) }
        let visible = max(0, capacity - 1)
        return (visible, totalItems - visible)
    }
}

/// How a month-grid day cell presents its own date.
///
/// Four states rather than two, and that is the whole point. The grid tiles months *without*
/// overlap — a block opens on its month's first Sunday and pads its final week from the next
/// month — so 1–6 days of the next month are drawn on this block, and one of them can perfectly
/// well be today. "Is today" and "belongs to another month" are independent facts, and a cell
/// has to be able to state both at once.
///
/// The failure this replaces: the label styling asked `isToday` first and returned early, so
/// today's cell was never dimmed even when it was a carried day on another month's page. On
/// Jun 3 2026 that produced a page headed "May 2026" showing two cells labelled "3" — May 3 in
/// the first row, Jun 3 in the last — with only the latter marked, and nothing on it saying why.
enum CalendarMonthDayEmphasis: Equatable {
    /// An ordinary day of the block's own month. Unchanged from before this state existed.
    case inMonth
    /// Today, drawn on its own month's page: the filled accent disc.
    case inMonthToday
    /// A day carried onto this block from the next month.
    case outOfMonth
    /// Today, carried onto this block from the next month — the case the old code could not say.
    case outOfMonthToday

    var isToday: Bool {
        self == .inMonthToday || self == .outOfMonthToday
    }

    var isOutOfMonth: Bool {
        self == .outOfMonth || self == .outOfMonthToday
    }
}

extension CalendarMonthDayEmphasis {
    /// How far `Theme.dim` is pulled back for a carried day. Named once so the day number and the
    /// month abbreviation beside it cannot drift apart.
    ///
    /// 0.50, down from 0.58. Composited on the carried plate (`Theme.bg`) that is #3d3d43 rather
    /// than #47474d — 1.84:1 against its own cell, down from 2.11:1 — while the in-month number
    /// stays `Theme.text` at 15.9:1. This is close to the floor, and deliberately so: Apple's own
    /// other-month numeral is `tertiaryLabelColor`, white at 0.25, which lands near 2.3:1 on its
    /// cell, so the label was never the part that was too bright and a darker one alone cannot buy
    /// the separation this grid was missing. Past here it stops being *grey* and starts being
    /// unreadable — 0.35 gives 1.45:1, at which a 12pt numeral no longer resolves. The band that
    /// reads at a glance is `cellBackground` below; this is the supporting half.
    private static let outOfMonthLabelOpacity: Double = 0.50
    /// Wash behind the cell on the page that owns today.
    private static let todayCellWashOpacity: Double = 0.04
    /// Stroke width of the hollow today marker used for a carried today.
    static let todayRingWidth: CGFloat = 1.5

    var dateLabelColor: Color {
        switch self {
        case .inMonth: return Theme.text
        // Reads against the filled disc, not against the cell.
        case .inMonthToday: return Theme.onColor
        case .outOfMonth: return Theme.dim.opacity(Self.outOfMonthLabelOpacity)
        // Not dimmed — dimming today would throw away the emphasis this cell has to keep. It
        // takes the accent's *own* colour instead of the accent's contrast colour, because there
        // is no filled disc behind it to contrast against.
        case .outOfMonthToday: return Theme.blue
        }
    }

    var dateLabelWeight: Font.Weight {
        switch self {
        case .inMonth: return .medium
        case .inMonthToday: return .bold
        case .outOfMonth: return .regular
        // One stop below the in-month today, so the two never read as equals in the same grid.
        case .outOfMonthToday: return .semibold
        }
    }

    /// Filled accent disc — today, on the page that owns it. `nil` everywhere else.
    var todayDiscFill: Color? {
        self == .inMonthToday ? Theme.blue : nil
    }

    /// Hollow accent ring — today, visiting from the next month.
    ///
    /// Filled vs hollow is the second half of the answer to "how does one cell say *today* and
    /// *not this month* at the same time": the marker is still unmistakably the today marker, in
    /// the same colour and the same place, but an outline instead of a solid reads as the
    /// lighter-weight version of it. Paired with the month abbreviation the cell now always
    /// carries, and the dropped-back plate under it, there is nothing left to confuse it with.
    var todayRingStroke: Color? {
        self == .outOfMonthToday ? Theme.blue : nil
    }

    /// Apple greys the whole out-of-month cell; this is that, in the app's own ramp — and the
    /// relationship is deliberately *inverted* rather than "paint the carried cells darker".
    ///
    /// `Theme.bg` is #09090b. There is no useful room below it, so the previous arrangement —
    /// in-month `bg` (#09090b) against out-of-month `surfaceRecessed` (#0d0d0f) — was four units
    /// on a near-black plate: invisible, and backwards, since the "recessed" stop is *lighter*
    /// than the page it was meant to sit under. Lifting the displayed month onto `Theme.surface`
    /// instead makes that month the page and lets the carried days fall back to the app
    /// background, which is a real step (L* 5.98 vs 2.51, a 2.4x luminance ratio, against L* 1.18
    /// the wrong way before) and needs no colour below black.
    ///
    /// It stops at `surface` rather than reaching higher on the ramp because the chips inside a
    /// cell are plated in `surfaceHover` — by definition the hover lift *for* `surface`. One stop
    /// further and the chips would read as holes punched into the cell instead of cards sitting
    /// on it, which trades one legibility problem for another.
    ///
    /// The carried plate covers a carried today too, so the "not this month" band is unbroken —
    /// the ring, not the backdrop, is what marks today there.
    var cellBackground: Color {
        switch self {
        case .inMonth, .inMonthToday: return Theme.surface
        case .outOfMonth, .outOfMonthToday: return Theme.bg
        }
    }

    /// Accent wash drawn *over* `cellBackground`, on the page that owns today. `nil` everywhere
    /// else.
    ///
    /// Split from the plate because today's cell now has to be both things at once: the raised
    /// in-month plate, so it stays visibly part of the displayed month, plus the wash that marks
    /// it. It used to be the wash *instead of* a plate, floating over whatever the grid happened
    /// to put behind the cell. Raising the plate makes the wash read more, not less — composited
    /// it is #15191f on the in-month #131316 (ΔL* 2.6), where before it was #0c0f15 on #09090b
    /// (ΔL* 1.8).
    var cellWash: Color? {
        self == .inMonthToday ? Theme.blue.opacity(Self.todayCellWashOpacity) : nil
    }
}

/// Resolves what a month-grid day cell says about its own date.
///
/// Pure and view-free so the labelling rule — the thing that actually removes the ambiguity —
/// can be tested without standing up a grid.
enum CalendarMonthDayLabelSupport {
    static func emphasis(
        for date: Date,
        displayMonth: Date,
        today: Date,
        calendar: Calendar
    ) -> CalendarMonthDayEmphasis {
        let isOutOfMonth = !calendar.isDate(date, equalTo: displayMonth, toGranularity: .month)
        let isToday = calendar.isDate(date, inSameDayAs: today)
        switch (isOutOfMonth, isToday) {
        case (false, false): return .inMonth
        case (false, true): return .inMonthToday
        case (true, false): return .outOfMonth
        case (true, true): return .outOfMonthToday
        }
    }

    /// Month abbreviation the cell must draw beside its day number, or `nil` when the page it is
    /// on already says which month it is.
    ///
    /// Apple's paged grid can rely on "the 1st is always drawn on its own month's page", so
    /// marking the 1st is enough to orient the reader. This grid tiles without overlap, so a
    /// month whose 1st is not a Sunday has its first 1–6 days drawn on the *previous* page and
    /// that guarantee is gone: a carried day only happened to name itself when it happened to be
    /// the 1st. Every day drawn outside its block's month therefore names its month — the same
    /// convention, adapted to a grid where the 1st is not a reliable landmark.
    ///
    /// Takes the already-resolved `emphasis` rather than re-deriving "is this out of month":
    /// the grid draws hundreds of these, and one month comparison per cell is enough.
    static func monthAbbreviation(
        for date: Date,
        emphasis: CalendarMonthDayEmphasis,
        calendar: Calendar
    ) -> String? {
        let day = calendar.component(.day, from: date)
        // The in-month 1st keeps the marker it has always had; out-of-month days all gain one.
        guard emphasis.isOutOfMonth || day == 1 else { return nil }

        // Month name taken from the same calendar the cell is measured in. A shared
        // `DateFormatter` carries the *system* zone, so a grid running in another calendar would
        // be the parse-in-one-zone/measure-in-another mistake again.
        let month = calendar.component(.month, from: date)
        let symbols = calendar.shortMonthSymbols
        guard month >= 1, month <= symbols.count else { return nil }
        return symbols[month - 1]
    }
}

struct MonthGridWeekdayHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .background(Theme.surface)
    }
}
#endif
