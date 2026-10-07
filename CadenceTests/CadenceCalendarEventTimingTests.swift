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
//  **T-3051 added a fourth.** `CalendarManager.createStandaloneEvent` — the macOS drag-to-create
//  path, reached from `CalendarPageMonthSupportViews` and `SchedulePanel` — had the same defect
//  spelled `startOfDay.addingTimeInterval(TimeInterval(startMin * 60))`, with its *end* anchored at
//  the same midnight. An `rg 'byAdding: .minute'` scores 0 on that spelling, which is how both
//  earlier audits walked past it. It holds the day as a `Date` rather than a key, so
//  `CadenceCalendarEventTiming` grew a `startDate(day:startMin:calendar:)` **overload** of the one
//  rule rather than a second copy of it, and the scan below now hunts `addingTimeInterval` too.
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

    // MARK: - 2b. The `Date`-day overload, T-3051

    /// `CalendarManager.createStandaloneEvent` holds the day as a `Date`, not a stored key, so it
    /// takes the `day:` overload. Same three days, same answer — and this is the macOS
    /// drag-to-create path, which writes into the owner's real Calendar.
    @Test func theDayOverloadSetsTheWallClockMinuteOfDayOnBothTransitionDaysAndAnOrdinaryOne() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            let start = try #require(
                CadenceCalendarEventTiming.startDate(day: base, startMin: 540, calendar: calendar),
                "09:00 on \(dateKey) must resolve from a Date day"
            )
            let components = calendar.dateComponents([.hour, .minute], from: start)
            #expect(components.hour == 9, "the standalone event on \(dateKey) starts at hour \(components.hour ?? -1), not 9")
            #expect(components.minute == 0, "the standalone event on \(dateKey) starts at minute \(components.minute ?? -1), not 0")
            #expect(calendar.isDate(start, inSameDayAs: base), "the standalone event on \(dateKey) left its own day")
        }
    }

    /// The old spelling at `CalendarManager.swift:235`, asserted rather than quoted:
    /// `startOfDay.addingTimeInterval(startMin * 60)` is elapsed seconds, so it lands on hour 10 on
    /// the spring-forward day and hour 8 on the fall-back day. `addingTimeInterval` is why two
    /// `byAdding: .minute` audits walked straight past this site.
    @Test func addingElapsedSecondsToMidnightLandsAnHourOffOnlyOnTheTransitionDays() throws {
        let calendar = try newYork()

        let expectedElapsedHours = [Self.springForward: 10, Self.ordinary: 9, Self.fallBack: 8]
        for (dateKey, expectedHour) in expectedElapsedHours {
            let base = try midnight(dateKey, calendar)
            let elapsed = calendar.startOfDay(for: base).addingTimeInterval(TimeInterval(540 * 60))
            #expect(
                calendar.component(.hour, from: elapsed) == expectedHour,
                "adding 540 minutes of real time to midnight on \(dateKey) must read hour \(expectedHour)"
            )

            let set = try #require(
                CadenceCalendarEventTiming.startDate(day: base, startMin: 540, calendar: calendar)
            )
            if dateKey == Self.ordinary {
                #expect(set == elapsed, "an ordinary day cannot tell the two spellings apart")
            } else {
                #expect(set != elapsed, "\(dateKey) must distinguish setting the clock from adding seconds")
            }
        }
    }

    /// `SchedulePanel` hands this overload `Date()` — an instant in the *middle* of the day, not
    /// its midnight — while `CalendarPageMonthSupportViews` hands it the column's own date. So the
    /// answer must not depend on **when during the day** the user dragged, and it must stay on
    /// that day.
    ///
    /// **Measured on this toolchain, because the obvious worry turns out not to be the mechanism:**
    /// `date(bySettingHour:minute:second:of:)` is documented as searching forward, but it answers
    /// the *same calendar day* for every `of:` instant tried here — 00:00, 09:00, 15:42 and 23:59,
    /// on all three days, and for the ambiguous 01:30 on the fall-back day as well. The
    /// `startOfDay` narrowing inside the helper is therefore belt-and-braces rather than the thing
    /// preventing a roll onto tomorrow; it is kept because it makes the `day:` overload provably
    /// the same function as the `dateKey:` one, whose base is always a midnight. Do not delete it
    /// on the strength of this paragraph — delete it and `theKeyAndDayOverloadsAgree…` below is the
    /// pin that still has to hold.
    @Test func theDayOverloadAnswersTheSameInstantFromAnyTimeOfDayWithinTheDay() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            let expected = try #require(
                CadenceCalendarEventTiming.startDate(day: base, startMin: 540, calendar: calendar)
            )
            for (hour, minute) in [(0, 0), (9, 0), (15, 42), (23, 59)] {
                let instant = try #require(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base))
                let start = try #require(
                    CadenceCalendarEventTiming.startDate(day: instant, startMin: 540, calendar: calendar),
                    "09:00 must resolve from \(hour):\(minute) on \(dateKey)"
                )
                #expect(start == expected, "the answer moved when the day was handed in as \(hour):\(minute) on \(dateKey)")
                #expect(calendar.isDate(start, inSameDayAs: base), "09:00 asked of a \(hour):\(minute) \(dateKey) rolled onto another day")
                #expect(calendar.component(.hour, from: start) == 9)
            }
        }
    }

    /// Out of range on the `Date` overload too. `createStandaloneEvent` refuses the write rather
    /// than filing the event on a different calendar day than the one the user dragged on.
    @Test func anOutOfRangeMinuteNamesNoInstantOnTheDayOverloadEither() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            for startMin in [1440, 1441, 1500, 2880, -1] {
                #expect(
                    CadenceCalendarEventTiming.startDate(day: base, startMin: startMin, calendar: calendar) == nil,
                    "\(startMin) names no time on \(dateKey)"
                )
            }
        }
    }

    /// The two overloads are one rule, not two: for every day key they answer the same instant.
    @Test func theKeyAndDayOverloadsAgreeOnEveryMinuteTheyBothResolve() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            for startMin in [0, 90, 150, 540, 1439] {
                let fromKey = CadenceCalendarEventTiming.startDate(dateKey: dateKey, startMin: startMin, calendar: calendar)
                let fromDay = CadenceCalendarEventTiming.startDate(day: base, startMin: startMin, calendar: calendar)
                #expect(fromKey == fromDay, "the two overloads disagree at \(startMin) on \(dateKey)")
                #expect(fromKey != nil, "\(startMin) must resolve on \(dateKey)")
            }
        }
    }

    // MARK: - 2c. The iOS bundle edit sheet's round trip, T-3051

    //  **The fifth site, and the first one that mutates data Cadence itself stores.** T-3051's
    //  filing called `iOSCalendarBundleDetailSheet.timeDate(on:minute:)` a `DatePicker` seed and
    //  listed it as display-only. It is not. The seed is read straight back out by that sheet's
    //  `startMinute`, and `save()` hands `startMinute` to
    //  `CadenceTaskMutationSupport.updateBundle(startMin:)`, which assigns `bundle.startMin` and
    //  commits through `CadencePendingChangePersistence` — so on a transition day, *opening the
    //  sheet and tapping Save moved the block an hour with no user edit at all*.
    //
    //  The sheet is behind `#if os(iOS)` and `timeDate` is `private static`, so `CadenceTests`
    //  (a macOS target) cannot call it. It is pinned the way the iOS quick-create site is: the
    //  behaviour is asserted on the shared helper the sheet now delegates to — which, after the
    //  fix, *is* the sheet's arithmetic — and the delegation itself is asserted in source by
    //  `theBundleEditSheetSeedsItsPickerBySettingTheClock` below.

    /// The headline: a block stored at `startMin = 540` must seed 09:00 and read back **540**, on
    /// a 23-hour day, a 25-hour day and an ordinary one alike. The old
    /// `date(byAdding: .minute, value: 540, to: startOfDay)` seed read back 600 on the
    /// spring-forward day and 480 on the fall-back day — the filing's two numbers.
    @Test func theBundleEditSheetRoundTripsAStoredStartMinuteOnBothTransitionDaysAndAnOrdinaryOne() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            let seeded = try #require(
                CadenceCalendarEventTiming.startDate(day: base, startMin: 540, calendar: calendar),
                "09:00 on \(dateKey) must seed the block sheet's picker"
            )
            let components = calendar.dateComponents([.hour, .minute], from: seeded)
            #expect(
                components.hour == 9,
                "the 09:00 block on \(dateKey) seeds hour \(components.hour ?? -1), not 9"
            )
            #expect(
                components.minute == 0,
                "the 09:00 block on \(dateKey) seeds minute \(components.minute ?? -1), not 0"
            )

            // `startMinute`'s own arithmetic, spelled exactly as the sheet spells it. This is the
            // integer `save()` writes into `bundle.startMin`.
            let readBack = max(0, min((components.hour ?? 0) * 60 + (components.minute ?? 0), (24 * 60) - 5))
            #expect(
                readBack == 540,
                "saving the block sheet unopened on \(dateKey) rewrote startMin 540 as \(readBack)"
            )
            #expect(calendar.isDate(seeded, inSameDayAs: base), "the seed left \(dateKey)")
        }
    }

    /// The same round trip over **every** minute the sheet can hold, not just 09:00: a green run on
    /// one number cannot distinguish a fixed conversion from a lucky one.
    ///
    /// It is the identity everywhere except the hour the spring-forward day does not have. 02:00 to
    /// 02:59 on 2026-03-08 never occur, so there is nothing for them to round-trip *to*; they all
    /// resolve forward to 03:00 (180), the helper's chosen gap answer, and that collapse is the one
    /// place an edit the user did not make can still change the stored minute. It is asserted
    /// rather than skipped, so a later change to the gap rule fails here.
    ///
    /// The fall-back day has no such exception: an ambiguous 01:30 resolves to the *first* of its
    /// two occurrences, whose `.hour`/`.minute` are still 1 and 30, so the identity holds there.
    @Test func everyMinuteTheBundleSheetCanHoldSurvivesTheRoundTripExceptTheHourTheClockSkips() throws {
        let calendar = try newYork()
        let ceiling = (24 * 60) - 5

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            var collapsed: [Int] = []

            for minute in 0...ceiling {
                let seeded = try #require(
                    CadenceCalendarEventTiming.startDate(day: base, startMin: minute, calendar: calendar),
                    "minute \(minute) must seed on \(dateKey)"
                )
                let components = calendar.dateComponents([.hour, .minute], from: seeded)
                let readBack = max(0, min((components.hour ?? 0) * 60 + (components.minute ?? 0), ceiling))
                if readBack != minute { collapsed.append(minute) }
                #expect(calendar.isDate(seeded, inSameDayAs: base), "minute \(minute) left \(dateKey)")
            }

            if dateKey == Self.springForward {
                #expect(
                    collapsed == Array(120...179),
                    "only the hour 2026-03-08 skips may move, got \(collapsed.prefix(5))… (\(collapsed.count) minutes)"
                )
                let gap = try #require(
                    CadenceCalendarEventTiming.startDate(day: base, startMin: 150, calendar: calendar)
                )
                #expect(calendar.component(.hour, from: gap) == 3, "02:30 opens when the gap closes")
                #expect(calendar.component(.minute, from: gap) == 0)
            } else {
                #expect(
                    collapsed.isEmpty,
                    "\(dateKey) must round-trip every minute, but \(collapsed.count) moved: \(collapsed.prefix(5))…"
                )
            }
        }
    }

    /// The ambiguous reading, named on its own because the round trip above would also pass if the
    /// helper answered the *second* 01:30. It answers the first, which is EDT.
    @Test func theBundleSheetSeedsTheFirstOfTwoAmbiguousReadingsOnTheFallBackDay() throws {
        let calendar = try newYork()

        let base = try midnight(Self.fallBack, calendar)
        let seeded = try #require(
            CadenceCalendarEventTiming.startDate(day: base, startMin: 90, calendar: calendar)
        )
        #expect(calendar.component(.hour, from: seeded) == 1)
        #expect(calendar.component(.minute, from: seeded) == 30)
        #expect(
            calendar.timeZone.secondsFromGMT(for: seeded) == Self.edt,
            "the block sheet seeds the first 01:30, which is still EDT"
        )
    }

    /// **Out of range diverges from the three write sites, deliberately.** They refuse rather than
    /// mis-date a real calendar event; this is a non-failable `@State` seed inside a `View.init`,
    /// so the picker must be handed *some* instant and the sheet clamps instead.
    ///
    /// The old code clamped the floor (`max(0, minute)`) and had **no ceiling**, so a stored 1500
    /// rolled the seed onto the *next calendar day* at 01:00 and `startMinute` read it back as 60 —
    /// the block jumped a day as well as an hour. The ceiling is now the one `startMinute` and
    /// `updateBundle` already impose, so an out-of-range minute lands at 23:55 on the block's own
    /// day. Both halves are asserted: the old roll-off, so "it used to be worse" is a measurement,
    /// and the new clamp.
    @Test func anOutOfRangeBundleStartMinuteClampsToTheBlocksOwnDayInsteadOfRollingOntoTheNext() throws {
        let calendar = try newYork()
        let ceiling = (24 * 60) - 5

        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)

            // The old arithmetic, asserted rather than quoted.
            let rolled = try #require(calendar.date(byAdding: .minute, value: 1500, to: base))
            #expect(
                !calendar.isDate(rolled, inSameDayAs: base),
                "adding 1500 elapsed minutes to midnight on \(dateKey) used to leave the day"
            )

            // The helper itself still refuses, which is what the write sites rely on …
            #expect(
                CadenceCalendarEventTiming.startDate(day: base, startMin: 1500, calendar: calendar) == nil,
                "1500 names no time on \(dateKey)"
            )

            // … and the sheet's two-sided clamp is what turns that refusal into a seed.
            for minute in [1440, 1500, 2880, -1, -600] {
                let clamped = min(max(0, minute), ceiling)
                let seeded = try #require(
                    CadenceCalendarEventTiming.startDate(day: base, startMin: clamped, calendar: calendar),
                    "the clamped \(minute) must seed on \(dateKey)"
                )
                #expect(
                    calendar.isDate(seeded, inSameDayAs: base),
                    "a clamped \(minute) must stay on \(dateKey)"
                )
                let components = calendar.dateComponents([.hour, .minute], from: seeded)
                let readBack = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                #expect(readBack == clamped, "the clamped \(minute) must round-trip on \(dateKey)")
            }
        }
    }

    /// The delegation, in source. `timeDate` is `private static` inside an `#if os(iOS)` file, so
    /// this is the only reachable pin that the sheet actually calls the shared rule — and it is
    /// what fails if a later edit respells the conversion locally, which is how one rule reached
    /// five copies.
    @Test func theBundleEditSheetSeedsItsPickerBySettingTheClock() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSCalendarBundleDetailSheet.swift")

        // The stripper must be discriminating, or every absence below is free. The doc comments on
        // this sheet quote both offending spellings on purpose.
        let strippedProbe = CadenceSourceScan.strippingComments("let a = 1 // byAdding: .minute\n")
        #expect(!strippedProbe.contains("byAdding"), "the comment stripper is not stripping")
        #expect(strippedProbe.contains("let a = 1"), "the comment stripper ate code")

        #expect(
            CadenceSourceScan.matchCount("CadenceCalendarEventTiming\\.startDate\\(", in: sheet) == 1,
            "the block edit sheet has exactly one minute-of-day seed and it routes through the helper"
        )

        // Negative, in both spellings — `addingTimeInterval` is the one an `rg 'byAdding: .minute'`
        // scores 0 on, and it is how two audits walked past `createStandaloneEvent`.
        let added = CadenceSourceScan.matchLines("byAdding:\\s*\\.minute,\\s*value:\\s*(max\\(0,\\s*)?minute", in: sheet)
        #expect(added.isEmpty, "the block edit sheet still adds a minute-of-day to midnight: \(added)")
        let elapsed = CadenceSourceScan.matchLines("addingTimeInterval", in: sheet)
        #expect(elapsed.isEmpty, "the block edit sheet converts a time by elapsed seconds: \(elapsed)")

        // Non-vacuity: the regex matches the line that was there and misses a real duration.
        #expect(
            CadenceSourceScan.matchCount(
                "byAdding:\\s*\\.minute,\\s*value:\\s*(max\\(0,\\s*)?minute",
                in: "return calendar.date(byAdding: .minute, value: max(0, minute), to: start) ?? start"
            ) == 1
        )
        #expect(
            CadenceSourceScan.matchCount(
                "byAdding:\\s*\\.minute,\\s*value:\\s*(max\\(0,\\s*)?minute",
                in: "x = cal.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate)"
            ) == 0
        )

        // The read-back direction is wall-clock and must stay that way: it is the half that turns
        // a wrong seed into a wrong `bundle.startMin`.
        #expect(
            sheet.contains("calendar.dateComponents([.hour, .minute], from: startTime)"),
            "the block edit sheet reads its picker back as a clock reading"
        )
        // And the write it feeds, so "this is a write path, not a preview" is pinned, not asserted
        // in a comment.
        #expect(
            CadenceSourceScan.matchCount("CadenceTaskMutationSupport\\.updateBundle\\(", in: sheet) == 1,
            "the block edit sheet's Save writes startMinute into the store"
        )
        #expect(sheet.contains("startMin: startMinute"), "and it is startMinute that it writes")
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

        // T-3051: the same claim for `createStandaloneEvent`'s end, whose duration is a dragged
        // `endMin - startMin` rather than a fixed hour. A 30-minute drag is 30 minutes of real time
        // on every one of the three days; it used to be `startMin + 30` measured from midnight, so
        // it inherited the start's error instead of being a duration at all.
        for dateKey in Self.everyDay {
            let base = try midnight(dateKey, calendar)
            let start = try #require(
                CadenceCalendarEventTiming.startDate(day: base, startMin: 540, calendar: calendar)
            )
            let end = try #require(calendar.date(byAdding: .minute, value: max(5, 30), to: start))
            #expect(end.timeIntervalSince(start) == 1800, "a 30-minute drag on \(dateKey) is 1800 seconds")
            #expect(calendar.component(.hour, from: end) == 9, "and still ends at 09:30 on \(dateKey)")
            #expect(calendar.component(.minute, from: end) == 30)
        }
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
            CadenceSourceScan.matchCount("CadenceCalendarEventTiming\\.startDate\\(", in: manager) == 3,
            "CalendarManager has exactly three minute-of-day start legs"
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
            manager.contains("timingCalendar.date(byAdding: .minute, value: max(5, durationMinutes), to: startDate)"),
            "createStandaloneEvent's end is durationMinutes of real time after its start (T-3051)"
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

        // **T-3051, the spelling two audits missed.** `addingTimeInterval` is elapsed seconds and
        // is the form `createStandaloneEvent` used, so a `byAdding: .minute` scan — the one above,
        // and the `rg` that produced T-3048 and T-3050 — scores 0 on it. Neither file may turn a
        // minute-of-day into an instant that way again.
        for (path, source) in [("CalendarManager.swift", manager), ("iOSCalendarQuickCreateSheet.swift", sheet)] {
            let offenders = CadenceSourceScan.matchLines("addingTimeInterval", in: source)
            #expect(offenders.isEmpty, "\(path) converts a time by elapsed seconds: \(offenders)")
        }

        // Non-vacuity for that scan too.
        #expect(
            CadenceSourceScan.matchCount(
                "addingTimeInterval",
                in: "event.startDate = startOfDay.addingTimeInterval(TimeInterval(startMin * 60))"
            ) == 1
        )

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
