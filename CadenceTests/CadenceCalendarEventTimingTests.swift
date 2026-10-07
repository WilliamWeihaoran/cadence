//
//  CadenceCalendarEventTimingTests.swift
//  CadenceTests
//
//  T-3050, the EventKit half of T-3048. Three write paths turned a `yyyy-MM-dd` day key plus a
//  minute-of-day into an `EKEvent`'s `startDate` by adding elapsed minutes to midnight. `.minute`
//  is not a calendrical unit, so on the two days a year that are 23 or 25 hours long the event
//  landed an hour away from the time the picker showed — and unlike a notification, the wrong
//  instant is written into the **owner's real Calendar**, outside Cadence and not undoable from
//  inside it.
//
//  **Why this file states a zone instead of relying on the host.** The scheme's `TestAction` pins
//  `TZ=UTC` ([[T-1116]]) and UTC has no DST, so a test that read `Calendar.current` here would
//  measure a zone in which the whole distinction is invisible: it would pass against the defect
//  and against the fix, forever, and say nothing either time. Every assertion below builds an
//  explicit `America/New_York` calendar through `CadenceTestTimeZones.calendar(_:)` and reads its
//  components back out of that same calendar. The pin is not touched and must not be.
//
//  **Nothing here reaches EventKit.** The arithmetic under test is a pure function
//  (`CadenceCalendarEventTiming.startDate`); no `EKEventStore` is constructed, no authorization is
//  requested, and no event is written, moved or deleted. `CalendarManagerScenarioTests` owns the
//  manager-level behaviour, under the T-3032 fence.
//
//  **Half of this file pins the lines that are CORRECT.** An event's *end* is a duration added to
//  a start that is already right, and 60 minutes of meeting is 60 minutes of real time on a
//  23-hour day too. A later reader "fixing" those lines symmetrically with the start would be
//  introducing the bug, not removing it, so the elapsed spelling is pinned from both directions:
//  behaviourally, and in the source of the three call sites.
//

import Foundation
import Testing
@testable import Cadence

@MainActor
struct CadenceCalendarEventTimingTests {
    /// 2026-03-08 loses an hour at 02:00, 2026-11-01 repeats one at 02:00, and 2026-06-15 is an
    /// ordinary 24-hour day. The ordinary day is not padding: without it a green run cannot
    /// distinguish "the transition days are right" from "every day is wrong by the same amount".
    private static let springForward = "2026-03-08"
    private static let fallBack = "2026-11-01"
    private static let ordinary = "2026-06-15"
    private static let everyDay = [springForward, ordinary, fallBack]

    /// The two offsets `America/New_York` uses, as `secondsFromGMT` reports them.
    private static let edt = -4 * 3600
    private static let est = -5 * 3600

    private func newYork() throws -> Calendar {
        try CadenceTestTimeZones.calendar("America/New_York")
    }

    private func midnight(_ dateKey: String, _ calendar: Calendar) throws -> Date {
        try #require(DateFormatters.date(from: dateKey, in: calendar))
    }

    // MARK: - 1. The defect: a minute-of-day is a wall-clock reading

    @Test func eventStartSetsTheWallClockMinuteOfDayOnBothDSTTransitionDaysAndAnOrdinaryOne() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            let start = try #require(
                CadenceCalendarEventTiming.startDate(dateKey: dateKey, startMin: 540, calendar: calendar),
                "09:00 on \(dateKey) must resolve"
            )
            let components = calendar.dateComponents([.hour, .minute], from: start)
            #expect(components.hour == 9, "the event on \(dateKey) starts at hour \(components.hour ?? -1), not 9")
            #expect(components.minute == 0, "the event on \(dateKey) starts at minute \(components.minute ?? -1), not 0")
            #expect(calendar.isDate(start, inSameDayAs: base), "the event on \(dateKey) left its own day")
        }
    }

    /// The measurement the ticket is built on, asserted rather than quoted, so the battery above
    /// cannot be green for the wrong reason: on these two days the old arithmetic really does land
    /// an hour away, and on the ordinary day the two spellings really do agree.
    @Test func addingElapsedMinutesToMidnightLandsAnHourOffOnlyOnTheTransitionDays() throws {
        let calendar = try newYork()

        let expectedElapsedHours = [Self.springForward: 10, Self.ordinary: 9, Self.fallBack: 8]
        for (dateKey, expectedHour) in expectedElapsedHours {
            let base = try midnight(dateKey, calendar)
            let elapsed = try #require(calendar.date(byAdding: .minute, value: 540, to: base))
            #expect(
                calendar.component(.hour, from: elapsed) == expectedHour,
                "adding 540 minutes to midnight on \(dateKey) must read hour \(expectedHour)"
            )

            let set = try #require(
                CadenceCalendarEventTiming.startDate(dateKey: dateKey, startMin: 540, calendar: calendar)
            )
            if dateKey == Self.ordinary {
                #expect(set == elapsed, "an ordinary day cannot tell the two spellings apart")
            } else {
                #expect(set != elapsed, "\(dateKey) must distinguish setting the clock from adding minutes")
            }
        }
    }

    // MARK: - 2. The three readings that needed a decision

    /// 02:30 on 2026-03-08 never occurs: 01:59:59 EST is followed by 03:00:00 EDT. Foundation
    /// answers the first instant at or after the missing reading, and that is the chosen behaviour
    /// — a block dropped into the gap opens the moment the gap closes. The old arithmetic answered
    /// 03:30, an hour past a time nobody picked.
    @Test func anEventStartInsideTheSpringForwardGapResolvesToTheInstantTheGapCloses() throws {
        let calendar = try newYork()

        let start = try #require(
            CadenceCalendarEventTiming.startDate(dateKey: Self.springForward, startMin: 150, calendar: calendar)
        )
        let components = calendar.dateComponents([.hour, .minute], from: start)
        #expect(components.hour == 3, "02:30 on a spring-forward day must answer hour 3, got \(components.hour ?? -1)")
        #expect(components.minute == 0, "and minute 0, got \(components.minute ?? -1)")
        #expect(calendar.timeZone.secondsFromGMT(for: start) == Self.edt, "the gap closes into EDT")

        let base = try midnight(Self.springForward, calendar)
        let oldAnswer = try #require(calendar.date(byAdding: .minute, value: 150, to: base))
        #expect(calendar.component(.hour, from: oldAnswer) == 3)
        #expect(calendar.component(.minute, from: oldAnswer) == 30, "the old arithmetic answered 03:30")
        #expect(start != oldAnswer)
    }

    /// 01:30 on 2026-11-01 happens twice. Foundation answers the **first** (01:30 EDT), the earlier
    /// of the two and the one the user watching the clock sees first.
    @Test func anAmbiguousEventStartOnTheFallBackDayTakesTheFirstOfTheTwoOccurrences() throws {
        let calendar = try newYork()

        let start = try #require(
            CadenceCalendarEventTiming.startDate(dateKey: Self.fallBack, startMin: 90, calendar: calendar)
        )
        let components = calendar.dateComponents([.hour, .minute], from: start)
        #expect(components.hour == 1)
        #expect(components.minute == 30)
        #expect(
            calendar.timeZone.secondsFromGMT(for: start) == Self.edt,
            "the first 01:30 is still EDT; EST would be the repeat an hour later"
        )

        // The repeat, named explicitly so "first" is a measurement and not a word: midnight plus
        // 150 minutes of *elapsed* time is 01:30 EST, and it is one hour after the answer above.
        let base = try midnight(Self.fallBack, calendar)
        let repeated = try #require(calendar.date(byAdding: .minute, value: 150, to: base))
        #expect(calendar.component(.hour, from: repeated) == 1)
        #expect(calendar.component(.minute, from: repeated) == 30)
        #expect(calendar.timeZone.secondsFromGMT(for: repeated) == Self.est)
        #expect(repeated.timeIntervalSince(start) == 3600, "the two readings are an hour apart")
    }

    /// `1440` and up name no time on the day. The write is refused rather than rolled onto the next
    /// calendar day, which is what the old arithmetic did silently — and this is a write into the
    /// owner's real Calendar, so a mis-dated event is not something Cadence can take back.
    @Test func anOutOfRangeEventStartMinuteNamesNoInstantOnAnyOfTheThreeDays() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            for startMin in [1440, 1441, 1500, 2880] {
                #expect(
                    CadenceCalendarEventTiming.startDate(dateKey: dateKey, startMin: startMin, calendar: calendar) == nil,
                    "\(startMin) names no time on \(dateKey)"
                )
            }
            #expect(
                CadenceCalendarEventTiming.startDate(dateKey: dateKey, startMin: -1, calendar: calendar) == nil,
                "a negative minute names no time on \(dateKey)"
            )
        }
    }

    @Test func theEndsOfTheDayResolveOnEveryDayAndStayOnTheirOwnDate() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            for (startMin, hour, minute) in [(0, 0, 0), (1439, 23, 59)] {
                let start = try #require(
                    CadenceCalendarEventTiming.startDate(dateKey: dateKey, startMin: startMin, calendar: calendar),
                    "\(startMin) must resolve on \(dateKey)"
                )
                let components = calendar.dateComponents([.hour, .minute], from: start)
                #expect(components.hour == hour)
                #expect(components.minute == minute)
                #expect(calendar.isDate(start, inSameDayAs: base), "\(startMin) rolled off \(dateKey)")
            }
        }
    }

    /// A day key that is not three integers names no instant.
    ///
    /// **Measured, not assumed, about the half this does not own:** `DateFormatters.date(from:in:)`
    /// hands its three integers to `Calendar.date(from:)`, which **normalizes** rather than
    /// rejects — `"2026-13-01"` resolves to 2027-01-01 on this toolchain rather than to `nil`. That
    /// is the existing contract of the shared parser, which `TaskNotificationPlanner` reads the
    /// same way ([[T-3048]]); it is recorded here so a reader does not mistake its absence from the
    /// list below for a claim it was rejected. Nothing in Cadence writes a 13th month — every key
    /// reaching an EventKit write comes from `DateFormatters.dateKey(from:)` or
    /// `normalizedDateKey(_:)`.
    @Test func aDayKeyThatIsNotADayKeyNamesNoEventStart() throws {
        let calendar = try newYork()

        for key in ["", "not-a-date", "2026-03", "2026-03-08-01", "2026-ab-08"] {
            #expect(
                CadenceCalendarEventTiming.startDate(dateKey: key, startMin: 540, calendar: calendar) == nil,
                "\(key) is not a day key"
            )
        }

        // The normalizing half, asserted so the comment above cannot go stale silently.
        let normalized = try #require(
            CadenceCalendarEventTiming.startDate(dateKey: "2026-13-01", startMin: 540, calendar: calendar)
        )
        #expect(calendar.component(.year, from: normalized) == 2027)
        #expect(calendar.component(.month, from: normalized) == 1)
    }

    // MARK: - 3. The lines that are CORRECT, pinned so they are not "fixed" symmetrically

    /// An event's duration is **elapsed** time, and on a transition day that is visibly different
    /// from setting a clock reading: a 60-minute meeting starting at 01:30 on 2026-03-08 ends at
    /// 03:30 — two hours later on the wall, one hour later in the world — and a 60-minute meeting
    /// starting at 01:30 on 2026-11-01 ends at 01:30 again. Both are right. If either of these
    /// expectations ever has to change, the end legs were rewritten and T-3050 was undone.
    @Test func anEventDurationIsElapsedTimeAndCrossesATransitionWithoutChangingLength() throws {
        let calendar = try newYork()

        let springStart = try #require(
            CadenceCalendarEventTiming.startDate(dateKey: Self.springForward, startMin: 90, calendar: calendar)
        )
        let springEnd = try #require(calendar.date(byAdding: .minute, value: 60, to: springStart))
        #expect(calendar.component(.hour, from: springEnd) == 3, "01:30 + 60 real minutes reads 03:30 that day")
        #expect(calendar.component(.minute, from: springEnd) == 30)
        #expect(springEnd.timeIntervalSince(springStart) == 3600, "the meeting is still an hour long")

        let fallStart = try #require(
            CadenceCalendarEventTiming.startDate(dateKey: Self.fallBack, startMin: 90, calendar: calendar)
        )
        let fallEnd = try #require(calendar.date(byAdding: .minute, value: 60, to: fallStart))
        #expect(calendar.component(.hour, from: fallEnd) == 1, "01:30 + 60 real minutes reads 01:30 again that day")
        #expect(calendar.component(.minute, from: fallEnd) == 30)
        #expect(fallEnd.timeIntervalSince(fallStart) == 3600, "the meeting is still an hour long")

        // Setting the clock instead would make the meeting 0 or 7200 seconds long, which is the
        // mistake this test exists to make loud.
        let setInstead = try #require(
            calendar.date(bySettingHour: 2, minute: 30, second: 0, of: fallStart)
        )
        #expect(setInstead.timeIntervalSince(fallStart) != 3600)
    }

    /// The three call sites, in source: each sets its start through `CadenceCalendarEventTiming`
    /// and each keeps its end as a duration added to that start. `Cadence/iOS/` is behind
    /// `#if os(iOS)` while `CadenceTests` builds on macOS, so the iOS site has no other reachable
    /// pin; the two macOS sites are scanned the same way because their end legs are likewise
    /// unreachable without an authorized `EKEventStore`, which this suite must never open.
    @Test func everyEventStartWriteSetsTheClockAndEveryEventEndStaysADuration() throws {
        let manager = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Services/CalendarManager.swift")
        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")

        // The stripper must actually be discriminating here, or every absence below is free.
        let strippedProbe = CadenceSourceScan.strippingComments("let a = 1 // value: startMin\n")
        #expect(!strippedProbe.contains("value: startMin"), "the comment stripper is not stripping")
        #expect(strippedProbe.contains("let a = 1"), "the comment stripper ate code")

        // Positive: the start legs route through the one helper.
        #expect(
            CadenceSourceScan.matchCount("CadenceCalendarEventTiming\\.startDate\\(", in: manager) == 2,
            "CalendarManager has exactly two minute-of-day start legs"
        )
        #expect(
            CadenceSourceScan.matchCount("CadenceCalendarEventTiming\\.startDate\\(", in: sheet) == 1,
            "the quick-create sheet has exactly one"
        )

        // Positive: the end legs are still durations added to the start.
        #expect(
            manager.contains("calendar.date(byAdding: .minute, value: 60, to: startDate)"),
            "convertAllDayEventToTimed's one-hour block is an hour of real time after its start"
        )
        #expect(
            manager.contains("calendar.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate)"),
            "updateEvent's end is durationMinutes of real time after its start"
        )
        #expect(
            sheet.contains("Calendar.current.date(byAdding: .minute, value: max(5, estimatedMinutes), to: startDate)"),
            "the sheet's end is estimatedMinutes of real time after its start"
        )

        // Negative: no minute-of-day is added to a day's midnight anywhere in these two files.
        for (path, source) in [("CalendarManager.swift", manager), ("iOSCalendarQuickCreateSheet.swift", sheet)] {
            let offenders = CadenceSourceScan.matchLines(
                "byAdding:\\s*\\.minute,\\s*value:\\s*start(Min|Minute)",
                in: source
            )
            #expect(offenders.isEmpty, "\(path) still adds a minute-of-day to midnight: \(offenders)")
        }

        // Non-vacuity: the regex above must match the shape it is hunting and miss the duration it
        // must not touch.
        #expect(
            CadenceSourceScan.matchCount(
                "byAdding:\\s*\\.minute,\\s*value:\\s*start(Min|Minute)",
                in: "x = cal.date(byAdding: .minute, value: startMin, to: baseDate)"
            ) == 1
        )
        #expect(
            CadenceSourceScan.matchCount(
                "byAdding:\\s*\\.minute,\\s*value:\\s*start(Min|Minute)",
                in: "x = cal.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate)"
            ) == 0
        )
    }
}
