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

// MARK: - Date selection geometry

nonisolated enum CadenceDateSelectionMetrics {
    static let cellSide: CGFloat = 34
    static let numeralSize: CGFloat = 12
    static let gridPadding: CGFloat = 8
    static let gridSpacing: CGFloat = 2

    static func cellSide(at size: DynamicTypeSize) -> CGFloat {
        CadenceTypeScale.height(cellSide, holding: .metadata, textBase: numeralSize, at: size, scaling: .enabled)
    }

    static func gridWidth(at size: DynamicTypeSize) -> CGFloat {
        cellSide(at: size) * 7 + gridPadding * 2 + gridSpacing * 6
    }

    static func usesDateRows(at size: DynamicTypeSize, availableWidth: CGFloat) -> Bool {
        CadenceTypeScale.isAccessibilitySize(size) || gridWidth(at: size) > availableWidth
    }

    static func width(at size: DynamicTypeSize) -> CGFloat {
        if CadenceTypeScale.isAccessibilitySize(size) {
            return CadenceTypeScale.height(256, holding: .metadata, at: size, scaling: .enabled)
        }
        return max(256, gridWidth(at: size))
    }

    static func dateRowHeight(at size: DynamicTypeSize) -> CGFloat {
        max(44, CadenceTypeScale.lineHeight(.metadata, at: size, scaling: .enabled) + 16)
    }

    // A scroll viewport is a cap, not a text container. The quick actions get the freed space.
    static func quickViewportHeight(at size: DynamicTypeSize, inlineStyle: Bool) -> CGFloat {
        CadenceTypeScale.isAccessibilitySize(size) ? 180 : (inlineStyle ? 314 : 294)
    }

    static func quickActionHeight(at size: DynamicTypeSize) -> CGFloat {
        CadenceTypeScale.lineHeight(.controlLabel, base: 11, at: size, scaling: .enabled) + 16
    }
}

// MARK: - Month Calendar Panel

struct MonthCalendarPanel: View {
    @Binding var selection: Date
    @Binding var viewMonth: Date
    @Binding var isOpen: Bool
    var inlineStyle: Bool = false
    var viewportHeight: CGFloat? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let cal = Calendar.current
    // Was a hard-coded Sunday-first array, which disagreed with the iOS month grid's ordering in
    // every Monday-first region. Both grids now read one function.
    private var dayNames: [String] {
        CadenceScheduleSupport.weekdaySymbols(calendar: cal, width: .compact)
    }
    private let visibleMonthOffsets = Array(-24...24)

    var body: some View {
        GeometryReader { geometry in
            let usesRows = CadenceDateSelectionMetrics.usesDateRows(
                at: dynamicTypeSize, availableWidth: geometry.size.width
            )
            calendarContent(usesRows: usesRows)
        }
        .frame(width: inlineStyle ? nil : CadenceDateSelectionMetrics.width(at: dynamicTypeSize))
        .frame(maxWidth: inlineStyle ? .infinity : nil)
        .frame(height: viewportHeight ?? (inlineStyle ? 314 : 294))
        .background(inlineStyle ? Color.clear : Theme.surfaceElevated)
        .cadenceScaledTypography()
    }

    private func calendarContent(usesRows: Bool) -> some View {
        VStack(spacing: 0) {
            if !usesRows {
                HStack(spacing: 0) {
                    ForEach(dayNames, id: \.self) { name in
                        Text(name)
                            .cadenceFont(.metadata, base: 10, weight: .medium)
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(visibleMonthOffsets, id: \.self) { offset in
                            let month = cal.date(byAdding: .month, value: offset, to: anchorMonth) ?? anchorMonth
                            VStack(alignment: .leading, spacing: 8) {
                                Text(DateFormatters.monthYear.string(from: month))
                                    .cadenceFont(.controlLabel)
                                    .foregroundStyle(Theme.text)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 2)

                                let days = calendarDays(for: month)
                                if usesRows {
                                    LazyVStack(spacing: 2) {
                                        ForEach(days.compactMap { $0 }, id: \.self) { day in
                                            dateRow(day)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                } else {
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
                                                            .cadenceFont(.metadata, base: CadenceDateSelectionMetrics.numeralSize, weight: isSelected || isToday ? .semibold : .regular)
                                                            .foregroundStyle(isSelected ? Theme.onColor(for: Theme.blue) : (isToday ? Theme.blue : Theme.text))
                                                    }
                                                    .frame(width: cellSide, height: cellSide)
                                                    .contentShape(Circle())
                                                }
                                                .buttonStyle(.cadencePlain)
                                                .accessibilityLabel(DateFormatters.longDate.string(from: d))
                                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                                                .modifier(PickerHoverHighlight(cornerRadius: cellSide / 2, padding: 0))
                                            } else {
                                                Color.clear.frame(width: cellSide, height: cellSide)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                }
                            }
                            .id(monthID(for: offset))
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(monthID(for: 0), anchor: .top)
                    }
                }
                .onChange(of: usesRows) {
                    proxy.scrollTo(monthID(for: 0), anchor: .top)
                }
            }
        }
    }

    private var cellSide: CGFloat {
        CadenceDateSelectionMetrics.cellSide(at: dynamicTypeSize)
    }

    private func dateRow(_ day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selection)
        let isToday = cal.isDateInToday(day)
        return Button {
            selection = day
            syncViewMonthToSelection()
            isOpen = false
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DateFormatters.longDate.string(from: day))
                    .cadenceFont(.metadata, weight: isSelected || isToday ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .cadenceFont(.metadata)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected || isToday ? Theme.blue : Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: CadenceDateSelectionMetrics.dateRowHeight(at: dynamicTypeSize), alignment: .leading)
            .background(isSelected ? Theme.blue.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { quickActions }
                    .fixedSize(horizontal: true, vertical: false)
                // T-1492. Without this middle candidate the row falls straight to three lines, and
                // on an iPhone at the DEFAULT text size that is what rendered: the popover is
                // `width(at:)` wide less 12pt of padding each side, and one row of all three pills
                // needs a few points more than that. `ViewThatFits` was choosing correctly from two
                // extremes; what it was given is what was wrong. Today + Tomorrow share a line with
                // room to spare, so the near miss now costs one extra row rather than two.
                VStack(spacing: 6) { quickActionRows }
                VStack(spacing: 6) { quickActions }
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
                inlineStyle: true,
                viewportHeight: CadenceDateSelectionMetrics.quickViewportHeight(at: dynamicTypeSize, inlineStyle: inlineStyle)
            )

            if showsClear {
                Divider().background(Theme.borderSubtle)
                Button("Clear date") {
                    onClear?()
                    isOpen = false
                }
                .buttonStyle(.cadencePlain)
                .cadenceFont(.controlLabel, base: 11, weight: .regular)
                .foregroundStyle(Theme.red)
                .padding(.vertical, 10)
            }
        }
        .frame(width: inlineStyle ? nil : CadenceDateSelectionMetrics.width(at: dynamicTypeSize))
        .frame(maxWidth: inlineStyle ? .infinity : nil)
        .background(inlineStyle ? Color.clear : Theme.surfaceElevated)
        .cadenceScaledTypography()
    }

    @ViewBuilder
    private var quickActions: some View {
        quickPill("Today", target: today)
        quickPill("Tomorrow", target: tomorrow)
        if let weekend = thisWeekend {
            quickPill("This Weekend", target: weekend)
        }
    }

    /// The same three pills as `quickActions`, arranged two rows deep instead of one or three.
    ///
    /// The two short labels pair and the long one takes the second line, which is the arrangement
    /// that fits whenever the single row does not. The inner row is `fixedSize` for the same reason
    /// the single-row candidate is: `ViewThatFits` has to be told the row's ideal width, not a
    /// compressed one, or it would accept a candidate that then squeezes its own pills.
    @ViewBuilder
    private var quickActionRows: some View {
        HStack(spacing: 6) {
            quickPill("Today", target: today)
            quickPill("Tomorrow", target: tomorrow)
        }
        .fixedSize(horizontal: true, vertical: false)
        if let weekend = thisWeekend {
            quickPill("This Weekend", target: weekend)
        }
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
                .cadenceFont(.controlLabel, base: 11, weight: .medium)
                .foregroundStyle(isSelected ? Theme.onColor(for: Theme.blue) : Theme.muted)
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
    var padding: CGFloat = 2
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Theme.blue.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
    }
}
