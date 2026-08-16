#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// Month with its detail **under** the grid: the compact month grid on top, whatever reading of the
/// day the toggle selected below it. Every phone, and any iPad pane too narrow to place that reading
/// beside the grid (an 11" in portrait).
///
/// Month was the last calendar mode still carrying the chrome block `ecaf80f` took off Week and
/// Board — the four "0 total / 0 timed / 0 tasks / 0 events" chips, the selected-day card, and the
/// oversized empty state. It was left on purpose, because a month grid on its own lists nothing:
/// removing the day inspector before there was an agenda would have replaced a pane that said too
/// much with one that said nothing at all. This is where the agenda arrived, and the day inspector
/// is now the other thing this container can hold rather than the thing it replaced.
///
/// What the old inspector cost the grid is the other half of the point. It took the top of the pane
/// and the grid took the rest, at a 104pt minimum cell — so on a phone the month view showed three
/// weeks of the month. The grid here is sized by `CadenceCalendarMonthAgendaSupport.gridRowHeight`,
/// which fits *every* week of the month into a share of the pane and never drops a cell below a
/// 44pt touch target. `CadenceCalendarMonthAgendaSupport.agendaMinimumHeight` is what the grid is
/// capped against, so the detail's room comes out of cell height and never out of weeks. Both
/// readings reserve the same amount: the inspector used to need more only because it opened with a
/// 63pt date header, and that header is gone.
struct iOSCalendarMonthStack<Detail: View>: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]
    @ViewBuilder let detail: () -> Detail

    private let calendar = Calendar.current
    private let weekdayHeaderHeight: CGFloat = 22

    private var gridDays: [Date] {
        CadenceCalendarMonthAgendaSupport.agendaDays(forMonthContaining: monthDate, calendar: calendar)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                iOSCalendarMonthCompactGrid(
                    monthDate: monthDate,
                    selectedDate: $selectedDate,
                    days: gridDays,
                    rowHeight: CadenceCalendarMonthAgendaSupport.gridRowHeight(
                        availableHeight: proxy.size.height,
                        rowCount: CadenceCalendarMonthAgendaSupport.weekRowCount(
                            forMonthContaining: monthDate,
                            calendar: calendar
                        ),
                        weekdayHeaderHeight: weekdayHeaderHeight
                    ),
                    weekdayHeaderHeight: weekdayHeaderHeight,
                    monthTasksByDate: monthTasksByDate,
                    bundlesByDate: bundlesByDate,
                    eventsByDate: eventsByDate
                )

                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 1)

                detail()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
    }
}

/// Every day the month grid draws, in sequence, with what each one holds.
///
/// The grid and this list are one selection, both ways: tapping a grid day scrolls the list to that
/// day's section, and scrolling the list moves the grid's selection to whichever day is at the top.
/// The rules that keep those two from driving each other in a loop are
/// `CadenceCalendarMonthAgendaSupport.scrollTarget` / `selectionTarget`, in `Shared/` and tested.
///
/// There is no add control here. Capture on a compact Calendar tab is the tab bar's centre `+`, the
/// same as compact Today.
struct iOSCalendarMonthAgendaList: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]

    /// The agenda section at the top of the scroll view — both the position the agenda is *set* to
    /// when a grid day is tapped and the one it reports back as it is scrolled. `scrollPosition(id:)`
    /// is what places a lazy stack; an `onAppear` → `scrollTo` against one runs before its rows
    /// exist and silently does nothing (`ecaf80f`).
    ///
    /// Seeded from the selected day, and **that seed is not a scroll position on its own.** A value
    /// handed to `.scrollPosition(id:)` in `init` is resolved against a `LazyVStack` that has not
    /// built a row yet, so the offset comes out of estimates of nothing and the pane opens blank —
    /// which is what Month → Agenda did at iPad regular width until you stepped a month, that step
    /// being the one thing that re-assigned this binding *after* layout. The seed is what makes the
    /// first frame right where it can be; `cadenceLazyScrollAnchor` is what makes it right where it
    /// cannot. See `CadenceLazyScrollAnchor`.
    @State private var scrolledDayKey: String?
    @State private var selectedBundle: TaskBundle?
    @State private var selectedEvent: iOSCalendarEventSelection?

    private let calendar = Calendar.current

    init(
        monthDate: Date,
        selectedDate: Binding<Date>,
        monthTasksByDate: [String: [AppTask]],
        bundlesByDate: [String: [TaskBundle]],
        eventsByDate: [String: [EKEvent]]
    ) {
        self.monthDate = monthDate
        self._selectedDate = selectedDate
        self.monthTasksByDate = monthTasksByDate
        self.bundlesByDate = bundlesByDate
        self.eventsByDate = eventsByDate
        self._scrolledDayKey = State(
            initialValue: CadenceCalendarMonthAgendaSupport.initialScrollTarget(
                selectedKey: DateFormatters.dateKey(from: selectedDate.wrappedValue),
                agendaDayKeys: CadenceCalendarMonthAgendaSupport.agendaDayKeys(forMonthContaining: monthDate)
            )
        )
    }

    private var agendaDays: [Date] {
        CadenceCalendarMonthAgendaSupport.agendaDays(forMonthContaining: monthDate, calendar: calendar)
    }

    private var agendaDayKeys: [String] {
        CadenceCalendarMonthAgendaSupport.agendaDayKeys(forMonthContaining: monthDate, calendar: calendar)
    }

    /// The section the agenda opens on, re-read every pass so the one-shot assertion below uses the
    /// selection as it stands at first layout rather than as it stood in `init`.
    private var initialScrollTarget: String? {
        CadenceCalendarMonthAgendaSupport.initialScrollTarget(
            selectedKey: DateFormatters.dateKey(from: selectedDate),
            agendaDayKeys: agendaDayKeys
        )
    }

    var body: some View {
        agenda
            .background(Theme.bg)
            .sheet(item: $selectedBundle) { bundle in
                iOSCalendarBundleDetailSheet(bundle: bundle)
            }
            .sheet(item: $selectedEvent) { selection in
                iOSCalendarEventEditSheet(event: selection.event)
            }
    }

    private var agenda: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(agendaDays, id: \.self) { date in
                    daySection(for: date)
                        .id(DateFormatters.dateKey(from: date))
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 14)
            .padding(.top, 12)
            // See the note in `iOSCompactTodayView`.
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledDayKey, anchor: .top)
        .cadenceLazyScrollAnchor($scrolledDayKey, target: initialScrollTarget)
        .onChange(of: selectedDate) { _, newValue in
            scrollAgenda(toSelected: DateFormatters.dateKey(from: newValue))
        }
        .onChange(of: scrolledDayKey) { _, newValue in
            adoptScrolledDay(newValue)
        }
        .onChange(of: monthDate) { _, _ in
            realignAgendaWithMonth()
        }
    }

    @ViewBuilder
    private func daySection(for date: Date) -> some View {
        let key = DateFormatters.dateKey(from: date)
        let items = agendaItems(on: key, date: date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

        VStack(alignment: .leading, spacing: 10) {
            // The same header every board column gets. An empty day is the header on its own: the
            // count says nothing is there, and a "Nothing scheduled" card repeated down thirty
            // quiet days would be more chrome than the chrome this view removed.
            iOSBoardColumnHeader(
                dotColor: isToday ? Theme.amber : isSelected ? Theme.blue : Theme.dim,
                title: CadenceCalendarMonthAgendaSupport.dayHeaderLabel(for: date),
                count: items.count,
                accentRule: isToday ? Theme.amber : nil
            )

            ForEach(items) { item in
                agendaRow(item)
            }
        }
        .opacity(calendar.isDate(date, equalTo: monthDate, toGranularity: .month) ? 1 : 0.55)
    }

    @ViewBuilder
    private func agendaRow(_ item: iOSCalendarBoardColumnItem) -> some View {
        switch item {
        case .event(let eventItem):
            Button {
                selectedEvent = iOSCalendarEventSelection(event: eventItem.event)
            } label: {
                iOSCalendarEventSummaryRow(event: eventItem.event)
            }
            .buttonStyle(.iosPressable)

        case .bundle(let bundle):
            Button {
                selectedBundle = bundle
            } label: {
                iOSFeatureSummaryRow(
                    title: bundle.displayTitle,
                    subtitle: CadenceScheduleSupport.timeRangeLabel(
                        startMinute: bundle.startMin,
                        endMinute: bundle.endMin
                    ),
                    detail: "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")",
                    icon: "tray.full.fill",
                    color: Theme.amber
                )
            }
            .buttonStyle(.iosPressable)

        case .task(let task):
            iOSTaskRow(task: task, density: .compact)
        }
    }

    /// One day's items, in the order a board day column would put them: events, then blocks, then
    /// tasks, all interleaved by start time. Reuses `iOSCalendarBoardColumnItem` rather than
    /// introducing a second ordering for the same three kinds of thing.
    ///
    /// Tasks come from the **same** `monthTasksByDate` the grid dots are drawn from, so a day the
    /// grid marks is never a day the agenda shows as empty.
    private func agendaItems(on key: String, date: Date) -> [iOSCalendarBoardColumnItem] {
        let events = iOSCalendarBoardEventItem
            .items(
                from: CadenceScheduleSupport.items(on: key, in: eventsByDate),
                for: date,
                calendar: calendar
            )
            .map { iOSCalendarBoardColumnItem.event($0) }
        let bundles = CadenceScheduleSupport.items(on: key, in: bundlesByDate)
            .map { iOSCalendarBoardColumnItem.bundle($0) }
        let tasks = CadenceScheduleSupport.items(on: key, in: monthTasksByDate)
            .map { iOSCalendarBoardColumnItem.task($0) }

        return (events + bundles + tasks).sorted { $0.sortKey < $1.sortKey }
    }

    private func scrollAgenda(toSelected key: String) {
        guard let target = CadenceCalendarMonthAgendaSupport.scrollTarget(
            selectedKey: key,
            scrolledKey: scrolledDayKey,
            agendaDayKeys: agendaDayKeys
        ) else { return }
        withAnimation(.snappy(duration: 0.24)) {
            scrolledDayKey = target
        }
    }

    private func adoptScrolledDay(_ key: String?) {
        guard let target = CadenceCalendarMonthAgendaSupport.selectionTarget(
            scrolledKey: key,
            selectedKey: DateFormatters.dateKey(from: selectedDate)
        ), let date = DateFormatters.date(from: target) else { return }
        selectedDate = calendar.startOfDay(for: date)
    }

    /// Stepping the month rebuilds the agenda's day list under the scroll position. Without this the
    /// remembered section can be a day the new month does not list, and `scrollPosition(id:)` drops
    /// a scroll to an id that is not there — leaving the grid and the agenda pointing at different
    /// days with no gesture that puts them back.
    private func realignAgendaWithMonth() {
        let keys = agendaDayKeys
        let selectedKey = DateFormatters.dateKey(from: selectedDate)
        scrolledDayKey = keys.contains(selectedKey) ? selectedKey : keys.first
    }
}

/// The month grid in its compact form: a day number and, when the day holds anything at all, a dot.
///
/// The full-size cell (`iOSCalendarMonthDayCell`, still what a split-width iPad pane draws) lists up
/// to five chips per day and needs 104pt to do it, which is why only three weeks fitted. Here
/// the day's items are one scroll away in the agenda, so the cell only has to answer "is there
/// something on this day" — and every week of the month fits.
private struct iOSCalendarMonthCompactGrid: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let days: [Date]
    let rowHeight: CGFloat
    let weekdayHeaderHeight: CGFloat
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(CadenceScheduleSupport.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: weekdayHeaderHeight)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { date in
                    iOSCalendarMonthCompactDayCell(
                        date: date,
                        displayMonth: monthDate,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        hasItems: hasItems(on: DateFormatters.dateKey(from: date)),
                        rowHeight: rowHeight
                    ) {
                        selectedDate = date
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
        .background(Theme.surface)
    }

    private func hasItems(on key: String) -> Bool {
        !CadenceScheduleSupport.items(on: key, in: monthTasksByDate).isEmpty ||
        !CadenceScheduleSupport.items(on: key, in: bundlesByDate).isEmpty ||
        !CadenceScheduleSupport.items(on: key, in: eventsByDate).isEmpty
    }
}

private struct iOSCalendarMonthCompactDayCell: View {
    let date: Date
    let displayMonth: Date
    let isSelected: Bool
    let hasItems: Bool
    let rowHeight: CGFloat
    let action: () -> Void

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var isCurrentMonth: Bool { calendar.isDate(date, equalTo: displayMonth, toGranularity: .month) }

    private var dateLabelColor: Color {
        if isToday { return Theme.onColor }
        if isSelected { return Theme.blue }
        return isCurrentMonth ? Theme.text : Theme.dim
    }

    private var badgeFill: Color {
        if isToday { return Theme.blue }
        if isSelected { return Theme.blue.opacity(0.16) }
        return Color.clear
    }

    /// The day badge is 32pt on every pane tall enough to give the row its 44pt touch target, and
    /// shrinks with the row below that. `gridRowHeight` only returns a sub-44 row when the pane
    /// cannot hold the grid and the agenda at once; a fixed 32pt badge plus its dot is 40pt of
    /// content, which would then overrun the row and let neighbouring weeks overlap.
    private var badgeSize: CGFloat {
        min(32, max(18, rowHeight - 12))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(DateFormatters.dayNumber.string(from: date))
                    .font(.system(size: badgeSize >= 28 ? 15 : 12, weight: isToday || isSelected ? .bold : .medium))
                    .foregroundStyle(dateLabelColor)
                    .monospacedDigit()
                    .frame(width: badgeSize, height: badgeSize)
                    .background(badgeFill)
                    .clipShape(Circle())
                    .overlay {
                        if isSelected && !isToday {
                            Circle().strokeBorder(Theme.blue.opacity(0.65), lineWidth: 1.5)
                        }
                    }

                // Reserved whether or not it is drawn, so the day numbers sit on one baseline
                // across the whole grid rather than shifting row by row.
                Circle()
                    .fill(hasItems ? Theme.blue : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .opacity(isCurrentMonth ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(DateFormatters.longDate.string(from: date))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
#endif
