import CoreGraphics

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
}
