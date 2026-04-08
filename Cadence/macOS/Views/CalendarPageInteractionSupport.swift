#if os(macOS)
import SwiftUI

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
        rememberedDateKey: inout String,
        timelineScrollState: CalendarTimelineScrollState,
        clearRequest: () -> Void
    ) {
        rememberedDateKey = request.dateKey
        let target = CalendarPageStateSupport.timelineJumpTarget(
            request: request,
            bufferStart: bufferStart,
            todayDayIdx: todayDayIdx,
            calendar: calendar
        )
        visibleTimelineDayIndex = target.day
        visibleTimelineHour = target.hour
        externalJumpDayIndex = target.day
        externalJumpHour = target.hour
        externalJumpToken = request.token
        timelineScrollState.jumpHeaderOffset(to: -CGFloat(target.day) * max(1, calTimeWidth))
        clearRequest()
    }
}
#endif
