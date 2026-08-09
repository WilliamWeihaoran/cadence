#if os(macOS)
import SwiftUI

struct CalendarPageStateSupport {
    static let todayMonthIndex = CalendarMonthGridMetrics.todayMonthIndex

    /// `visibleMonthIdx` is a **block** index throughout the calendar page: it is what
    /// `handleScroll` writes (via `dominantMonthIndex`), what `handleAppear` scrolls to, and
    /// what the header is named from. Every write to it must therefore come from
    /// `blockIndex(for:)`, never from `monthIndex(for:)`.
    ///
    /// One consequence is deliberate: on a day before its month's first Sunday — Aug 1 2026,
    /// say — jumping to "today" anchors *July's* block, because that is the page the grid draws
    /// Aug 1 on, and so the header reads "July 2026" beside a highlighted cell labelled "Aug 1".
    /// The header names the page, and 27 of that page's 28 cells are July; renaming it August
    /// would misdescribe the other 96% of the screen, and would have to flip back to July the
    /// instant the reader nudged the scroll wheel. The cell itself carries the distinction —
    /// every day drawn outside the page's month is dimmed onto a recessed plate and names its own
    /// month, today included (see `CalendarMonthDayEmphasis`) — so nothing is ambiguous even when
    /// the marked cell is one of them. Keeping `visibleMonthIdx` a single, unambiguous
    /// block index is also what keeps `dateKeyForVisibleMonth` and the month -> timeline return
    /// path honest.
    static func visibleMonthLabel(visibleMonthIdx: Int, calendar: Calendar) -> String {
        let currentMonthStart: Date = {
            var comps = calendar.dateComponents([.year, .month], from: Date())
            comps.day = 1
            return calendar.date(from: comps) ?? Date()
        }()
        let month = calendar.date(byAdding: .month, value: visibleMonthIdx - todayMonthIndex, to: currentMonthStart) ?? Date()
        return DateFormatters.monthYear.string(from: month)
    }

    static func timelineDayIndex(
        anchorDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> Int {
        guard let anchorDate = DateFormatters.date(from: anchorDateKey, in: calendar) else { return todayDayIdx }
        let day = calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: anchorDate)).day ?? todayDayIdx
        return min(max(day, 0), calRenderDays - 1)
    }

    static func rememberedTimelineDayIndex(
        rememberedDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> Int {
        timelineDayIndex(
            anchorDateKey: rememberedDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: calendar
        )
    }

    static func monthIndexForTimelineAnchor(
        anchorDateKey: String,
        currentMonthStart: Date,
        todayMonthIdx: Int = todayMonthIndex,
        calendar: Calendar
    ) -> Int {
        // Parsed in the grid's own calendar, then measured with that same calendar — parsing a
        // key in the system zone and measuring it in another silently shifts a day.
        guard let anchorDate = DateFormatters.date(from: anchorDateKey, in: calendar) else { return todayMonthIdx }
        return blockIndex(
            for: anchorDate,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )
    }

    /// Index of the block that renders today — what "jump to today" and the grid's initial
    /// position should target.
    static func monthIndexForToday(
        todayMonthIdx: Int = todayMonthIndex,
        calendar: Calendar,
        today: Date = Date()
    ) -> Int {
        blockIndex(
            for: today,
            currentMonthStart: CalendarMonthGridSupport.currentMonthStart(calendar: calendar, reference: today),
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )
    }

    /// The date a block stands for when the reader leaves the month grid.
    ///
    /// Inverse of `blockIndex(for:)`, and it has to actually invert it: returning the 1st of the
    /// block's month would name a day the block does not draw whenever that month starts
    /// mid-week, so month -> week -> month would come back one block early. The block's first
    /// rendered day — its month's first Sunday — is both a true round trip and the first day the
    /// reader was actually looking at.
    static func dateKeyForVisibleMonth(
        visibleMonthIdx: Int,
        todayMonthIdx: Int = todayMonthIndex,
        currentMonthStart: Date,
        calendar: Calendar,
        today: Date = Date()
    ) -> String {
        // "You were on the page showing today" — asked of the block, not of the calendar month,
        // so the shortcut still fires on the days when those differ.
        let todayBlockIdx = blockIndex(
            for: today,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )
        if visibleMonthIdx == todayBlockIdx {
            return DateFormatters.dateKey(from: today, calendar: calendar)
        }

        let targetMonth = calendar.date(
            byAdding: .month,
            value: visibleMonthIdx - todayMonthIdx,
            to: currentMonthStart
        ) ?? currentMonthStart
        // Formatted with the grid's calendar, to match the `date(from:in:)` that reads it back.
        return DateFormatters.dateKey(
            from: CalendarMonthGridSupport.blockFirstDay(of: targetMonth, calendar: calendar),
            calendar: calendar
        )
    }

    static func boardAnchorDateKey(
        viewMode: CadenceCalendarViewMode,
        visibleMonthIdx: Int,
        visibleTimelineDayIndex: Int?,
        anchorDateKey: String,
        bufferStart: Date,
        currentMonthStart: Date,
        calendar: Calendar
    ) -> String {
        if viewMode == .month {
            return dateKeyForVisibleMonth(
                visibleMonthIdx: visibleMonthIdx,
                currentMonthStart: currentMonthStart,
                calendar: calendar
            )
        }

        if let visibleTimelineDayIndex,
           let visibleDate = calendar.date(byAdding: .day, value: visibleTimelineDayIndex, to: bufferStart) {
            return DateFormatters.dateKey(from: visibleDate)
        }

        return anchorDateKey
    }

    static func boardDateByMovingMonth(_ date: Date, by delta: Int, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        guard let shiftedMonth = calendar.date(byAdding: .month, value: delta, to: startOfDay) else {
            return startOfDay
        }

        var targetComponents = calendar.dateComponents([.year, .month], from: shiftedMonth)
        let currentDay = calendar.component(.day, from: startOfDay)
        let monthStart = calendar.date(from: targetComponents) ?? shiftedMonth
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        targetComponents.day = min(currentDay, dayRange?.count ?? currentDay)

        return calendar.startOfDay(for: calendar.date(from: targetComponents) ?? shiftedMonth)
    }

    /// Day-index form of `dateKeyForVisibleMonth`, expressed through it rather than beside it —
    /// a second copy of "which day does this block stand for" is a second chance to disagree
    /// with the grid.
    static func timelineDayIndexForMonthViewReturn(
        visibleMonthIdx: Int,
        todayMonthIdx: Int = todayMonthIndex,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar,
        today: Date = Date()
    ) -> Int {
        let targetKey = dateKeyForVisibleMonth(
            visibleMonthIdx: visibleMonthIdx,
            todayMonthIdx: todayMonthIdx,
            currentMonthStart: monthStart(for: today, calendar: calendar),
            calendar: calendar,
            today: today
        )
        return timelineDayIndex(
            anchorDateKey: targetKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: calendar
        )
    }

    static func restoreTimelineScrollIfNeeded(
        didRestoreTimelineScroll: inout Bool,
        rememberedScrollHour: Int,
        anchorDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        visibleTimelineDayIndex: inout Int?,
        visibleTimelineHour: inout Int?,
        vProxy: ScrollViewProxy,
        hProxy: ScrollViewProxy,
        setHorizontalRestoring: @escaping (Bool) -> Void,
        setVerticalRestoring: @escaping (Bool) -> Void
    ) {
        guard !didRestoreTimelineScroll else { return }

        let currentHour = Calendar.current.component(.hour, from: Date())
        let fallbackHour = max(calStartHour, currentHour - 1)
        let scrollHour = rememberedScrollHour >= calStartHour ? rememberedScrollHour : fallbackHour
        let targetDay = rememberedTimelineDayIndex(
            rememberedDateKey: anchorDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: Calendar.current
        )

        didRestoreTimelineScroll = true
        setHorizontalRestoring(true)
        setVerticalRestoring(true)
        visibleTimelineDayIndex = targetDay
        visibleTimelineHour = scrollHour

        DispatchQueue.main.async {
            hProxy.scrollTo("day_\(targetDay)", anchor: .leading)
            vProxy.scrollTo("tl_\(scrollHour)", anchor: .top)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                setHorizontalRestoring(false)
                setVerticalRestoring(false)
            }
        }
    }

    static func schedulePersistence<T: Equatable>(
        value: T,
        cancelPending: () -> Void,
        storePending: @escaping (DispatchWorkItem?) -> Void,
        delay: TimeInterval = 0.12,
        persist: @escaping (T) -> Void
    ) {
        cancelPending()
        let workItem = DispatchWorkItem {
            persist(value)
            storePending(nil)
        }
        storePending(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    static func timelineJumpTarget(
        request: CalendarNavigationManager.Request,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> (day: Int, hour: Int) {
        let day = min(max(
            calendar.dateComponents([.day], from: bufferStart, to: calendar.startOfDay(for: DateFormatters.date(from: request.dateKey, in: calendar) ?? Date())).day ?? todayDayIdx,
            0
        ), calRenderDays - 1)
        let hour = min(max(request.preferredHour - 1, calStartHour), calEndHour - 1)
        return (day, hour)
    }
}
#endif
