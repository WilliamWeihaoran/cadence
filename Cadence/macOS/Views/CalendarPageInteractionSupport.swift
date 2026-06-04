#if os(macOS)
import SwiftUI

struct CalendarTimelineJumpTarget: Equatable {
    let dateKey: String
    let dayIndex: Int
    let hour: Int
}

enum CalendarPageInteractionSupport {
    static func persistVisibleTimelineDay(
        dayIndex: Int,
        calendar: Calendar,
        bufferStart: Date,
        cancelPending: () -> Void,
        storePending: @escaping (DispatchWorkItem?) -> Void,
        persist: @escaping (String) -> Void
    ) {
        let date = calendar.date(byAdding: .day, value: dayIndex, to: bufferStart) ?? Date()
        let dateKey = DateFormatters.dateKey(from: date)
        CalendarPageStateSupport.schedulePersistence(
            value: dateKey,
            cancelPending: cancelPending,
            storePending: storePending,
            persist: persist
        )
    }

    static func persistVisibleTimelineHour(
        hour: Int,
        cancelPending: () -> Void,
        storePending: @escaping (DispatchWorkItem?) -> Void,
        persist: @escaping (Int) -> Void
    ) {
        CalendarPageStateSupport.schedulePersistence(
            value: hour,
            cancelPending: cancelPending,
            storePending: storePending,
            persist: persist
        )
    }

    static func applyExternalCalendarJump(
        request: CalendarNavigationManager.Request,
        calendar: Calendar,
        bufferStart: Date,
        todayDayIdx: Int,
        visibleTimelineDayIndex: inout Int?,
        visibleTimelineHour: inout Int?,
        externalJumpDayIndex: inout Int?,
        externalJumpHour: inout Int?,
        externalJumpToken: inout UUID?,
        anchorDateKey: inout String,
        clearRequest: () -> Void
    ) {
        let target = externalTimelineJumpTarget(
            request: request,
            calendar: calendar,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx
        )
        applyTimelineJump(
            target,
            token: request.token,
            visibleTimelineDayIndex: &visibleTimelineDayIndex,
            visibleTimelineHour: &visibleTimelineHour,
            externalJumpDayIndex: &externalJumpDayIndex,
            externalJumpHour: &externalJumpHour,
            externalJumpToken: &externalJumpToken,
            anchorDateKey: &anchorDateKey
        )
        clearRequest()
    }

    static func todayTimelineJumpTarget(
        now: Date = Date(),
        calendar: Calendar,
        bufferStart: Date,
        todayDayIdx: Int
    ) -> CalendarTimelineJumpTarget {
        let startOfToday = calendar.startOfDay(for: now)
        let day = min(max(
            calendar.dateComponents([.day], from: bufferStart, to: startOfToday).day ?? todayDayIdx,
            0
        ), calRenderDays - 1)
        let preferredHour = calendar.component(.hour, from: now) - 1
        let hour = min(max(preferredHour, calStartHour), calEndHour - 1)

        return CalendarTimelineJumpTarget(
            dateKey: DateFormatters.dateKey(from: startOfToday, calendar: calendar),
            dayIndex: day,
            hour: hour
        )
    }

    static func externalTimelineJumpTarget(
        request: CalendarNavigationManager.Request,
        calendar: Calendar,
        bufferStart: Date,
        todayDayIdx: Int
    ) -> CalendarTimelineJumpTarget {
        let target = CalendarPageStateSupport.timelineJumpTarget(
            request: request,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: calendar
        )

        return CalendarTimelineJumpTarget(
            dateKey: request.dateKey,
            dayIndex: target.day,
            hour: target.hour
        )
    }

    static func applyTimelineJump(
        _ target: CalendarTimelineJumpTarget,
        token: UUID?,
        visibleTimelineDayIndex: inout Int?,
        visibleTimelineHour: inout Int?,
        externalJumpDayIndex: inout Int?,
        externalJumpHour: inout Int?,
        externalJumpToken: inout UUID?,
        anchorDateKey: inout String
    ) {
        anchorDateKey = target.dateKey
        visibleTimelineDayIndex = target.dayIndex
        visibleTimelineHour = target.hour
        externalJumpDayIndex = target.dayIndex
        externalJumpHour = target.hour
        externalJumpToken = token
    }
}
#endif
