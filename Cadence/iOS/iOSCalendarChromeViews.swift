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
    /// `dateTitle` below and `iOSDateJumpTitle`.
    @Binding var leadingDate: Date
    /// Which unit that date is read in. See `CadenceCalendarDateTitleFormat`.
    var titleFormat: CadenceCalendarDateTitleFormat = .day
    @Binding var monthDetail: CadenceCalendarMonthDetail
    var showsMonthDetailControl = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let calendar = Calendar.current

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

            dateTitle
        }
        .frame(minWidth: horizontalSizeClass == .regular ? 208 : 116, idealWidth: 246, maxWidth: 312, alignment: .leading)
    }

    /// The calendar's date title: the date at the **leading edge of what is on screen**, and the
    /// control that jumps to another one.
    ///
    /// It used to read `Aug 19-25` on a timed grid, `Aug 7-13` on the Board and `August 2026` on
    /// Month — spans of the fixed windows those surfaces rendered. All four scroll continuously now,
    /// so there is no such window: what is on screen straddles whatever the finger left it on, and a
    /// range printed over it would be describing something the surface no longer has. One live
    /// reading is the honest one — and it is the one that can also be a button, which is what made
    /// deleting `‹ ➤ ›` safe.
    ///
    /// `titleFormat` is the unit that reading is in: a day for the timed grids and the Board, a
    /// month for the month grid, whose bound value is a week row rather than a day. Everything the
    /// two differ by is in `CadenceCalendarDateTitleSupport`, which is in `Shared/` and tested — and
    /// it is exactly the four answers `iOSDateJumpTitle` asks a caller for, which is why this is now
    /// an argument list rather than a second copy of the Notes header's title.
    private var dateTitle: some View {
        iOSDateJumpTitle(
            date: $leadingDate,
            label: CadenceCalendarDateTitleSupport.label(
                for: leadingDate,
                format: titleFormat,
                calendar: calendar
            ),
            isAtNow: CadenceCalendarDateTitleSupport.isAtNow(
                leadingDate,
                format: titleFormat,
                calendar: calendar
            ),
            metrics: .page,
            pickerDate: { date in
                CadenceCalendarDateTitleSupport.pickerDate(for: date, format: titleFormat, calendar: calendar)
            },
            anchor: { picked in
                CadenceCalendarDateTitleSupport.anchor(forPicked: picked, format: titleFormat, calendar: calendar)
            }
        )
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
    // home. `dateTitle` carries it on all four now.
}

#endif
