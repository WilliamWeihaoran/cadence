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
        let targetMonthIdx = min(max(visibleMonthIdx.wrappedValue, 0), todayMonthIdx * 2 - 1)
        DispatchQueue.main.async {
            proxy.scrollTo("month_\(targetMonthIdx)", anchor: .top)
            DispatchQueue.main.async {
                setDidInitialPosition(true)
            }
        }
    }

    static func handleTodayTrigger(
        proxy: ScrollViewProxy,
        todayMonthIdx: Int
    ) {
        withAnimation {
            proxy.scrollTo("month_\(todayMonthIdx)", anchor: .top)
        }
    }
}
#endif
