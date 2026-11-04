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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    /// The week row at the top of the grid — read as "which month am I looking at", written to jump.
    @Binding var topRowDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let eventsByDate: [String: [EKEvent]]
    /// The page's observed day ([[T-5010]]), handed to every cell's today mark.
    let todayKey: String

    private let calendar = Calendar.current
    /// The event a chip opened, while its editor is up ([[T-8725]]). The month agenda beside this
    /// grid owns its editor the same way; a cell cannot, because a cell is rebuilt the moment the
    /// grid's query moves and would take its own sheet down with it.
    @State private var selectedEvent: iOSCalendarEventSelection?
    /// The band was 36 here and 22 in `iOSCalendarMonthStack`, for the same row of the same grid.
    /// One figure now; the reasoning for which of the two survived is on the constant.
    private var weekdayHeaderHeight: CGFloat { CadenceCalendarWeekdayHeaderMetrics.bandHeight + iOSCalendarTypographyMetrics.lineGain(CadenceCalendarWeekdayHeaderMetrics.labelSize, at: dynamicTypeSize, scaling: scaling) }

    var body: some View {
        GeometryReader { proxy in
            let rowHeight = max(
                iOSCalendarMonthMetrics.minimumCellHeight + 5 * iOSCalendarTypographyMetrics.lineGain(10, at: dynamicTypeSize, scaling: scaling) + iOSCalendarTypographyMetrics.lineGain(12, at: dynamicTypeSize, scaling: scaling),
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
                    events: CadenceScheduleSupport.items(on: key, in: eventsByDate),
                    todayKey: todayKey,
                    minHeight: rowHeight,
                    onOpenEvent: { selectedEvent = iOSCalendarEventSelection(event: $0) }
                ) {
                    selectedDate = date
                }
            }
        }
        .background(Theme.bg)
        // A chip opens its event here, in the grid, for the reason `selectedEvent` records.
        .sheet(item: $selectedEvent) { selection in
            iOSCalendarEventEditSheet(event: selection.event)
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
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
        GeometryReader { viewport in
            ScrollView(.horizontal) {
                grid
                    .frame(width: max(viewport.size.width, 7 * iOSCalendarTypographyMetrics.monthColumnWidth(at: dynamicTypeSize, scaling: scaling)))
            }
        }
    }

    private var grid: some View {
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
                    .cadenceFont(.metadata, base: CadenceCalendarWeekdayHeaderMetrics.labelSize, weight: .semibold)
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

/// What a Month-grid chip does when it is drawn in a band that opens its items ([[T-8725]]).
///
/// The Week band's `iOSCalendarAllDayChipOpen` is the same four modifiers for the same reason, and
/// is private to its own file and pinned there verbatim by a source census; this is deliberately
/// not a rename of it. `nil` leaves the chip exactly as it was — which is what the reserved,
/// hidden copy inside the select-the-day `Button` wants.
private struct iOSCalendarMonthChipOpen: ViewModifier {
    let onOpen: (() -> Void)?

    func body(content: Content) -> some View {
        if let onOpen {
            content
                .contentShape(Rectangle())
                .onTapGesture { onOpen() }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onOpen() }
        } else {
            content
        }
    }
}

private struct iOSCalendarMonthDayCell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.cadenceTypographyScaling) private var scaling
    let date: Date
    let displayMonth: Date
    let isSelected: Bool
    let tasks: [AppTask]
    let events: [EKEvent]
    /// The grid's observed day ([[T-5010]]) — the cell's today badge and wash compare against it.
    let todayKey: String
    let minHeight: CGFloat
    /// Opens a chip's event in the grid's one editor ([[T-8725]]). **Declared before `action`**,
    /// because the grid hands `action` as a trailing closure and that binds to whichever parameter
    /// the memberwise initialiser puts last — the same ordering rule
    /// `iOSCalendarTimelineDayHeader` records for its own opener.
    let onOpenEvent: (EKEvent) -> Void
    let action: () -> Void
    // T-201's rule: the page's `iOSTaskInspectorHost` presents, this cell does not. A cell in a
    // scrolling month grid is rebuilt whenever the day's tasks move, so a sheet it owned would go
    // down with it the first time the panel completed the task.
    @Environment(\.iOSTaskInspector) private var taskInspector

    private let calendar = Calendar.current
    private var isToday: Bool { DateFormatters.dateKey(from: date) == todayKey }
    private var isCurrentMonth: Bool { calendar.isDate(date, equalTo: displayMonth, toGranularity: .month) }
    /// The scrolling grid fixes each week to `minHeight`. Timed event chips now use a second
    /// line so a clock never steals the title's width; reserve the day header and overflow line
    /// before allocating the same events-first order the shared priority helper uses.
    private static let maximumChipCount = 5

    private var chipCapacity: Int {
        let heights = events.prefix(Self.maximumChipCount).map {
            iOSCalendarMiniChip.height(hasTime: timeLabel(for: $0) != nil, at: dynamicTypeSize, scaling: scaling)
        } + tasks.prefix(Self.maximumChipCount).map {
            iOSCalendarMiniChip.height(hasTime: taskTimeLabel(for: $0) != nil, at: dynamicTypeSize, scaling: scaling)
        }
        var used: CGFloat = 0
        var count = 0
        for height in heights.prefix(Self.maximumChipCount) {
            let next = used + (count == 0 ? 0 : 3) + height
            guard next <= max(0, minHeight - (50 + iOSCalendarTypographyMetrics.lineGain(12, at: dynamicTypeSize, scaling: scaling) + iOSCalendarTypographyMetrics.lineGain(9, at: dynamicTypeSize, scaling: scaling))) else { break }
            used = next
            count += 1
        }
        return count
    }

    /// The Mac's month-chip rule through the one shared helper ([[T-8723]]): start time on the
    /// first day, `ends <time>` on the last, nothing between. The compact `9a` face is gated on
    /// COMPACT WIDTH -- a 393 pt iPhone month column -- so an iPad's regular-width grid draws the
    /// Mac's `9 AM`.
    private func timeLabel(for event: EKEvent) -> String? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        let lastInstant = end.addingTimeInterval(-1)
        func minutes(_ instant: Date) -> Int {
            calendar.component(.hour, from: instant) * 60 + calendar.component(.minute, from: instant)
        }
        return CalendarEventChipTimeSupport.label(
            isAllDay: event.isAllDay,
            isMultiDayTimedEvent: !calendar.isDate(start, inSameDayAs: lastInstant),
            isFirstSegment: calendar.isDate(start, inSameDayAs: date),
            isLastSegment: calendar.isDate(lastInstant, inSameDayAs: date),
            eventStartMin: minutes(start),
            eventEndMin: minutes(end),
            compact: horizontalSizeClass == .compact
        )
    }

    /// A timed task's start through the same shared helper and the same compact-width face as
    /// the event chip above it ([[T-8044]]); an untimed task draws no time line.
    private func taskTimeLabel(for task: AppTask) -> String? {
        CalendarEventChipTimeSupport.taskLabel(
            scheduledDate: task.scheduledDate,
            scheduledStartMin: task.scheduledStartMin,
            dayKey: DateFormatters.dateKey(from: date),
            compact: horizontalSizeClass == .compact
        )
    }

    /// Who gets those slots. The ordering is `CadenceCalendarMonthCellPriority`'s and is shared
    /// with macOS's `MonthDayCell`; it replaces three hardcoded per-kind caps that spelled the same
    /// events-before-tasks intent without ever stating it, and that macOS had drifted the other way
    /// from.
    ///
    /// This cell ranks two kinds of item. It passed `bundles: 0` until [[T-3170]]'s trio pass took
    /// macOS's `MonthBundleChip`, which was the last caller of that leg on either platform — so
    /// the parameter is gone from the shared function rather than left taking a literal zero from
    /// both cells.
    private var split: CadenceCalendarMonthCellPriority.Split {
        CadenceCalendarMonthCellPriority.split(
            events: events.count,
            tasks: tasks.count,
            capacity: chipCapacity
        )
    }

    private var visibleEvents: [EKEvent] { Array(events.prefix(split.events)) }
    private var visibleTasks: [AppTask] { Array(tasks.prefix(split.tasks)) }
    private var overflow: Int { split.hidden }

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
        case .onFill: return Theme.onColor(for: Theme.blue)
        }
    }

    private var dateLabelWeight: Font.Weight {
        if badge.isEmphasized { return .bold }
        return isCurrentMonth ? .medium : .regular
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                dateHeaderRow
                // **Reserved, not drawn** ([[T-8725]]). The chips a person sees are the ones in
                // `chipBand` below, which is drawn OVER this Button rather than inside its label:
                // a tap inside a button's label is arbitrated against the button's own gesture and
                // may lose, while a chip drawn over it is simply the topmost hit-testable thing at
                // that point. That is how the Week band's header already opens its chips, and this
                // placeholder is the same two subviews in the same order at the same spacing, so
                // the two stacks cannot drift apart into two layouts.
                chipStack(opens: false)
                    .hidden()

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background {
                cellPlate
                if let cellWash { cellWash }
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
        .overlay(alignment: .topLeading) { chipBand }
        // The count capsule this cell draws, and the selection its blue border draws. Neither
        // reached VoiceOver: the sibling agenda cell had the trait and this one did not, in the
        // same grid, off the same tap (T-573).
        .accessibilityLabel(
            CadenceCalendarDayAccessibility.countedDayLabel(date: date, isToday: isToday, itemCount: itemCount)
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // `.contain`, not `.combine`: the select-the-day button and each openable chip are
        // separate elements, and a combined cell would fold them into one that VoiceOver can only
        // select the day from. The Week band's day header is `.contain` for the same reason.
        .accessibilityElement(children: .contain)
    }

    /// The day number and the count capsule — the one row of the cell a chip is never drawn over.
    private var dateHeaderRow: some View {
        // No month abbreviation beside the 1st. The toolbar heading names the month, and
        // now that it is derived from the middle of the visible window rather than from the
        // top row it names the month the grid is actually showing — so a cell repeating it
        // was the second answer to a question already answered, in the one place with the
        // least room for it. (macOS keeps its abbreviation, for a reason that does not
        // apply here: its grid tiles discrete month blocks, so a day can be drawn on
        // another month's page and needs to say so. These rows are one continuous run.)
        HStack(spacing: 6) {
            Text(DateFormatters.dayNumber.string(from: date))
                .cadenceFont(.metadata, base: 12, weight: dateLabelWeight)
                .foregroundStyle(dateLabelColor)
                .frame(width: 25 + iOSCalendarTypographyMetrics.lineGain(12, at: dynamicTypeSize, scaling: scaling), height: 25 + iOSCalendarTypographyMetrics.lineGain(12, at: dynamicTypeSize, scaling: scaling))
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
                    .cadenceFont(.metadata, base: 9, weight: .bold)
                    .foregroundStyle(Theme.dim)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(height: 18 + iOSCalendarTypographyMetrics.lineGain(9, at: dynamicTypeSize, scaling: scaling))
                    .background(Theme.surfaceElevated.opacity(0.52))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 7)
    }

    /// The chips a person sees and taps, drawn ABOVE the select-the-day `Button` ([[T-8725]]).
    ///
    /// It reproduces the Button's own stack exactly — the same `dateHeaderRow`, the same
    /// `chipStack`, the same 5pt spacing and the same frame — with the half it does not own
    /// hidden, so the chips land precisely on the space reserved for them whatever the text size
    /// does to the day badge. There is no second layout and no offset figure to keep in step.
    private var chipBand: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The day number's space. A tap on the day number belongs to the Button underneath,
            // and a hidden view is not hit-tested, so this reserves the height and takes nothing.
            dateHeaderRow
                .hidden()

            chipStack(opens: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }

    /// The day's chips, events first, then the overflow line.
    ///
    /// **`opens` is the whole difference between the two copies**: the reserved one inside the
    /// Button draws the same shapes and takes no taps (it is `.hidden()` anyway), and the one in
    /// `chipBand` opens its item. A chip that opens is the Mac's Month behaviour
    /// (`calendarTaskChipInteractions`, `calendarEventChipEditor`) and iOS's own Week band's; this
    /// cell wrapped everything in one select-the-day `Button`, so tapping "Dentist" selected the
    /// date and opened nothing ([[T-8725]], under [[T-8201]]).
    private func chipStack(opens: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(visibleEvents, id: \.calendarItemIdentifier) { event in
                iOSCalendarMiniChip(
                    title: iOSCalendarEventSupport.title(for: event),
                    icon: event.isAllDay ? "calendar" : "calendar.badge.clock",
                    color: iOSCalendarEventSupport.color(for: event.calendar),
                    isEvent: true,
                    timeLabel: timeLabel(for: event)
                )
                .modifier(iOSCalendarMonthChipOpen(onOpen: opens ? { onOpenEvent(event) } : nil))
            }
            ForEach(visibleTasks) { task in
                iOSCalendarMiniChip(
                    title: TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle),
                    icon: "circle.fill",
                    color: Color(hex: task.containerColor),
                    timeLabel: taskTimeLabel(for: task),
                    completion: .resolve(task: task),
                    // [[T-8243]]: the cell's own observed day, not a fresh clock read inside each
                    // chip, so every chip in the grid turns over at the midnight the badges do.
                    dueDateKey: task.dueDate,
                    todayKey: todayKey,
                    // [[T-10821]]: the iPad's regular-width cell has the room the Mac's does.
                    dueMarkerDayKey: dueMarkerDayKey
                )
                .modifier(iOSCalendarMonthChipOpen(onOpen: opens ? { taskInspector(task) } : nil))
            }
            if overflow > 0 {
                // **The one line in the band that still selects the day.** It names no item, so
                // there is nothing for it to open; the hidden items are read in the month detail
                // pane, which is the path this cell has always offered for them. Taking no hit
                // lets the tap reach the Button underneath, exactly as it did before.
                Text(CadenceTaskSurfaceOptions.moreLabel(hidden: overflow))
                    .cadenceFont(.metadata, base: 9, weight: .semibold)
                    .foregroundStyle(Theme.subdued)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 6)
    }

    /// Exactly what the count capsule shows — one number, read once.
    private var itemCount: Int { tasks.count + events.count }

    /// This cell's day for the due marker, or `nil` where the column is too narrow to draw one
    /// ([[T-10821]]) -- the shared width rule, fed the size class the time labels above already read.
    private var dueMarkerDayKey: String? {
        CalendarChipDueMarkerSupport.drawsMarker(isCompactWidth: horizontalSizeClass == .compact)
            ? DateFormatters.dateKey(from: date)
            : nil
    }

    /// **The plate is what says "not this month" now (T-568)** — the shape macOS's month grid
    /// settled on, and the reason it can avoid a cell-wide `.opacity`, which would fade the today
    /// ring and the event chips along with the day number.
    ///
    /// Every cell here used to be `Theme.bg` and the carried ones were faded on top of it. The
    /// displayed month is lifted onto `Theme.surface` instead and the carried days fall back to the
    /// app background, which is a real step (#131316 against #09090b) and needs no colour below
    /// black. It stops at `surface` rather than climbing further because `iOSCalendarMiniChip`
    /// plates itself in its own object's colour — one stop more and the chips would read as holes
    /// punched into the cell instead of cards sitting on it.
    ///
    /// The plate answers one question only — which month is this day in — so it is split from the
    /// accent wash below rather than being the same `Color` property answering both. It had to be:
    /// a single property returning the wash *instead of* the plate would have made a today carried
    /// in from the next month indistinguishable from an in-month one, which is the fact the whole
    /// change is about.
    private var cellPlate: Color {
        isCurrentMonth ? Theme.surface : Theme.bg
    }

    /// Today's accent, drawn *over* whichever plate the cell has, so a today carried in from the
    /// next month keeps the carried plate — the "not this month" band stays unbroken, which is
    /// `CalendarMonthDayEmphasis.cellBackground`'s rule too.
    ///
    /// **Selection is not here (T-603).** This cell used to state one fact with three layers at two
    /// radii: a square-cornered `Theme.blue.opacity(0.075)` fill across the whole cell, a
    /// `Theme.radiusControl` ring inset 4pt over it, *and* the solid badge behind the day number
    /// that `CadenceCalendarDayBadge.selected` already specifies. The badge is the layer that
    /// survives, which is the one hover/selection layer at one radius the repo asks for — and it is
    /// the convergent answer as well as the minimal one: `iOSCalendarMonthCompactDayCell` beside it
    /// already marks selection with the badge alone, so the two grids in this feature no longer
    /// disagree about what a tapped day looks like.
    private var cellWash: Color? {
        isToday ? Theme.blue.opacity(0.045) : nil
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

/// The compact chip a month cell or a timeline day header draws per item.
///
/// **Both branches are solved plates now (T-3160); what differs is which treatment.** An `isEvent`
/// chip takes `CadenceCalendarEventStyle.rail*` — Apple Calendar's dark tinted plate with the
/// title in the calendar's own hue — and what Cadence owns, a task, takes
/// `plate*`, the bright luminance-solved fill with `Theme.onColor` ink that an event wore here
/// until this ticket. The two are still as far apart as they were, which is the point: before any
/// of this an event chip was washed exactly like a task, so a day full of events and a day full of
/// tasks looked the same at a glance.
///
/// The flag is `isEvent` rather than the old `isEventPlate`, because after the swap an event is
/// the one thing on this chip that is *not* wearing the plate treatment and a name that says
/// otherwise is a trap for the next reader.
///
/// **No rail here either** — see `MonthEventChip` on macOS for the measurement. The one-line
/// form remains 17pt tall, clipped to `Theme.radiusControl`; its leading edge is mostly corner.
/// T-1468 gives timed month events a second line (29pt total) but keeps the same treatment across
/// both forms. The clock has its own width, so adding it never takes space from the title.
///
/// The icon is each family's *tertiary* tier in both branches rather than the object's own colour.
/// It has to be: the plate is now that colour, so a list-coloured glyph on a list-coloured fill is
/// invisible. A glyph owes the 3:1 non-text bar, which both tertiary tiers are solved to hold.
///
/// **Which ROW the icon sits on is `CadenceCalendarChipGlyphRow`'s decision, not this view's**
/// ([[T-3311]]). A chip that draws a time line puts the glyph there and gives the title row the
/// whole cell — in the iPad month grid's ~115pt cell that is the difference between "Dee…" and a
/// readable title. A one-line chip has nowhere to move it to and keeps it where it was.
struct iOSCalendarMiniChip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let title: String
    let icon: String
    let color: Color
    var isEvent = false
    var timeLabel: String? = nil

    static func height(hasTime: Bool, at size: DynamicTypeSize = .large, scaling: CadenceTypographyScaling = .fixed) -> CGFloat {
        iOSCalendarTypographyMetrics.chipHeight(hasTime: hasTime, at: size, scaling: scaling)
    }
    /// **"Not placed on the clock yet", which is a different axis from "event or task"** (T-3184's
    /// sibling, T-3185).
    ///
    /// The iOS day-header strip carries all-day EVENTS beside UNSCHEDULED TASKS since T-3163.
    /// T-3160's rail-vs-plate says which of the two *kinds* a chip is, and says it well; what
    /// nothing said is *spans the whole day* against *has no time yet*, so "Buy milk" sat beside
    /// "Company offsite" reading as an all-day commitment. The owner ruled that the two are to be
    /// set apart by an icon **and** other attributes — more than one channel, not colour alone —
    /// and explicitly not by re-using the rail, which already means "event".
    ///
    /// So this flag turns on **two** channels at once, and neither is the rail:
    ///
    /// 1. The caller passes `circle.dashed` where it passed `circle.fill`. That glyph is already
    ///    the app's word for a thing with nothing assigned to it — `HabitsView`'s "Unassigned",
    ///    `GoalPickerViews`' "None", `iOSTimelineDraftCreate`'s not-yet-created task — so this is a
    ///    vocabulary that exists rather than one invented at this size. The all-day event keeps
    ///    `calendar`, which `iOSCalendarMonthDayCell` already uses to mean all-day against the
    ///    `calendar.badge.clock` it gives a timed one.
    /// 2. The chip's **own rim** goes dashed. This is the channel that survives the size: the chip
    ///    is a 10pt line plus 2.5pt of padding, about **17pt** tall against a `Theme.radiusControl`
    ///    of 10 — the measurement that rules a 3pt rail out entirely, because at that radius the
    ///    leading edge is corner from end to end. A 1pt outline is not a bar at the leading edge,
    ///    it is the whole perimeter, which on a strip-width chip is a couple of hundred points of
    ///    line and tens of dash periods. It also says the same thing the glyph says, which is what
    ///    makes the pair read as one idea rather than two decorations.
    var isUnscheduled = false
    /// **A task's completion, which the chip used to be handed only as an icon** ([[T-8241]]).
    ///
    /// Before this the chip had no done input at all: the caller swapped `icon` to a check and the
    /// chip drew it grey, at full title weight, where macOS's chips draw a green check and drop the
    /// title one tier. `icon` is now the OPEN glyph; the settled glyph, its tint and the title tier
    /// are `CadenceCalendarTaskDoneStyle`'s, the same decision macOS's `MonthTaskChip` and
    /// `AllDayTaskChip` read. `nil` is an event, or a task chip drawn without a state.
    var completion: CadenceTaskCompletionState? = nil
    /// **The task's deadline, so an OPEN chip's circle can carry its urgency** ([[T-8243]]).
    ///
    /// macOS tints an open chip glyph red when the task is overdue and amber when it is due today;
    /// every open glyph here was one flat `plateTertiaryLabelColor()`, so an iPhone chip said
    /// nothing about a deadline the same chip on the Mac shouted about. Nothing about touch
    /// explains that, which is [[T-8201]]'s test, and the rule both now read is
    /// `CadenceCalendarTaskDoneStyle.chipGlyphTint(for:dueDateKey:todayKey:open:)`.
    ///
    /// Empty -- the default, and what an event chip passes -- means no deadline, and the glyph
    /// keeps the neutral tier it always had. The chip takes the KEY rather than the task because
    /// it is handed events too, and an event has no task to read it from.
    ///
    /// **macOS's SECOND due-date channel draws only where the chip is wide enough** ([[T-10821]]).
    /// That one is `CalendarChipDueMarker`, a 9pt date drawn after the title and given layout
    /// priority OVER it. On the owner's 393pt iPhone a seven-column grid leaves a column about
    /// 56pt wide and the title already down to a few characters, so a marker that wins the width
    /// contest would leave no title at all. That is a screen-width reason, the kind [[T-8201]]
    /// accepts, and it is why a compact-width chip carries the tint alone -- which costs no width
    /// whatever. A regular-width chip (the iPad month cell, the iPad week band) has the width, so
    /// it draws the marker the Mac draws; the host decides through
    /// `CalendarChipDueMarkerSupport.drawsMarker(isCompactWidth:)` and says so with `dueMarkerDayKey`.
    var dueDateKey: String = ""
    /// The surface's observed day ([[T-5010]]), so a chip left on screen past midnight re-tints
    /// with the grid around it instead of holding yesterday's red.
    var todayKey: String = DateFormatters.todayKey()
    /// The `yyyy-MM-dd` day this chip is drawn on, when its host has the width for the due marker
    /// ([[T-10821]]); `nil` -- the default, and every compact-width host's -- draws no marker. The
    /// marker needs the day because it names the deadline only when the chip is NOT on it.
    var dueMarkerDayKey: String? = nil

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    /// 2pt on, 2pt off. Short enough that the chip's end curve — which at this height is the whole
    /// of the leading edge — carries four or five periods rather than reading as one broken line,
    /// and the repo's existing dashes ([5, 4], [6, 5]) are scaled to drop targets many times this
    /// size rather than to a 17pt chip.
    private static let unscheduledDash: [CGFloat] = [2, 2]

    private var rimStyle: StrokeStyle {
        StrokeStyle(lineWidth: 1, dash: isUnscheduled ? Self.unscheduledDash : [])
    }

    private var plate: Color {
        isEvent
            ? CadenceCalendarEventStyle.railChipFill(for: color)
            : CadenceCalendarEventStyle.plateChipFill(for: color)
    }

    /// The rim carries the rail's own solved colour on an event, so a near-black calendar still
    /// has a visible edge — `railColor` is floored at `railMinimumLuminance`, the raw hue is not.
    /// A task keeps its raw list colour, which is already bright enough to rim the brighter plate.
    private var rim: Color {
        isEvent ? CadenceCalendarEventStyle.railColor(for: color) : color
    }

    /// Where this chip's glyph goes, and therefore which row is left to the title alone
    /// ([[T-3311]]). The rule is `CadenceCalendarChipGlyphRow`'s, not this view's — see it for why
    /// the glyph moved and what it was moved over.
    private var glyphRow: CadenceCalendarChipGlyphRow {
        CadenceCalendarChipGlyphRow.forChip(hasTimeLine: timeLabel != nil)
    }

    /// 4pt, and the same number on whichever row carries the glyph, so moving it between the two
    /// cannot also move how far the row's text starts from its icon.
    private static let glyphSpacing: CGFloat = 4

    private var openGlyphTint: Color {
        isEvent
            ? CadenceCalendarEventStyle.railTertiaryLabelColor(for: color)
            : CadenceCalendarEventStyle.plateTertiaryLabelColor()
    }

    /// An event carries no completion and no deadline, so it keeps the flat tier; a task's glyph
    /// is the shared settled-then-urgency ladder over that same tier ([[T-8243]]).
    private var glyphTint: Color {
        guard let completion else { return openGlyphTint }
        return CadenceCalendarTaskDoneStyle.chipGlyphTint(
            for: completion,
            dueDateKey: dueDateKey,
            todayKey: todayKey,
            open: openGlyphTint
        )
    }

    private var glyph: some View {
        Image(systemName: completion.map { CadenceCalendarTaskDoneStyle.chipGlyphSymbol(for: $0, open: icon) } ?? icon)
            .cadenceFont(.metadata, base: 8, weight: .semibold)
            .foregroundStyle(glyphTint)
    }

    private var titleInk: Color {
        if let completion, CadenceCalendarTaskDoneStyle.dimsTitle(for: completion) {
            return CadenceCalendarEventStyle.plateSecondaryLabelColor()
        }
        return isEvent
            ? CadenceCalendarEventStyle.railTitleColor(for: color)
            : CadenceCalendarEventStyle.platePrimaryLabelColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            titleRow
            if let timeLabel {
                HStack(spacing: Self.glyphSpacing) {
                    if glyphRow == .time { glyph }
                    Text(timeLabel)
                        .cadenceFont(.metadata, base: 8, weight: .medium)
                        // A task's clock sits on the plate, not the rail ([[T-8044]]).
                        .foregroundStyle(
                            isEvent
                                ? CadenceCalendarEventStyle.railSecondaryLabelColor(for: color)
                                : CadenceCalendarEventStyle.plateSecondaryLabelColor()
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(scaling == .enabled && dynamicTypeSize > .large ? 1 : 0.8)
                        // The clock keeps the 2pt of optical overhang it has always had; the glyph
                        // beside it does not, so the two rows' leading edges still line up.
                        .padding(.leading, glyphRow == .time ? 0 : -2)
                        .padding(.trailing, -2)
                }
            }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: iOSCalendarTypographyMetrics.chipHeight(hasTime: timeLabel != nil, at: dynamicTypeSize, scaling: scaling))
        .background { shape.fill(plate) }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                rim.opacity(CadenceCalendarEventStyle.chipBorderOpacity()),
                style: rimStyle
            )
        }
    }

    private var titleRow: some View {
        HStack(spacing: Self.glyphSpacing) {
            if glyphRow == .title { glyph }
            Text(title)
                .cadenceFont(.metadata, base: 10, weight: .medium)
                .foregroundStyle(titleInk)
                .lineLimit(1)
            if let dueMarkerDayKey, let completion {
                // An event has no completion and no deadline, so it never reaches here. `isDone`
                // is the Mac's `task.isDone` -- done, not cancelled -- read off the same state.
                CalendarChipDueMarker(
                    dueDateKey: dueDateKey,
                    dayKey: dueMarkerDayKey,
                    todayKey: todayKey,
                    isDone: completion == .done
                )
            }
        }
    }
}
#endif
