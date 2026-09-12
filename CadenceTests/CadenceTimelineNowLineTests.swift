import Foundation
import Testing
@testable import Cadence

/// **T-1131 — the now-line, and the fact that there is exactly one of it.**
///
/// The ticket's question was whether iOS's two timed grids should get the red current-time rule
/// macOS has always drawn; the repository owner's answer was *"Add it to iOS."* The standing repo
/// rule is one shared component over near-copies, so the Mac's `TimelineCurrentTimeOverlay` was
/// moved into `Shared/Components/` as `CadenceTimelineNowLine` and all three surfaces now build
/// that one type.
///
/// Two halves, and the split is forced rather than stylistic: `CadenceTests` builds on macOS, so it
/// compiles none of `Cadence/iOS/` and cannot instantiate either iOS call site. The arithmetic is
/// therefore behavioural — it lives in `CadenceTimelineNowLineSupport` precisely so it can be — and
/// only *which surfaces build the component* is a source scan.
@Suite(.serialized)
struct CadenceTimelineNowLineTests {

    // MARK: - The arithmetic

    /// Minutes-since-midnight carries the seconds, and it is measured in the zone the caller names.
    ///
    /// The zone is stated ([[T-1115]], [[T-1116]]) rather than left to `Calendar.current`: the same
    /// instant is a different time of day in every zone, so an unstated read here would have the
    /// test passing on the host's longitude. One instant, three zones, three different answers —
    /// which is the whole reason the function takes a calendar.
    @Test func theCurrentMinuteCarriesItsSecondsAndIsReadInTheStatedZone() throws {
        // 2026-09-12T12:30:30Z, built from components in a stated zone rather than parsed, so
        // the fixture itself carries no ambient reading.
        let utcForFixture = try CadenceTestTimeZones.calendar("UTC")
        let instant = try #require(
            utcForFixture.date(
                from: DateComponents(year: 2026, month: 9, day: 12, hour: 12, minute: 30, second: 30)
            )
        )

        let expected: [(zone: String, minute: CGFloat)] = [
            ("UTC", CGFloat(12 * 60 + 30) + 0.5),
            ("Asia/Tokyo", CGFloat(21 * 60 + 30) + 0.5),
            ("America/Los_Angeles", CGFloat(5 * 60 + 30) + 0.5)
        ]

        for probe in expected {
            let calendar = try CadenceTestTimeZones.calendar(probe.zone)
            let measured = CadenceTimelineNowLineSupport.fractionalMinuteOfDay(
                at: instant,
                calendar: calendar
            )
            #expect(
                abs(measured - probe.minute) < 0.0001,
                "\(probe.zone) read \(measured), not \(probe.minute)"
            )
        }

        // The seconds are the half-point of a minute rather than a rounding of it. Without the
        // fractional term the rule would sit still for a minute and then jump a whole one, which
        // at 58pt an hour is 0.97pt of visible stutter every tick cycle.
        let utc = utcForFixture
        let onTheMinute = try #require(
            utc.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12, minute: 30, second: 0))
        )
        #expect(
            CadenceTimelineNowLineSupport.fractionalMinuteOfDay(at: instant, calendar: utc)
                > CadenceTimelineNowLineSupport.fractionalMinuteOfDay(at: onTheMinute, calendar: utc)
        )
    }

    /// **The rule is drawn on today's canvas and nowhere else**, which on iOS's Calendar grid is
    /// the difference between one red line and one per visible day column.
    ///
    /// Both halves of `isVisible` are exercised against the same instant: the day test, and the
    /// range test for a canvas that does not draw the whole day. The Mac's Schedule panel and both
    /// iOS surfaces run `calendarStartHour..<calendarEndHour`, so the range half never fires there
    /// — it is `TimelineMetrics`' narrower canvases it exists for, and it is asserted here rather
    /// than trusted because the component is shared and the next canvas may not draw midnight.
    @Test func theNowLineIsDrawnOnlyOnTodaysCanvasAndOnlyInsideTheHoursItDraws() throws {
        let calendar = try CadenceTestTimeZones.calendar("UTC")
        let now = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 12, hour: 12, minute: 30, second: 0)
            )
        )
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))

        func visible(day: Date, startHour: Int = 0, endHour: Int = 24) -> Bool {
            CadenceTimelineNowLineSupport.isVisible(
                day: day,
                now: now,
                startHour: startHour,
                endHour: endHour,
                calendar: calendar
            )
        }

        #expect(visible(day: now))
        #expect(!visible(day: yesterday), "the rule was drawn on a column that is not today")
        #expect(!visible(day: tomorrow), "the rule was drawn on a column that is not today")

        // The range half: 12:30 is inside 9–17 and outside 13–17 and 0–12.
        #expect(visible(day: now, startHour: 9, endHour: 17))
        #expect(!visible(day: now, startHour: 13, endHour: 17))
        #expect(!visible(day: now, startHour: 0, endHour: 12))

        // Today's timeline passes a one-hour window per row — `startHour: hour, endHour: hour + 1`
        // — so exactly one of its 24 rows draws, and it is the row that owns the hour.
        let drawingRows = CadenceScheduleSupport.calendarHours.filter {
            visible(day: now, startHour: $0, endHour: $0 + 1)
        }
        #expect(drawingRows == [12], "\(drawingRows.count) of Today's hour rows drew a now-line")
    }

    /// The rule's own geometry: where it starts and how far it runs.
    ///
    /// The dot is the split macOS already had — the Schedule panel draws one, the Calendar page
    /// does not — and it is the only thing that moves the rule's origin: with a dot the rule backs
    /// up by the dot's radius so it leaves the dot's centre instead of its right edge, and it gets
    /// that radius back in width so the far end does not move. Both halves asserted, because a fix
    /// to one without the other shortens or lengthens the rule by 4pt on one surface only.
    @Test func theNowLineRuleStartsAtTheDotsCentreAndKeepsItsFarEnd() {
        let dot = CadenceTimelineNowLineSupport.dotDiameter
        let width: CGFloat = 300
        let leading: CGFloat = 8
        let trailing: CGFloat = 4

        let withDotX = CadenceTimelineNowLineSupport.lineOriginX(leadingInset: leading, showDot: true)
        let withoutDotX = CadenceTimelineNowLineSupport.lineOriginX(leadingInset: leading, showDot: false)
        let backedUp: CGFloat = leading - dot / 2
        #expect(withoutDotX == leading)
        #expect(withDotX == backedUp)

        func ruleWidth(showDot: Bool) -> CGFloat {
            CadenceTimelineNowLineSupport.lineWidth(
                totalWidth: width,
                leadingInset: leading,
                trailingInset: trailing,
                showDot: showDot
            )
        }

        let plainEnd: CGFloat = withoutDotX + ruleWidth(showDot: false)
        let dottedEnd: CGFloat = withDotX + ruleWidth(showDot: true)
        let farEdge: CGFloat = width - trailing
        #expect(plainEnd == farEdge)
        #expect(dottedEnd == plainEnd, "the dot moved the far end of the rule")

        // A canvas narrower than its own insets asks for nothing rather than for a negative frame:
        // a day column mid-pinch, or a pane being dragged shut.
        #expect(
            CadenceTimelineNowLineSupport.lineWidth(
                totalWidth: 2,
                leadingInset: leading,
                trailingInset: trailing,
                showDot: false
            ) == 0
        )
    }

    /// **The cadence is macOS's own 15 seconds, adopted rather than tightened ([[T-1131]]).**
    ///
    /// The brief's constraint, stated as a number: a `TimelineView(.periodic)` schedule is a real
    /// timer and iOS now runs them too, so the interval is the Mac's rather than a new one. Pinned
    /// against what a tick is *worth* on the densest canvas the app draws: at
    /// `iOSCalendarTimelineMetrics.hourHeight` a minute is under a point, so 15 seconds already
    /// moves the rule by a fraction of a point and anything tighter buys redraws rather than
    /// precision.
    @Test func theNowLineTicksAtTheCadenceMacOSAlreadyPaid() {
        #expect(CadenceTimelineNowLineSupport.tickInterval == 15)

        let pointsPerMinute: CGFloat = iOSCalendarTimelineMetrics.hourHeight / 60
        let pointsPerTick: CGFloat = pointsPerMinute
            * CGFloat(CadenceTimelineNowLineSupport.tickInterval / 60)
        #expect(pointsPerTick < 0.5, "a tick moves the rule \(pointsPerTick)pt")
        #expect(pointsPerTick > 0)
    }

    // MARK: - The population

    /// **Three surfaces, one component, and no second copy of the drawing.**
    ///
    /// The Mac's `TimelineCurrentTimeOverlay` kept its name and its five parameters — its call site
    /// in `TimelineDayCanvas` is untouched — but its body is now an adapter: it reads the hours and
    /// the insets off `TimelineMetrics`/`TimelineBlockStyle` and hands `CadenceTimelineNowLine` the
    /// canvas's own `yOffset(forFractionalMinute:)`. That closure is the point: the minute-to-Y
    /// expression is written once per canvas and shared with every block on it, which is the drift
    /// `yOffset(forFractionalMinute:)`'s own doc comment records, and a shared component taking an
    /// `hourHeight` instead would have re-created it three times over.
    ///
    /// The absence checks are paired with a positive one per file, so a renamed or deleted file
    /// fails instead of passing on an absence.
    @Test func everyTimedSurfaceDrawsItsNowLineWithTheSharedComponent() throws {
        let callSites: [(path: String, anchor: String)] = [
            ("Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift", "struct TimelineCurrentTimeOverlay: View {"),
            ("Cadence/iOS/iOSCalendarTimelineViews.swift", "struct iOSCalendarTimelineDayColumn: View {"),
            ("Cadence/iOS/iOSTodaySchedulePanel.swift", "struct iOSScheduleHourRow: View {")
        ]

        for site in callSites {
            let source = CadenceSourceScan.strippingComments(
                try CadenceSourceScan.sourceFile(site.path)
            )
            #expect(
                source.contains(site.anchor),
                "\(site.path) no longer declares \(site.anchor), so this read proves nothing"
            )
            #expect(
                source.contains("CadenceTimelineNowLine("),
                "\(site.path) does not build the shared now-line"
            )
            #expect(
                source.contains("yOffset:"),
                "\(site.path) hands the component no minute-to-Y of its own"
            )
            #expect(
                CadenceSourceScan.matchCount(#"TimelineView\(\.periodic"#, in: source) == 0,
                "\(site.path) schedules its own periodic tick instead of the component's"
            )
        }

        // The component itself, and the one place the schedule may be written.
        let component = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceTimelineNowLine.swift")
        )
        #expect(component.contains("struct CadenceTimelineNowLine: View {"))
        #expect(
            CadenceSourceScan.matchCount(#"TimelineView\(\.periodic"#, in: component) == 1,
            "the shared now-line does not own exactly one periodic schedule"
        )
        #expect(
            component.contains("CadenceTimelineNowLineSupport.tickInterval"),
            "the component types its own interval instead of reading the stated one"
        )

        // And the interval is not typed anywhere else. A population sweep rather than a list of the
        // three call sites, for the reason [[T-976]] closed on: a per-file allowlist lets the
        // fourth site escape. The instrument carries its own two witnesses, so a detector that had
        // stopped discriminating could not be built at all.
        let instrument = try CadenceScanInstrument(
            "a periodic tick with its interval typed rather than read",
            fires: "TimelineView(.periodic(from: Date(), by: 15)) { context in",
            andNotOn: "TimelineView(.periodic(from: Date(), by: CadenceTimelineNowLineSupport.tickInterval)) { context in",
            by: CadenceNowLineTickScan.typesItsOwnTickInterval
        )
        // The nearest misses: the conjunction is the rule, not a ban on the number.
        #expect(
            !instrument.fires(on: "TimelineView(.periodic(from: .now, by: 1)) { context in"),
            "the detector fires on the focus timer, which is not this rule's business"
        )
        #expect(
            !instrument.fires(on: "let inset = padding(by: 15)"),
            "the detector fires on a 15 that has no periodic schedule near it"
        )

        let offenders = try instrument.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            atLeast: 500,
            including: "Cadence/Shared/Components/CadenceTimelineNowLine.swift",
            read: CadenceSourceScan.strippedSourceReader()
        )
        #expect(
            offenders.isEmpty,
            """
            these files type the now-line's tick interval instead of reading \
            CadenceTimelineNowLineSupport.tickInterval: \(offenders.joined(separator: ", "))
            """
        )
    }
}

/// The detector the sweep above rests on, at file scope and `nonisolated` so the closure
/// `CadenceScanInstrument` is built from carries no actor isolation across its escape — the same
/// shape `CadenceHardCodedClockScan` and `CadenceAmbientZoneReadScan` take.
nonisolated enum CadenceNowLineTickScan {

    /// A literal 15 in a `by:` position. Word-bounded so `by: 150` cannot trip it.
    static let literalInterval = #"\bby:\s*15\b"#

    /// **The conjunction is the rule, not the ban.** A file may write `by: 15` — nothing about the
    /// number is wrong — and a file may schedule a periodic tick; `iOSFocusView`'s one-second focus
    /// clock does, legitimately. What is wrong is a *now-line* schedule whose interval is typed
    /// beside it instead of read from the one place it is stated, because that is the copy that
    /// drifts when the cadence is next argued about.
    static func typesItsOwnTickInterval(_ source: String) -> Bool {
        source.contains("TimelineView(.periodic")
            && CadenceSourceScan.matchCount(literalInterval, in: source) > 0
    }
}
