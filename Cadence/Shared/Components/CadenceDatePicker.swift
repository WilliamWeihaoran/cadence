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
    /// A second day marked on the grid behind this control, in amber. See `MonthCalendarPanel`.
    var markedDay: Date? = nil
    var markedDayCaption: String = "DUE"

    @State private var isOpen = false
    @State private var viewMonth: Date

    init(
        label: String = "",
        selection: Binding<Date>,
        placeholder: String? = nil,
        minHeight: CGFloat = 30,
        showsClear: Bool = false,
        onClear: (() -> Void)? = nil,
        markedDay: Date? = nil,
        markedDayCaption: String = "DUE"
    ) {
        self.label = label
        self._selection = selection
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.showsClear = showsClear
        self.onClear = onClear
        self.markedDay = markedDay
        self.markedDayCaption = markedDayCaption
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
        // **`arrowEdge: nil`, so the platform may put the panel on a side that can hold it**
        // ([[T-8476]], the same reading [[T-8473]] measured on the duration editor).
        //
        // A named `arrowEdge:` is not a preference: on iOS it reaches UIKit's PERMITTED arrow
        // directions with exactly ONE direction in it, so the flip is forbidden, and a panel that
        // cannot give ground is compressed in place instead. The edge names the popover's own
        // edge, so `.bottom` could only hang this panel ABOVE its chip.
        //
        // **This panel cannot give ground.** `MonthCalendarPanel` is a hard
        // `.frame(height: viewportHeight ?? 294)` — a scroll viewport is a cap, not a text
        // container, as `quickViewportHeight`'s own note says — and the quick-action row above it
        // is intrinsic, with no `ScrollView` anywhere around the panel. A short placement can only
        // take content.
        //
        // Measured on `Cadence-iPadPro11` 834x1210 portrait, at the Starts chip of the timeline
        // draft editor's event schedule: chip top y=252, so 252pt of room above a panel wanting
        // ~342. With `arrowEdge: .bottom` the drawn chrome was ~201pt tall and had lost the
        // Today / Tomorrow / This Weekend row, the divider and the weekday-name header, with
        // "October 2026" spilling out over the panel's own top edge. `nil` is not a free choice
        // of side: there were 934pt below the same chip, and the panel opens whole beside it now.
        .popover(isPresented: $isOpen, arrowEdge: nil) {
            CadenceQuickDatePopover(
                selection: $selection,
                viewMonth: $viewMonth,
                isOpen: $isOpen,
                showsClear: showsClear && onClear != nil,
                onClear: onClear,
                markedDay: markedDay,
                markedDayCaption: markedDayCaption
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
    /// The in-cell marker caption ("DUE").
    ///
    /// **It fits because the cell grows with it and because the grid stops before it cannot.**
    /// `cellSide` is 34 around a 12pt numeral and is scaled by `cellSide(at:)`, which holds the
    /// same ratio as the text grows — so the caption's 7pt rides the same curve and the pair never
    /// outgrows the cell they are in. Above that, `usesDateRows(at:availableWidth:)` already
    /// abandons the grid entirely at accessibility sizes, so the grid branch is never asked to draw
    /// this at a size where it could not. The numeral is untouched: nothing here shrinks it to make
    /// room, which was the other way this could have been paid for and the wrong one.
    static let markerCaptionSize: CGFloat = 7

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
    /// A second day to mark on the same grid, in amber, captioned `markedDayCaption` (T-3169).
    ///
    /// **The schedule panel's Do calendar shows the task's DUE day on it**, so the two dates the
    /// user is reconciling are visible together instead of one row apart. It is a marker, not a
    /// second selection: the cell is not selectable *as* the marked day, it is the same button it
    /// always was, and the day is drawn differently only when it is not the selected one — the
    /// blue selection wins where they coincide, because a day that is both is first of all the one
    /// you picked.
    ///
    /// Defaulted to `nil`, so the dozen existing call sites are byte-for-byte unchanged.
    var markedDay: Date? = nil
    /// The word inside the marked cell. Three marks say it, not one: an amber ring, the numeral in
    /// amber, and this caption. A ring alone reads as "some other state" rather than as a deadline.
    var markedDayCaption: String = "DUE"
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
                                                let isMarked = isMarkedDay(d) && !isSelected
                                                Button {
                                                    selection = d
                                                    syncViewMonthToSelection()
                                                    isOpen = false
                                                } label: {
                                                    ZStack {
                                                        Circle()
                                                            .fill(isSelected ? Theme.blue : (isToday ? Theme.blue.opacity(0.15) : Color.clear))

                                                        if isMarked {
                                                            Circle()
                                                                .strokeBorder(Theme.amber, lineWidth: 1.5)
                                                        }

                                                        VStack(spacing: 0) {
                                                            Text("\(cal.component(.day, from: d))")
                                                                .cadenceFont(.metadata, base: CadenceDateSelectionMetrics.numeralSize, weight: isSelected || isToday || isMarked ? .semibold : .regular)
                                                                .foregroundStyle(isSelected ? Theme.onColor(for: Theme.blue) : (isMarked ? Theme.amber : (isToday ? Theme.blue : Theme.text)))
                                                            if isMarked {
                                                                Text(markedDayCaption)
                                                                    .cadenceFont(.metadata, base: CadenceDateSelectionMetrics.markerCaptionSize, weight: .bold)
                                                                    .foregroundStyle(Theme.amber)
                                                                    .lineLimit(1)
                                                                    .fixedSize()
                                                            }
                                                        }
                                                    }
                                                    .frame(width: cellSide, height: cellSide)
                                                    .contentShape(Circle())
                                                }
                                                .buttonStyle(.cadencePlain)
                                                .accessibilityLabel(
                                                    isMarked
                                                        ? "\(DateFormatters.longDate.string(from: d)), \(markedDayCaption.lowercased())"
                                                        : DateFormatters.longDate.string(from: d)
                                                )
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

    private func isMarkedDay(_ day: Date) -> Bool {
        guard let markedDay else { return false }
        return cal.isDate(day, inSameDayAs: markedDay)
    }

    /// The marked day in the **rows** layout.
    ///
    /// This branch is what an accessibility text size gets — see
    /// `CadenceDateSelectionMetrics.usesDateRows` — and a row has no cell to put a caption inside,
    /// so the word goes beside the date where there is room for it to grow. The grid's three marks
    /// become two and a word here, which is the same three statements in a layout that can hold
    /// them.
    private func dateRow(_ day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selection)
        let isToday = cal.isDateInToday(day)
        let isMarked = isMarkedDay(day) && !isSelected
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
                if isMarked {
                    Text(markedDayCaption)
                        .cadenceFont(.metadata, weight: .bold)
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .cadenceFont(.metadata)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected || isToday ? Theme.blue : (isMarked ? Theme.amber : Theme.text))
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
    /// Forwarded to `MonthCalendarPanel`; see its note. Defaulted, so no existing caller moved.
    var markedDay: Date? = nil
    var markedDayCaption: String = "DUE"
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
                viewportHeight: CadenceDateSelectionMetrics.quickViewportHeight(at: dynamicTypeSize, inlineStyle: inlineStyle),
                markedDay: markedDay,
                markedDayCaption: markedDayCaption
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
