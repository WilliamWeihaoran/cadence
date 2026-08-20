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
    /// The week row at the top of the grid. The grid scrolls through its rows continuously now, so
    /// this is a scroll position that reports itself back rather than a month the chevrons rebuilt.
    @Binding var topRowDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]
    @ViewBuilder let detail: () -> Detail

    private let weekdayHeaderHeight: CGFloat = 22
    private let gridBottomPadding: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            // Six rows, always. It used to be this month's own row count, which was right while one
            // month was on screen at a time and wrong the moment the rows scroll: a five-week month
            // scrolling into a six-week one would have changed the row height under the finger. See
            // `CadenceCalendarMonthWindow.visibleRowCount`.
            let rowHeight = CadenceCalendarMonthAgendaSupport.gridRowHeight(
                availableHeight: proxy.size.height,
                rowCount: CadenceCalendarMonthWindow.visibleRowCount,
                weekdayHeaderHeight: weekdayHeaderHeight,
                gridBottomPadding: gridBottomPadding
            )

            VStack(spacing: 0) {
                iOSCalendarMonthCompactGrid(
                    topRowDate: $topRowDate,
                    selectedDate: $selectedDate,
                    rowHeight: rowHeight,
                    weekdayHeaderHeight: weekdayHeaderHeight,
                    bottomPadding: gridBottomPadding,
                    monthTasksByDate: monthTasksByDate,
                    bundlesByDate: bundlesByDate,
                    eventsByDate: eventsByDate
                )
                // Explicit, because the grid is a scroll view now and a scroll view left flexible
                // takes the whole stack. This is the same total the fixed grid used to occupy —
                // header, six rows, and the padding under them — which is what
                // `gridRowHeight`'s cap is stated against.
                .frame(
                    height: weekdayHeaderHeight
                        + rowHeight * CGFloat(CadenceCalendarMonthWindow.visibleRowCount)
                        + gridBottomPadding
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

/// One section per day of the month grid that **holds something**, in sequence.
///
/// The grid and this list are one selection, both ways: tapping a grid day scrolls the list to that
/// day's section, and scrolling the list moves the grid's selection to whichever day is at the top.
/// The rules that keep those two from driving each other in a loop are
/// `CadenceCalendarMonthAgendaSupport.scrollTarget` / `selectionTarget`, in `Shared/` and tested.
///
/// Quiet days are not listed, so most of the grid's cells have no section of their own and a tap on
/// one is resolved to the nearest that does — `CadenceCalendarMonthAgendaSupport.nearestListedDayKey`,
/// applied inside `scrollTarget(forSelectedDay:…)` so the resolution and the loop guard cannot be
/// composed in the wrong order.
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
    /// Set by the first report that agrees with the placement. Until then this agenda believes
    /// nothing it is told about where it is scrolled — see the switch in `agenda`.
    @State private var didConfirmInitialDay = false
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
                forSelectedDay: DateFormatters.dateKey(from: selectedDate.wrappedValue),
                listedDayKeys: Self.sections(
                    monthDate: monthDate,
                    calendar: .current,
                    monthTasksByDate: monthTasksByDate,
                    bundlesByDate: bundlesByDate,
                    eventsByDate: eventsByDate
                ).map(\.key)
            )
        )
    }

    /// The sections this view draws, and the **only** source of the key list that drives
    /// `.scrollPosition(id:)`.
    ///
    /// One array read two ways, deliberately: a key list assembled separately from the rendered
    /// list is free to name a day the stack has no section for, and `scrollPosition(id:)` drops a
    /// scroll to an id it cannot find without saying so.
    ///
    /// `static` because `init` needs it too — the seeded scroll position has to be resolved against
    /// the same list the first layout will build.
    private static func sections(
        monthDate: Date,
        calendar: Calendar,
        monthTasksByDate: [String: [AppTask]],
        bundlesByDate: [String: [TaskBundle]],
        eventsByDate: [String: [EKEvent]]
    ) -> [iOSCalendarAgendaDaySection] {
        CadenceCalendarMonthAgendaSupport.agendaDays(forMonthContaining: monthDate, calendar: calendar)
            .compactMap { date in
                let key = DateFormatters.dateKey(from: date, calendar: calendar)
                let items = agendaItems(
                    on: key,
                    date: date,
                    calendar: calendar,
                    monthTasksByDate: monthTasksByDate,
                    bundlesByDate: bundlesByDate,
                    eventsByDate: eventsByDate
                )
                guard !items.isEmpty else { return nil }
                return iOSCalendarAgendaDaySection(date: date, key: key, items: items)
            }
    }

    private var sections: [iOSCalendarAgendaDaySection] {
        Self.sections(
            monthDate: monthDate,
            calendar: calendar,
            monthTasksByDate: monthTasksByDate,
            bundlesByDate: bundlesByDate,
            eventsByDate: eventsByDate
        )
    }

    var body: some View {
        content
            .background(Theme.bg)
            .sheet(item: $selectedBundle) { bundle in
                iOSCalendarBundleDetailSheet(bundle: bundle)
            }
            .sheet(item: $selectedEvent) { selection in
                iOSCalendarEventEditSheet(event: selection.event)
            }
    }

    /// A month holding nothing draws no scroll view at all.
    ///
    /// Not a nicety: an empty `LazyVStack` under a live `.scrollPosition(id:)` binding is a
    /// position pointing at a stack with no ids, which is the state every scroll bug on this
    /// surface has started from. There is nothing to place, so there is nothing to place it with.
    @ViewBuilder
    private var content: some View {
        let sections = self.sections
        if sections.isEmpty {
            EmptyStateView(
                message: "Nothing this month",
                subtitle: "Days with events, blocks or tasks show up here.",
                icon: "calendar"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            agenda(sections)
        }
    }

    private func agenda(_ sections: [iOSCalendarAgendaDaySection]) -> some View {
        let listedDayKeys = sections.map(\.key)
        let initialScrollTarget = CadenceCalendarMonthAgendaSupport.initialScrollTarget(
            forSelectedDay: DateFormatters.dateKey(from: selectedDate),
            listedDayKeys: listedDayKeys
        )

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    daySection(section)
                        .id(section.key)
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
            scrollAgenda(toSelected: DateFormatters.dateKey(from: newValue), listedDayKeys: listedDayKeys)
        }
        .onChange(of: scrolledDayKey) { _, newValue in
            // The same gate the month grid above this agenda already applies, and for the same
            // reason: `cadenceLazyScrollAnchor` asserts the opening section, and a report older
            // than that assertion names the section the layout happened to start at. Adopting it
            // moves the selection — and therefore the lit grid cell — to a day the user never
            // touched. Only the reading that confirms the assertion switches this on.
            switch CadenceLazyScrollAnchor.report(
                newValue,
                target: initialScrollTarget,
                hasConfirmedPlacement: didConfirmInitialDay
            ) {
            case .ignore:
                return
            case .confirmsPlacement:
                didConfirmInitialDay = true
            case .adopt:
                adoptScrolledDay(newValue)
            }
        }
        .onChange(of: monthDate) { _, _ in
            realignAgendaWithMonth(listedDayKeys: listedDayKeys)
        }
    }

    private func daySection(_ section: iOSCalendarAgendaDaySection) -> some View {
        let isToday = calendar.isDateInToday(section.date)
        let isSelected = calendar.isDate(section.date, inSameDayAs: selectedDate)

        return VStack(alignment: .leading, spacing: 10) {
            // The same header every board column gets — and now only over days that have something
            // under it. This used to draw for every day of the month, on the argument that a bare
            // header says "nothing here" more quietly than a "Nothing scheduled" card would. That
            // was the right comparison and the wrong conclusion: it only ranked two kinds of
            // chrome against each other, and the user, looking at thirty quiet headers, asked for
            // the third option. A day with nothing on it is now not a section at all.
            CadenceBoardColumnHeader(
                dotColor: isToday ? Theme.amber : isSelected ? Theme.blue : Theme.dim,
                title: CadenceCalendarMonthAgendaSupport.dayHeaderLabel(for: section.date),
                count: section.items.count,
                accentRule: isToday ? Theme.amber : nil
            )

            ForEach(section.items) { item in
                agendaRow(item)
            }
        }
        .opacity(calendar.isDate(section.date, equalTo: monthDate, toGranularity: .month) ? 1 : 0.55)
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
            iOSTaskRow(task: task)
        }
    }

    /// One day's items, in the order a board day column would put them: events, then blocks, then
    /// tasks, all interleaved by start time. Reuses `iOSCalendarBoardColumnItem` rather than
    /// introducing a second ordering for the same three kinds of thing.
    ///
    /// Tasks come from the **same** `monthTasksByDate` the grid dots are drawn from, so a day the
    /// grid marks is never a day the agenda shows as empty.
    private static func agendaItems(
        on key: String,
        date: Date,
        calendar: Calendar,
        monthTasksByDate: [String: [AppTask]],
        bundlesByDate: [String: [TaskBundle]],
        eventsByDate: [String: [EKEvent]]
    ) -> [iOSCalendarBoardColumnItem] {
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

    /// A tap on a grid day. Most days have no section of their own now, so the resolution to the
    /// nearest one that does is part of this decision rather than something the caller layers on
    /// top — see `CadenceCalendarMonthAgendaSupport.scrollTarget(forSelectedDay:…)`.
    private func scrollAgenda(toSelected key: String, listedDayKeys: [String]) {
        guard let target = CadenceCalendarMonthAgendaSupport.scrollTarget(
            forSelectedDay: key,
            scrolledKey: scrolledDayKey,
            listedDayKeys: listedDayKeys
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
    ///
    /// Doubly so now that a quiet day is not listed at all: the same day can be a section in one
    /// month's list and absent from the next month's for no reason the user did anything about.
    private func realignAgendaWithMonth(listedDayKeys: [String]) {
        scrolledDayKey = CadenceCalendarMonthAgendaSupport.initialScrollTarget(
            forSelectedDay: DateFormatters.dateKey(from: selectedDate),
            listedDayKeys: listedDayKeys
        )
    }
}

/// One drawn day of the agenda: the day, its key, and the items that made it worth drawing.
///
/// A value type rather than a tuple so `ForEach` has an identity to use, and so "the sections" and
/// "the section keys" are provably the same list.
private struct iOSCalendarAgendaDaySection: Identifiable {
    let date: Date
    let key: String
    let items: [iOSCalendarBoardColumnItem]

    var id: String { key }
}

/// The month grid in its compact form: a day number and, when the day holds anything at all, a dot.
///
/// The full-size cell (`iOSCalendarMonthDayCell`, still what a split-width iPad pane draws) lists up
/// to five chips per day and needs 104pt to do it, which is why only three weeks fitted. Here
/// the day's items are one scroll away in the agenda, so the cell only has to answer "is there
/// something on this day" — and every week of the month fits.
private struct iOSCalendarMonthCompactGrid: View {
    @Binding var topRowDate: Date
    @Binding var selectedDate: Date
    let rowHeight: CGFloat
    let weekdayHeaderHeight: CGFloat
    let bottomPadding: CGFloat
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]

    private let calendar = Calendar.current

    var body: some View {
        iOSCalendarMonthScrollingGrid(
            topRowDate: $topRowDate,
            rowHeight: rowHeight,
            weekdayHeaderHeight: weekdayHeaderHeight
        ) { date, displayMonth in
            iOSCalendarMonthCompactDayCell(
                date: date,
                displayMonth: displayMonth,
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                hasItems: hasItems(on: DateFormatters.dateKey(from: date)),
                rowHeight: rowHeight
            ) {
                selectedDate = date
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, bottomPadding)
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

    /// The same treatment the full-size cell and every date picker in the app use — see
    /// `CadenceCalendarDayBadge`. This cell had it inverted too.
    private var badge: CadenceCalendarDayBadge {
        CadenceCalendarDayBadge.style(isToday: isToday, isSelected: isSelected)
    }

    private var dateLabelColor: Color {
        switch badge.label {
        case .normal: return isCurrentMonth ? Theme.text : Theme.dim
        case .accent: return Theme.blue
        case .onFill: return Theme.onColor
        }
    }

    private var badgeFill: Color {
        switch badge.fill {
        case .none:  return Color.clear
        case .wash:  return Theme.blue.opacity(CadenceCalendarDayBadge.washOpacity)
        case .solid: return Theme.blue
        }
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
                    .font(.system(size: badgeSize >= 28 ? 15 : 12, weight: badge.isEmphasized ? .bold : .medium))
                    .foregroundStyle(dateLabelColor)
                    .monospacedDigit()
                    .frame(width: badgeSize, height: badgeSize)
                    .background(badgeFill)
                    .clipShape(Circle())
                    .overlay {
                        // Today, when it is also the selected day — both take the solid fill, so
                        // this ring is what keeps the two facts from collapsing into one.
                        if badge.showsTodayRing {
                            Circle()
                                .strokeBorder(Theme.blue, lineWidth: 1.5)
                                .padding(-2.5)
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
