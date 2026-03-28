import SwiftUI

/// App-wide custom date picker. Shows a compact button; tap opens a month calendar popover.
struct CadenceDatePicker: View {
    var label: String = ""
    @Binding var selection: Date

    @State private var isOpen = false
    @State private var viewMonth: Date

    init(label: String = "", selection: Binding<Date>) {
        self.label = label
        self._selection = selection
        var comps = Calendar.current.dateComponents([.year, .month], from: selection.wrappedValue)
        comps.day = 1
        self._viewMonth = State(initialValue: Calendar.current.date(from: comps) ?? Date())
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.blue)
                Text(formattedDate)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            MonthCalendarPanel(selection: $selection, viewMonth: $viewMonth, isOpen: $isOpen)
        }
        .onChange(of: selection) {
            var comps = Calendar.current.dateComponents([.year, .month], from: selection)
            comps.day = 1
            if let m = Calendar.current.date(from: comps) { viewMonth = m }
        }
    }

    private var formattedDate: String {
        DateFormatters.fullShortDate.string(from: selection)
    }
}

// MARK: - Month Calendar Panel

struct MonthCalendarPanel: View {
    @Binding var selection: Date
    @Binding var viewMonth: Date
    @Binding var isOpen: Bool

    private let cal = Calendar.current
    private let dayNames = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation header
            HStack(spacing: 8) {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 26, height: 26)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Spacer()

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 26, height: 26)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Day names
            HStack(spacing: 0) {
                ForEach(dayNames, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // Calendar grid
            let days = calendarDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(days.indices, id: \.self) { i in
                    if let d = days[i] {
                        let isSelected = cal.isDate(d, inSameDayAs: selection)
                        let isToday = cal.isDateInToday(d)
                        Button {
                            selection = d
                            isOpen = false
                        } label: {
                            Text("\(cal.component(.day, from: d))")
                                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .white : (isToday ? Theme.blue : Theme.text))
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle().fill(isSelected ? Theme.blue : (isToday ? Theme.blue.opacity(0.15) : Color.clear))
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 30, height: 30)
                    }
                }
            }
            .padding(.horizontal, 8)

            // Today shortcut
            Button {
                selection = cal.startOfDay(for: Date())
                isOpen = false
            } label: {
                Text("Today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Theme.blue.opacity(0.1))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(width: 256)
        .background(Theme.surfaceElevated)
    }

    private var monthTitle: String {
        DateFormatters.monthYear.string(from: viewMonth)
    }

    private func shiftMonth(_ delta: Int) {
        viewMonth = cal.date(byAdding: .month, value: delta, to: viewMonth) ?? viewMonth
    }

    private func calendarDays() -> [Date?] {
        var comps = cal.dateComponents([.year, .month], from: viewMonth)
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps) else { return [] }
        let firstWeekday = cal.component(.weekday, from: firstOfMonth) - 1
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in 1...daysInMonth {
            days.append(cal.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}
