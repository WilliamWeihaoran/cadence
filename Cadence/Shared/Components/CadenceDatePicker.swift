import SwiftUI

/// App-wide custom date picker. Shows a compact button; tap opens a month calendar popover.
struct CadenceDatePicker: View {
    var label: String = ""
    @Binding var selection: Date
    /// Shown instead of the bound date when the field has no value yet — "No due date" rather than
    /// today's date, which a caller with an optional date field would otherwise be claiming.
    /// Set it and this one button covers the whole field: pick a day to set it, Clear to unset it,
    /// with no separate switch that could disagree with the date beside it.
    var placeholder: String? = nil
    /// Minimum height of the trigger. Touch callers pass 44; the default is the desktop control
    /// height every existing call site was built against.
    var minHeight: CGFloat = 30
    var showsClear: Bool = false
    var onClear: (() -> Void)? = nil

    @State private var isOpen = false
    @State private var viewMonth: Date

    init(
        label: String = "",
        selection: Binding<Date>,
        placeholder: String? = nil,
        minHeight: CGFloat = 30,
        showsClear: Bool = false,
        onClear: (() -> Void)? = nil
    ) {
        self.label = label
        self._selection = selection
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.showsClear = showsClear
        self.onClear = onClear
        var comps = Calendar.current.dateComponents([.year, .month], from: selection.wrappedValue)
        comps.day = 1
        self._viewMonth = State(initialValue: Calendar.current.date(from: comps) ?? Date())
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(placeholder == nil ? Theme.blue : Theme.dim)
                Text(placeholder ?? formattedDate)
                    .font(.system(size: 12))
                    .foregroundStyle(placeholder == nil ? Theme.text : Theme.dim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControlCompact).strokeBorder(Theme.borderSubtle))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            CadenceQuickDatePopover(
                selection: $selection,
                viewMonth: $viewMonth,
                isOpen: $isOpen,
                showsClear: showsClear && onClear != nil,
                onClear: onClear
            )
            // Stays an anchored popover on iPhone. Without this, compact width promotes it to a
            // full-height sheet around a 256×294 calendar — most of the screen empty — while every
            // other picker in the iOS app stays a small overlay beside the control it edits.
            .presentationCompactAdaptation(.popover)
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
    var inlineStyle: Bool = false

    private let cal = Calendar.current
    // Was a hard-coded Sunday-first array, which disagreed with the iOS month grid's ordering in
    // every Monday-first region. Both grids now read one function.
    private var dayNames: [String] {
        CadenceScheduleSupport.weekdaySymbols(calendar: cal, width: .compact)
    }
    private let visibleMonthOffsets = Array(-24...24)

    var body: some View {
        VStack(spacing: 0) {
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
                                                        .foregroundStyle(isSelected ? Theme.onColor : (isToday ? Theme.blue : Theme.text))
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
                .frame(height: inlineStyle ? 314 : 294)
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(monthID(for: 0), anchor: .top)
                    }
                }
            }
        }
        .frame(width: inlineStyle ? nil : 256)
        .frame(maxWidth: inlineStyle ? .infinity : nil, alignment: .leading)
        .background(inlineStyle ? Color.clear : Theme.surfaceElevated)
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
        // `weekday - 1` here was Sunday-first unconditionally, so the cells shifted against the
        // headings above them wherever the locale starts its week on Monday.
        let leadingBlanks = CadenceScheduleSupport.leadingBlankCount(forFirstOf: firstOfMonth, calendar: cal)
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in 1...daysInMonth {
            days.append(cal.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }
}

struct CadenceQuickDatePopover: View {
    @Binding var selection: Date
    @Binding var viewMonth: Date
    @Binding var isOpen: Bool
    var showsClear: Bool = true
    var onClear: (() -> Void)? = nil
    var inlineStyle: Bool = false

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                quickPill("Today", target: today)
                quickPill("Tomorrow", target: tomorrow)
                if let weekend = thisWeekend {
                    quickPill("This Weekend", target: weekend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().background(Theme.borderSubtle)

            MonthCalendarPanel(
                selection: Binding(
                    get: { selection },
                    set: { newValue in
                        selection = newValue
                        isOpen = false
                    }
                ),
                viewMonth: $viewMonth,
                isOpen: $isOpen,
                inlineStyle: inlineStyle
            )

            if showsClear {
                Divider().background(Theme.borderSubtle)
                Button("Clear date") {
                    onClear?()
                    isOpen = false
                }
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.red)
                .padding(.vertical, 10)
            }
        }
        .background(inlineStyle ? Color.clear : Theme.surfaceElevated)
    }

    private var today: Date {
        cal.startOfDay(for: Date())
    }

    private var tomorrow: Date {
        cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private var thisWeekend: Date? {
        let todayWeekday = cal.component(.weekday, from: today)
        if todayWeekday == 7 || todayWeekday == 1 {
            return today
        }
        let daysUntilSaturday = (7 - todayWeekday + 7) % 7
        return cal.date(byAdding: .day, value: daysUntilSaturday, to: today)
    }

    @ViewBuilder
    private func quickPill(_ label: String, target: Date) -> some View {
        let isSelected = cal.isDate(selection, inSameDayAs: target)
        Button {
            selection = target
            isOpen = false
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.onColor : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.blue : Theme.surface)
                .clipShape(Capsule())
        }
        .buttonStyle(.cadencePlain)
        .modifier(PickerHoverHighlight(cornerRadius: 999))
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
