#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCalendarBoardMonth: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]

    private var summariesByDate: [String: CadenceCalendarBoardDaySummary] {
        CadenceCalendarBoardSupport.monthSummaries(
            monthDate: monthDate,
            tasksByDate: monthTasksByDate,
            bundlesByDate: bundlesByDate
        )
    }

    var body: some View {
        CalendarBoardMonthView(
            monthDate: monthDate,
            selectedDate: $selectedDate,
            summariesByDate: summariesByDate,
            minCellHeight: 66
        )
    }
}
#endif
