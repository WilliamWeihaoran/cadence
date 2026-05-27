#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCalendarBoardMonth: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]

    private let calendar = Calendar.current
    private var summariesByDate: [String: CadenceCalendarBoardDaySummary] {
        Dictionary(uniqueKeysWithValues: CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar).map { date in
            let key = DateFormatters.dateKey(from: date)
            return (
                key,
                CadenceCalendarBoardSupport.daySummary(
                    dateKey: key,
                    tasks: CadenceScheduleSupport.monthTasks(on: key, in: monthTasksByDate),
                    bundles: CadenceScheduleSupport.bundles(on: key, in: bundlesByDate)
                )
            )
        })
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
