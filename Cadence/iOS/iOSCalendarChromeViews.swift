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

    private var headerMetrics: CadencePageHeaderMetrics {
        CadencePageHeaderMetrics.metrics(role: .page, isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        toolbar
            .padding(
                .horizontal,
                iOSCalendarPageMetrics.horizontalPadding(isRegularWidth: horizontalSizeClass == .regular)
            )
            .padding(.vertical, iOSCalendarToolbarMetrics.verticalPadding)
            .background(Theme.surface)
    }

    /// One layout for both widths, chosen by whether the single row **fits** rather than by which
    /// device is holding it.
    ///
    /// It used to be two: an `if horizontalSizeClass == .compact` that always wrapped, beside a
    /// `ViewThatFits` whose fallback was — in its own words — "the phone's own two-row shape". So
    /// the phone's layout was already good enough for the iPad, and the iPad's was withheld from the
    /// phone at widths where it fits perfectly well: an iPhone in landscape has 820pt of row and was
    /// spending two rows on 500pt of content. Asking the question once answers it correctly at every
    /// width, which is what a size-class branch is standing in for whenever it is not about shape.
    ///
    /// `ViewThatFits` falls back to its **last** child when none of them fit, and then squeezes it.
    /// With only single-row options an 11" iPad in portrait — 632pt of pane after the 188pt sidebar —
    /// had no fitting layout, so the mode group was compressed to `iOSSegmentedPill`'s 58pt
    /// `minWidth` and "Week", "Month" and "Board" all rendered as a bare "…". A chooser whose options
    /// are indistinguishable is worse than one that has wrapped, so the fallback wraps.
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            // One single-row option, not two. There used to be a wider one that also carried the
            // `− 1x +` zoom cluster and a narrower fallback without it; with zoom moved onto the
            // canvas as a pinch, the two collapsed into the same row.
            singleRowToolbar {
                HStack(spacing: iOSCalendarToolbarMetrics.controlSpacing) {
                    monthDetailControl
                    modeControl
                }
            }

            wrappedToolbar
        }
    }

    /// The fallback: title on its own row, controls under it.
    ///
    /// The control run scrolls horizontally at **both** widths. That was the phone's safety valve —
    /// on Month the two pill groups come to roughly 385pt against 361pt of iPhone row — and there is
    /// no width at which a control run silently clipped is the better failure, so the iPad gets the
    /// same valve rather than a different one.
    private var wrappedToolbar: some View {
        VStack(alignment: .leading, spacing: iOSCalendarToolbarMetrics.stackSpacing) {
            HStack(spacing: iOSCalendarToolbarMetrics.controlSpacing) {
                titleBlock
                Spacer(minLength: iOSCalendarToolbarMetrics.controlSpacing)
            }

            ScrollView(.horizontal) {
                HStack(spacing: iOSCalendarToolbarMetrics.controlSpacing) {
                    monthDetailControl
                    modeControl
                }
                .padding(.trailing, 1)
            }
            .scrollIndicators(.hidden)
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
        HStack(spacing: iOSCalendarToolbarMetrics.controlSpacing) {
            titleBlock

            Spacer(minLength: iOSCalendarToolbarMetrics.controlSpacing)

            controls()
                .layoutPriority(1)
        }
        .frame(minHeight: iOSCalendarToolbarMetrics.singleRowMinHeight)
    }

    /// Title only. This used to carry a "CALENDAR" eyebrow above the date — a page header naming
    /// the page you are already looking at, which the tab bar and sidebar both already say.
    ///
    /// **And no identity tile.** The run was `iOSPageHeader`'s — optional back control, tile, title
    /// — and the tile is gone from this one surface deliberately. The calendar's title is not a
    /// label, it is a *control* (`iOSDateJumpTitle`, chevron and popover), and a filled purple
    /// calendar glyph sitting immediately to its left reads as the button's leading icon rather
    /// than as the page's identity — an identity the tab bar and the sidebar are already carrying.
    /// Today and the Notes headers keep their tiles: this is a considered difference on the one
    /// header whose title is a button, not an inconsistency to go and resolve.
    ///
    /// What remains is still drawn at `CadencePageHeaderMetrics`' figures rather than at a private
    /// copy of them — it had a private copy, a 34/15 tile at regular width only — so the back
    /// chevron and the gap after it stay in step with every other header.
    private var titleBlock: some View {
        let metrics = headerMetrics

        return HStack(spacing: metrics.rowSpacing) {
            if let onBack {
                iOSHeaderBackButton(action: onBack)
                    .padding(.leading, -8)
            }

            dateTitle
        }
        .frame(
            minWidth: iOSCalendarToolbarMetrics.titleMinWidth,
            idealWidth: iOSCalendarToolbarMetrics.titleIdealWidth,
            maxWidth: iOSCalendarToolbarMetrics.titleMaxWidth,
            alignment: .leading
        )
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
