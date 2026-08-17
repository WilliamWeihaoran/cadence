#if os(iOS)
import SwiftUI

struct iOSCalendarLeadItem: Equatable {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    static func == (lhs: iOSCalendarLeadItem, rhs: iOSCalendarLeadItem) -> Bool {
        lhs.title == rhs.title &&
        lhs.detail == rhs.detail &&
        lhs.systemImage == rhs.systemImage
    }
}

/// The line under the toolbar that says what the selected day holds.
///
/// It used to be five shadowed cards in a row — a day card, four metric cards and a lead-item card,
/// each with its own fill, radius and elevation — occupying a full band above the calendar. Every
/// number in it is still here; they are chips on one row now, which is the treatment macOS uses for
/// exactly this kind of small tinted fact. The two things that went are the presentation label
/// ("Week" / "Board"), which only repeated the toolbar pill already lit up beside it, and the
/// "No lead item / Add work from the inspector" placeholder card, which took a card's worth of
/// space to say nothing.
struct iOSCalendarContextStrip: View {
    let selectedDate: Date
    let timedCount: Int
    let taskCount: Int
    let eventCount: Int
    let bundleCount: Int
    let leadItem: iOSCalendarLeadItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var summary: String? {
        CadenceCalendarDaySummary.line(
            taskCount: taskCount,
            timedCount: timedCount,
            bundleCount: bundleCount,
            eventCount: eventCount
        )
    }

    /// On iPhone this row exists only to say what the day holds, so a day holding nothing has no
    /// row: the band used to persist and render "0 total · 0 timed · 0 tasks · 0 events". On iPad it
    /// also carries the date, and every surface that still asks for this row is one where nothing
    /// else names the selected day — the Board, where the leading column did, no longer asks. See
    /// `CadenceCalendarPaneLayout.showsDaySummaryStrip`.
    private var hasContent: Bool {
        !isCompact || summary != nil || leadItem != nil
    }

    var body: some View {
        if hasContent {
            strip
        }
    }

    private var strip: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    // On iPhone the day inspector sits immediately below this row and heads itself
                    // with the same date tile and the same "Thursday, January 15" — the two were
                    // about 50pt apart. The date belongs to the pane that lists the day's items, so
                    // it stays there and this row keeps only the counts. On iPad the inspector is a
                    // column to the side, not the next thing down, and this is the only date the
                    // calendar pane itself carries.
                    if !isCompact {
                        selectedDayLabel
                    }

                    if let summary {
                        summaryLabel(summary)
                    }

                    if let leadItem {
                        leadItemLabel(leadItem)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, isCompact ? 16 : 18)
                .padding(.vertical, 9)
                .frame(minWidth: horizontalSizeClass == .regular ? nil : 0)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(Theme.bg.opacity(0.84))

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
    }

    private var selectedDayLabel: some View {
        HStack(spacing: 9) {
            VStack(spacing: 1) {
                Text(DateFormatters.dayOfWeek.string(from: selectedDate).prefix(3).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .lineLimit(1)
                Text(DateFormatters.dayNumber.string(from: selectedDate))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }
            .frame(width: 36, height: 36)
            .background(Theme.blue.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.22), lineWidth: 1)
            }

            Text(DateFormatters.longDate.string(from: selectedDate))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// One quiet line, not a rank of tinted chips.
    ///
    /// This was five `iOSMetaChip`s in four colours — blue "total", purple "timed", green "tasks",
    /// amber "blocks"/"events" — every one of them permanently on screen, so an empty day, which is
    /// most days, spent a band of chrome saying "0" four times in four hues. Blocks and events are
    /// still counted separately (summing them made 2 blocks + 1 event read as 0 blocks + 3 events);
    /// they, and the row itself, are simply absent at zero. See `CadenceCalendarDaySummary`.
    private func summaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .fixedSize()
    }

    private func leadItemLabel(_ leadItem: iOSCalendarLeadItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: leadItem.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(leadItem.tint)

            Text(leadItem.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Text(leadItem.detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.subdued)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next up: \(leadItem.title), \(leadItem.detail)")
    }
}

/// The ghost add row a day surface carries — one line, full width, no date on it.
///
/// The Calendar Board's day column has had this row since it was built; Month's `Day` reading lost
/// its only add control in `42de745`, when the day header bar that carried the `+` came out for
/// naming a day the grid beside it had already named. The row is the shape that gives it back
/// without giving the bar back: it says what it does and nothing about which day it is on, so it can
/// sit under a grid cell that is already lit up.
///
/// One row rather than two near-copies, because the two surfaces open the same quick-create sheet.
struct iOSCalendarAddItemRow: View {
    var title = "Add task"
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.surfaceElevated.opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

struct iOSCalendarToolbar: View {
    let title: String
    /// Set on iPhone, where the page is pushed with its navigation bar hidden and this row is the
    /// top of the screen. See `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil
    @Binding var viewMode: CadenceCalendarViewMode
    @Binding var presentation: CadenceCalendarPresentation
    /// Set on the timed grids, where the title *is* the date control — the day at the leading edge
    /// of the grid, and the way to jump to another one. `nil` on Month and Board, whose titles name
    /// a whole span that no single date could stand for. See `iOSCalendarDateTitle`.
    var leadingDate: Binding<Date>? = nil
    @Binding var monthDetail: CadenceCalendarMonthDetail
    var showsMonthDetailControl = false
    /// Month and Board still step a window at a time and have nothing that scrolls in its place, so
    /// they keep the chevrons. The timed grids do not — see `navigationControls`.
    var showsNavigationControls = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactToolbar
            } else {
                regularToolbar
            }
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 18 : 16)
        .padding(.vertical, horizontalSizeClass == .regular ? 10 : 12)
        .background(Theme.surface)
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                titleBlock
                Spacer(minLength: 10)
                navigationControls
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    modeControl
                    monthDetailControl
                }
                .padding(.trailing, 1)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// `ViewThatFits` falls back to its **last** child when none of them fit, and then squeezes it.
    /// With only the two single-row options here, an 11" iPad in portrait — 632pt of pane after the
    /// 188pt sidebar — had no fitting layout, so the mode group was compressed to `iOSSegmentedPill`'s
    /// 58pt `minWidth` and "Week", "Month" and "Board" all rendered as a bare "…". A chooser whose
    /// options are indistinguishable is worse than one that has wrapped, so the fallback is now the
    /// phone's own two-row shape rather than an unreadable single row.
    private var regularToolbar: some View {
        ViewThatFits(in: .horizontal) {
            // One single-row option, not two. There used to be a wider one that also carried the
            // `− 1x +` zoom cluster and a narrower fallback without it; with zoom moved onto the
            // canvas as a pinch, the two collapsed into the same row.
            singleRowToolbar {
                HStack(spacing: 10) {
                    modeControl
                    monthDetailControl
                    navigationControls
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    titleBlock
                    Spacer(minLength: 8)
                    navigationControls
                        .layoutPriority(1)
                }

                HStack(spacing: 8) {
                    modeControl
                    monthDetailControl
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The controls hold `layoutPriority(1)`, not the title.
    ///
    /// It used to be the other way round, and that is what made the outer `ViewThatFits` lie to
    /// itself: the fit test measures ideal sizes, but in the real layout a priority-1 `titleBlock`
    /// grew to its 312pt `maxWidth` whatever the title said, so a row `ViewThatFits` had accepted
    /// arrived 26pt short and the mode pills were squeezed to "Mo…" and "B…" on a 13" iPad. The
    /// controls are the part that cannot shrink without becoming unreadable; the title is the part
    /// with slack in it, and `minWidth` still stops it going under 208.
    private func singleRowToolbar<Controls: View>(@ViewBuilder controls: () -> Controls) -> some View {
        HStack(spacing: 12) {
            titleBlock

            Spacer(minLength: 8)

            controls()
                .layoutPriority(1)
        }
        .frame(minHeight: 48)
    }

    /// Title only. This used to carry a "CALENDAR" eyebrow above the date — a page header naming
    /// the page you are already looking at, which the tab bar and sidebar both already say.
    private var titleBlock: some View {
        HStack(spacing: horizontalSizeClass == .regular ? 11 : 0) {
            if let onBack {
                iOSHeaderBackButton(action: onBack)
                    .padding(.leading, -8)
                    .padding(.trailing, 2)
            }

            if horizontalSizeClass == .regular {
                iOSIconTile(
                    systemImage: CadenceFeatureDestination.calendar.systemImage,
                    color: CadenceFeatureDestination.calendar.tint,
                    size: 34,
                    iconSize: 15
                )
            }

            if let leadingDate {
                iOSCalendarDateTitle(date: leadingDate)
            } else {
                Text(title)
                    .font(.system(size: horizontalSizeClass == .regular ? 21 : 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(minWidth: horizontalSizeClass == .regular ? 208 : 116, idealWidth: 246, maxWidth: 312, alignment: .leading)
    }

    private var modeControl: some View {
        iOSSegmentedPillGroup {
            ForEach(CadenceCalendarViewMode.pickerCases, id: \.self) { mode in
                iOSSegmentedPill(
                    title: mode.rawValue,
                    systemImage: mode == .month ? "calendar" : "rectangle.split.3x1",
                    isSelected: presentation == .timeline && viewMode == mode
                ) {
                    presentation = .timeline
                    viewMode = mode
                }
            }

            iOSSegmentedPill(
                title: "Board",
                systemImage: "rectangle.grid.2x2",
                isSelected: presentation == .board
            ) {
                presentation = .board
            }
        }
    }

    /// Month only, and only where both of its readings can actually be placed — see
    /// `CadenceCalendarMonthLayout.showsDetailControl`. It sits immediately beside the mode control
    /// because it is the second half of the same question: Month, read how?
    ///
    /// Which reading you got used to be a consequence of window width, so rotating an iPad swapped
    /// the agenda for the day inspector with nothing on screen admitting it had happened.
    @ViewBuilder
    private var monthDetailControl: some View {
        if showsMonthDetailControl {
            iOSSegmentedPillGroup {
                ForEach(CadenceCalendarMonthDetail.allCases, id: \.self) { detail in
                    iOSSegmentedPill(
                        title: detail.title,
                        systemImage: detail.systemImage,
                        isSelected: monthDetail == detail,
                        minWidth: 52,
                        accessibilityHint: detail.accessibilityHint
                    ) {
                        monthDetail = detail
                    }
                }
            }
        }
    }

    /// `‹ ➤ ›` — but only where something else does not already do its job.
    ///
    /// The timed grids scroll now, in both directions and without end, so the two chevrons say
    /// nothing a finger does not. The middle control is the one that had to be replaced rather than
    /// simply dropped: it is `location.fill`, **jump to today**, not a direction, and deleting the
    /// cluster without a replacement would have left no way back to now from a grid that can be
    /// scrolled arbitrarily far. `iOSCalendarDateTitle` carries it — the same shape the Notes
    /// header uses, where the date popover grows a `Today` button once you are away from now.
    ///
    /// Month and Board keep the cluster. Neither of them scrolls in the axis their chevrons move:
    /// Month is a fixed grid stepped a month at a time, and the Board steps its window a week at a
    /// time and floors it at today. Deleting the control there would have removed navigation
    /// nothing replaced — which is exactly the mistake being avoided on the grids.
    @ViewBuilder
    private var navigationControls: some View {
        if showsNavigationControls {
            iOSSegmentedPillGroup {
                iOSIconButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Previous",
                    plateSize: 38,
                    iconSize: 13,
                    showsPlate: false,
                    action: previous
                )
                iOSIconButton(
                    systemImage: "location.fill",
                    accessibilityLabel: "Today",
                    foreground: Theme.blue,
                    plateSize: 38,
                    iconSize: 13,
                    showsPlate: false,
                    action: today
                )
                iOSIconButton(
                    systemImage: "chevron.right",
                    accessibilityLabel: "Next",
                    plateSize: 38,
                    iconSize: 13,
                    showsPlate: false,
                    action: next
                )
            }
        }
    }
}

/// The timed grid's title: the date of the **leftmost column on screen**, and the control that
/// jumps to another one.
///
/// It used to read `Aug 19-25` — the span of the fixed week the grid rendered. With the grid
/// scrolling continuously there is no such week: the columns on screen straddle whatever the finger
/// left them on, and a range printed over them would be describing a window the grid no longer has.
/// One date, live, is the honest reading — and it is the one that can also be a button.
///
/// This is deliberately the same shape as `iOSNotesDateTitle` (`2929867`): a bold label, a
/// `chevron.down`, blue when you are away from now, and a popover whose first row is a way back.
/// It is **not** that view reused, and the reason is a file boundary rather than a design one —
/// `iOSNotesDateTitle` is written against `CadenceMobileNotesTab` and a `"yyyy-MM-dd"` string
/// binding, and generalising it means editing `iOSNotesPanel.swift`. When the two are next open at
/// the same time they should become one view taking a `Date` binding, a label closure and a
/// "back to now" title; everything below this line is that view with the notes-specific half
/// removed.
struct iOSCalendarDateTitle: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var date: Date

    @State private var isOpen = false
    @State private var viewMonth = Date()

    private let calendar = Calendar.current

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    private var label: String {
        DateFormatters.shortDate.string(from: date)
    }

    var body: some View {
        Button {
            syncViewMonth()
            isOpen = true
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: horizontalSizeClass == .regular ? 21 : 18, weight: .bold))
                    // Blue when the grid is showing some other day, so the header itself says you
                    // have scrolled away. Without it a week in March is indistinguishable at a
                    // glance from this one.
                    .foregroundStyle(isToday ? Theme.text : Theme.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.dim : Theme.blue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .accessibilityLabel("\(label). Choose a date")
        // `.top`, for the reason `iOSNotesDateTitle` gives: the arrow edge names the popover's own
        // edge, so `.bottom` would put the panel above an anchor that is already in the top chrome.
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            iOSCalendarDatePopover(date: $date, viewMonth: $viewMonth, isOpen: $isOpen)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func syncViewMonth() {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = 1
        viewMonth = calendar.date(from: components) ?? Date()
    }
}

/// The calendar behind the grid's date title, plus the one shortcut that replaced the toolbar's
/// `location.fill`.
private struct iOSCalendarDatePopover: View {
    @Binding var date: Date
    @Binding var viewMonth: Date
    @Binding var isOpen: Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            if !calendar.isDateInToday(date) {
                Button {
                    date = calendar.startOfDay(for: Date())
                    isOpen = false
                } label: {
                    Text("Today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

                Divider().background(Theme.borderSubtle)
            }

            // `inlineStyle` because this popover owns its own width and background; see the same
            // call in `iOSNotesDatePopover`.
            MonthCalendarPanel(selection: $date, viewMonth: $viewMonth, isOpen: $isOpen, inlineStyle: true)
                .padding(.top, 10)
        }
        .frame(width: 280)
        .background(Theme.surfaceElevated)
    }
}
#endif
