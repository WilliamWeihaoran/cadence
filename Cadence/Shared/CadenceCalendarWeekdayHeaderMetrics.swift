import CoreGraphics
import SwiftUI

/// Every measurement a calendar column heads itself with: the weekday label, and — on the timed
/// surfaces — the day number and today-circle under it.
///
/// **The fork this ends was invisible to grep.** macOS's `CalDayHeaderView` set `MON` at a literal
/// `10` semibold kerned `0.5`; iOS's `iOSCalendarTimelineDayHeader` set the same label at a *named*
/// `iOSCalendarTimelineMetrics.weekdaySize` of `11` with no kerning at all. One literal against one
/// constant is a fork that no search for a shared token can find, which is why it outlived a
/// dedicated sweep of hand-rolled label styles (`docs/TODO.md` T-275, T-277).
///
/// **It is deliberately not `SectionEyebrowLabel`.** An eyebrow names the *section you are looking
/// at*; this names a date, above the number it belongs to, and it is tinted `Theme.blue` on today.
/// Pointing both at the eyebrow would have made the two headers agree by accident, on a component
/// whose job is a different one.
///
/// **There is no surface axis here**, for `CadenceBoardColumnHeaderMetrics`' reason: a day column
/// is a fixed-width column on every surface (macOS week/2-week, iPad and iPhone timed grids), so a
/// Mac gives this label no more room than an iPhone does and it gets no bigger type.
///
/// A `nonisolated` value type outside every platform conditional, so `CadenceTests` — which builds
/// for macOS and cannot see `Cadence/iOS/` at all — can pin the figures both platforms draw with.
nonisolated struct CadenceCalendarWeekdayHeaderMetrics: Sendable {
    /// The uppercased weekday over a day column, and the weekday row over a month grid.
    ///
    /// **10 wins, and macOS had it.** 10 is this app's size for the whole uppercased-semibold label
    /// tier — `SectionEyebrowLabel.fontSize`, `CadencePageHeaderMetrics.eyebrowSize`,
    /// `CadenceBoardColumnHeaderMetrics.labelSize`, which settled this exact 10-against-11 argument
    /// against an iOS 11 already.
    ///
    /// iOS's 11 had a stated reason and the reason did not hold: `iOSCalendarTimelineMetrics`
    /// documented it as "the same label the month grid sets over its own columns, at the same 11pt".
    /// The month grid renders that row at **both** sizes — `iOSCalendarMonthScrollingGrid` defaulted
    /// its `weekdaySymbolSize` to 10, which the agenda's compact grid took, while the full month
    /// grid passed 11 — so the same view drew two sizes and there was never one figure to agree
    /// with. That parameter is gone; all four weekday headers read this.
    static let labelSize: CGFloat = 10

    /// Kerning for the **uppercased** spelling — `MON` on the timed day columns.
    ///
    /// **macOS's 0.5 won the fork and then lost the ratio (T-496).** iOS's difference was never a
    /// decision — every uppercased short label in Cadence is kerned, a 3-letter uppercase run is
    /// the case kerning exists for, and the iOS side was a *missing modifier* rather than a `0`
    /// anybody typed; `iOSCalendarTimelineMetrics` never named kerning at all. So 0.5 was the right
    /// answer to "kerned or not". It was still a **third** letterspacing for one 10pt uppercase
    /// semibold role, beside `CadenceBoardColumnHeaderMetrics`' literal 0.4 and
    /// `SectionEyebrowLabel`'s derived 0.08em, in the one of the three files that had both siblings
    /// in view and disagreed with both anyway.
    ///
    /// The user settled it at 0.08em everywhere, which takes this label from 0.5 to 0.8 — measured
    /// at 1–6pt of line width across the strings actually drawn (`MON` 26 → 28pt, `WED` 26 → 27),
    /// with no truncation at any candidate in the narrowest column this label heads. The collapsed
    /// calendar-board rail, which is the one place letterspacing moves a layout *slot* rather than
    /// a line width, was measured too and is not a constraint: `UNSCHEDULED` is 88pt at 0.08em
    /// against a 96pt slot.
    ///
    /// **Derived, not typed.** A `0.8` here would be the same defect one value later — three files
    /// each holding an independently editable constant, with the ratio the design system derives
    /// from read by one of them. Multiplied by *this* struct's own `labelSize`, so the ratio is
    /// what is shared and the size stays this file's to state.
    ///
    /// The month grids do **not** take this: they spell their weekdays title-case (`Sun`, from
    /// `CadenceScheduleSupport.weekdaySymbols`), and kerning belongs to the uppercased run.
    static let labelKerning: CGFloat = labelSize * SectionEyebrowLabel.kerningRatio

    /// The band that row of weekdays fills, over a month grid.
    ///
    /// **The height was left behind when T-277 hoisted the size.** `iOSCalendarMonthGrid` framed it
    /// at 36 and `iOSCalendarMonthStack` at 22 — one row, one label, one grid container underneath
    /// both — and neither number carried a reason, so this is settled the way T-588 settled the hour
    /// label's inset: on which value more of the repo already stands behind.
    ///
    /// **22 wins on both counts.** It is the height `CadenceCalendarMonthAgendaSupport.gridRowHeight` is
    /// pinned against at eight call sites in `CalendarMonthAgendaTests` and `CalendarMonthDetailTests`,
    /// so 36 was the spelling no test had ever seen; and it is the one that clears the label without
    /// tripling the band — `labelSize` lays out at about 12pt, which 22 surrounds with the same 5pt
    /// the timed band gives its own date block (`iOSCalendarTimelineMetrics.dateBlockVerticalPadding`),
    /// where 36 would surround it with 12. The 14pt 36 was spending came straight out of cell height,
    /// on the one grid whose job is showing a whole month.
    static let bandHeight: CGFloat = 22

    /// Between the weekday label and the day number under it.
    ///
    /// **macOS's 2 wins**, and this is the one of the three differences with a measured consequence.
    /// macOS's band is a fixed `calDayHeaderHeight` of 52 that 2 already fits; iOS's is *derived*
    /// (`iOSCalendarTimelineMetrics.dayHeaderHeight`), and its own doc records that the band had
    /// been overflowing what the chip strip under it asks for. Taking the label to 10 and the gap to
    /// 2 hands that strip back 2.2pt. iOS's 3 carried no reason beyond being written down.
    static let labelSpacing: CGFloat = 2

    /// The day number, and the circle that fills behind it on today. **Both platforms already drew
    /// 18-in-32**, macOS as literals and iOS as `dayNumberSize` / `dayCircleSize`; stating them once
    /// is what stops them drifting the way the label above them did.
    static let dayNumberSize: CGFloat = 18
    static let dayCircleSize: CGFloat = 32

    /// The plate every day column's header paints — weekday, day disc and all-day band alike.
    ///
    /// **`Theme.bg`, the Mac's, and not iOS's `Theme.surface` (T-18808).** The header row sits on
    /// `Theme.bg` on both platforms already: the Mac's header strip and the iOS grid both paint it
    /// behind the row, and so do both time rails' corner above the hour labels. A `Theme.surface`
    /// header was therefore a lighter band with a seam at the rail corner on iOS, and on the Mac it
    /// would have merged the row into the `Theme.surface` toolbar directly above it. The hairlines
    /// under and between the headers are what separate the pinned row, not a plate colour.
    static var headerPlate: Color { Theme.bg }

    /// Today's accent wash over `headerPlate`. The Mac's 0.05: it is the platform whose today
    /// header already read as a highlight. One figure for the whole column — the Mac's all-day band
    /// had its own 0.03 and iOS's one fill covered its band at 0.035, which is two answers to the
    /// same question.
    static let todayWashOpacity: Double = 0.05

    /// The one fill both platforms' day headers paint (T-18808).
    ///
    /// **Today's wash is composited over the plate, never painted bare.** iOS painted a bare
    /// `Theme.blue.opacity(0.035)` on today and an opaque `Theme.surface` on every other day, and
    /// the pinned row has no background of its own — so today's 3.5% fell through to the grid's
    /// darker `Theme.bg` and the highlight read *darker* than its neighbours. Returned opaque, the
    /// fill cannot depend on whatever happens to be painted underneath it.
    ///
    /// `accent` exists so a test can walk `CadenceAccentPalette.all` without switching the app's
    /// shared selection; every call site takes the default.
    static func headerFill(isToday: Bool, accent: Color = Theme.blue) -> Color {
        guard isToday else { return headerPlate }
        return accent.opacity(todayWashOpacity).composited(over: headerPlate)
    }
}
