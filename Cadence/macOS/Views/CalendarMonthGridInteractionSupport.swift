#if os(macOS)
import SwiftUI

enum CalendarMonthGridInteractionSupport {
    static func handleScroll(
        y: CGFloat,
        offsets: [CGFloat],
        totalMonths: Int,
        visibleMonthIdx: inout Int,
        didInitialPosition: Bool
    ) {
        guard didInitialPosition else { return }
        let visibleTopY = max(y, 0)
        let computedFromTop = monthIndexForOffset(y: visibleTopY, offsets: offsets, totalMonths: totalMonths)
        agentDebugLogMonthGrid(
            runId: "month-drift",
            hypothesisId: "H2",
            location: "CalendarPageComponents.swift:MonthGridView.onScrollGeometryChange",
            message: "Computed visible month from top scroll offset",
            data: [
                "y": y,
                "visibleTopY": visibleTopY,
                "computedFromTop": computedFromTop,
                "previousVisibleMonthIdx": visibleMonthIdx,
                "didInitialPosition": didInitialPosition
            ]
        )
        if visibleMonthIdx != computedFromTop {
            visibleMonthIdx = computedFromTop
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
