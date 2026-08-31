#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// The month grid at full size — the cell that lists what each day holds, on a pane wide enough to
/// place a detail column beside it.
///
/// It scrolls vertically and without end. It used to be exactly the 4/5/6 week rows of one month,
/// rebuilt by the toolbar's `‹ ›`; the last week of August and the first of September were two
/// chevron presses and a full redraw apart, on the one surface where "what does the turn of the
/// month look like" is the obvious question.
struct iOSCalendarMonthGrid: View {
    /// The week row at the top of the grid — read as "which month am I looking at", written to jump.
    @Binding var topRowDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]

    private let calendar = Calendar.current
    /// The band was 36 here and 22 in `iOSCalendarMonthStack`, for the same row of the same grid.
    /// One figure now; the reasoning for which of the two survived is on the constant.
    private var weekdayHeaderHeight: CGFloat { CadenceCalendarWeekdayHeaderMetrics.bandHeight }

    var body: some View {
        GeometryReader { proxy in
            let rowHeight = max(
                iOSCalendarMonthMetrics.minimumCellHeight,
                (proxy.size.height - weekdayHeaderHeight) / CGFloat(CadenceCalendarMonthWindow.visibleRowCount)
            )

            iOSCalendarMonthScrollingGrid(
                topRowDate: $topRowDate,
                rowHeight: rowHeight,
                weekdayHeaderHeight: weekdayHeaderHeight
            ) { date, displayMonth in
                let key = DateFormatters.dateKey(from: date)
                iOSCalendarMonthDayCell(
                    date: date,
                    displayMonth: displayMonth,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    tasks: CadenceScheduleSupport.items(on: key, in: monthTasksByDate),
                    bundles: CadenceScheduleSupport.items(on: key, in: bundlesByDate),
                    events: CadenceScheduleSupport.items(on: key, in: eventsByDate),
                    minHeight: rowHeight
                ) {
                    selectedDate = date
                }
            }
        }
        .background(Theme.bg)
    }
}

/// A month grid that scrolls vertically through a wide run of week rows, with the weekday header
/// pinned above it.
///
/// One container for both cells — the full-size one above and the compact one under
/// `iOSCalendarMonthStack` — because what differs between them is a cell, and the scroll machinery is
/// the part that is easy to get subtly wrong. This repo has now had five scroll-position bugs of one
/// shape (`ecaf80f`, `8a316c4`, `68d78ec`, and one found mid-flight in `cf785a8`); a second copy of
/// this would be the place the sixth came from.
///
/// The machinery is the Board's, turned ninety degrees:
///
/// - **`.scrollPosition(id:)` over a `LazyVStack` of week rows**, not an offset computed by hand.
///   The id resolves the position, so a row height that changes under it — a rotation, the shell
///   sidebar folding — moves no dates, and there is no second spelling of "index × height" to keep in
///   step with the first.
/// - **`cadenceLazyScrollAnchor` re-asserts that position once the stack reports it has laid out.**
///   A `@State` seeded before the rows exist is not a scroll position; the first build of this view
///   proved it again, opening Month on the first row of its window — **four years** behind the anchor,
///   the same distance and the same cause as `ecaf80f`. See `CadenceLazyScrollAnchor`.
/// - **Nothing is adopted before that assertion lands.** The position a scroll view reports before
///   this view has placed itself is whatever the layout started at, and adopting it writes a month
///   the user never chose into persisted state.
/// - **The window slides** when the top row nears either end of the rendered run, which is what makes
///   "without end" true rather than merely large — but never *during* a scroll, unless the run is
///   about to be exhausted. See `CadenceCalendarMonthWindow.recenterTiming`, and `isScrolling` below.
struct iOSCalendarMonthScrollingGrid<Cell: View>: View {
    @Binding var topRowDate: Date
    let rowHeight: CGFloat
    let weekdayHeaderHeight: CGFloat
    /// The cell for one day, given the month the grid is currently *reading as* — which is what
    /// decides whether the cell is dimmed as a neighbouring month's.
    @ViewBuilder let cell: (Date, Date) -> Cell

    /// The week row at the top of the scroll view — both the position it is *set* to and the one it
    /// reports back. Seeded, because a seed makes the first frame right where it can be; the anchor
    /// modifier is what makes it right where it cannot.
    @State private var scrolledRowIndex: Int? = CadenceCalendarMonthWindow.leadingRowCount
    @State private var windowStart: Date?
    @State private var didPlaceInitialRow = false
    /// Latches a `topRowDate` write this view made itself, so the change coming back does not
    /// re-scroll the grid under the finger that caused it. The timed grid and the Board carry the
    /// same latch.
    @State private var isReportingTopRow = false
    /// Whether the scroll view says it is moving — `ScrollPhase.isScrolling`, so a drag, its
    /// momentum, and a programmatic animation all read as `true` and idle reads as `false`.
    ///
    /// This is the gate on recentring, and it is a **signal**: the transition to idle is the scroll
    /// view reporting that it has stopped, which is the thing a settle delay was only ever guessing
    /// at. `CadenceLazyScrollAnchor` records what the guess cost (`ecaf80f`: a 0.08s guard that
    /// expired before the settle arrived and wrote a garbage day into persisted state), and the
    /// same objection would apply to any timer put here.
    @State private var isScrolling = false

    private let calendar = Calendar.current

    private var activeWindowStart: Date {
        windowStart ?? CadenceCalendarMonthWindow.windowStart(for: topRowDate, calendar: calendar)
    }

    /// The row `topRowDate` sits at in the window as it currently stands. Re-read every pass, so the
    /// one-shot assertion uses the date at first layout rather than one from `init`.
    private var targetIndex: Int {
        CadenceCalendarMonthWindow.index(for: topRowDate, windowStart: activeWindowStart, calendar: calendar)
    }

    private var displayMonth: Date {
        CadenceCalendarMonthWindow.displayedMonth(topRowStart: topRowDate, calendar: calendar)
    }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            // **Not built until the row height is real.** `iOSCalendarMonthStack` derives its row
            // height from a `GeometryReader`, whose first pass reports a height of zero — and
            // `gridRowHeight` answers zero to that. A `LazyVStack` of 420 zero-height rows has zero
            // content, so `.scrollPosition(id:)` resolves the seeded row to offset 0, the scroll view
            // reports row 0 back, and that reading becomes the anchor: Month opened four years behind
            // itself, twice, before this guard. Deferring the scroll view by one layout pass means
            // its very first render already has rows with heights for the id to resolve against.
            if rowHeight > 0 {
                rows
            } else {
                Color.clear
            }
        }
        .onAppear { alignWindow(to: topRowDate) }
        .onChange(of: topRowDate) { _, newDate in
            if isReportingTopRow {
                isReportingTopRow = false
                return
            }
            alignWindow(to: newDate, animated: true)
        }
    }

    /// `Sun Mon Tue` over the columns.
    ///
    /// The size was a `weekdaySymbolSize` parameter this grid's two callers disagreed about — the
    /// agenda took the default 10, the full month passed 11 — so one view drew the same row at two
    /// sizes, and the timed grid's day header cited "the month grid" as the reason for *its* 11.
    /// One figure now, in `CadenceCalendarWeekdayHeaderMetrics`. Title-case here, so it takes the
    /// size and not the kerning; see that type. `docs/TODO.md` T-277.
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(CadenceScheduleSupport.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: CadenceCalendarWeekdayHeaderMetrics.labelSize, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
                    .frame(height: weekdayHeaderHeight)
            }
        }
        .background(Theme.surface)
    }

    private var rows: some View {
        let month = displayMonth

        return ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<CadenceCalendarMonthWindow.renderRowCount, id: \.self) { index in
                    weekRow(at: index, displayMonth: month)
                        .frame(height: rowHeight)
                        .id(index)
                }
            }
            // Directly on the lazy stack, so the ids `scrollPosition` resolves are the week rows.
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledRowIndex, anchor: .top)
        .cadenceLazyScrollAnchor($scrolledRowIndex, target: targetIndex, axis: .vertical)
        // The settle, from the scroll view itself. A recentre deferred during a fling is performed
        // here, on the transition to idle — so a deferral that would otherwise never be redeemed
        // cannot leave the grid parked near the end of its rendered run.
        .onScrollPhaseChange { _, phase in
            guard phase.isScrolling != isScrolling else { return }
            isScrolling = phase.isScrolling
            guard !isScrolling else { return }
            recenterWindowIfOwed()
        }
        .onChange(of: scrolledRowIndex) { _, index in
            guard let index else { return }
            // The first reading this view believes is the one that **confirms its own assertion**;
            // everything before it is the position the layout happened to start at, and adopting
            // that writes a month the user never chose into persisted state. This surface did it
            // twice while being built. `cadenceLazyScrollAnchor` guarantees the confirmation
            // arrives: it re-drives the binding once the stack reports it has laid out.
            //
            // The rule now lives in `CadenceLazyScrollAnchor.report` because the timed grid needed
            // it too — see T-70.
            switch CadenceLazyScrollAnchor.report(
                index,
                target: targetIndex,
                hasConfirmedPlacement: didPlaceInitialRow
            ) {
            case .ignore:
                return
            case .confirmsPlacement:
                didPlaceInitialRow = true
            case .adopt:
                adoptTopRow(index)
            }
        }
    }

    private func weekRow(at index: Int, displayMonth: Date) -> some View {
        let start = CadenceCalendarMonthWindow.date(at: index, windowStart: activeWindowStart, calendar: calendar)
        return HStack(spacing: 0) {
            ForEach(0..<CadenceCalendarMonthWindow.daysPerRow, id: \.self) { offset in
                let date = calendar.startOfDay(
                    for: calendar.date(byAdding: .day, value: offset, to: start) ?? start
                )
                cell(date, displayMonth)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Window and scroll placement

    /// Rebuilds the rendered run around `date` and puts that week at the top.
    ///
    /// Setting `scrolledRowIndex` is both the request and, once SwiftUI honours it, the report — so
    /// the no-op guard matters: re-assigning the row the grid is already on would bounce back through
    /// `adoptTopRow` on every anchor change.
    private func alignWindow(to date: Date, animated: Bool = false) {
        let start = CadenceCalendarMonthWindow.windowStart(for: date, calendar: calendar)
        let target = CadenceCalendarMonthWindow.index(for: date, windowStart: start, calendar: calendar)
        windowStart = start
        guard scrolledRowIndex != target else { return }
        if animated {
            withAnimation(.snappy(duration: 0.22)) { scrolledRowIndex = target }
        } else {
            scrolledRowIndex = target
        }
    }

    private func adoptTopRow(_ index: Int) {
        guard didPlaceInitialRow else { return }
        let date = CadenceCalendarMonthWindow.date(at: index, windowStart: activeWindowStart, calendar: calendar)
        if !calendar.isDate(date, inSameDayAs: topRowDate) {
            isReportingTopRow = true
            topRowDate = date
        }
        recenterWindowIfNeeded(topIndex: index, topDate: date)
    }

    /// Re-asks the question for wherever the grid currently sits. Called on the scroll settling,
    /// where `isScrolling` is `false` and a deferred recentre therefore resolves to `.now`.
    private func recenterWindowIfOwed() {
        guard let index = scrolledRowIndex else { return }
        let date = CadenceCalendarMonthWindow.date(at: index, windowStart: activeWindowStart, calendar: calendar)
        recenterWindowIfNeeded(topIndex: index, topDate: date)
    }

    /// Rebuilds the rendered run around the top row — the expensive half of this view, and the
    /// reason it is gated.
    ///
    /// Assigning `windowStart` re-dates all `renderRowCount` rows and then the scroll position is
    /// written to the row's new index; doing that inside a scroll callback relayouts the stack and
    /// reassigns the position underneath live momentum. `recenterTiming` is what says whether this
    /// moment is one where that is acceptable.
    private func recenterWindowIfNeeded(topIndex index: Int, topDate date: Date) {
        switch CadenceCalendarMonthWindow.recenterTiming(topIndex: index, isScrolling: isScrolling) {
        case .none, .whenScrollSettles:
            return
        case .now:
            break
        }

        guard let start = CadenceCalendarMonthWindow.recenteredWindowStart(
            topIndex: index,
            topDate: date,
            currentWindowStart: activeWindowStart,
            calendar: calendar
        ) else { return }

        windowStart = start
        scrolledRowIndex = CadenceCalendarMonthWindow.index(for: date, windowStart: start, calendar: calendar)
    }
}

private struct iOSCalendarMonthDayCell: View {
    let date: Date
    let displayMonth: Date
    let isSelected: Bool
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let events: [EKEvent]
    let minHeight: CGFloat
    let action: () -> Void

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var isCurrentMonth: Bool { calendar.isDate(date, equalTo: displayMonth, toGranularity: .month) }
    private var visibleBundles: [TaskBundle] { Array(bundles.prefix(3)) }
    private var visibleEvents: [EKEvent] { Array(events.prefix(max(0, 4 - visibleBundles.count))) }
    private var visibleTasks: [AppTask] { Array(tasks.prefix(max(0, 5 - visibleBundles.count - visibleEvents.count))) }
    private var overflow: Int { max(0, tasks.count + bundles.count + events.count - visibleTasks.count - visibleBundles.count - visibleEvents.count) }

    /// `MonthCalendarPanel`'s treatment, via `CadenceCalendarDayBadge` — this cell used to have it
    /// inverted, giving today the solid fill and the selection the wash.
    private var badge: CadenceCalendarDayBadge {
        CadenceCalendarDayBadge.style(isToday: isToday, isSelected: isSelected)
    }

    /// **One dimming layer for a carried day, at the value macOS measured (T-568).**
    ///
    /// This cell used to dim a neighbouring month's day three separate times — 0.58 here, 0.18→0.08
    /// on the badge behind the numeral, and `.opacity(0.52)` on the cell as a whole — and SwiftUI
    /// multiplies them, so the 12pt number landed at 0.30 against a floor of 0.35 that
    /// `CadenceCalendarDayBadge.outOfMonthLabelOpacity` records the contrast maths for. The other
    /// two layers are gone; this is the only one left.
    private var dateLabelColor: Color {
        switch badge.label {
        case .normal:
            return isCurrentMonth
                ? Theme.text
                : Theme.dim.opacity(CadenceCalendarDayBadge.outOfMonthLabelOpacity)
        case .accent: return Theme.blue
        case .onFill: return Theme.onColor
        }
    }

    private var dateLabelWeight: Font.Weight {
        if badge.isEmphasized { return .bold }
        return isCurrentMonth ? .medium : .regular
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                // No month abbreviation beside the 1st. The toolbar heading names the month, and
                // now that it is derived from the middle of the visible window rather than from the
                // top row it names the month the grid is actually showing — so a cell repeating it
                // was the second answer to a question already answered, in the one place with the
                // least room for it. (macOS keeps its abbreviation, for a reason that does not
                // apply here: its grid tiles discrete month blocks, so a day can be drawn on
                // another month's page and needs to say so. These rows are one continuous run.)
                HStack(spacing: 6) {
                    Text(DateFormatters.dayNumber.string(from: date))
                        .font(.system(size: 12, weight: dateLabelWeight))
                        .foregroundStyle(dateLabelColor)
                        .frame(width: 25, height: 25)
                        .background(dateBadgeFill)
                        .clipShape(Circle())
                        .overlay {
                            // Today, when it is also the selected day. Both take the solid fill, so
                            // without this the "today" marker disappears the moment you tap it.
                            if badge.showsTodayRing {
                                Circle()
                                    .strokeBorder(Theme.blue, lineWidth: 1.5)
                                    .padding(-2.5)
                            }
                        }

                    Spacer(minLength: 0)

                    // The same `itemCount` the accessibility label reads, so the capsule and the
                    // announcement cannot state two numbers.
                    if itemCount > 0 {
                        Text("\(itemCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Theme.surfaceElevated.opacity(0.52))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 7)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleBundles) { bundle in
                        iOSCalendarMiniChip(
                            title: bundle.displayTitle,
                            icon: "tray.full.fill",
                            color: Theme.amber
                        )
                    }
                    ForEach(visibleEvents, id: \.calendarItemIdentifier) { event in
                        iOSCalendarMiniChip(
                            title: iOSCalendarEventSupport.title(for: event),
                            icon: event.isAllDay ? "calendar" : "calendar.badge.clock",
                            color: iOSCalendarEventSupport.color(for: event.calendar),
                            isEventPlate: true
                        )
                    }
                    ForEach(visibleTasks) { task in
                        iOSCalendarMiniChip(
                            title: TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle),
                            icon: task.isDone ? "checkmark.circle.fill" : "circle.fill",
                            color: Color(hex: task.containerColor)
                        )
                    }
                    if overflow > 0 {
                        Text(CadenceTaskSurfaceOptions.moreLabel(hidden: overflow))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.subdued)
                            .padding(.horizontal, 5)
                    }
                }
                .padding(.horizontal, 6)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background {
                cellPlate
                if let cellWash { cellWash }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .strokeBorder(Theme.blue.opacity(0.65), lineWidth: 1.5)
                        .padding(4)
                }
            }
            // One cell, one weight. These two edges drew 0.30 and 0.42 — see
            // `iOSCalendarHairlineMetrics`, which is also where the timed canvas's column edge now
            // reads from, because a day ruled off from the next day is the same line in both.
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(iOSCalendarHairlineMetrics.dayEdgeOpacity))
                    .frame(width: iOSCalendarHairlineMetrics.width)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(iOSCalendarHairlineMetrics.dayEdgeOpacity))
                    .frame(height: iOSCalendarHairlineMetrics.width)
            }
        }
        .buttonStyle(.iosPressable)
        // The count capsule this cell draws, and the selection its blue border draws. Neither
        // reached VoiceOver: the sibling agenda cell had the trait and this one did not, in the
        // same grid, off the same tap (T-573).
        .accessibilityLabel(
            CadenceCalendarDayAccessibility.countedDayLabel(date: date, itemCount: itemCount)
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Exactly what the count capsule shows — one number, read once.
    private var itemCount: Int { tasks.count + bundles.count + events.count }

    /// **The plate is what says "not this month" now (T-568)** — the shape macOS's month grid
    /// settled on, and the reason it can avoid a cell-wide `.opacity`, which would fade the today
    /// ring and the event chips along with the day number.
    ///
    /// Every cell here used to be `Theme.bg` and the carried ones were faded on top of it. The
    /// displayed month is lifted onto `Theme.surface` instead and the carried days fall back to the
    /// app background, which is a real step (#131316 against #09090b) and needs no colour below
    /// black. It stops at `surface` rather than climbing further because `iOSCalendarMiniChip`
    /// plates itself in `Theme.surfaceElevated` — one stop more and the chips would read as holes
    /// punched into the cell instead of cards sitting on it.
    ///
    /// The plate answers one question only — which month is this day in — so it is split from the
    /// accent wash below rather than being the same `Color` property answering both. It had to be:
    /// a single property returning the wash *instead of* the plate would have made a selected
    /// carried day indistinguishable from a selected in-month one, which is the fact the whole
    /// change is about.
    private var cellPlate: Color {
        isCurrentMonth ? Theme.surface : Theme.bg
    }

    /// Today's and the selection's accent, drawn *over* whichever plate the cell has. So a today
    /// carried in from next month keeps the carried plate and is marked by its ring instead — the
    /// "not this month" band stays unbroken, which is `CalendarMonthDayEmphasis.cellBackground`'s
    /// rule too.
    private var cellWash: Color? {
        if isSelected { return Theme.blue.opacity(0.075) }
        if isToday { return Theme.blue.opacity(0.045) }
        return nil
    }

    private var dateBadgeFill: Color {
        switch badge.fill {
        // Not dimmed for a carried day. It was 0.18 in-month against 0.08 out, which was the
        // second of the three multiplied layers T-568 removed — and the numeral's own dimming is
        // the layer that survives, so this one was pulling the plate out from under it as well.
        case .none:  return Theme.surfaceElevated.opacity(0.18)
        case .wash:  return Theme.blue.opacity(CadenceCalendarDayBadge.washOpacity)
        case .solid: return Theme.blue
        }
    }
}

/// The one-line chip a month cell or a timeline day header draws per item.
///
/// `isEventPlate` gives a calendar event the solved plate of its own calendar colour — the same
/// treatment macOS's month grid gives an event chip — while tasks and bundles keep a wash of their
/// list colour over the neutral surface. Before, an event chip was washed like a task, so a day
/// full of events and a day full of tasks looked the same at a glance.
struct iOSCalendarMiniChip: View {
    let title: String
    let icon: String
    let color: Color
    var isEventPlate = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(isEventPlate ? CadenceCalendarEventStyle.tertiaryLabelColor() : color)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isEventPlate ? CadenceCalendarEventStyle.primaryLabelColor : Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isEventPlate {
                shape.fill(CadenceCalendarEventStyle.chipFill(for: color))
            } else {
                ZStack {
                    shape.fill(Theme.surfaceElevated.opacity(0.82))
                    shape.fill(color.opacity(0.16))
                }
            }
        }
        .clipShape(shape)
        .overlay {
            if isEventPlate {
                shape.strokeBorder(color.opacity(CadenceCalendarEventStyle.chipBorderOpacity()), lineWidth: 1)
            }
        }
    }
}
#endif
