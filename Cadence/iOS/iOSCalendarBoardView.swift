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
        GeometryReader { geo in
            let headerHeight: CGFloat = 42
            let verticalSpacing: CGFloat = 10
            let horizontalPadding: CGFloat = 22
            let availableGridHeight = max(geo.size.height - headerHeight - 28, 0)
            let cellHeight = max((availableGridHeight - verticalSpacing * 5) / 6, 66)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 10)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: verticalSpacing) {
                    ForEach(days, id: \.self) { date in
                        let key = DateFormatters.dateKey(from: date)
                        iOSCalendarDayCell(
                            date: date,
                            isCurrentMonth: calendar.isDate(date, equalTo: monthDate, toGranularity: .month),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            taskCount: (monthTasksByDate[key]?.count ?? 0) + (bundlesByDate[key]?.count ?? 0),
                            minHeight: cellHeight
                        ) {
                            selectedDate = date
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)

                Spacer(minLength: 0)
            }
        }
        .background(Theme.surface)
    }
}
#endif
