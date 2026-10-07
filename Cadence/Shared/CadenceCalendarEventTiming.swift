import Foundation

/// Turns a `yyyy-MM-dd` day key plus a **minute of day** into the instant an EventKit event starts
/// at, on both platforms.
///
/// **A minute-of-day is a wall-clock reading, so the start is *set*, never added** ([[T-3050]],
/// the EventKit half of [[T-3048]]). `date(byAdding: .minute, value:, to: midnight)` is **elapsed**
/// time — `.hour`, `.minute` and `.second` are not calendrical units — so on a day that is 23 or 25
/// hours long it lands on a different clock reading than the picker, the timeline and the chip all
/// render for the same number. Measured on this toolchain in `America/New_York` with
/// `startMin = 540`: adding 540 minutes to midnight gives **10:00** on 2026-03-08 and **08:00** on
/// 2026-11-01, while `date(bySettingHour:minute:second:of:)` gives 09:00 on both and on an ordinary
/// day. Unlike the notification half, the wrong instant here is written **into the owner's real
/// Calendar** by `CalendarManager` and `iOSCalendarQuickCreateSheet`, outside Cadence and not
/// undoable from inside it.
///
/// **This is the start leg only, and deliberately so.** An event's *end* is a **duration** added to
/// a start that is already correct, and a 60-minute meeting really does last 60 minutes of real
/// time across a transition — so the end legs beside every call site keep their
/// `date(byAdding: .minute, value: duration, to: startDate)` and must not be "fixed" symmetrically.
/// `CadenceCalendarEventTimingTests` pins that distinction from both directions.
///
/// **The three readings that need a decision rather than a default**, all measured on this
/// toolchain in `America/New_York`, and all the same answers [[T-3048]] chose for the notification
/// leg:
///
/// - **A time the day does not have.** 02:30 on 2026-03-08 never occurs — the clocks jump from
///   01:59:59 EST to 03:00:00 EDT. Foundation answers **03:00 EDT**, the first instant at or after
///   the missing reading. For an event that is the behaviour we want and the same one Apple
///   Calendar shows: a block dropped into the gap opens the moment the gap closes, rather than
///   being written an hour past a time nobody picked (the old arithmetic answered 03:30).
/// - **An ambiguous time.** 01:30 on 2026-11-01 happens twice. Foundation answers the **first**
///   (01:30 EDT). Taking the earlier of the two keeps the event ahead of, not behind, the reading
///   on the wall, and it is the one the user watching the clock sees first.
/// - **Out of range.** `1440` or more names no time on the day and `bySettingHour:` returns `nil`,
///   so this returns `nil` and the caller refuses the write with `.invalidRange` rather than
///   rolling the event quietly onto a *different calendar day* than the one it was filed under, as
///   the old arithmetic did. An EventKit write wants this answer at least as much as a
///   notification does: a mis-dated row in the owner's real Calendar is not something Cadence can
///   take back. No production caller can reach it — the iOS sheet clamps through
///   `minuteOfDay(from:)` and the macOS timeline drop clamps through `TimelineMetrics.clampStart`
///   — so nothing changes about *whether* an event is written; this is the floor under them.
nonisolated enum CadenceCalendarEventTiming {
    /// The instant `startMin` minutes-of-day names on `dateKey`, or `nil` when it names none.
    ///
    /// - Parameter calendar: The calendar whose time zone the day key is parsed in **and** the
    ///   start time is set in — one calendar for both halves, because parsing a key in one zone and
    ///   setting a time in another lands on the wrong day (`DateFormatters.date(from:in:)` records
    ///   that measurement). Defaults to `.current`, which is every production call. A test passes an
    ///   explicit DST-observing zone because the scheme pins the test host to `TZ=UTC` ([[T-1116]]),
    ///   in which this whole distinction is invisible.
    static func startDate(dateKey: String, startMin: Int, calendar: Calendar = .current) -> Date? {
        guard let baseDate = DateFormatters.date(from: dateKey, in: calendar) else { return nil }
        return startDate(day: baseDate, startMin: startMin, calendar: calendar)
    }

    /// The same instant for a caller that holds a **`Date` somewhere in the day** rather than a
    /// stored day key ([[T-3051]]).
    ///
    /// `CalendarManager.createStandaloneEvent` is the one such caller: the macOS drag-to-create
    /// path hands it the day as a `Date` (`Date()` from `SchedulePanel`, the column's own date from
    /// `CalendarPageMonthSupportViews`), so it cannot reach the key overload. This is an *overload*
    /// and not a second helper on purpose — the rule "a minute-of-day is set, never added" is one
    /// rule, and the repo reached six copies of it by letting each call site spell it locally.
    ///
    /// **`day` is narrowed to its own start first.** `SchedulePanel` hands this `Date()` — any
    /// instant in the day — so the answer must not depend on when during the day the user dragged.
    /// *Measured, rather than assumed:* `date(bySettingHour:minute:second:of:)` is documented as
    /// searching forward, but on this toolchain it already answers the **same calendar day** from
    /// a 00:00, 09:00, 15:42 or 23:59 `of:`, on both transition days and an ordinary one, and for
    /// an ambiguous reading too. So the narrowing is not what stops a roll onto tomorrow — it is
    /// what makes this provably the *same* function as the key overload, whose base is always a
    /// midnight. `CadenceCalendarEventTimingTests` pins both halves.
    ///
    /// Every reading above about gaps, ambiguity and out-of-range applies here unchanged, because
    /// this is the function the key overload delegates to.
    static func startDate(day: Date, startMin: Int, calendar: Calendar = .current) -> Date? {
        guard startMin >= 0 else { return nil }
        return calendar.date(
            bySettingHour: startMin / 60,
            minute: startMin % 60,
            second: 0,
            of: calendar.startOfDay(for: day)
        )
    }
}
