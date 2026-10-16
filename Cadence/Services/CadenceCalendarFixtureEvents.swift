import CoreGraphics
import EventKit
import Foundation

/// **[[T-3186]] — the committed way to put calendar events on screen without EventKit.**
///
/// Agents may not request EventKit permission and may not open the owner's real calendar, which is
/// the right rule and has one consequence nobody wrote down: **the calendar surfaces cannot be
/// looked at at all.** `CalendarEventDayCache` asks `CalendarManager.isAuthorized` first, an
/// agent or UI-test launch is disarmed by `CadenceEventKitLaunchGate`, and so every day answers
/// `[]`. Three agents in two days hand-built the same five patches in a scratch tree to get round
/// it (`calvisual`, `calsee`, `monthallday`); a restart cleared `/var/folders` and took all three.
/// Visual verification is the one thing tests cannot do for the calendar — [[T-3160]] shipped a
/// whole treatment swap unseen, and [[T-3163]]/[[T-3164]]/[[T-3165]] were found only by looking —
/// so the harness is committed rather than re-derived.
///
/// **Why this file and not `CadenceUITestScenarioSeed`.** That file is the seam for the *task*
/// half and stays it: it takes a `ModelContext` and writes SwiftData rows once, at launch. This
/// half writes nothing and owns no store. It answers a *read*, at fetch time, with objects that
/// are never saved — a different mechanism with a different lifetime, and folding it in would have
/// put `import EventKit` into the file whose whole job is the SwiftData store. It lives beside it
/// in `Cadence/Services/` rather than under `Cadence/macOS/`, with the rest of the launch-gate
/// vocabulary (`CadenceUITestSupport`, `CadenceEventKitLaunchGate`), because nothing in it is
/// desktop-only and the iOS calendar board will want it next — this repository has moved four
/// files out of an accidental `#if os(macOS)` already, each time after the accident had cost iOS a
/// feature. The *scenario name* still lives in `CadenceUITestScenarioSeed.Scenario`, because that
/// enum is the one place a launch's vocabulary is spelled and the task half and the event half of
/// one scenario must not be selectable separately.
///
/// **The safety constraint is the whole design.** The gate is `CADENCE_UI_TEST_MODE=1` **and** a
/// recognised `CADENCE_UI_TEST_SCENARIO` — the identical two-part shape
/// `CalendarBoardUITestEventSupport` has carried since [[T-1843]], and no new variable is
/// introduced. Either half alone answers `nil`, and `nil` means "ask EventKit", so a shipping
/// launch reaches exactly the code it reached before this file existed. The first half is also one
/// of `CadenceEventKitLaunchGate`'s three disarm signals, which makes the safety property
/// structural rather than a promise: **a launch that can see these fixtures is a launch that
/// cannot reach a real `EKEventStore`**, and `CadenceCalendarFixtureEventsTests` pins that
/// implication in both directions.
///
/// **Nothing here is saved and nothing is fetched.** `EKEvent(eventStore:)` and
/// `EKCalendar(for:eventStore:)` on objects that are never written need no TCC prompt and touch no
/// store — a reading, not an assumption: `CalendarBoardUITestEventSupport` has been doing it on
/// this surface since T-1843 and `CadenceTests` since T-693.
enum CadenceCalendarFixtureEvents {

    /// One fixture calendar's colour, as components rather than as a hex literal.
    ///
    /// `hex` is **derived** from the components, so a test can state the hue the ticket named
    /// (`#3D0000`) against the colour the screen is actually given, and the two cannot drift. It is
    /// also why no hex is hand-typed here: these are stand-ins for an external calendar's colour,
    /// which arrives out of EventKit and is not an app-defined colour at all, but spelling one as a
    /// literal would still read as the thing `AGENTS.md` forbids.
    /// Deliberately **not** `Equatable`: this enum's members are main-actor isolated, so a
    /// synthesised conformance is a main-actor-isolated one and using it from a `nonisolated`
    /// context is an error under the Swift 6 language mode. Identity between two hues is asked for
    /// by `hex`, which is the spelling a reader and a failure message both want anyway.
    struct Hue {
        let red: Int
        let green: Int
        let blue: Int

        var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

        var cgColor: CGColor {
            CGColor(
                srgbRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        }
    }

    /// One fixture event: a hue, a title, and a window in minutes of the day.
    struct Spec {
        let title: String
        let calendarTitle: String
        let hue: Hue
        /// Minutes from midnight. `nil` on the all-day entry, which has no time of day.
        let startMinute: Int?
        let durationMinutes: Int
    }

    /// **The `calendar-hues` fixture: the two pathological hues [[T-3168]] is about, a pale
    /// control, and an all-day entry so the second cache door is exercised too.**
    ///
    /// `#3D0000` and `#0000FF` are the two hues named in T-3168 — a deep red and a primary blue,
    /// the pair whose event plates measured *louder* than a task plate before the chroma ceiling.
    /// The pale calendar is the control: it was already quiet, so a change that quietened
    /// everything equally would show up here as the pale block going dark.
    ///
    /// **The times are fixed, not derived from the clock.** A fixture whose band moves with the
    /// hour is a screenshot that cannot be retaken, and the scenario must mean the same thing on
    /// any day it runs — the rule `CadenceUITestScenarioSeed` already states for its dates.
    ///
    /// **The deep red overlaps the seeded task, and starts `cascadeOffsetMinutes` LATER than it.**
    /// The overlap is what puts an event plate and a task plate side by side in one frame, which
    /// is the only way [[T-3168]]'s claim — that an event now reads quieter *than a task* — can be
    /// checked at all. The offset is the half agent `compactcascade` found missing: two blocks
    /// that start on the same minute are laid out as a plain split, so there was **no cascade to
    /// photograph** and the harness could not answer a layout question. Fifteen minutes is enough
    /// for `CadenceCalendarOverlapLayout` to cascade them while both plates stay fully visible.
    enum Fixture {
        static let deepRed = Hue(red: 0x3D, green: 0x00, blue: 0x00)
        static let pureBlue = Hue(red: 0x00, green: 0x00, blue: 0xFF)
        /// A pale cream, well above the band the ceiling binds on, so it is untouched by it.
        static let pale = Hue(red: 0xED, green: 0xE7, blue: 0xD3)

        /// 9:00. The seeded task starts here; the deep red event starts
        /// `cascadeOffsetMinutes` after it. See the note above.
        static let bandStartMinute = 9 * 60

        /// How far the deep red event starts after the task it overlaps. Named rather than folded
        /// into the spec below because the seed reads it too: "the task starts first, by this
        /// much" is one fact and must not be spelled in two places.
        static let cascadeOffsetMinutes = 15

        static let timed: [Spec] = [
            Spec(
                title: "Deep red event",
                calendarTitle: "Deep Red Calendar",
                hue: deepRed,
                startMinute: bandStartMinute + cascadeOffsetMinutes,
                durationMinutes: 60
            ),
            Spec(
                title: "Pure blue event",
                calendarTitle: "Pure Blue Calendar",
                hue: pureBlue,
                startMinute: bandStartMinute + 75,
                durationMinutes: 60
            ),
            Spec(
                title: "Pale event",
                calendarTitle: "Pale Calendar",
                hue: pale,
                startMinute: bandStartMinute + 150,
                durationMinutes: 60
            ),
        ]

        static let allDay: [Spec] = [
            Spec(
                title: "Deep red all-day",
                calendarTitle: "Deep Red Calendar",
                hue: deepRed,
                startMinute: nil,
                durationMinutes: 24 * 60
            )
        ]
    }

    /// `true` only for a launch that asked for the fixture scenario by name **and** carries the
    /// test-mode flag. Pure over its input, so it is driven with literal dictionaries rather than
    /// by launching — the shape `CadenceEventKitLaunchGate.isDisarmed(in:)` already has.
    static func isActive(in environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard environment[CadenceEventKitLaunchGate.uiTestModeVariable] == "1" else { return false }
        return CadenceUITestScenarioSeed.scenario(in: environment) == .calendarHues
    }

    /// The day's timed fixtures, or `nil` for "ask EventKit" — which is every shipping launch.
    ///
    /// When it *is* asking it owns the whole answer, including the empty one for every day that is
    /// not today. Falling through to EventKit for the other columns would give the timeline under
    /// inspection two sources, and a block appearing in the wrong column would read as a layout
    /// defect rather than as a second source. Same reasoning as
    /// `CalendarBoardUITestEventSupport.injectedItems`.
    static func timedEvents(
        for date: Date,
        calendar: Calendar = .current,
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [EKEvent]? {
        events(for: date, specs: Fixture.timed, calendar: calendar, in: environment)
    }

    /// The day's all-day fixtures, or `nil` for "ask EventKit". Same contract as above.
    static func allDayEvents(
        for date: Date,
        calendar: Calendar = .current,
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [EKEvent]? {
        events(for: date, specs: Fixture.allDay, calendar: calendar, in: environment)
    }

    private static func events(
        for date: Date,
        specs: [Spec],
        calendar: Calendar,
        in environment: [String: String]
    ) -> [EKEvent]? {
        guard isActive(in: environment) else { return nil }
        guard DateFormatters.dateKey(from: date) == DateFormatters.todayKey() else { return [] }
        return specs.map { built(spec: $0, on: date, calendar: calendar) }
    }

    /// **Held once per spec title, and that is not an optimisation.** Every surface here
    /// re-renders on each store change, and a fresh `EKEvent` per render carries a fresh
    /// `calendarItemIdentifier` — a new `ForEach` identity, and therefore a block whose selection
    /// and popover `@State` reset underneath the pointer. The board seam learned this the same way.
    private static var heldEvents: [String: EKEvent] = [:]

    private static func built(spec: Spec, on date: Date, calendar: Calendar) -> EKEvent {
        if let held = heldEvents[spec.title] { return held }
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        // The unsaved `EKCalendar` is **measured, not decoration** ([[T-2047]]):
        // `CalendarEventEditPopover.init` reads `ekEvent.calendar` through an implicitly-unwrapped
        // optional, so a fixture event without one kills the app the moment its block is clicked.
        // It also carries the colour, which is the entire point of this fixture.
        let eventCalendar = EKCalendar(for: .event, eventStore: store)
        eventCalendar.title = spec.calendarTitle
        eventCalendar.cgColor = spec.hue.cgColor
        event.calendar = eventCalendar
        event.title = spec.title
        let dayStart = calendar.startOfDay(for: date)
        if let startMinute = spec.startMinute {
            let start = calendar.date(byAdding: .minute, value: startMinute, to: dayStart) ?? dayStart
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(spec.durationMinutes * 60))
            event.isAllDay = false
        } else {
            event.startDate = dayStart
            event.endDate = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            event.isAllDay = true
        }
        heldEvents[spec.title] = event
        return event
    }
}
