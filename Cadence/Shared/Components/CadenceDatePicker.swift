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
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle))
        }
        .buttonStyle(.cadencePlain)
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
    private let visibleMonthOffsets = Array(-24...24)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scroll to Browse Months")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    selection = cal.startOfDay(for: Date())
                    syncViewMonthToSelection()
                } label: {
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.blue.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.cadencePlain)
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

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(visibleMonthOffsets, id: \.self) { offset in
                            let month = cal.date(byAdding: .month, value: offset, to: anchorMonth) ?? anchorMonth
                            VStack(alignment: .leading, spacing: 8) {
                                Text(DateFormatters.monthYear.string(from: month))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 2)

                                let days = calendarDays(for: month)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                                    ForEach(days.indices, id: \.self) { i in
                                        if let d = days[i] {
                                            let isSelected = cal.isDate(d, inSameDayAs: selection)
                                            let isToday = cal.isDateInToday(d)
                                            Button {
                                                selection = d
                                                syncViewMonthToSelection()
                                                isOpen = false
                                            } label: {
                                                ZStack {
                                                    Circle()
                                                        .fill(isSelected ? Theme.blue : (isToday ? Theme.blue.opacity(0.15) : Color.clear))

                                                    Text("\(cal.component(.day, from: d))")
                                                        .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                                                        .foregroundStyle(isSelected ? .white : (isToday ? Theme.blue : Theme.text))
                                                }
                                                .frame(width: 34, height: 34)
                                                .contentShape(Circle())
                                            }
                                            .buttonStyle(.cadencePlain)
                                            .modifier(PickerHoverHighlight(cornerRadius: 17))
                                        } else {
                                            Color.clear.frame(width: 34, height: 34)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                            .id(monthID(for: offset))
                        }
                    }
                }
                .frame(height: 294)
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(monthID(for: 0), anchor: .top)
                    }
                }
            }
        }
        .frame(width: 256)
        .background(Theme.surfaceElevated)
    }

    private var anchorMonth: Date {
        var comps = cal.dateComponents([.year, .month], from: viewMonth)
        comps.day = 1
        return cal.date(from: comps) ?? viewMonth
    }

    private func syncViewMonthToSelection() {
        var comps = cal.dateComponents([.year, .month], from: selection)
        comps.day = 1
        viewMonth = cal.date(from: comps) ?? selection
    }

    private func monthID(for offset: Int) -> String {
        "picker_month_\(offset)"
    }

    private func calendarDays(for month: Date) -> [Date?] {
        var comps = cal.dateComponents([.year, .month], from: month)
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

private struct PickerHoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Theme.blue.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}
