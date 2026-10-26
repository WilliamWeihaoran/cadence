import EventKit
import Foundation
import Testing

@testable import Cadence

/// **[[T-3186]] — the gate on the committed calendar fixture harness, pinned from both sides.**
///
/// The harness exists because the calendar cannot otherwise be looked at: an agent launch is
/// EventKit-disarmed, so every day answers `[]` and no event has ever been drawn outside the
/// owner's own session. The hazard it creates is the exact inverse — a build that could draw
/// fabricated calendar events, or worse could be nudged into reaching a real `EKEventStore`, would
/// be worse than no harness at all. So the gate is the thing under test here, not the fixtures.
///
/// Everything below is driven with literal environment dictionaries. `CadenceCalendarFixtureEvents`
/// and `CadenceUITestScenarioSeed.scenario(in:)` are both pure over that input precisely so this
/// suite never has to mutate the host's environment to ask the question.
@Suite("Calendar fixture events (T-3186)")
struct CadenceCalendarFixtureEventsTests {

    private static let mode = CadenceEventKitLaunchGate.uiTestModeVariable
    private static let scenario = CadenceUITestScenarioSeed.scenarioVariable

    private static let active: [String: String] = [mode: "1", scenario: "calendar-hues"]

    @Test func bothMobileCacheCallersAdmitTheActiveFixtureBeforeReachingTheManager() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarView.swift"))
        for name in ["refreshVisibleEvents", "refreshSelectedDayEvents"] {
            let body = try CadenceCommitSurfaceScan.declarationBody(named: name, in: source)
            let guardRange = try #require(body.range(of: "guard calendarManager.isAuthorized || CadenceCalendarFixtureEvents.isActive()"))
            let fetchRange = try #require(body.range(of: "calendarManager.fetchEvents("))
            #expect(guardRange.lowerBound < fetchRange.lowerBound)
            #expect(CadenceSourceScan.matchCount(#"CadenceCalendarFixtureEvents\.isActive\(\)"#, in: body) == 1)
        }
        let selected = try CadenceCommitSurfaceScan.declarationBody(named: "refreshSelectedDayEvents", in: source)
        #expect(selected.contains("cached[selectedKey] == nil else"))
    }

    // MARK: - 1. Unreachable without the variable

    /// The claim the whole design rests on: with nothing set, the fixture path does not exist and
    /// `nil` sends the caller to the real `EKEventStore` path it has always used.
    @Test func anEnvironmentThatAsksForNothingReachesNoFixture() {
        #expect(CadenceCalendarFixtureEvents.isActive(in: [:]) == false)
        #expect(CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: [:]) == nil)
        #expect(CadenceCalendarFixtureEvents.allDayEvents(for: Date(), in: [:]) == nil)
    }

    /// And not only for a dictionary this test wrote: **this host** sets neither variable, so the
    /// production call — the one the day cache actually makes, with the default argument — is `nil`
    /// here too. Without this the suite would only ever have proved something about its own input.
    @Test func theRunningProcessIsItselfOutsideTheGate() {
        let environment = ProcessInfo.processInfo.environment
        #expect(environment[Self.mode] != "1", "non-vacuity: this host must not be in UI-test mode")
        #expect(CadenceCalendarFixtureEvents.isActive() == false)
        #expect(CadenceCalendarFixtureEvents.timedEvents(for: Date()) == nil)
        #expect(CadenceCalendarFixtureEvents.allDayEvents(for: Date()) == nil)
    }

    /// Neither half opens it alone. This is the assertion a mutation that drops the test-mode check
    /// has to walk through, and it is why the check is spelled as two separate conditions.
    @Test func neitherHalfOfTheGateIsEnoughOnItsOwn() {
        #expect(CadenceCalendarFixtureEvents.isActive(in: [Self.mode: "1"]) == false)
        #expect(CadenceCalendarFixtureEvents.isActive(in: [Self.scenario: "calendar-hues"]) == false)
        #expect(CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: [Self.mode: "1"]) == nil)
        #expect(
            CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: [Self.scenario: "calendar-hues"]) == nil
        )
    }

    /// Any value but this scenario's own closes it — including the other three the build knows,
    /// which is what keeps the existing UI suites' columns free of fabricated events.
    @Test func onlyThisScenarioOpensTheGate() {
        for other in ["today-geometry", "today-row-crush", "popover-anchors", "calendar-hue", "", "1"] {
            #expect(
                CadenceCalendarFixtureEvents.isActive(in: [Self.mode: "1", Self.scenario: other]) == false,
                "scenario '\(other)' opened the fixture gate"
            )
        }
        // Non-vacuity: the one value that must open it does.
        #expect(CadenceCalendarFixtureEvents.isActive(in: Self.active))
    }

    /// `CADENCE_UI_TEST_MODE` is read as the exact string `1`, like every other site that reads it.
    @Test func theTestModeFlagIsNotTruthy() {
        for value in ["0", "true", "YES", "", "2"] {
            #expect(
                CadenceCalendarFixtureEvents.isActive(in: [Self.mode: value, Self.scenario: "calendar-hues"]) == false,
                "CADENCE_UI_TEST_MODE='\(value)' opened the fixture gate"
            )
        }
    }

    // MARK: - 2. The safety implication, stated structurally

    /// **The property that makes the harness safe rather than merely gated**: every environment
    /// that can see the fixtures is one `CadenceEventKitLaunchGate` has already disarmed, because
    /// the first half of this gate *is* one of its three disarm signals. So a launch cannot be in a
    /// state where it both draws fabricated events and can reach the owner's real calendar — the
    /// two are mutually exclusive by construction, not by habit.
    @Test func aLaunchThatSeesTheFixturesCannotReachARealEventStore() {
        var checked = 0
        for modeValue in ["1", "0", ""] {
            for scenarioValue in ["calendar-hues", "calendar-cascade", "today-geometry", "nonsense", ""] {
                let environment = [Self.mode: modeValue, Self.scenario: scenarioValue]
                guard CadenceCalendarFixtureEvents.isActive(in: environment) else { continue }
                checked += 1
                #expect(
                    CadenceEventKitLaunchGate.isDisarmed(in: environment),
                    "a fixture-active launch was not EventKit-disarmed: \(environment)"
                )
            }
        }
        #expect(checked == 2, "non-vacuity: expected exactly two active combinations, saw \(checked)")
    }

    // MARK: - 3. What it answers when it is open

    @Test func theOpenGateAnswersTodayAndOnlyToday() throws {
        let timed = try #require(CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: Self.active))
        #expect(timed.count == CadenceCalendarFixtureEvents.Fixture.timed.count)
        #expect(timed.allSatisfy { $0.isAllDay == false })

        let allDay = try #require(CadenceCalendarFixtureEvents.allDayEvents(for: Date(), in: Self.active))
        #expect(allDay.count == CadenceCalendarFixtureEvents.Fixture.allDay.count)
        #expect(allDay.allSatisfy { $0.isAllDay })

        // Another day is answered — not fallen through. An empty array and a `nil` mean different
        // things here, and the difference is whether EventKit is consulted for that column.
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        #expect(CadenceCalendarFixtureEvents.timedEvents(for: tomorrow, in: Self.active)?.isEmpty == true)
        #expect(CadenceCalendarFixtureEvents.allDayEvents(for: tomorrow, in: Self.active)?.isEmpty == true)
    }

    /// The hues the ticket named, read off the colour the screen is actually handed rather than off
    /// the constant — `Hue.hex` is derived from the components, so the two cannot drift apart.
    @Test func theFixtureCarriesTheTwoHuesTheTicketNamed() throws {
        #expect(CadenceCalendarFixtureEvents.Fixture.deepRed.hex == "#3D0000")
        #expect(CadenceCalendarFixtureEvents.Fixture.pureBlue.hex == "#0000FF")

        let timed = try #require(CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: Self.active))
        let byTitle = Dictionary(uniqueKeysWithValues: timed.map { ($0.title ?? "", $0) })
        for spec in CadenceCalendarFixtureEvents.Fixture.timed {
            let event = try #require(byTitle[spec.title], "no fixture event titled '\(spec.title)'")
            // T-2047: a fixture event without a calendar kills the app when its block is clicked.
            let calendar = try #require(event.calendar, "'\(spec.title)' carries no EKCalendar")
            let components = try #require(calendar.cgColor?.components)
            #expect(components.count >= 3)
            #expect(abs(components[0] - CGFloat(spec.hue.red) / 255) < 0.004, "\(spec.title) red")
            #expect(abs(components[1] - CGFloat(spec.hue.green) / 255) < 0.004, "\(spec.title) green")
            #expect(abs(components[2] - CGFloat(spec.hue.blue) / 255) < 0.004, "\(spec.title) blue")
        }
    }

    /// **The comparison the fixture exists to make: an event plate and a task plate side by side.**
    ///
    /// Two claims, and they pull in opposite directions, which is why both are asserted here. The
    /// task and the deep red event must OVERLAP, or there is no frame holding an event plate beside
    /// a task plate and [[T-3168]]'s claim cannot be looked at. And they must not start on the SAME
    /// minute, the gap agent `compactcascade` hit. A different start is NECESSARY for a cascade
    /// but not sufficient: `CadenceCalendarOverlapLayout` cascades only at a start gap of at least
    /// `cascadeGapMinutes` (~47 min on iOS at rest) and the Mac never cascades a task, so this
    /// 15-minute fixture photographs a SPLIT ([[T-3220]]). Nothing here asserts a cascade.
    ///
    /// Read through the derived constants rather than against a respelled 540 and 555, so moving
    /// the band moves every part of this together.
    @Test func theSeededTaskOverlapsTheDeepRedEventWithoutSharingItsStart() throws {
        let deepRed = try #require(
            CadenceCalendarFixtureEvents.Fixture.timed.first {
                $0.hue.hex == CadenceCalendarFixtureEvents.Fixture.deepRed.hex
            }
        )
        let band = CadenceCalendarFixtureEvents.Fixture.bandStartMinute
        let offset = CadenceCalendarFixtureEvents.Fixture.cascadeOffsetMinutes
        let taskStart = CadenceUITestScenarioSeed.Fixture.hueTaskStartMinute
        let taskEnd = taskStart + CadenceUITestScenarioSeed.Fixture.hueTaskEstimateMinutes
        let eventStart = try #require(deepRed.startMinute)

        #expect(taskStart == band, "the task opens the band")
        #expect(eventStart == band + offset)
        // Different starts (necessary for a cascade, not sufficient; see the note above).
        #expect(offset > 0, "a same-start fixture draws a split and has no cascade to photograph")
        // ...and genuinely overlapping, which is what puts both plates in one frame.
        #expect(eventStart < taskEnd, "the event starts after the task has ended; nothing overlaps")
        // Both plates stay fully visible: the offset is a fraction of the shorter block.
        #expect(offset < deepRed.durationMinutes / 2)
    }

    /// Held, not rebuilt: a fresh `EKEvent` per render is a fresh `calendarItemIdentifier`, a fresh
    /// `ForEach` identity, and a block whose selection resets underneath the pointer.
    @Test func theFixtureEventsAreTheSameObjectsOnASecondAsk() throws {
        let first = try #require(CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: Self.active))
        let second = try #require(CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: Self.active))
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a === b, "'\(a.title ?? "")' was rebuilt rather than held")
        }
    }

    // MARK: - 3b. The calendar-cascade scenario (T-3194)

    private static let cascadeActive: [String: String] = [mode: "1", scenario: "calendar-cascade"]

    /// Each calendar scenario serves its own specs and nothing of the other's: a cascade frame with
    /// the hue fixture's three events in it would no longer be the frame it was built to show.
    @Test func eachCalendarScenarioServesOnlyItsOwnEvents() throws {
        #expect(CadenceCalendarFixtureEvents.activeScenario(in: Self.cascadeActive) == .calendarCascade)
        #expect(CadenceCalendarFixtureEvents.activeScenario(in: Self.active) == .calendarHues)
        #expect(CadenceCalendarFixtureEvents.activeScenario(in: [Self.scenario: "calendar-cascade"]) == nil)

        let cascade = CadenceCalendarFixtureEvents.CascadeFixture.self
        let hues = CadenceCalendarFixtureEvents.Fixture.self
        let cascadeTimed = try #require(CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: Self.cascadeActive))
        let cascadeAllDay = try #require(CadenceCalendarFixtureEvents.allDayEvents(for: Date(), in: Self.cascadeActive))
        #expect(cascadeTimed.compactMap(\.title) == cascade.timed.map(\.title))
        #expect(cascadeAllDay.compactMap(\.title) == cascade.allDay.map(\.title))
        #expect(cascadeTimed.compactMap(\.title) == ["Lunch with Sam"])
        #expect(cascadeAllDay.compactMap(\.title) == ["Company offsite"])
        #expect(cascadeTimed.allSatisfy { $0.isAllDay == false && $0.calendar != nil })
        #expect(cascadeAllDay.allSatisfy { $0.isAllDay && $0.calendar != nil })

        let hueTimed = try #require(CadenceCalendarFixtureEvents.timedEvents(for: Date(), in: Self.active))
        #expect(hueTimed.compactMap(\.title) == hues.timed.map(\.title))
        #expect(Set(hueTimed.compactMap(\.title)).isDisjoint(with: cascadeTimed.compactMap(\.title)))

        // Titles key the held events, so they must be unique across both scenarios.
        let allTitles = (hues.timed + hues.allDay + cascade.timed + cascade.allDay).map(\.title)
        #expect(Set(allTitles).count == allTitles.count)

        // Another day is answered empty, not fallen through, exactly as for `calendar-hues`.
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        #expect(CadenceCalendarFixtureEvents.timedEvents(for: tomorrow, in: Self.cascadeActive)?.isEmpty == true)
    }

    /// **The thing the scenario exists to show, measured against the live layout:** at the iOS
    /// grid's resting hour, the seeded task CASCADES over `Lunch with Sam` on a phone-width column
    /// and SPLITS from it at regular width ([[T-3184]]). The recipe's 40-minute gap would split at
    /// both widths since [[T-3193]] raised the threshold to 47 minutes; this goes red if the gap or
    /// the threshold moves so that the fixture stops cascading.
    @Test func theCascadeTaskCascadesOverTheLunchOnAPhoneAndSplitsOnAnIPad() throws {
        let lunch = try #require(CadenceCalendarFixtureEvents.CascadeFixture.timed.first)
        let lunchStart = try #require(lunch.startMinute)
        let taskStart = CadenceUITestScenarioSeed.Fixture.cascadeTaskStartMinute
        let taskEnd = taskStart + CadenceUITestScenarioSeed.Fixture.cascadeTaskEstimateMinutes
        #expect(lunchStart < taskStart && taskStart < lunchStart + lunch.durationMinutes, "the task must start inside the lunch")
        #expect(taskEnd > lunchStart + lunch.durationMinutes, "the task runs past the lunch's end")

        let blocks: [iOSCalendarTimelineBlockLayout.Block<String>] = [
            .init(key: "lunch", kind: .event, startMin: lunchStart, endMin: lunchStart + lunch.durationMinutes),
            .init(key: "task", kind: .task, startMin: taskStart, endMin: taskEnd),
        ]
        func placements(compact: Bool) -> [String: CadenceCalendarOverlapPlacement] {
            iOSCalendarTimelineBlockLayout.placements(
                for: blocks,
                hourHeight: iOSCalendarTimelineMetrics.hourHeight,
                headerHeight: CadenceCalendarOverlapLayout.iOSEventHeaderHeight,
                isCompactWidth: compact
            )
        }
        let phone = placements(compact: true)
        #expect(phone["task"]?.cascadeDepth == 1, "phone: \(phone)")
        #expect(phone["lunch"]?.cascadeDepth == 0)
        #expect(phone["task"]?.totalColumns == 1, "a cascade shares one column")

        let pad = placements(compact: false)
        #expect(pad["task"]?.cascadeDepth == 0, "pad: \(pad)")
        #expect(pad["task"]?.totalColumns == 2, "regular width splits a task from an event")
    }

    /// The strip task is unscheduled by construction: `Fixture` names it, the seed leaves its start
    /// at the model default, and only an unscheduled task reaches the day-header strip.
    @Test func theCascadeSeedsAnUnscheduledStripTaskBesideTheAllDayEvent() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Services/CadenceUITestScenarioSeed.swift")
        )
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "seedCalendarCascade", in: source)
        #expect(body.contains("AppTask(title: Fixture.stripTaskTitle)"))
        #expect(body.contains("AppTask(title: Fixture.cascadeTaskTitle)"))
        #expect(CadenceSourceScan.matchCount(#"scheduledStartMin\s*="#, in: body) == 1, "only the cascade task is timed")
        #expect(CadenceSourceScan.matchCount(#"scheduledDate\s*=\s*todayKey"#, in: body) == 2)
        #expect(AppTask(title: "probe").scheduledStartMin < 0, "the model default is unscheduled")
    }

    // MARK: - 4. The scenario reader the gate is built on

    @Test func theScenarioReaderIsPureAndRefusesWhatItDoesNotKnow() {
        #expect(CadenceUITestScenarioSeed.scenario(in: [:]) == nil)
        #expect(CadenceUITestScenarioSeed.scenario(in: [Self.scenario: ""]) == nil)
        #expect(CadenceUITestScenarioSeed.scenario(in: [Self.scenario: "no-such-scenario"]) == nil)
        #expect(CadenceUITestScenarioSeed.scenario(in: [Self.scenario: "calendar-hues"]) == .calendarHues)
        #expect(CadenceUITestScenarioSeed.scenario(in: [Self.scenario: "calendar-cascade"]) == .calendarCascade)
        // The process reader is the pure one over this process, not a second implementation.
        #expect(CadenceUITestScenarioSeed.requestedScenario
            == CadenceUITestScenarioSeed.scenario(in: ProcessInfo.processInfo.environment))
    }

    // MARK: - 5. Where the seam is wired, and where it is not

    /// Both cache doors consult the fixture, and each does so **before** its authorisation guard —
    /// which is the only ordering that works, since the guard is what answers `[]` on a disarmed
    /// launch. Source-text, because the cache's branch cannot be reached from a host that is not
    /// itself inside the gate.
    @Test func bothDoorsOfTheDayCacheConsultTheFixtureAheadOfTheAuthorisationGuard() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarTimelineSupport.swift")
        )
        for door in ["timedEvents", "allDayEvents"] {
            let fixtureCall = "CadenceCalendarFixtureEvents.\(door)(for: date)"
            let fixtureIndex = try #require(code.range(of: fixtureCall)?.lowerBound, "no \(door) fixture consult")
            let signature = "func \(door)(for date: Date, calendarManager: any CalendarEventDaySource)"
            let signatureIndex = try #require(code.range(of: signature)?.lowerBound, "no \(door) signature")
            let guardIndex = try #require(
                code.range(of: "guard calendarManager.isAuthorized", range: signatureIndex..<code.endIndex)?.lowerBound
            )
            #expect(signatureIndex < fixtureIndex, "\(door)'s fixture consult is outside its body")
            #expect(fixtureIndex < guardIndex, "\(door) asks EventKit before it asks the fixture")
        }
    }

    @Test func theMobileFixtureAnswerPrecedesAndCannotFallThroughTheDisarmedStoreGuard() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarManager.swift")
        )
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "fetchEvents", in: source)
        let timed = try #require(body.range(of: "CadenceCalendarFixtureEvents.timedEvents(for: date)"))
        let allDay = try #require(body.range(of: "CadenceCalendarFixtureEvents.allDayEvents(for: date)"))
        let answer = try #require(body.range(of: "return (timed + allDay).sorted(by: CadenceCalendarEventSearchSupport.precedes)"))
        let gate = try #require(body.range(of: "guard !isEventKitDisarmed, isAuthorized"))
        let storeRead = try #require(body.range(of: "store.predicateForEvents("))
        #expect(timed.upperBound < allDay.lowerBound)
        #expect(allDay.upperBound < answer.lowerBound)
        #expect(answer.upperBound < gate.lowerBound)
        #expect(gate.upperBound < storeRead.lowerBound)
    }

    /// T-1483 was an absent call, despite a portable implementation. Count each door on each
    /// platform: equality alone would also pass if both platforms lost the harness entirely.
    @Test func bothPlatformsCallBothCalendarFixtureDoorsExactlyOnce() throws {
        for door in ["timedEvents", "allDayEvents"] {
            let pattern = #"\bCadenceCalendarFixtureEvents\."# + door + #"\s*\("#
            let sample = "if let events = CadenceCalendarFixtureEvents.\(door)(for: date) { return events }"
            #expect(CadenceSourceScan.matchCount(pattern, in: sample) == 1)
            #expect(CadenceSourceScan.matchCount(pattern, in: "OtherFixture.\(door)(for: date)") == 0)
            var counts: [Int] = []
            for path in [
                "Cadence/macOS/Views/CalendarTimelineSupport.swift",
                "Cadence/iOS/iOSCalendarManager.swift"
            ] {
                let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
                let count = CadenceSourceScan.matchCount(pattern, in: code)
                #expect(count == 1, "\(path) must call the shared \(door) fixture once")
                counts.append(count)
            }
            #expect(counts == [1, 1])
        }
    }

    /// Both platform fetch paths are intentional. Keep the census closed so another fixture
    /// consumer cannot appear without its launch gate and ordering being checked here.
    @Test func nothingElseInTheAppReachesTheFixture() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(files.count > 200, "non-vacuity: walked \(files.count) files")
        var referencing: [String] = []
        for path in files {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            if code.contains("CadenceCalendarFixtureEvents") { referencing.append(path) }
        }
        #expect(
            Set(referencing) == [
                "Cadence/Services/CadenceCalendarFixtureEvents.swift",
                "Cadence/Services/CadenceUITestScenarioSeed.swift",
                "Cadence/macOS/Views/CalendarTimelineSupport.swift",
                "Cadence/iOS/iOSCalendarManager.swift",
                "Cadence/iOS/iOSCalendarView.swift",
            ],
            "unexpected reach of the calendar fixture harness: \(referencing.sorted())"
        )
    }

    // MARK: - T-4220: a fixture minute-of-day is wall-clock time on a transition day

    private static func newYork() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private static func wallMinute(_ date: Date, in calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// **[[T-4220]].** The four-day fixture used to ADD its minutes to midnight, so on the 25-hour
    /// 2026-11-01 its 07:30 start drew at 06:30, and on the 23-hour 2026-03-08 at 08:30. Both ends
    /// are pinned on both transition days: the start by anchoring on the transition day, the end by
    /// anchoring three days before it. An ordinary day is the control — both spellings agree there,
    /// which is why the bug never showed outside two days a year.
    @Test func theMultiDayFixtureLandsOnItsWallClockTimesOnBothTransitionDays() throws {
        let calendar = try Self.newYork()
        let spec = CadenceCalendarFixtureEvents.Fixture.multiDay
        #expect(spec.startMinute == 7 * 60 + 30 && spec.endMinute == 16 * 60 + 15 && spec.endDayOffset == 3)

        for (year, month, dayOfMonth) in [(2026, 11, 1), (2026, 3, 8), (2026, 10, 14)] {
            let transition = try Self.day(year, month, dayOfMonth, in: calendar)

            let fromTransition = spec.interval(anchoredOn: transition, calendar: calendar)
            #expect(Self.wallMinute(fromTransition.start, in: calendar) == spec.startMinute,
                    "start on \(year)-\(month)-\(dayOfMonth) is not 07:30 on the wall")
            #expect(calendar.isDate(fromTransition.start, inSameDayAs: transition))

            let anchor = try #require(calendar.date(byAdding: .day, value: -spec.endDayOffset, to: transition))
            let endingOnTransition = spec.interval(anchoredOn: anchor, calendar: calendar)
            #expect(Self.wallMinute(endingOnTransition.end, in: calendar) == spec.endMinute,
                    "end on \(year)-\(month)-\(dayOfMonth) is not 16:15 on the wall")
            #expect(calendar.isDate(endingOnTransition.end, inSameDayAs: transition))
        }

        // Non-vacuity: the two days really are 25 and 23 hours long in this calendar, so the old
        // spelling would have been an hour out on each.
        for (year, month, dayOfMonth, hours) in [(2026, 11, 1, 25.0), (2026, 3, 8, 23.0)] {
            let start = try Self.day(year, month, dayOfMonth, in: calendar)
            let next = try #require(calendar.date(byAdding: .day, value: 1, to: start))
            #expect(next.timeIntervalSince(start) == hours * 3600)
        }
    }

    /// The single-day fixture builder and the board's injected event hold their `EKEvent` once per
    /// launch, so they cannot be re-driven on a chosen day from here; their two starts are pinned
    /// by shape instead. Each must SET its minute through the shared helper and add none to a
    /// midnight, and each end stays a duration of real time after the start.
    @Test func everyFixtureStartIsSetOnTheWallClockAndEveryEndStaysADuration() throws {
        let addedMinute = #"byAdding:\s*\.minute"#
        let setStart = #"CadenceCalendarEventTiming\.startDate\("#
        let durationEnd = #"\.endDate = start\.addingTimeInterval\("#
        for (path, starts, durationEnds) in [
            ("Cadence/Services/CadenceCalendarFixtureEvents.swift", 3, 1),
            ("Cadence/macOS/Views/CalendarPageBoardSupportViews.swift", 1, 1),
        ] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(CadenceSourceScan.matchLines(addedMinute, in: code).isEmpty,
                    "\(path) adds a minute-of-day to a midnight again")
            #expect(CadenceSourceScan.matchCount(setStart, in: code) == starts, "\(path)")
            #expect(CadenceSourceScan.matchCount(durationEnd, in: code) == durationEnds, "\(path)")
        }
        // Non-vacuity: the scan sees the spelling it hunts, including the multi-line form the board
        // used, and misses the day step it must leave alone.
        #expect(CadenceSourceScan.matchCount(addedMinute, in: "calendar.date(\n    byAdding: .minute,\n") == 1)
        #expect(CadenceSourceScan.matchCount(addedMinute, in: "calendar.date(byAdding: .day, value: 1") == 0)
    }
}
