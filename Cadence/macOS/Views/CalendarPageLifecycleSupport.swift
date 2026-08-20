#if os(macOS)
import SwiftUI

enum CalendarPageLifecycleSupport {
    /// The title over the calendar.
    ///
    /// In Month it is the grid's **displayed month** — the same single value every cell in the grid
    /// is tinted against, reported back by `MonthGridView`. The header and the highlight are
    /// therefore one answer by construction, which is the arrangement iOS has always had
    /// (`iOSCalendarView.displayedMonth` feeds both its toolbar title and its cells).
    ///
    /// They were two before, and the two rules do not agree: the block index comes from
    /// `dominantMonthIndex`, which measures which *block* fills most of the viewport, and the
    /// displayed month comes from `CadenceCalendarMonthWindow.displayedMonth`, which takes the
    /// middle *row*. A block carries the 0–6 days before its successor's first Sunday, so its last
    /// row is already mostly the next month — and the two therefore flip about half a row apart,
    /// roughly a tenth of every month scrolled. Half a row is small; a header naming a month the
    /// grid has visibly stopped highlighting is not.
    ///
    /// `nil` before the grid has measured itself, where the block index is the right fallback: the
    /// grid opens with a block anchored to the top of the viewport, and there the block's own month
    /// *is* the displayed month.
    ///
    /// `visibleMonthIdx` keeps every other job it had. It is still a block index, still written
    /// only from `blockIndex(for:)`, and still what the grid is scrolled to and what the month →
    /// timeline return path inverts — see `CalendarPageStateSupport`. Only the label moved.
    static func calendarTitleLabel(
        viewMode: CadenceCalendarViewMode,
        visibleMonthIdx: Int,
        displayedMonth: Date?,
        visibleTimelineDayIndex: Int?,
        anchorDateKey: String,
        bufferStart: Date,
        todayDayIdx: Int,
        calendar: Calendar
    ) -> String {
        if viewMode == .month {
            guard let displayedMonth else {
                return CalendarPageStateSupport.visibleMonthLabel(
                    visibleMonthIdx: visibleMonthIdx,
                    calendar: calendar
                )
            }
            return DateFormatters.monthYear.string(from: displayedMonth)
        }

        let dayIndex = visibleTimelineDayIndex ?? CalendarPageStateSupport.timelineDayIndex(
            anchorDateKey: anchorDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: calendar
        )
        let visibleDate = calendar.date(byAdding: .day, value: dayIndex, to: bufferStart) ?? Date()
        return DateFormatters.monthYear.string(from: visibleDate)
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
        CalendarPageStateSupport.restoreTimelineScrollIfNeeded(
            didRestoreTimelineScroll: &didRestoreTimelineScroll,
            rememberedScrollHour: rememberedScrollHour,
            anchorDateKey: anchorDateKey,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            visibleTimelineDayIndex: &visibleTimelineDayIndex,
            visibleTimelineHour: &visibleTimelineHour,
            vProxy: vProxy,
            hProxy: hProxy,
            setHorizontalRestoring: setHorizontalRestoring,
            setVerticalRestoring: setVerticalRestoring
        )
    }
}
#endif
