#if os(iOS)
import SwiftUI

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
    /// Set on iPhone, where the page is pushed with its navigation bar hidden and this row is the
    /// top of the screen. See `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil
    @Binding var viewMode: CadenceCalendarViewMode
    @Binding var presentation: CadenceCalendarPresentation
    /// The leading edge of whatever is on screen — the leftmost day column on a timed grid or the
    /// Board, the top week row on Month. Every surface has one now, so the title *is* the date
    /// control on all four: it names where you are and it is the way to go somewhere else. See
    /// `iOSCalendarDateTitle`.
    @Binding var leadingDate: Date
    /// Which unit that date is read in. See `CadenceCalendarDateTitleFormat`.
    var titleFormat: CadenceCalendarDateTitleFormat = .day
    @Binding var monthDetail: CadenceCalendarMonthDetail
    var showsMonthDetailControl = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    monthDetailControl
                    modeControl
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
                    monthDetailControl
                    modeControl
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    titleBlock
                    Spacer(minLength: 8)
                }

                HStack(spacing: 8) {
                    monthDetailControl
                    modeControl
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

            iOSCalendarDateTitle(date: $leadingDate, format: titleFormat)
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

    // `‹ ➤ ›` used to close this row. It is gone from every calendar surface, because every one of
    // them now scrolls in the axis its chevrons moved: the timed grids and the Board through a wide
    // run of day columns, Month through a wide run of week rows. Two chevrons that say nothing a
    // finger does not are two controls to explain and one row of chrome to pay for.
    //
    // The middle control was the one that had to be *replaced* rather than dropped — `location.fill`
    // is jump-to-today, not a direction, and a surface that scrolls arbitrarily far needs a way
    // home. `iOSCalendarDateTitle` carries it on all four now.
}

/// The calendar's title: the date at the **leading edge of what is on screen**, and the control that
/// jumps to another one.
///
/// It used to read `Aug 19-25` on a timed grid, `Aug 7-13` on the Board and `August 2026` on Month —
/// spans of the fixed windows those surfaces rendered. All four scroll continuously now, so there is
/// no such window: what is on screen straddles whatever the finger left it on, and a range printed
/// over it would be describing something the surface no longer has. One live reading is the honest
/// one — and it is the one that can also be a button, which is what made deleting `‹ ➤ ›` safe.
///
/// `format` is the unit that reading is in: a day for the timed grids and the Board, a month for the
/// month grid, whose bound value is a week row rather than a day. Everything the two differ by is in
/// `CadenceCalendarDateTitleSupport`, which is in `Shared/` and tested.
///
/// This is deliberately the same shape as `iOSNotesDateTitle` (`2929867`): a bold label, a
/// `chevron.down`, blue when you are away from now, and a popover whose first row is a way back.
/// It is **not** that view reused, and the reason is a file boundary rather than a design one —
/// `iOSNotesDateTitle` is written against `CadenceMobileNotesTab` and a `"yyyy-MM-dd"` string
/// binding, and generalising it means editing `iOSNotesView.swift`. When the two are next open at
/// the same time they should become one view taking a `Date` binding, a label closure and a
/// "back to now" title; everything below this line is that view with the notes-specific half
/// removed.
struct iOSCalendarDateTitle: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var date: Date
    var format: CadenceCalendarDateTitleFormat = .day

    @State private var isOpen = false
    @State private var viewMonth = Date()
    /// The day the popover's calendar is on. Not `date` itself: on Month the bound value is a week
    /// row start, so binding the picker straight to it would light up July 27 under a grid reading
    /// "August" and would take a picked day as a week rather than as a month.
    @State private var pickerDate = Date()

    private let calendar = Calendar.current

    private var isAtNow: Bool {
        CadenceCalendarDateTitleSupport.isAtNow(date, format: format, calendar: calendar)
    }

    private var label: String {
        CadenceCalendarDateTitleSupport.label(for: date, format: format, calendar: calendar)
    }

    var body: some View {
        Button {
            syncPickerDate()
            isOpen = true
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: horizontalSizeClass == .regular ? 21 : 18, weight: .bold))
                    // Blue when the surface is showing some other day or month, so the header itself
                    // says you have scrolled away. Without it a week in March is indistinguishable
                    // at a glance from this one.
                    .foregroundStyle(isAtNow ? Theme.text : Theme.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isAtNow ? Theme.dim : Theme.blue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .accessibilityLabel("\(label). Choose a date")
        // `.top`, for the reason `iOSNotesDateTitle` gives: the arrow edge names the popover's own
        // edge, so `.bottom` would put the panel above an anchor that is already in the top chrome.
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            iOSCalendarDatePopover(
                date: pickedDate,
                viewMonth: $viewMonth,
                isOpen: $isOpen,
                isAtNow: isAtNow,
                onNow: {
                    date = CadenceCalendarDateTitleSupport.nowAnchor(format: format, calendar: calendar)
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    /// A binding rather than `onChange(of: pickerDate)`, so only a **pick** writes back. Seeding the
    /// picker when the popover opens would otherwise look like one: on Month the seed round-trips
    /// through `displayedMonth` → `topRow`, so merely opening the panel mid-month would snap the
    /// grid to that month's first row without the user touching anything.
    private var pickedDate: Binding<Date> {
        Binding(
            get: { pickerDate },
            set: { newValue in
                pickerDate = newValue
                date = CadenceCalendarDateTitleSupport.anchor(
                    forPicked: newValue,
                    format: format,
                    calendar: calendar
                )
            }
        )
    }

    private func syncPickerDate() {
        let seed = CadenceCalendarDateTitleSupport.pickerDate(for: date, format: format, calendar: calendar)
        pickerDate = seed
        var components = calendar.dateComponents([.year, .month], from: seed)
        components.day = 1
        viewMonth = calendar.date(from: components) ?? Date()
    }
}

/// The calendar behind the title, plus the one shortcut that replaced the toolbar's
/// `location.fill`.
private struct iOSCalendarDatePopover: View {
    @Binding var date: Date
    @Binding var viewMonth: Date
    @Binding var isOpen: Bool
    let isAtNow: Bool
    let onNow: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            if !isAtNow {
                Button {
                    onNow()
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
