//
//  CadenceTimeZoneIndependenceTests.swift
//  CadenceTests
//
//  T-1116. Three layers of one property: a `CadenceTests` run must mean the same thing on every
//  machine, and must still be able to catch "this breaks west of UTC".
//
//  1. The scheme's `TestAction` pins `TZ=UTC`, and `theTestHostRunsInTheZoneTheSchemePins` is the
//     assertion that the pin actually reached the process rather than merely being written down.
//  2. A suite pinned to UTC can never notice a bug that only appears at a negative offset, which is
//     exactly the bug that made this ticket. So the zone-sensitive shared date surfaces are
//     exercised across an explicit set of zones instead of whichever one the host is in.
//  3. `noDateSensitiveTestSilentlyInheritsTheHostsTimeZone` keeps new tests from re-acquiring the
//     dependency the pin now hides.
//

import Foundation
import Testing
@testable import Cadence

// MARK: - The zones every zone-sensitive rule in this target is read in

/// The explicit set of zones a zone-sensitive assertion is exercised in.
///
/// Three, and each is here for a reason a pair would not cover:
///
/// - **UTC** is what the test host is pinned to, so it is the zone a green run is actually
///   reporting on. Including it keeps the pinned reading in the same comparison as the others
///   rather than in a separate, privileged one.
/// - **Asia/Tokyo** is a positive offset with no DST. Every helper here was authored at `+0800`,
///   where a whole family of day-boundary defects is invisible, so this is the zone the repository's
///   existing green runs were already effectively measured in.
/// - **America/Los_Angeles** is a negative offset *with* DST, and is the pair of properties T-1115
///   was made of: an instant that is Monday in UTC is still Sunday there, and two days a year are
///   23 or 25 hours long. A single non-DST negative zone would catch the first and not the second.
///
/// Spelled as identifiers and force-unwrapped at the point of use rather than as `TimeZone` statics,
/// because a `TimeZone(identifier:)` that returns `nil` from a static initialiser is a crash with no
/// test name attached to it.
nonisolated enum CadenceTestTimeZones {
    static let identifiers = ["UTC", "Asia/Tokyo", "America/Los_Angeles"]

    /// The zone the scheme's `TestAction` pins the test host to.
    ///
    /// `UTC` and `GMT` are the same zone with two spellings, and which one comes back is not ours
    /// to choose: `TZ=UTC` in the environment yields a `TimeZone.current` whose identifier is
    /// **`GMT`** on this toolchain (measured 2026-09-08). Anything asserting on the pin therefore
    /// asserts on the offset, which has one spelling.
    static let pinnedIdentifier = "UTC"

    /// A Gregorian calendar in `identifier`'s zone.
    ///
    /// Gregorian rather than `Calendar.current`: every `yyyy-MM-dd` key Cadence stores is Gregorian
    /// (`DateFormatters.storageCalendar` says why), and a test that took the host's calendar
    /// identifier would be reading a second ambient input beside the zone this file exists to pin.
    ///
    /// The locale is left alone deliberately. Measured on this host under `TZ=UTC`:
    /// `Calendar(identifier: .gregorian)` and `Calendar.current` agree on both of the fields a
    /// week-shaped assertion can turn on — `firstWeekday` 1 and `minimumDaysInFirstWeek` 1 — so
    /// converting a `Calendar.current` site to this helper changes the zone's *spelling* and
    /// nothing about the arithmetic. Pinning a locale here as well would have changed both at once
    /// and made a failing conversion impossible to attribute.
    static func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: identifier),
            "\(identifier) is not a zone this system knows"
        )
        return calendar
    }

    /// A Gregorian calendar in the zone the test host is pinned to.
    ///
    /// The right replacement for a `Calendar.current` that a test never meant to be a variable: it
    /// computes what the pinned host computes, and says so.
    ///
    /// Non-throwing where `calendar(_:)` is throwing, and the asymmetry is deliberate rather than a
    /// convenience. A mistyped identifier handed to `calendar(_:)` must **fail**, because the zones
    /// it is asked for are the whole point of the comparison and one of them silently becoming UTC
    /// would turn a three-zone battery into a one-zone one that still says three. Here the
    /// identifier is a constant and the fallback is the same zone spelled differently, so there is
    /// no wrong answer to fall back to — and the call sites are ordinary tests that would otherwise
    /// have to gain a `throws` for a value that cannot fail. Same shape as `HabitStreakTests`'
    /// `gregorian(timeZoneIdentifier:)`, which this replaces the ad-hoc copies of.
    static func pinnedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: pinnedIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

// MARK: - The other ambient input a clock label reads: 12-hour or 24-hour

/// The hour cycles a clock-shaped assertion is read in, and the pin that keeps an unstated one from
/// meaning whatever the developer's Mac is set to.
///
/// **T-1135 made this necessary and [[T-1115]] is why it is a helper rather than a literal.** Until
/// then `TimeFormatters.timeString(from:)` spelled 12-hour AM/PM unconditionally, so a test could
/// assert `"1 PM"` and be right on every machine by accident. Now the formatter asks the locale, and
/// an assertion that does not state one is exactly the shape that cost a session: green here,
/// red on a German or British Mac, with nothing in the test saying which input moved.
///
/// Two zones of defence, the same two T-1116 built for the time zone:
///
/// - the scheme's `TestAction` pins **`-AppleLocale en_US`** so the whole target has a stated hour
///   cycle rather than the host's, and `theTestHostRunsInTheClockTheSchemePins` asserts the pin
///   landed rather than merely being written down;
/// - a test whose *subject* is the clock format states its locale outright, with these.
///
/// A launch argument rather than an environment variable, and that is measured rather than a style
/// choice (2026-09-12, macOS 26.1): `AppleLocale` set in the per-process **argument** domain does
/// reach `Locale.current` — `-AppleLocale en_GB` yields `hourCycle == .zeroToTwentyThree` — while
/// `AppleICUForce24HourTime`, the key the System Settings switch writes, is read only from the
/// global domain and ignores the argument domain entirely. So the locale is pinnable from a scheme
/// and the 24-hour *switch* is not; `twentyFourHour` below states the cycle through the locale
/// identifier instead, which is the same channel the switch uses once it is set.
nonisolated enum CadenceTestClocks {

    /// The locale the scheme's `TestAction` pins the host to.
    static let pinnedIdentifier = "en_US"

    /// A 12-hour clock, stated. `en_US` is the pinned identifier, so this is what an unstated
    /// assertion *should* be reading — naming it makes that a claim rather than a coincidence.
    static let twelveHour = Locale(identifier: "en_US")

    /// A 24-hour clock, stated, without changing the language with it.
    ///
    /// `en_US@hours=h23` rather than `en_GB`: it isolates the hour cycle from every other locale
    /// difference, so a failure cannot be blamed on British date order or spelling. Measured
    /// 2026-09-12 — Foundation honours the keyword: `hourCycle` is `.zeroToTwentyThree` and the
    /// `jmm` template is `HH:mm`, the same answers `en_GB`, `de_DE` and `fr_FR` give.
    static let twentyFourHour = Locale(identifier: "en_US@hours=h23")

    /// `h24`, the rarer 24-hour cycle in which midnight is `24:00`. Present so the app's choice to
    /// fold it into the `h23` spelling is asserted rather than assumed.
    static let twentyFourHourFromOne = Locale(identifier: "en_US@hours=h24")

    /// Both faces, for a test that has to be read in each.
    static let all: [(name: String, locale: Locale)] = [
        ("12-hour", twelveHour),
        ("24-hour", twentyFourHour),
    ]
}

// MARK: - The detectors

/// The two source-text detectors the sweeps rest on, at file scope and `nonisolated` so the
/// closures `CadenceScanInstrument` is built from carry no actor isolation across their escape.
nonisolated enum CadenceAmbientZoneReadScan {

    /// An ambient read is a zone the test never stated; a day-boundary needle is what makes that
    /// matter. Both must be present — the conjunction is the rule, not the ban.
    static func readsAmbientZoneForADayBoundary(_ body: String) -> Bool {
        ambientNeedles.contains { body.contains($0) } && dayBoundaryNeedles.contains { body.contains($0) }
    }

    /// A wall-clock read that reaches a day derivation. Weaker than the rule above and ledgered
    /// rather than banned; it is a clock race, not a zone dependency, and the pin does not fix it.
    static func readsTheClockForADayBoundary(_ body: String) -> Bool {
        body.contains("Date()") && dayBoundaryNeedles.contains { body.contains($0) }
    }

    /// Assembled from pieces so this file's own source does not contain the needles it scans for —
    /// the reason `CadenceRealTreeSweepScan` gives for the same trick. Without it, this suite would
    /// depend on `codeOnly`'s literal masking to avoid reporting itself, which makes the rule a
    /// property of the masker.
    static let ambientNeedles: [String] = {
        let current = "current"
        return [
            "Calendar." + current,
            "TimeZone." + current,
            "Calendar.autoupdating" + current.capitalized,
            "TimeZone.autoupdating" + current.capitalized,
            "calendar: ." + current,
            "timeZone: ." + current,
        ]
    }()

    /// The derivations whose answer changes with the zone. Not "anything that touches a Calendar":
    /// adding an hour to a timed event, or reading a `.minute`, is the same answer everywhere, and
    /// that difference is 28 of the 50 tests the ambient needles alone would have named.
    static let dayBoundaryNeedles = [
        "dateKey(",
        "weekKey(",
        "todayKey(",
        "storageKey(",
        "startOfDay",
        "dayOffset(",
        "relativeDate(",
        "CadenceCalendarDateMemory",
    ]
}

@MainActor
struct CadenceTimeZoneIndependenceTests {

    // MARK: - 1. The pin reaches the process

    /// The pin is only worth anything if it lands, and "it is written in the scheme" is not that
    /// claim. Measured 2026-09-08, and it is why this test asserts from inside the host rather than
    /// from the shell: a shell-level `TZ=` does **not** reach the spawned macOS test host — two
    /// full runs under `TZ=Asia/Shanghai` and `TZ=America/Los_Angeles` produced byte-identical
    /// failures — so the only mechanism that can pin the host is the scheme's own environment, and
    /// the only place that can confirm it did is here.
    ///
    /// Asserted on the **offset**, at four instants spread across the year, rather than on the
    /// identifier: `TZ=UTC` yields a `TimeZone.current` spelled `GMT`, and a zone with no DST is
    /// the property the pin is actually for. One instant would pass under `Europe/London` in
    /// January.
    @Test func theTestHostRunsInTheZoneTheSchemePins() throws {
        let probes = ["2026-01-15", "2026-04-15", "2026-07-15", "2026-10-15"]
        let reference = try CadenceTestTimeZones.calendar("UTC")

        for key in probes {
            let instant = try #require(DateFormatters.date(from: key, in: reference))
            #expect(
                TimeZone.current.secondsFromGMT(for: instant) == 0,
                """
                the test host is running at UTC\(TimeZone.current.secondsFromGMT(for: instant) / 3600) \
                on \(key), not UTC. The scheme's TestAction pins TZ=UTC; either that block was \
                dropped or shouldUseLaunchSchemeArgsEnv went back to YES.
                """
            )
        }

        // The ambient calendar is what an unpinned test silently reads, so it is what has to be
        // shown to agree with the pin — `TimeZone.current` alone would leave the possibility that
        // `Calendar.current` carries a different zone.
        #expect(Calendar.current.timeZone.secondsFromGMT() == 0)
    }

    /// **T-1135.** The second ambient input, and the same claim made about it: the host's clock
    /// face is pinned, and the pin reached the process.
    ///
    /// Worth its own assertion rather than a line in the zone one because it fails for a different
    /// reason and says so. `TZ` is an environment variable and `AppleLocale` is a launch argument —
    /// different blocks of the scheme, different delivery mechanisms — so a change that drops one
    /// need not drop the other, and a suite that lost this pin would go red on a British Mac with
    /// nothing pointing at the scheme.
    ///
    /// The assertion is on the **hour cycle**, not on the identifier. `en_US` is one of several
    /// identifiers that would satisfy this suite, and the identifier is not what any assertion in
    /// the target actually turns on; a test pinned to the spelling would fail on a correct change
    /// to `en_US_POSIX`. The identifier check underneath it is a separate, weaker claim about
    /// *which* locale arrived, phrased as a prefix so a region or keyword suffix does not break it.
    @Test func theTestHostRunsInTheClockTheSchemePins() {
        #expect(
            !TimeFormatters.usesTwentyFourHourClock(),
            """
            the test host reads a 24-hour clock (Locale.current = \(Locale.current.identifier), \
            hourCycle = \(Locale.current.hourCycle)), so every clock-shaped assertion in this target \
            that did not state a locale is measuring this machine. The TestAction pins \
            -AppleLocale \(CadenceTestClocks.pinnedIdentifier); either that argument was dropped or \
            shouldUseLaunchSchemeArgsEnv went back to YES.
            """
        )
        #expect(
            Locale.current.identifier.hasPrefix(CadenceTestClocks.pinnedIdentifier),
            "the host locale is \(Locale.current.identifier), not the pinned \(CadenceTestClocks.pinnedIdentifier)"
        )

        // And the pin is only useful if the helper a stated test uses agrees with it, so the two
        // faces are separated here as well — otherwise a `usesTwentyFourHourClock` that returned
        // `false` for everything would satisfy the assertion above.
        #expect(!TimeFormatters.usesTwentyFourHourClock(CadenceTestClocks.twelveHour))
        #expect(TimeFormatters.usesTwentyFourHourClock(CadenceTestClocks.twentyFourHour))
        #expect(TimeFormatters.usesTwentyFourHourClock(CadenceTestClocks.twentyFourHourFromOne))
    }

    /// The pin lives on the **TestAction**, not on the LaunchAction, and this is the assertion that
    /// keeps it there.
    ///
    /// `TestAction` inherited the Launch action's environment (`shouldUseLaunchSchemeArgsEnv =
    /// "YES"`) and carried no environment of its own, so there were two ways to pin it. Adding `TZ`
    /// to the LaunchAction would have been one line fewer and would also have pinned **the app a
    /// human runs from Xcode** to UTC — a debugging session in which every date on screen is
    /// several hours off the one on the wall clock, which is a change to the product surface made
    /// in service of the test suite. So the TestAction gained its own block and stopped inheriting.
    ///
    /// Not inheriting has a cost that is paid explicitly rather than lost: the LaunchAction's
    /// `OS_ACTIVITY_MODE=disable` and its three CoreData logging arguments no longer arrive by
    /// inheritance, so they are spelled again in the TestAction and checked here. A test run that
    /// silently regained CoreData's stderr logging would not fail anything; it would just make
    /// every log unreadable.
    @Test func theZonePinIsOnTheTestActionAndDoesNotFollowAHumanRunningTheApp() throws {
        let scheme = try CadenceSourceScan.sourceFile(
            "Cadence.xcodeproj/xcshareddata/xcschemes/Cadence.xcscheme"
        )
        let testAction = try #require(
            section(of: scheme, from: "<TestAction", to: "</TestAction>"),
            "the scheme no longer has a TestAction"
        )
        let launchAction = try #require(
            section(of: scheme, from: "<LaunchAction", to: "</LaunchAction>"),
            "the scheme no longer has a LaunchAction"
        )

        #expect(
            testAction.contains("shouldUseLaunchSchemeArgsEnv = \"NO\""),
            "the TestAction inherits the Launch action's environment again, so its own TZ pin may be ignored"
        )
        #expect(
            testAction.contains("key = \"TZ\""),
            "the TestAction declares no TZ, so a run means whatever the machine's zone happens to be"
        )
        #expect(
            testAction.contains("value = \"\(CadenceTestTimeZones.pinnedIdentifier)\""),
            "the TestAction's TZ is no longer \(CadenceTestTimeZones.pinnedIdentifier)"
        )
        #expect(
            testAction.contains("key = \"OS_ACTIVITY_MODE\""),
            "the TestAction stopped inheriting the Launch environment and did not re-declare OS_ACTIVITY_MODE"
        )
        #expect(
            testAction.contains("-com.apple.CoreData.Logging.stderr 0"),
            "the TestAction stopped inheriting the Launch arguments and did not re-declare the CoreData logging ones"
        )
        // T-1135's pin, in the same block and for the same reason.
        #expect(
            testAction.contains("-AppleLocale \(CadenceTestClocks.pinnedIdentifier)"),
            """
            the TestAction declares no AppleLocale, so a clock-shaped assertion means whatever \
            hour cycle the machine's Language & Region happens to be set to
            """
        )

        #expect(
            !launchAction.contains("key = \"TZ\""),
            """
            the LaunchAction pins TZ, so running Cadence from Xcode now shows a human dates in \
            the test suite's zone rather than their own
            """
        )
        #expect(
            !launchAction.contains("-AppleLocale"),
            """
            the LaunchAction pins AppleLocale, so running Cadence from Xcode now shows a human a \
            clock face chosen by the test suite rather than the one their Mac is set to
            """
        )
    }

    // MARK: - 2. What the pin would otherwise hide: the same rules, read in three zones

    /// Every day of a year round-trips through its own storage key, in each zone.
    ///
    /// This is the shape of the defect the pin would hide. `DateFormatters.date(from:in:)` resolves
    /// a key to midnight in the calendar's zone and `dateKey(from:calendar:)` names an instant's day
    /// in the calendar's zone; if either one silently used a fixed zone instead, the pair would
    /// still agree on a UTC host and disagree by a day on every machine with a non-zero offset. A
    /// full year is walked rather than a handful of dates because the two ways this breaks are
    /// seasonal: a DST transition, and a month boundary that a zone offset moves across.
    @Test func everyDayOfAYearRoundTripsThroughItsStorageKeyInEveryZone() throws {
        for identifier in CadenceTestTimeZones.identifiers {
            let calendar = try CadenceTestTimeZones.calendar(identifier)
            var key = "2026-01-01"

            for _ in 0..<365 {
                let midnight = try #require(
                    DateFormatters.date(from: key, in: calendar),
                    "\(key) did not resolve in \(identifier)"
                )
                #expect(
                    DateFormatters.dateKey(from: midnight, calendar: calendar) == key,
                    "\(key) did not survive its own round trip in \(identifier)"
                )
                #expect(
                    calendar.startOfDay(for: midnight) == midnight,
                    "\(key) resolved to something other than midnight in \(identifier)"
                )

                let next = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
                key = DateFormatters.dateKey(from: next, calendar: calendar)
            }

            #expect(key == "2027-01-01", "walking 365 days from 2026-01-01 in \(identifier) landed on \(key)")
        }
    }

    /// One instant, three zones, and the key is the zone's own day rather than UTC's.
    ///
    /// The year-long round trip above is self-consistent by construction — it asks a zone to agree
    /// with itself, which a helper that ignored the zone entirely would also do. This is the other
    /// half: two instants chosen so that the answer *differs* by zone, in both directions, so a
    /// derivation that dropped the calendar it was handed cannot pass.
    @Test func anInstantIsKeyedToItsZonesOwnDayNotToUTCs() throws {
        let utc = try CadenceTestTimeZones.calendar("UTC")
        // 2026-03-15 06:30Z: still 2026-03-14 in Los Angeles (23:30 PDT), already 2026-03-15
        // elsewhere.
        let beforeUTCMidday = try #require(
            DateFormatters.date(from: "2026-03-15", in: utc)?.addingTimeInterval(6.5 * 3600)
        )
        // 2026-03-15 15:30Z: already 2026-03-16 in Tokyo (00:30 JST), still 2026-03-15 elsewhere.
        let afterUTCMidday = try #require(
            DateFormatters.date(from: "2026-03-15", in: utc)?.addingTimeInterval(15.5 * 3600)
        )

        let expected: [(instant: Date, keys: [String: String])] = [
            (
                beforeUTCMidday,
                [
                    "UTC": "2026-03-15",
                    "Asia/Tokyo": "2026-03-15",
                    "America/Los_Angeles": "2026-03-14",
                ]
            ),
            (
                afterUTCMidday,
                [
                    "UTC": "2026-03-15",
                    "Asia/Tokyo": "2026-03-16",
                    "America/Los_Angeles": "2026-03-15",
                ]
            ),
        ]

        for probe in expected {
            for identifier in CadenceTestTimeZones.identifiers {
                let calendar = try CadenceTestTimeZones.calendar(identifier)
                let wanted = try #require(probe.keys[identifier])
                #expect(
                    DateFormatters.dateKey(from: probe.instant, calendar: calendar) == wanted,
                    "\(probe.instant) is not \(wanted) in \(identifier)"
                )
                #expect(
                    CadenceCalendarDateMemory.storageKey(for: probe.instant, calendar: calendar) == wanted,
                    "the remembered day for \(probe.instant) is not \(wanted) in \(identifier)"
                )
            }
        }
    }

    /// The two days a year that are not 24 hours long, in the only one of the three zones that has
    /// them.
    ///
    /// A day-count that works by adding 86,400 seconds is correct in UTC and in Tokyo and wrong
    /// twice a year in Los Angeles, so a suite pinned to UTC and read only there could never
    /// separate the two implementations. Both transitions are asserted, because they fail in
    /// opposite directions: the spring one has no 02:00 at all and the autumn one has 01:00 twice.
    @Test func aDaylightSavingTransitionDoesNotMoveADayOffItsOwnKey() throws {
        let losAngeles = try CadenceTestTimeZones.calendar("America/Los_Angeles")

        // 2026: second Sunday in March is the 8th, first Sunday in November is the 1st.
        let transitions: [(key: String, hours: Double)] = [
            ("2026-03-08", 23),
            ("2026-11-01", 25),
        ]

        for transition in transitions {
            let midnight = try #require(DateFormatters.date(from: transition.key, in: losAngeles))
            let nextMidnight = try #require(losAngeles.date(byAdding: .day, value: 1, to: midnight))

            #expect(
                nextMidnight.timeIntervalSince(midnight) == transition.hours * 3600,
                "\(transition.key) is not \(transition.hours) hours long in America/Los_Angeles"
            )
            #expect(DateFormatters.dateKey(from: midnight, calendar: losAngeles) == transition.key)

            // The hour that does not exist, and the hour that happens twice, both still key to the
            // day they are part of. `addingTimeInterval` deliberately, not calendar arithmetic:
            // this is the wall-clock-naive spelling, and it is the one that has to stay correct.
            for offset in stride(from: 0.0, to: transition.hours, by: 1) {
                #expect(
                    DateFormatters.dateKey(
                        from: midnight.addingTimeInterval(offset * 3600),
                        calendar: losAngeles
                    ) == transition.key,
                    "hour \(offset) of \(transition.key) keyed to another day"
                )
            }
        }
    }

    /// A remembered calendar position survives a round trip through `UserDefaults` in every zone.
    ///
    /// `CadenceCalendarDateMemory` writes a `yyyy-MM-dd` and reads it back, and its own
    /// documentation names the failure this covers: snapping in one zone and spelling in another
    /// names the day before. Both edges of the day are probed, because a one-hour-wide error is
    /// invisible in the middle of one.
    @Test func aRememberedDayIsReadBackAsTheSameDayInEveryZone() throws {
        for identifier in CadenceTestTimeZones.identifiers {
            let calendar = try CadenceTestTimeZones.calendar(identifier)
            let key = "2026-11-01"
            let midnight = try #require(DateFormatters.date(from: key, in: calendar))

            for minutesIntoTheDay in [1.0, 60.0, 12 * 60.0, 23 * 60.0 + 59.0] {
                let instant = midnight.addingTimeInterval(minutesIntoTheDay * 60)
                let stored = CadenceCalendarDateMemory.storageKey(for: instant, calendar: calendar)
                #expect(stored == key, "\(minutesIntoTheDay) minutes into \(key) stored as \(stored) in \(identifier)")

                let readBack = try #require(
                    CadenceCalendarDateMemory.date(fromStored: stored, calendar: calendar),
                    "\(stored) did not read back in \(identifier)"
                )
                #expect(
                    CadenceCalendarDateMemory.storageKey(for: readBack, calendar: calendar) == key,
                    "the remembered day did not survive a round trip in \(identifier)"
                )
            }
        }
    }

    /// The storage calendar keeps the caller's zone and forces Gregorian, in every zone.
    ///
    /// Both halves in one assertion because they are the two ways the same string goes wrong:
    /// a key derived under the host's *calendar* reads `2569-08-11` in Thailand, and a key derived
    /// under the host's *zone* reads the day before west of UTC.
    @Test func theStorageCalendarKeepsTheZoneAndForcesGregorianInEveryZone() throws {
        for identifier in CadenceTestTimeZones.identifiers {
            for source in [Calendar.Identifier.gregorian, .buddhist, .japanese, .islamicUmmAlQura] {
                var calendar = Calendar(identifier: source)
                calendar.timeZone = try #require(TimeZone(identifier: identifier))

                let storage = DateFormatters.storageCalendar(inheritingTimeZoneFrom: calendar)
                #expect(storage.identifier == .gregorian, "\(source) did not become Gregorian in \(identifier)")
                // The zone itself, not its identifier. Measured 2026-09-08: `TimeZone(identifier:
                // "UTC")` comes back spelled **`GMT`**, so a string comparison here fails on a
                // correct implementation — the same trap the pin assertion above sidesteps by
                // reading the offset.
                #expect(
                    storage.timeZone == calendar.timeZone,
                    "\(source) lost its \(identifier) zone on the way to the storage calendar"
                )

                let parsed = try #require(DateFormatters.date(from: "2026-08-11", in: calendar))
                #expect(
                    DateFormatters.dateKey(from: parsed, calendar: calendar) == "2026-08-11",
                    "the key did not round-trip under \(source) in \(identifier)"
                )
            }
        }
    }

    // MARK: - 3. Nothing re-acquires the dependency the pin now hides

    /// A `@Test` that derives a calendar day from the **ambient** zone is a test whose meaning is a
    /// property of the machine it ran on. Pinning the host makes that reproducible; it does not make
    /// it stated, and a pin that is ever loosened would silently give every such test a different
    /// meaning. So they have to name a zone.
    ///
    /// **The inclusion rule, stated rather than implied.** A test is an offender when its own body,
    /// read with comments and string literals blanked, contains **both**:
    ///
    /// - an ambient read — `Calendar.current`, `TimeZone.current`, either `autoupdatingCurrent`, or
    ///   a `.current` passed as a `calendar:`/`timeZone:` argument; **and**
    /// - a **day-boundary** use — a storage-key or week-key derivation, a `startOfDay`, a
    ///   day-offset or relative-date label, or `CadenceCalendarDateMemory`.
    ///
    /// Both halves are load-bearing and the second is the whole reason this is not a ban on
    /// `Calendar.current`. Measured over this target on 2026-09-08: the ambient needles alone
    /// appear in **50** tests across 14 files, most of them reading a `Calendar` only to add an
    /// hour to a timed calendar event or to build a `DateComponents` — nothing there turns on which
    /// day an instant falls in, and rewriting those would be churn with no property behind it. The
    /// conjunction is **22** tests across 11 files, and that is the family T-1115 came out of.
    ///
    /// **`Date()` is a separate, weaker finding and is ledgered rather than banned** — see
    /// `theBareNowLedgerStatesHowManyDateSensitiveTestsStillReadTheClock` below.
    ///
    /// **One exemption, and it is a whole file.** `WeekKeyResolutionTests` exists to pin what the
    /// parameterless week-key helpers do *in the device's zone*; a test whose subject is the
    /// ambient default cannot state a zone instead. Exempting the file rather than the test names
    /// inside it is deliberate: that suite is under active edit for T-1115, and a by-name ledger
    /// here would go stale on a rename that has nothing to do with this rule.
    @Test func noDateSensitiveTestSilentlyInheritsTheHostsTimeZone() throws {
        let offenders = try dateSensitiveAmbientReads()
            .filter { $0.file != Self.ambientZoneIsTheSubjectIn }
            .map { "\($0.file.replacingOccurrences(of: "CadenceTests/", with: ""))/\($0.name)" }
            .sorted()

        #expect(
            offenders.isEmpty,
            """
            these tests derive a calendar day from the machine's own time zone instead of stating \
            one — pass a calendar from CadenceTestTimeZones: \(offenders.joined(separator: ", "))
            """
        )
    }

    /// The file whose subject *is* the ambient default, so it cannot state a zone instead.
    static let ambientZoneIsTheSubjectIn = "CadenceTests/WeekKeyResolutionTests.swift"

    /// A ledger, not a ban, and the difference is the finding's strength.
    ///
    /// A bare `Date()` in a test that then derives a day key is reading the wall clock: correct
    /// almost always, and wrong for the run that straddles midnight. That is a real defect and it is
    /// **not** the zone defect this ticket is about — pinning the host does not fix it and never
    /// could. Measured 2026-09-08: `Date()` appears in 40 of this target's 315 files, and most uses
    /// are "some instant" rather than a date under test, so a ban would be a mass rewrite of tests
    /// that are not wrong.
    ///
    /// So the population is written down instead, per file, and may not grow. A new test that reads
    /// the clock to derive a day fails here and has to either state an instant or be added
    /// deliberately.
    ///
    /// The counts are per file rather than a single total for the reason
    /// `CadenceControlAccessibilityLabelTests`' unnamed-tooltip ledger gives: a total that stays the
    /// same while one file loses a site and another gains one records nothing.
    @Test func theBareNowLedgerStatesHowManyDateSensitiveTestsStillReadTheClock() throws {
        let live = try dateSensitiveClockReads()
        var counted: [String: Int] = [:]
        for entry in live { counted[entry.file, default: 0] += 1 }

        #expect(
            counted == Self.bareNowLedger,
            """
            the bare-`Date()` population moved. Live: \
            \(counted.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")). \
            Ledger: \(Self.bareNowLedger.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")). \
            A new entry means a test derived a calendar day from the wall clock; a missing one means \
            a site was fixed and the ledger should shrink with it.
            """
        )
        #expect(!Self.bareNowLedger.isEmpty, "an empty ledger would make the comparison above vacuous")
    }

    /// Every `@Test` that derives a calendar day from `Date()`, by file. Shrinks only.
    static let bareNowLedger: [String: Int] = [
        "CadenceTests/CadenceReadServiceTests.swift": 1,
        "CadenceTests/CadenceRegularPaneLayoutTests.swift": 1,
        "CadenceTests/CadenceTaskComposerLayoutTests.swift": 1,
        "CadenceTests/CadenceTaskComposerSupportTests.swift": 2,
        "CadenceTests/CadenceWriteServiceTests.swift": 2,
        "CadenceTests/CalendarBehaviorRegressionTests.swift": 2,
        "CadenceTests/DateFormatterSupportTests.swift": 1,
        "CadenceTests/HabitInsightsAuditTests.swift": 1,
        "CadenceTests/NonisolatedValueTypeTests.swift": 1,
        "CadenceTests/TaskWorkflowRecurrenceTests.swift": 1,
        "CadenceTests/WidgetSupportTests.swift": 1,
    ]

    /// The two detectors, built against literal witnesses a plausible mistake separates.
    ///
    /// This is the non-vacuity claim the sweeps above rest on, and it is here rather than beside
    /// them because "no offenders" is what a clean target and a blind detector look like from the
    /// outside. Four witnesses, in two pairs, and each negative is the *nearest* miss:
    ///
    /// - the ambient detector must fire on a body that reads `Calendar.current` and derives a key,
    ///   and must not fire on the same body with the zone stated — that is the exact edit that
    ///   fixes an offender, so a detector that could not see it would report every fix as a
    ///   no-change;
    /// - it must also not fire on a body that reads `Calendar.current` for something that is not a
    ///   day boundary, which is the 28-test difference between the conjunction and a blanket ban;
    /// - the clock detector must fire on `Date()` reaching a key derivation and not on a `Date()`
    ///   used as an opaque timestamp.
    @Test func bothDetectorsStillSeparateAStatedZoneFromAnInheritedOne() throws {
        let ambient = try CadenceScanInstrument(
            "date-sensitive ambient zone read",
            fires: """
                let calendar = Calendar.current
                #expect(DateFormatters.dateKey(from: instant, calendar: calendar) == "2026-03-15")
                """,
            andNotOn: """
                let calendar = CadenceTestTimeZones.pinnedCalendar()
                #expect(DateFormatters.dateKey(from: instant, calendar: calendar) == "2026-03-15")
                """,
            by: CadenceAmbientZoneReadScan.readsAmbientZoneForADayBoundary
        )
        #expect(
            !ambient.fires(on: """
                let calendar = Calendar.current
                let end = calendar.date(byAdding: .hour, value: 1, to: start)
                """),
            "the ambient detector fires on a Calendar.current that decides no day boundary"
        )

        let clock = try CadenceScanInstrument(
            "date-sensitive wall-clock read",
            fires: """
                let tomorrow = DateFormatters.dateKey(from: Date().addingTimeInterval(86_400))
                """,
            andNotOn: """
                let stamp = Date()
                #expect(task.createdAt <= stamp)
                """,
            by: CadenceAmbientZoneReadScan.readsTheClockForADayBoundary
        )
        #expect(
            !clock.fires(on: """
                let key = DateFormatters.dateKey(from: fixedInstant, calendar: calendar)
                """),
            "the clock detector fires on a key derived from a stated instant"
        )

        // And the walk itself: a detector that works over an empty file list is the other way a
        // sweep passes forever.
        let files = try cadenceTestFiles()
        #expect(files.count >= 300, "the walk reached \(files.count) test files, fewer than the 315 known to exist")
        #expect(
            files.contains(Self.ambientZoneIsTheSubjectIn),
            "the walk never reached \(Self.ambientZoneIsTheSubjectIn), so exempting it proves nothing"
        )
    }

    // MARK: - The walk

    struct SweptTest: Hashable {
        let file: String
        let name: String
    }

    private func dateSensitiveAmbientReads() throws -> [SweptTest] {
        try sweptTests(matching: CadenceAmbientZoneReadScan.readsAmbientZoneForADayBoundary)
    }

    private func dateSensitiveClockReads() throws -> [SweptTest] {
        try sweptTests(matching: CadenceAmbientZoneReadScan.readsTheClockForADayBoundary)
    }

    /// Every `@Test` in this target whose own body the detector fires on.
    ///
    /// Bodies come from `CadenceSourceScan.functionBody(named:in:)` over `codeOnly` source rather
    /// than from a second brace matcher written here: `codeOnly` blanks literals, so a fixture that
    /// *quotes* `Calendar.current` — this file has several — is not counted as one, and the shared
    /// matcher already balances a signature's own parentheses before it looks for the body.
    private func sweptTests(matching detect: (String) -> Bool) throws -> [SweptTest] {
        var found: [SweptTest] = []
        var sources: [String: String] = [:]

        for declaration in try cadenceTestDeclarations() {
            let source: String
            if let cached = sources[declaration.file] {
                source = cached
            } else {
                source = CadenceSourceScan.codeOnly(try cadenceTestSource(declaration.file))
                sources[declaration.file] = source
            }
            guard let body = CadenceSourceScan.functionBody(named: declaration.name, in: source) else {
                continue
            }
            if detect(body) {
                found.append(SweptTest(file: declaration.file, name: declaration.name))
            }
        }
        return found
    }

    /// The text of one `<Action …>…</Action>` block, or `nil` when either delimiter is absent.
    private func section(of text: String, from opening: String, to closing: String) -> String? {
        guard let start = text.range(of: opening), let end = text.range(of: closing) else { return nil }
        guard start.lowerBound < end.lowerBound else { return nil }
        return String(text[start.lowerBound..<end.upperBound])
    }
}
