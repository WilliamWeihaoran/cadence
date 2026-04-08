#if os(macOS)
import SwiftUI

enum CalendarMonthGridInteractionSupport {
    static func handleScroll(
        y: CGFloat,
        offsets: [CGFloat],
        totalMonths: Int,
        cellHeight: CGFloat,
        visibleMonthIdx: inout Int,
        didInitialPosition: Bool,
        currentMonthStart: Date,
        todayMonthIdx: Int,
        calendar: Calendar
    ) {
        guard didInitialPosition else { return }
        let offsetBasedIdx = monthIndexForOffset(y: y, offsets: offsets, totalMonths: totalMonths)
        let midpointY = y + (2 * cellHeight)
        let midIdx = monthIndexForOffset(y: midpointY, offsets: offsets, totalMonths: totalMonths)
        let month = calendar.date(byAdding: .month, value: midIdx - todayMonthIdx, to: currentMonthStart) ?? currentMonthStart
        let dateFromMidpoint = calendar.date(byAdding: .day, value: 14, to: month) ?? month
        let computedFromDate = monthIndex(
            for: dateFromMidpoint,
            currentMonthStart: currentMonthStart,
            todayMonthIdx: todayMonthIdx,
            calendar: calendar
        )
        agentDebugLogMonthGrid(
            runId: "month-drift",
            hypothesisId: "H2",
            location: "CalendarPageComponents.swift:MonthGridView.onScrollGeometryChange",
            message: "Computed visible month from scroll offset",
            data: [
                "y": y,
                "offsetBasedIdx": offsetBasedIdx,
                "midpointY": midpointY,
                "midIdx": midIdx,
                "dateDerivedIdx": computedFromDate,
                "previousVisibleMonthIdx": visibleMonthIdx,
                "didInitialPosition": didInitialPosition
            ]
        )
        if visibleMonthIdx != computedFromDate {
            visibleMonthIdx = computedFromDate
        }
    }

    static func handleAppear(
        proxy: ScrollViewProxy,
        visibleMonthIdx: Binding<Int>,
        todayMonthIdx: Int,
        setDidInitialPosition: @escaping (Bool) -> Void
    ) {
        agentDebugLogMonthGrid(
            runId: "month-drift",
            hypothesisId: "H1",
            location: "CalendarPageComponents.swift:MonthGridView.onAppear",
            message: "Month grid appeared and set baseline month index",
            data: [
                "todayMonthIdx": todayMonthIdx,
                "visibleMonthIdxBefore": visibleMonthIdx.wrappedValue
            ]
        )
        visibleMonthIdx.wrappedValue = todayMonthIdx
        DispatchQueue.main.async {
            proxy.scrollTo("month_\(todayMonthIdx)", anchor: .top)
            DispatchQueue.main.async {
                setDidInitialPosition(true)
                agentDebugLogMonthGrid(
                    runId: "month-drift",
                    hypothesisId: "H1",
                    location: "CalendarPageComponents.swift:MonthGridView.onAppear.async",
                    message: "Initial month positioning completed",
                    data: [
                        "didInitialPosition": true,
                        "visibleMonthIdxAfter": visibleMonthIdx.wrappedValue
                    ]
                )
            }
        }
    }

    static func handleTodayTrigger(
        proxy: ScrollViewProxy,
        visibleMonthIdx: Binding<Int>,
        todayMonthIdx: Int
    ) {
        agentDebugLogMonthGrid(
            runId: "month-drift",
            hypothesisId: "H4",
            location: "CalendarPageComponents.swift:MonthGridView.onChange.scrollToTodayTrigger",
            message: "Received Today trigger in month grid",
            data: [
                "visibleMonthIdxBefore": visibleMonthIdx.wrappedValue,
                "todayMonthIdx": todayMonthIdx
            ]
        )
        visibleMonthIdx.wrappedValue = todayMonthIdx
        withAnimation {
            proxy.scrollTo("month_\(todayMonthIdx)", anchor: .top)
        }
    }
}
#endif
