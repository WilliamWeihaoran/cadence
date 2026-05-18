#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCalendarBoardMonth: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]

    private let calendar = Calendar.current
    private var days: [Date] {
        CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { date in
                    let key = DateFormatters.dateKey(from: date)
                    iOSCalendarDayCell(
                        date: date,
                        isCurrentMonth: calendar.isDate(date, equalTo: monthDate, toGranularity: .month),
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        taskCount: (monthTasksByDate[key]?.count ?? 0) + (bundlesByDate[key]?.count ?? 0)
                    ) {
                        selectedDate = date
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .background(Theme.surface)
    }
}
#endif
