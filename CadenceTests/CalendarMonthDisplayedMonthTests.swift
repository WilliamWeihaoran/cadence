import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Which month the **macOS** month grid says you are looking at.
///
/// The grid stacks discrete month blocks, each one viewport-tall, and every block used to tint
/// against itself: half a block down you saw lit August rows, a dim stripe of August's carried
/// Sep 1–5, then lit September rows — two months lit at once. iOS's continuous grid has never had
/// that, because its tint comes from the scroll position rather than from which rows happen to be
/// drawn together, and the user asked for macOS to match it.
///
/// The fixture throughout is **August 2026**, which is the awkward one and therefore the useful
/// one. Aug 1 2026 is a Saturday, so August's block opens on Sunday Aug 2 and runs five rows to
/// Sep 5 — the first five days of September are drawn on August's page. September's own block
/// opens Sep 6 and is four rows. Two blocks, two different row counts, and a month boundary that
/// falls three quarters of the way through a row.
@MainActor
struct CalendarMonthDisplayedMonthTests {

    private static func gridCalendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    private static let viewportHeight: CGFloat = 600
    private static let totalMonths = 4
    private static let todayMonthIdx = 0

    private static func august2026(_ calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
    }

    private static func offsets(_ calendar: Calendar, from currentMonthStart: Date) -> [CGFloat] {
        CalendarMonthGridSupport.cumulativeOffsets(
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            viewportHeight: viewportHeight,
            calendar: calendar
        )
    }

    private static func displayedMonth(
        atTopY topY: CGFloat,
        calendar: Calendar,
        currentMonthStart: Date,
        // Spelled at every call site rather than defaulted: a default argument is evaluated in a
        // `nonisolated` context and this type is main-actor, which is a warning today and an error
        // in the Swift 6 language mode. The repo's warning baseline is zero on every scheme.
        viewportHeight: CGFloat
    ) -> Date {
        CalendarMonthGridSupport.displayedMonth(
            topY: topY,
            viewportHeight: viewportHeight,
            offsets: offsets(calendar, from: currentMonthStart),
            totalMonths: totalMonths,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: currentMonthStart,
            calendar: calendar
        )
    }

    private static func monthNumber(_ date: Date, _ calendar: Calendar) -> Int {
        calendar.component(.month, from: date)
    }

    // MARK: - The fixture is what it claims to be

    @Test func augustsBlockIsFiveRowsAndCarriesTheFirstFiveDaysOfSeptember() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)
        let september = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))

        #expect(CalendarMonthGridSupport.weeksInMonth(august, calendar: calendar) == 5)
        #expect(CalendarMonthGridSupport.weeksInMonth(september, calendar: calendar) == 4)

        let blockStart = CalendarMonthGridSupport.blockFirstDay(of: august, calendar: calendar)
        #expect(DateFormatters.dateKey(from: blockStart, calendar: calendar) == "2026-08-02")
        #expect(CalendarMonthGridSupport.leadingDaysRenderedInPreviousBlock(of: september, calendar: calendar) == 5)

        // Each block is exactly one viewport tall, which is what makes the offsets a clean table.
        #expect(Self.offsets(calendar, from: august) == [0, 600, 1200, 1800])
    }

    // MARK: - The behaviour the user asked for

    /// The whole grid re-tints as you scroll, and it does so **before** the block under the top of
    /// the viewport changes.
    ///
    /// Two rows down August's five-row block, more of what is on screen is September than August —
    /// the third row is already Aug 30 – Sep 5, and the two rows below it are September's own
    /// block. So the grid reads as September while the block being drawn at the top of the
    /// viewport is still August. That is precisely the case the old per-block tint could not
    /// express, because a block only ever knew its own month.
    @Test func theTintFollowsTheViewportAndFlipsInsideABlock() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)

        // Top of August's block: August.
        #expect(Self.monthNumber(Self.displayedMonth(atTopY: 0, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight), calendar) == 8)
        // One row down: still August.
        #expect(Self.monthNumber(Self.displayedMonth(atTopY: 120, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight), calendar) == 8)
        // Two rows down: September, while the top of the viewport is still inside August's block.
        let twoRowsDown = Self.displayedMonth(atTopY: 240, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight)
        #expect(Self.monthNumber(twoRowsDown, calendar) == 9)
        #expect(monthIndexForOffset(y: 240, offsets: Self.offsets(calendar, from: august), totalMonths: Self.totalMonths) == 0)

        // Top of September's own block: still September, so nothing flips back on the boundary.
        #expect(Self.monthNumber(Self.displayedMonth(atTopY: 600, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight), calendar) == 9)
    }

    /// The failure this replaces, stated as the thing that is now impossible: at a scroll position
    /// inside August's block, August's cells and September's cells cannot both be lit.
    ///
    /// The old grid gave every block its own month, so `emphasis` answered `.inMonth` for an
    /// August day on August's block *and* for a September day on September's block, at the same
    /// scroll position.
    @Test func onlyOneMonthIsLitAtAnyScrollPosition() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)
        let today = try #require(calendar.date(from: DateComponents(year: 1970, month: 1, day: 1)))

        let augustDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let septemberDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10)))
        let septemberBlock = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))

        // One mid-month day per block in the window, so "how many months are lit" is countable.
        let probes = try (7...11).map { month in
            try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: 15)))
        }

        for topY in stride(from: CGFloat(0), through: 1740, by: 30) {
            let tint = Self.displayedMonth(atTopY: topY, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight)
            let lit = probes.filter { probe in
                !CalendarMonthDayLabelSupport.emphasis(
                    for: probe, displayMonth: tint, today: today, calendar: calendar
                ).isOutOfMonth
            }
            #expect(lit.count == 1, "\(lit.count) months lit at topY \(topY)")
        }

        // And what the old arrangement did at the same moment: each block lit its own month, so
        // the two cells were both `.inMonth` on the one screen that showed both.
        #expect(
            CalendarMonthDayLabelSupport.emphasis(
                for: augustDay, displayMonth: august, today: today, calendar: calendar
            ) == .inMonth
        )
        #expect(
            CalendarMonthDayLabelSupport.emphasis(
                for: septemberDay, displayMonth: septemberBlock, today: today, calendar: calendar
            ) == .inMonth
        )
    }

    // MARK: - It is the shared rule, not a second copy of it

    /// **The point of this test: macOS must not grow its own middle-of-window arithmetic.**
    ///
    /// The rule — take the middle of the visible window, flip when half the rows have become the
    /// next month — lives in `CadenceCalendarMonthWindow.displayedMonth` and is what iOS reads.
    /// macOS's job is only to turn a scroll offset into that function's two arguments. So the
    /// answer is asserted against the shared helper called directly, at a scroll position where a
    /// locally reinvented rule would plausibly differ: two rows into August's block, where the top
    /// row's own month is August and the shared answer is September.
    ///
    /// Replacing the delegation with `monthStart(for: topRowStart)`, with the block's own month, or
    /// with any other "close enough" reading fails here.
    @Test func theDisplayedMonthIsTheSharedWindowHelpersAnswer() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)
        let blockStart = CalendarMonthGridSupport.blockFirstDay(of: august, calendar: calendar)

        for rowsScrolled in 0..<5 {
            let topRowStart = try #require(
                calendar.date(byAdding: .day, value: rowsScrolled * 7, to: blockStart)
            )
            let shared = CadenceCalendarMonthWindow.displayedMonth(
                topRowStart: topRowStart,
                // Five rows of 120pt fill the 600pt viewport.
                visibleRowCount: 5,
                calendar: calendar
            )
            let macOS = Self.displayedMonth(
                atTopY: CGFloat(rowsScrolled) * 120,
                calendar: calendar,
                currentMonthStart: august,
                viewportHeight: Self.viewportHeight
            )
            #expect(
                calendar.isDate(macOS, equalTo: shared, toGranularity: .month),
                "row \(rowsScrolled): macOS said \(Self.monthNumber(macOS, calendar)), shared said \(Self.monthNumber(shared, calendar))"
            )
        }

        // The row where the two readings of "which month" actually part company, spelled out so a
        // reimplementation cannot pass by accident: the top row is August's, the answer is not.
        let twoRowsDown = try #require(calendar.date(byAdding: .day, value: 14, to: blockStart))
        #expect(Self.monthNumber(twoRowsDown, calendar) == 8)
        #expect(Self.monthNumber(Self.displayedMonth(atTopY: 240, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight), calendar) == 9)
    }

    /// Nothing to measure yet: the block's own month, which is the right answer at the one moment
    /// it is asked — a block anchored to the top of an unmeasured viewport.
    @Test func anUnmeasuredViewportFallsBackToTheBlocksOwnMonth() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)

        #expect(
            Self.monthNumber(
                Self.displayedMonth(atTopY: 0, calendar: calendar, currentMonthStart: august, viewportHeight: 0),
                calendar
            ) == 8
        )
        // Overscroll above the first block clamps rather than reading off the front of the table.
        #expect(Self.monthNumber(Self.displayedMonth(atTopY: -400, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight), calendar) == 8)
        // An empty offset table has nothing to say and says the anchor month rather than crashing.
        #expect(
            CalendarMonthGridSupport.displayedMonth(
                topY: 240,
                viewportHeight: 600,
                offsets: [],
                totalMonths: 0,
                todayMonthIdx: 0,
                currentMonthStart: august,
                calendar: calendar
            ) == august
        )
    }

    @Test func theDisplayedMonthIsStableAcrossTimeZones() throws {
        for zone in ["America/New_York", "Asia/Shanghai", "UTC", "Pacific/Kiritimati"] {
            let calendar = Self.gridCalendar(zone)
            let august = try Self.august2026(calendar)
            #expect(Self.monthNumber(Self.displayedMonth(atTopY: 0, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight), calendar) == 8, "wrong at top in \(zone)")
            #expect(Self.monthNumber(Self.displayedMonth(atTopY: 240, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight), calendar) == 9, "wrong two rows down in \(zone)")
        }
    }

    // MARK: - The call site

    /// `handleScroll` is what `MonthGridView` actually calls on every scroll, and it is where the
    /// grid's tint month comes from. A scroll that only produced a block index — which is all this
    /// function used to produce — leaves the grid with nothing to tint against but the block.
    @Test func theScrollCallbackProducesTheTintMonthAndNotOnlyTheHeaderBlock() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)
        let offsets = Self.offsets(calendar, from: august)

        var visibleMonthIdx = 0
        var displayedMonth: Date?

        CalendarMonthGridInteractionSupport.handleScroll(
            y: 240,
            offsets: offsets,
            totalMonths: Self.totalMonths,
            viewportHeight: Self.viewportHeight,
            todayMonthIdx: Self.todayMonthIdx,
            currentMonthStart: august,
            calendar: calendar,
            visibleMonthIdx: &visibleMonthIdx,
            displayedMonth: &displayedMonth,
            didInitialPosition: true,
            isProgrammaticScroll: false
        )

        let tint = try #require(displayedMonth)
        #expect(Self.monthNumber(tint, calendar) == 9)
        // Exactly what the pure function says, so the callback cannot answer this its own way.
        #expect(
            calendar.isDate(
                tint,
                equalTo: Self.displayedMonth(atTopY: 240, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight),
                toGranularity: .month
            )
        )
    }

    /// The tint is under the same guard as the header: a scroll report that arrives while a
    /// programmatic jump is in flight names the offset the layout started at, and adopting it would
    /// flash the wrong month across the whole grid rather than across one label.
    @Test func aReportDuringAProgrammaticJumpTintsNothing() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)
        let offsets = Self.offsets(calendar, from: august)

        for (didInitialPosition, isProgrammatic) in [(false, false), (true, true), (false, true)] {
            var visibleMonthIdx = 0
            var displayedMonth: Date?
            CalendarMonthGridInteractionSupport.handleScroll(
                y: 1200,
                offsets: offsets,
                totalMonths: Self.totalMonths,
                viewportHeight: Self.viewportHeight,
                todayMonthIdx: Self.todayMonthIdx,
                currentMonthStart: august,
                calendar: calendar,
                visibleMonthIdx: &visibleMonthIdx,
                displayedMonth: &displayedMonth,
                didInitialPosition: didInitialPosition,
                isProgrammaticScroll: isProgrammatic
            )
            #expect(displayedMonth == nil)
            #expect(visibleMonthIdx == 0)
        }
    }

    /// The header reads the grid's displayed month, so the title and the highlight are one value.
    ///
    /// They were two, and the two rules flip about half a row apart: `dominantMonthIndex` measures
    /// which *block* fills most of the viewport, while the displayed month takes the middle *row*,
    /// and a block's last row is already mostly the next month. Two rows into August's block is
    /// inside that gap — the dominant block is still August and the grid is showing September.
    @Test func theTitleNamesTheMonthTheGridIsTinting() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)
        let offsets = Self.offsets(calendar, from: august)

        let dominantBlock = dominantMonthIndex(
            topY: 240,
            viewportHeight: Self.viewportHeight,
            offsets: offsets,
            totalMonths: Self.totalMonths
        )
        // The gap is real: the block reading and the month reading disagree here.
        #expect(dominantBlock == 0)
        let tint = Self.displayedMonth(atTopY: 240, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight)
        #expect(Self.monthNumber(tint, calendar) == 9)

        #expect(
            CalendarPageLifecycleSupport.calendarTitleLabel(
                viewMode: .month,
                visibleMonthIdx: CalendarMonthGridMetrics.todayMonthIndex,
                displayedMonth: tint,
                visibleTimelineDayIndex: nil,
                anchorDateKey: "",
                bufferStart: Date(),
                todayDayIdx: 0,
                calendar: calendar
            ) == DateFormatters.monthYear.string(from: tint)
        )
    }

    /// Before the grid has measured itself the block index is the fallback — the grid opens with a
    /// block anchored to the top of the viewport, where the two readings agree by construction.
    @Test func theTitleFallsBackToTheAnchoredBlockBeforeTheGridHasMeasuredItself() {
        let calendar = Self.gridCalendar()
        let todayIdx = CalendarMonthGridMetrics.todayMonthIndex

        #expect(
            CalendarPageLifecycleSupport.calendarTitleLabel(
                viewMode: .month,
                visibleMonthIdx: todayIdx,
                displayedMonth: nil,
                visibleTimelineDayIndex: nil,
                anchorDateKey: "",
                bufferStart: Date(),
                todayDayIdx: 0,
                calendar: calendar
            ) == CalendarPageStateSupport.visibleMonthLabel(visibleMonthIdx: todayIdx, calendar: calendar)
        )
    }

    // MARK: - What the tint must not take over

    /// The month abbreviation beside a day number stayed keyed to the **block**, not the tint.
    ///
    /// It exists because a block carries the 0–6 days before its successor's first Sunday, so the
    /// 1st is not a reliable landmark and a carried day has to name itself. That is true of exactly
    /// those days whatever the viewport is reading. Keying it to the displayed month instead would
    /// print "Aug" on all thirty-one August cells the moment the grid tipped into September — which
    /// is the noisiest possible way to answer a question the header already answers.
    @Test func theMonthAbbreviationStaysABlockFactNotATintFact() throws {
        let calendar = Self.gridCalendar()
        let august = try Self.august2026(calendar)

        let augustTwentieth = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let septemberSecond = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2)))

        // Both are drawn on August's block; only the carried one is out of it.
        #expect(!CalendarMonthDayLabelSupport.isCarried(augustTwentieth, ontoBlock: august, calendar: calendar))
        #expect(CalendarMonthDayLabelSupport.isCarried(septemberSecond, ontoBlock: august, calendar: calendar))

        #expect(
            CalendarMonthDayLabelSupport.monthAbbreviation(
                for: augustTwentieth,
                isCarriedOntoAnotherBlock: false,
                calendar: calendar
            ) == nil
        )
        #expect(
            CalendarMonthDayLabelSupport.monthAbbreviation(
                for: septemberSecond,
                isCarriedOntoAnotherBlock: true,
                calendar: calendar
            ) == calendar.shortMonthSymbols[8]
        )

        // The tint has flipped to September at this scroll position, and Aug 20 still says nothing.
        let tint = Self.displayedMonth(atTopY: 240, calendar: calendar, currentMonthStart: august, viewportHeight: Self.viewportHeight)
        #expect(Self.monthNumber(tint, calendar) == 9)
        let tintedEmphasis = CalendarMonthDayLabelSupport.emphasis(
            for: augustTwentieth,
            displayMonth: tint,
            today: try #require(calendar.date(from: DateComponents(year: 1970, month: 1, day: 1))),
            calendar: calendar
        )
        #expect(tintedEmphasis.isOutOfMonth)
        // The two inputs give opposite answers, which is the whole reason the cell takes the block
        // one: fed the tint, every August cell on screen would name its month.
        #expect(
            CalendarMonthDayLabelSupport.monthAbbreviation(
                for: augustTwentieth,
                isCarriedOntoAnotherBlock: tintedEmphasis.isOutOfMonth,
                calendar: calendar
            ) != CalendarMonthDayLabelSupport.monthAbbreviation(
                for: augustTwentieth,
                isCarriedOntoAnotherBlock: CalendarMonthDayLabelSupport.isCarried(
                    augustTwentieth,
                    ontoBlock: august,
                    calendar: calendar
                ),
                calendar: calendar
            )
        )
    }
}
