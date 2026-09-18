/// The hour ladder every timed grid in the app draws: how often it says the hour louder, and the
/// two weights it says it at — for the rule across the canvas and for the label down the rail.
///
/// **This is the whole of [[T-1129]], and the shape of the answer is the answer.** The repository
/// owner chose *"bring iOS's every-third-hour rung to the Mac"* over leaving the two ladders alone
/// and over flattening iOS, and bound whoever built it to derive the weights **once** here rather
/// than copy the cadence across — because copying a cadence without the weights it selects between
/// is exactly how [[T-596]] happened: two iOS surfaces both spelled `% 3` and then disagreed about
/// what the emphasis *was*. A cadence and its weights are one fact. There is one `% interval`
/// comparison in the app now, and it is `isEmphasised(hour:)`.
///
/// **What each platform still owns.** How tall an hour is (macOS derives it from a resizable
/// window, iOS multiplies a fixed base by a pinch), how wide a rule is drawn, and whether the
/// canvas subdivides the hour at all — macOS's half-hour tick at its deepest zoom has no iOS
/// counterpart and, per the decision, stays. What is shared is what the ladder *says*: every third
/// hour is structure and the two between it are texture.
///
/// **Why these four numbers.** They are iOS's, unchanged, and the decision is what picks them: the
/// rung travels from iOS to the Mac, not the Mac's weight to iOS, so the platform that already had
/// the vocabulary keeps its figures and the platform gaining it adopts them. [[T-619]]'s own
/// measurement says the same thing from the other end — the Mac was drawing *every* hour at 1.49×
/// iOS's heaviest hour and 3.42× its ordinary one, so a Mac ladder that grew a rung while keeping
/// its old every-hour weight underneath would have had texture lines louder than the other
/// platform's structure lines. The Mac's ordinary hour coming down to `ordinaryRuleOpacity` is the
/// correction those numbers were already asking for, and it does not go faint: the Mac draws this
/// pair at `CalendarVisualStyle.hourRuleWidth` (0.95pt) against iOS's
/// `iOSCalendarHairlineMetrics.width` (0.5pt), so every line on the Mac's ladder still carries
/// roughly 1.9× the ink of the iOS line that settled the figure.
///
/// A `nonisolated` enum outside every platform conditional, like `CadenceCalendarWeekdayHeaderMetrics`
/// and `CadenceTimelineNowLineSupport`, so `CadenceTests` — which builds for macOS and cannot see
/// `Cadence/iOS/` at all — can pin the figures both platforms draw with.
nonisolated enum CadenceCalendarHourLadderMetrics {
    /// How often the ladder says the hour louder: every third line, and every third label.
    ///
    /// Three, from iOS, where it has been the cadence on both timed surfaces since [[T-596]]. It is
    /// the coarsest rung that still lands inside a screenful at every zoom either platform offers,
    /// and — unlike a six- or twelve-hour rung — it divides the hours a working day is read in.
    static let emphasisInterval: Int = 3

    /// Whether this hour is a rung rather than one of the two between.
    ///
    /// Takes the hour rather than a row index on purpose: both platforms' canvases happen to start
    /// at `CadenceScheduleSupport.calendarStartHour` today, and an index-based rung would silently
    /// slide off the clock the day one of them does not. A rung is `0`, `3`, `6` … of the *day*.
    static func isEmphasised(hour: Int) -> Bool {
        hour % emphasisInterval == 0
    }

    // MARK: The rule across the canvas

    /// The hour rule on a rung.
    static let emphasisedRuleOpacity: Double = 0.46

    /// The hour rule on the two hours between rungs.
    ///
    /// The gap between this and `emphasisedRuleOpacity` is the whole effect — a 2.3× step, which is
    /// what makes the rung legible on a 24-hour grid without labels. They are stated as a pair, and
    /// read as a pair through `ruleOpacity(hour:)`, so neither can be tuned alone.
    static let ordinaryRuleOpacity: Double = 0.20

    /// The weight the hour rule at `hour` is drawn at. Every timed canvas in the app calls this.
    static func ruleOpacity(hour: Int) -> Double {
        isEmphasised(hour: hour) ? emphasisedRuleOpacity : ordinaryRuleOpacity
    }

    // MARK: The label down the rail

    /// The `12 AM` label beside a rung.
    ///
    /// Not 1.0. The rail is chrome beside the content, and a rung's label reads as the loud one
    /// because the two under it are quiet, not because it is at full strength.
    static let emphasisedLabelOpacity: Double = 0.9

    /// The `12 AM` label on the two hours between rungs.
    static let ordinaryLabelOpacity: Double = 0.45

    /// The weight the hour label at `hour` is drawn at. All four hour rails in the app call this.
    static func labelOpacity(hour: Int) -> Double {
        isEmphasised(hour: hour) ? emphasisedLabelOpacity : ordinaryLabelOpacity
    }
}
