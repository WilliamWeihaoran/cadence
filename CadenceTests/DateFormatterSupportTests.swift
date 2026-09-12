import AppKit
import Foundation
import Testing
@testable import Cadence

struct DateFormatterSupportTests {
    @Test func weekKeyUsesIsoWeekYearAcrossNewYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let janFirst = try #require(calendar.date(from: DateComponents(year: 2021, month: 1, day: 1, hour: 12)))
        let janFourth = try #require(calendar.date(from: DateComponents(year: 2021, month: 1, day: 4, hour: 12)))

        #expect(DateFormatters.weekKey(from: janFirst) == "2020-W53")
        #expect(DateFormatters.weekKey(from: janFourth) == "2021-W01")
    }

    @Test func relativeDateAndDurationLabelsFollowTaskFriendlyDisplayRules() throws {
        let calendar = CadenceTestTimeZones.pinnedCalendar()
        let today = calendar.startOfDay(for: Date())
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let inThirteenDays = try #require(calendar.date(byAdding: .day, value: 13, to: today))
        let inFourteenDays = try #require(calendar.date(byAdding: .day, value: 14, to: today))

        #expect(DateFormatters.relativeDate(from: DateFormatters.dateKey(from: today)) == "Today")
        #expect(DateFormatters.relativeDate(from: DateFormatters.dateKey(from: tomorrow)) == "Tomorrow")
        #expect(DateFormatters.relativeDate(from: DateFormatters.dateKey(from: yesterday)) == "Yesterday")
        #expect(DateFormatters.relativeDate(from: DateFormatters.dateKey(from: inThirteenDays)) == "in 13 days")
        #expect(
            DateFormatters.relativeDate(from: DateFormatters.dateKey(from: inFourteenDays)) ==
            DateFormatters.shortDate.string(from: inFourteenDays)
        )

        #expect(TimeFormatters.durationLabel(actual: 45, estimated: 0) == "45m/-")
        #expect(TimeFormatters.durationLabel(actual: 90, estimated: 120) == "1h\u{00A0}30m/2h")
        #expect(TimeFormatters.durationLabel(actual: 0, estimated: 30) == "-/30m")
    }

    /// `normalizedDateKey` is the single spelling of "this text is a storage key".
    ///
    /// The rule under test is normalize-when-unambiguous, reject-when-the-century-is-a-guess:
    /// `"2026-8-20"` names one day and becomes `"2026-08-20"`, while `"26-8-2"` parses just as
    /// happily to the year 26 AD and is refused rather than stored as `"0026-08-02"`.
    @Test func normalizedDateKeyCanonicalizesUnambiguousSpellingsAndRefusesAShortYear() {
        #expect(DateFormatters.normalizedDateKey("2026-08-20") == "2026-08-20")
        #expect(DateFormatters.normalizedDateKey("2026-8-20") == "2026-08-20")
        #expect(DateFormatters.normalizedDateKey("2026-8-2") == "2026-08-02")
        #expect(DateFormatters.normalizedDateKey("  2026-8-20  ") == "2026-08-20")
        #expect(DateFormatters.normalizedDateKey("2026-008-020") == "2026-08-20")
        #expect(DateFormatters.normalizedDateKey("2026/08/20") == "2026-08-20")

        // Refused, and the first two are the interesting ones: the parse succeeds, so nothing but
        // this function stands between them and a stored key.
        #expect(DateFormatters.date(from: "26-8-2") != nil)
        #expect(DateFormatters.normalizedDateKey("26-8-2") == nil)
        #expect(DateFormatters.normalizedDateKey("0026-08-02") == "0026-08-02")
        #expect(DateFormatters.normalizedDateKey("2026-13-01") == nil)
        #expect(DateFormatters.normalizedDateKey("2026-02-30") == nil)
        #expect(DateFormatters.normalizedDateKey("2026-08-20T10:00") == nil)
        #expect(DateFormatters.normalizedDateKey("next Tuesday") == nil)
        #expect(DateFormatters.normalizedDateKey("") == nil)
    }

    /// Why the padding is not pedantry: the app compares storage keys as strings, so a key that is
    /// not fixed-width sorts into a different day than it means.
    @Test func aLenientlySpelledKeyOrdersWrongUntilItIsNormalized() throws {
        let raw = "2026-8-20"
        let canonical = try #require(DateFormatters.normalizedDateKey(raw))

        #expect((raw < "2026-08-25") == false)
        #expect(canonical < "2026-08-25")
        #expect(DateFormatters.date(from: raw) == DateFormatters.date(from: canonical))
    }

    /// The locale is stated (T-1135). Before the formatter asked one, `"12 AM"` was right on every
    /// machine by construction; now an unstated assertion here would be reading the developer's
    /// Language & Region setting, which is the [[T-1115]] shape. The wrap is the subject, so it is
    /// asserted on both faces — a modulo that dropped the day would fail on either.
    @Test func timeLabelsWrapEndOfDayToMidnight() throws {
        #expect(TimeFormatters.timeString(from: 24 * 60, locale: CadenceTestClocks.twelveHour) == "12 AM")
        #expect(
            TimeFormatters.timeRange(startMin: 18 * 60, endMin: 24 * 60, locale: CadenceTestClocks.twelveHour)
                == "6 PM – 12 AM"
        )

        #expect(TimeFormatters.timeString(from: 24 * 60, locale: CadenceTestClocks.twentyFourHour) == "00:00")
        #expect(
            TimeFormatters.timeRange(startMin: 18 * 60, endMin: 24 * 60, locale: CadenceTestClocks.twentyFourHour)
                == "18:00 – 00:00"
        )
    }

    @Test func estimateLabelSplitsHoursAndMinutesAndNeverRendersADecimalHour() {
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 0) == "0m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: -30) == "0m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 1) == "1m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 59) == "59m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 60) == "1h")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 61) == "1h\u{00A0}1m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 90) == "1h\u{00A0}30m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 120) == "2h")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 1439) == "23h\u{00A0}59m")
    }

    /// These labels are drawn inside hard-clipped fixed-size chrome (timeline blocks get as
    /// narrow as ~50pt when tasks overlap). A plain space is a line-break opportunity, so a
    /// wrapped "1h 30m" would lose its clipped second line and report "1h" for a 90-minute
    /// task — wrong information, not truncation. The separator must stay non-breaking.
    ///
    /// The assertion has to name every surface that renders a duration, not just the canonical
    /// helper: this test passed for months while `TimelineEventBlockSupportViews` and
    /// `GoalContributionSummary.focusLabel` shipped their own copies with a breakable space in
    /// them. The subject of a test has to be the code that can break.
    @Test func durationLabelsUseANonBreakingSpaceBetweenHoursAndMinutes() {
        #expect(!CadenceTaskPresentationSupport.estimateLabel(minutes: 90).contains(" "))
        #expect(!TimeFormatters.durationLabel(actual: 90, estimated: 90).contains(" "))
        #expect(!TimeFormatters.durationLabel(minutes: 90, emptyPlaceholder: "–").contains(" "))

        let summary = GoalContributionSummary(
            progressType: .hours,
            targetHours: 4,
            totalTasks: 0,
            completedTasks: 0,
            directTaskCount: 0,
            linkedListCount: 0,
            focusMinutes: 165,
            overdueTaskIDs: [],
            recentCompletedCount: 0,
            nextActionTitle: nil,
            nextActionDueDate: nil
        )
        #expect(summary.focusLabel == "2h\u{00A0}45m")
        #expect(!summary.focusLabel.contains(" "))
    }

    /// The empty sentinel is the only thing the duration surfaces ever disagreed about, so it is
    /// the only thing that is a parameter. Everything else must come out identical.
    @Test func durationLabelKeepsOneShapeAcrossItsThreeEmptySentinels() {
        #expect(TimeFormatters.durationLabel(minutes: 0, emptyPlaceholder: "0m") == "0m")
        #expect(TimeFormatters.durationLabel(minutes: 0, emptyPlaceholder: "-") == "-")
        #expect(TimeFormatters.durationLabel(minutes: -5, emptyPlaceholder: "–") == "–")
        #expect(TimeFormatters.durationLabel(minutes: 90, emptyPlaceholder: "–") == "1h\u{00A0}30m")
        #expect(CadenceTaskPresentationSupport.estimateLabel(minutes: 0, emptyPlaceholder: "–") == "–")

        for minutes in [1, 30, 59, 60, 61, 90, 120, 1_439] {
            #expect(
                CadenceTaskPresentationSupport.estimateLabel(minutes: minutes)
                    == TimeFormatters.durationLabel(minutes: minutes, emptyPlaceholder: "–")
            )
        }
    }

    @Test func durationLabelPairsActualWithEstimatedAndDashesMissingValues() {
        #expect(TimeFormatters.durationLabel(actual: 0, estimated: 0) == "-/-")
        #expect(TimeFormatters.durationLabel(actual: -5, estimated: -5) == "-/-")
        #expect(TimeFormatters.durationLabel(actual: 1, estimated: 59) == "1m/59m")
        #expect(TimeFormatters.durationLabel(actual: 60, estimated: 61) == "1h/1h\u{00A0}1m")
        #expect(TimeFormatters.durationLabel(actual: 120, estimated: 1439) == "2h/23h\u{00A0}59m")
    }

    // MARK: - The backup folder stamp (T-303)

    /// The stamp `PersistenceController` names a store backup folder with. It is local wall-clock
    /// time on purpose — the name is shown back to the user as the backup being offered, so it has
    /// to say the hour they remember — and fixed-width POSIX on purpose, so the folders sort in the
    /// order they were made whatever the host's locale is.
    @Test func theBackupFolderStampNamesTheLocalWallClockInAFixedWidthSpelling() throws {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let reference = try #require(gregorian.date(from: DateComponents(
            year: 2026, month: 8, day: 27, hour: 1, minute: 42, second: 33
        )))

        #expect(DateFormatters.backupFolderTimestamp.string(from: reference) == "20260827-014233")
        // A December date too, so a formatter pinned to a two-digit-month-only mistake cannot pass.
        let december = try #require(gregorian.date(from: DateComponents(
            year: 2026, month: 12, day: 5, hour: 23, minute: 9, second: 7
        )))
        #expect(DateFormatters.backupFolderTimestamp.string(from: december) == "20261205-230907")
    }

    /// The rule that makes `DateFormatters.swift` worth opening: **every** `DateFormatter` Cadence
    /// builds is declared in it. A private one elsewhere can be perfectly correct — the backup
    /// stamp was — and still cost the next reader the search, because a file that claims to hold
    /// them all is only useful if it does.
    @Test func everyDateFormatterInTheAppIsDeclaredInTheFormatterFile() throws {
        // Negative lookbehind on a word character: `ISO8601DateFormatter()` is a different type
        // and several services legitimately build one.
        let needle = "(?<![A-Za-z0-9_])DateFormatter\\(\\)"
        #expect(CadenceSourceScan.matchCount(needle, in: "let f = DateFormatter()") == 1)
        #expect(CadenceSourceScan.matchCount(needle, in: "ISO8601DateFormatter()") == 0)

        let home = "Cadence/Shared/DateFormatters.swift"
        let root = CadenceSourceScan.repositoryRoot()
        var scanned = 0
        var offenders: [String] = []

        for folder in ["Cadence", "CadenceWidgets", "CadenceMCPServer"] {
            let base = root.appendingPathComponent(folder)
            // `enumerator(atPath:)` yields paths relative to `base`, which is what keeps this off
            // the `/tmp` vs `/private/tmp` symlink that string-subtracting an absolute root trips on.
            let walk = try #require(FileManager.default.enumerator(atPath: base.path))
            for case let element as String in walk where element.hasSuffix(".swift") {
                let relative = "\(folder)/\(element)"
                scanned += 1
                guard relative != home else { continue }
                let raw = try CadenceSourceScan.sourceFile(relative)
                if CadenceSourceScan.matchCount(needle, in: CadenceSourceScan.strippingComments(raw)) > 0 {
                    offenders.append(relative)
                }
            }
        }

        #expect(scanned > 400, "the walk read \(scanned) files; an empty walk would pass vacuously")
        #expect(offenders == [])

        // …and the one file that is allowed to declare them still does, so the exemption above is
        // not quietly exempting an empty file.
        let raw = try CadenceSourceScan.sourceFile(home)
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw)
        #expect(stripped.count == raw.count)
        #expect(CadenceSourceScan.matchCount(needle, in: stripped) >= 11)
        #expect(stripped.contains("static let backupFolderTimestamp: DateFormatter"))
    }
}

// MARK: - T-1135: the clock face follows the user's, and no file spells its own

/// The detector the population sweep below rests on, at file scope and `nonisolated` so the closure
/// `CadenceScanInstrument` is built from carries no actor isolation across its escape — the same
/// reason `CadenceAmbientZoneReadScan` is shaped this way.
nonisolated enum CadenceHardCodedClockScan {

    /// A bare `AM` or `PM` token. Word-bounded on both sides so `SPM`, `AMPMStyle` or a property
    /// called `pm` cannot trip it, and deliberately not anchored to a quote: the offender this was
    /// written against spells `"AM"` directly, but `"12 AM"` and `"\(hour) PM"` are the same defect
    /// and a quote-anchored needle would have missed both.
    static let amPmToken = "(?<![A-Za-z0-9_])[AP]M(?![A-Za-z0-9_])"

    /// The other way to hard-code a 12-hour face: an ICU pattern with an `a` field in it, as in
    /// `dateFormat = "h:mm a"`. Measured over `Cadence/` on 2026-09-12 — zero occurrences, so this
    /// half is a guard against a future spelling rather than a description of one.
    static let twelveHourTemplate = "\"[^\"]*h{1,2}:mm[^\"]*\\ba\\b[^\"]*\""

    /// The evidence that the file asked the system instead of deciding for itself.
    static let hourCycleNeedles = ["hourCycle", "usesTwentyFourHourClock"]

    /// **The conjunction is the rule, not the ban.** A file that names AM or PM is not wrong — the
    /// 12-hour branch of `TimeFormatters.timeString` has to spell them somewhere. A file that names
    /// them *without* consulting the hour cycle is, because that is a clock face chosen by the
    /// programmer rather than by the user. Written this way rather than as a per-file allowlist for
    /// the reason [[T-976]] closed on: per-file guards let a ninth site escape, and the exempt file
    /// then passes forever whatever it does.
    static func spellsAClockWithoutAskingTheHourCycle(_ source: String) -> Bool {
        let spellsOne = CadenceSourceScan.matchCount(amPmToken, in: source) > 0
            || CadenceSourceScan.matchCount(twelveHourTemplate, in: source) > 0
        guard spellsOne else { return false }
        return !hourCycleNeedles.contains { source.contains($0) }
    }
}

struct ClockFaceFollowsTheSystemTests {

    /// **T-1135, the behaviour.** Minutes-from-midnight render on the face the locale names.
    ///
    /// Both faces in one walk over the same minutes, because the two ways this regresses are
    /// opposite: a formatter that ignored the locale again would fail the 24-hour column, and one
    /// that switched everybody to 24-hour would fail the 12-hour column. The 12-hour expectations
    /// are the strings the app shipped before this change, character for character, which is the
    /// claim that nothing already on screen moved.
    @Test func aClockLabelFollowsTheLocalesHourCycleRatherThanAlwaysSayingAMPM() {
        let expected: [(minutes: Int, twelve: String, twentyFour: String)] = [
            (0, "12 AM", "00:00"),
            (1, "12:01 AM", "00:01"),
            (75, "1:15 AM", "01:15"),
            (9 * 60, "9 AM", "09:00"),
            (11 * 60 + 59, "11:59 AM", "11:59"),
            (12 * 60, "12 PM", "12:00"),
            (13 * 60, "1 PM", "13:00"),
            (13 * 60 + 15, "1:15 PM", "13:15"),
            (23 * 60 + 59, "11:59 PM", "23:59"),
            // The wrap, from both sides.
            (24 * 60, "12 AM", "00:00"),
            (-15, "11:45 PM", "23:45"),
        ]

        for probe in expected {
            #expect(
                TimeFormatters.timeString(from: probe.minutes, locale: CadenceTestClocks.twelveHour)
                    == probe.twelve,
                "\(probe.minutes) minutes did not read \(probe.twelve) on a 12-hour clock"
            )
            #expect(
                TimeFormatters.timeString(from: probe.minutes, locale: CadenceTestClocks.twentyFourHour)
                    == probe.twentyFour,
                "\(probe.minutes) minutes did not read \(probe.twentyFour) on a 24-hour clock"
            )
            // `h24` is the rarer cycle where midnight is written 24:00. Cadence has one 24-hour
            // face, so it folds into the `h23` spelling — asserted rather than assumed.
            #expect(
                TimeFormatters.timeString(from: probe.minutes, locale: CadenceTestClocks.twentyFourHourFromOne)
                    == probe.twentyFour
            )
        }

        // And a real 24-hour region agrees with the constructed one, so the keyword form above is
        // not a private dialect of this suite.
        for identifier in ["en_GB", "de_DE", "fr_FR"] {
            #expect(
                TimeFormatters.timeString(from: 13 * 60 + 15, locale: Locale(identifier: identifier)) == "13:15",
                "\(identifier) did not read as a 24-hour clock"
            )
        }

        // The range separator is the formatter's, not the caller's, so it is read on both faces too.
        #expect(
            TimeFormatters.timeRange(startMin: 9 * 60, endMin: 17 * 60, locale: CadenceTestClocks.twelveHour)
                == "9 AM – 5 PM"
        )
        #expect(
            TimeFormatters.timeRange(startMin: 9 * 60, endMin: 17 * 60, locale: CadenceTestClocks.twentyFourHour)
                == "09:00 – 17:00"
        )
    }

    /// The one call site whose output is read back rather than only drawn.
    ///
    /// `CalendarEventEditPopover` seeds its Start and End fields with `timeString`, parses what the
    /// user leaves there, and re-seeds them with `timeString`. Before T-1135 the format was fixed, so
    /// the parser only ever saw one spelling; now it can be handed `16:55` on a 24-hour Mac. A
    /// formatter change that altered a string something else reads back is a different bug from the
    /// one being fixed, which is why this is asserted over every minute of the day on both faces
    /// rather than sampled.
    ///
    /// The cross terms matter as much as the round trip: a 24-hour user who types `4 PM` out of
    /// habit, and a 12-hour user who types `16:55`, must both land on 16:55.
    @Test func aTypedTimeSurvivesTheEditorsFormatParseReformatRoundTrip() {
        for (face, locale) in CadenceTestClocks.all {
            for minute in 0..<(24 * 60) {
                let drawn = TimeFormatters.timeString(from: minute, locale: locale)
                #expect(
                    TimeFormatters.minutes(fromTimeString: drawn) == minute,
                    "the \(face) spelling of minute \(minute) — \(drawn) — did not parse back to it"
                )
                #expect(
                    TimeFormatters.timeString(
                        from: TimeFormatters.minutes(fromTimeString: drawn) ?? -1,
                        locale: locale
                    ) == drawn,
                    "\(drawn) did not survive a second trip through the \(face) editor"
                )
            }
        }

        // Typed by hand, in the other face's vocabulary, with the spacing people actually use.
        let typed: [(String, Int?)] = [
            ("4:55 PM", 16 * 60 + 55),
            ("16:55", 16 * 60 + 55),
            ("4 PM", 16 * 60),
            ("04:55", 4 * 60 + 55),
            ("  9:30 am  ", 9 * 60 + 30),
            ("12 AM", 0),
            ("00:00", 0),
            ("24:00", nil),
            ("noon", nil),
            ("", nil),
        ]
        for probe in typed {
            #expect(
                TimeFormatters.minutes(fromTimeString: probe.0) == probe.1,
                "\"\(probe.0)\" parsed to \(String(describing: TimeFormatters.minutes(fromTimeString: probe.0)))"
            )
        }
    }

    /// **T-1130 asked for a measurement rather than a hope, and this is the 24-hour half of it.**
    ///
    /// The hour rails are a fixed-width column of these labels, so the widest one decides whether
    /// the rail fits. `theHourLabelFitsTheNarrowRail` measures the 12-hour label against the narrow
    /// iOS rail; this asserts the 24-hour face does not make it worse, which is the only way T-1135
    /// could have broken a layout. Measured 2026-09-12 at 11pt medium, the rail's own size and
    /// weight: `12 AM` 32.8pt, `00:00` 32.3pt.
    @Test func theTwentyFourHourHourRailLabelIsNoWiderThanTheTwelveHourOne() {
        let font = NSFont.systemFont(ofSize: iOSCalendarTimelineMetrics.hourLabelSize, weight: .medium)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }

        var widestTwelve: CGFloat = 0
        var widestTwentyFour: CGFloat = 0
        for hour in CadenceScheduleSupport.calendarHours {
            widestTwelve = max(
                widestTwelve,
                width(TimeFormatters.timeString(from: hour * 60, locale: CadenceTestClocks.twelveHour))
            )
            widestTwentyFour = max(
                widestTwentyFour,
                width(TimeFormatters.timeString(from: hour * 60, locale: CadenceTestClocks.twentyFourHour))
            )
        }

        #expect(widestTwelve > 0, "the rail walked no hours, so this comparison would be vacuous")
        #expect(
            widestTwentyFour <= widestTwelve,
            """
            the widest 24-hour rail label is \(widestTwentyFour)pt against the 12-hour \
            \(widestTwelve)pt; re-measure CadenceCalendarWeekGridLayout.timeRailWidth before \
            shipping it
            """
        )
    }

    /// **T-1130's measurement, and the reason the Mac rails could take the shared formatter.**
    ///
    /// Both macOS rails drew a bare 24-hour integer — `13`, about 13pt wide — so routing them
    /// through `TimeFormatters` replaces the narrowest possible label with the widest one the app
    /// has, and the rail is a fixed-width column. The [[T-1130]] filing said in as many words that
    /// "probably enough" is what `theHourLabelFitsTheNarrowRail` exists to replace, so this
    /// measures rather than reformats and hopes.
    ///
    /// Measured 2026-09-12, each rail at its own size and weight: the Calendar page's
    /// `CalTimeRailLabel` at 10pt semibold in `calTimeWidth`'s 44pt box — widest 12-hour `10 AM`
    /// 30.89pt, widest 24-hour `08:00` 30.50pt; the Schedule panel's `ScheduleTimeRailRow` at 10pt
    /// medium in `timeLabelWidth`'s 36pt box — `10 AM` 30.44pt, `04:00` 29.81pt. The Schedule
    /// panel's is the tighter of the two and still clears its box by more than 5pt, and neither
    /// figure may move without moving `blockInset` with it, which would shift every block on that
    /// panel.
    ///
    /// The inequality against the box is what this asserts; the figures are in the message so a
    /// failure says by how much rather than merely that. The **24-hour face is the narrower one**
    /// on both rails, which is the claim that matters for [[T-1135]]: the user's clock setting
    /// cannot be what makes a rail overflow.
    @Test func theMacHourRailsFitTheWidestLabelOnEitherClockFace() {
        func widest(size: CGFloat, weight: NSFont.Weight, locale: Locale) -> CGFloat {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            var widestSoFar: CGFloat = 0
            for hour in CadenceScheduleSupport.calendarHours {
                let label = TimeFormatters.timeString(from: hour * 60, locale: locale)
                let measured = (label as NSString).size(withAttributes: [.font: font]).width
                widestSoFar = max(widestSoFar, measured)
            }
            return widestSoFar
        }

        let rails: [(name: String, size: CGFloat, weight: NSFont.Weight, box: CGFloat)] = [
            ("CalTimeRailLabel", 10, .semibold, calTimeWidth),
            ("ScheduleTimeRailRow", 10, .medium, timeLabelWidth)
        ]

        for rail in rails {
            let twelve = widest(size: rail.size, weight: rail.weight, locale: CadenceTestClocks.twelveHour)
            let twentyFour = widest(size: rail.size, weight: rail.weight, locale: CadenceTestClocks.twentyFourHour)

            // Non-vacuity: a rail that measured nothing would clear any box.
            #expect(twelve > 0, "\(rail.name) walked no hours, so the comparison below is vacuous")
            #expect(
                twelve < rail.box,
                "\(rail.name)'s widest 12-hour label is \(twelve)pt in a \(rail.box)pt box"
            )
            #expect(
                twentyFour < rail.box,
                "\(rail.name)'s widest 24-hour label is \(twentyFour)pt in a \(rail.box)pt box"
            )
            #expect(
                twentyFour <= twelve,
                """
                \(rail.name): the 24-hour face is \(twentyFour)pt against the 12-hour \(twelve)pt, \
                so the user's clock setting decides whether the rail fits
                """
            )
        }

        // The panel's block inset is derived from the rail, not typed beside it — so a rail that
        // had to be widened would have moved every block on the Schedule panel with it.
        let derivedInset: CGFloat = timeLabelWidth + timeLabelPad
        #expect(blockInset == derivedInset)
    }

    /// **The population sweep.** No file in the app spells a clock face without asking the system
    /// which one the user reads.
    ///
    /// A population rather than a list of the 33 known call sites, and a conjunction rather than a
    /// ban on the letters `AM`: the rule is "decide this from the locale", so the file that *does*
    /// consult the hour cycle passes on its merits and needs no exemption. [[T-976]] is the argument
    /// — its per-file guards let a ninth site escape, and the escape was invisible because the
    /// guard list looked complete.
    ///
    /// Measured over `Cadence/` on 2026-09-12: with comments blanked, the token appears in exactly
    /// one file, `Cadence/Shared/DateFormatters.swift`, which is the formatter itself. Every other
    /// occurrence in the tree is prose in a doc comment, which is why the sweep reads
    /// `strippingComments` rather than raw text — and why it reads `strippingComments` rather than
    /// `codeOnly`, which would blank the string literals the needle is looking for.
    @Test func noSourceFileSpellsAClockWithoutAskingTheHourCycle() throws {
        let instrument = try CadenceScanInstrument(
            "hard-coded 12-hour clock face",
            fires: """
                let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
                let ampm = h < 12 ? "AM" : "PM"
                return m == 0 ? "\\(h12) \\(ampm)" : String(format: "%d:%02d %@", h12, m, ampm)
                """,
            andNotOn: """
                if usesTwentyFourHourClock(locale) { return String(format: "%02d:%02d", h, m) }
                let ampm = h < 12 ? "AM" : "PM"
                return m == 0 ? "\\(h12) \\(ampm)" : String(format: "%d:%02d %@", h12, m, ampm)
                """,
            by: CadenceHardCodedClockScan.spellsAClockWithoutAskingTheHourCycle
        )

        // The nearest misses, each one a way the detector could stop discriminating.
        // The detector is deliberately **not** comment-aware — the sweep hands it stripped source,
        // which is the layer that has to ignore prose. `Cadence/` is full of doc comments that
        // discuss `12 AM`, so this pair is what stops the sweep reporting all of them: the raw
        // sentence fires, the stripped one does not.
        let prose = "/// at 11pt `12 AM` measures roughly 32.8pt\nlet width = railWidth"
        #expect(instrument.fires(on: prose))
        #expect(
            !instrument.fires(on: CadenceSourceScan.strippingComments(prose)),
            """
            a comment that merely discusses a clock reports its file — the sweep reads \
            strippingComments precisely so that prose cannot
            """
        )
        #expect(
            !instrument.fires(on: "let spm = SPM(rawValue: \"amplitude\") ?? .pm0"),
            "the detector fires on identifiers that merely contain the letters"
        )
        #expect(
            instrument.fires(on: "Text(\"\\(hour < 12 ? hour : hour - 12) \\(hour < 12 ? \"AM\" : \"PM\")\")"),
            "the detector misses a clock spelled inline in a view body, which is how the rails do it"
        )
        #expect(
            instrument.fires(on: "formatter.dateFormat = \"h:mm a\""),
            "the detector misses the ICU spelling of the same hard-coded face"
        )

        let offenders = try instrument.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            atLeast: 500,
            including: "Cadence/Shared/DateFormatters.swift",
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(
            offenders.isEmpty,
            """
            these files decide the clock face themselves instead of reading the user's — route them \
            through TimeFormatters.timeString(from:locale:), which asks Locale.hourCycle: \
            \(offenders.joined(separator: ", "))
            """
        )
    }
}
