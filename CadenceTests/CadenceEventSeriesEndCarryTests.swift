import EventKit
import Foundation
import Testing
@testable import Cadence

/// The capture card's `Ends` control, in **Event** mode, reaching EventKit ([[T-3229]]).
///
/// **The bug this suite exists over was silence, not a crash.** `CadenceScheduleCaptureCard` draws
/// `Frequency` and `Ends` with no `kind` guard, so a user could switch the card to Event, choose
/// *"ends after 10 occurrences"*, watch the card accept it — and get an endless series, because
/// the iOS manager's recurrence builder (`eventRecurrenceRule`, since moved to `Shared/` as
/// `CadenceEventCreationSupport.recurrenceRule`) built
/// every rule with `end: nil` and `createEvent` took a bare `repeatRule` with nowhere to put a
/// bound. Nothing anywhere said the limit was dropped.
/// On the Task side the same three draft fields persist correctly, which is exactly what made the
/// Event side a silent loss rather than a visible gap.
///
/// **Why half of this is a source scan and half is not.** The iOS write-path halves live under
/// `#if os(iOS)` and cannot be called from a macOS run, so their forwarding is pinned by reading
/// the function bodies. The recurrence mapping itself is **run**: [[T-3171]] (iii) moved it out of
/// `iOSCalendarManager` into `Shared/CadenceEventCreationSupport` so the macOS drag-create write
/// could use the same one, and an `EKRecurrenceRule` is a value that needs no `EKEventStore`. So
/// is `CadenceScheduleDraft.effectiveSeriesEndMode`, which decides whether there is a bound to
/// carry at all.
@Suite("Event series end")
struct CadenceEventSeriesEndCarryTests {

    // MARK: - The resolved value, tested for real

    @MainActor
    private func eventDraft(rule: TaskRecurrenceRule) -> CadenceScheduleDraft {
        var draft = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 14 * 60, kind: .event)
        draft.repeatRule = rule
        return draft
    }

    /// **The value an event write now forwards is the resolved mode, not the stored one.** An
    /// `.onDate` with no day and an `.afterCount` with no count are both "never" — `AppTask`'s own
    /// `effectiveRecurrenceEndMode` degrades them that way and the draft mirrors it. Forwarding the
    /// raw mode instead would hand `EKRecurrenceEnd` a bound the card never captured, which is the
    /// mirror image of the bug: inventing a limit rather than dropping one.
    ///
    /// Asserted on an **event** draft specifically. The degrade is written without reference to
    /// `kind`, and that is the claim — if it ever grew a `kind == .task` arm, the event write would
    /// start carrying unresolved values and this would go red.
    @Test("An event draft resolves its end mode exactly as a task draft does")
    @MainActor
    func theEventDraftResolvesItsOwnEndMode() {
        var draft = eventDraft(rule: .weekly)

        draft.seriesEndMode = .never
        #expect(draft.effectiveSeriesEndMode == .never)

        draft.seriesEndMode = .onDate
        draft.seriesEndDateKey = ""
        #expect(draft.effectiveSeriesEndMode == .never, "an .onDate with no day is not a bound")
        draft.seriesEndDateKey = "2026-12-24"
        #expect(draft.effectiveSeriesEndMode == .onDate)

        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 0
        #expect(draft.effectiveSeriesEndMode == .never, "an .afterCount of zero is not a bound")
        draft.seriesEndCount = 10
        #expect(draft.effectiveSeriesEndMode == .afterCount)

        // The kind comparison: a task draft set up identically answers identically.
        var task = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 14 * 60, kind: .task)
        task.repeatRule = .weekly
        task.seriesEndMode = .afterCount
        task.seriesEndCount = 10
        #expect(task.effectiveSeriesEndMode == draft.effectiveSeriesEndMode)
    }

    /// **A bound on a series that does not repeat is not a bound.** The card only draws `Ends`
    /// when `repeatRule != .none`, but the draft can still be holding a stale end from before the
    /// frequency was cleared, and `createEvent` forwards the fields unconditionally. The `.none`
    /// guard at the top of `effectiveSeriesEndMode` is what stops that stale value reaching
    /// EventKit — and `CadenceEventCreationSupport.recurrenceRule` returns `nil` for `.none` regardless.
    @Test("Clearing the frequency clears the bound the event write would carry")
    @MainActor
    func aNonRepeatingEventDraftCarriesNoBound() {
        var draft = eventDraft(rule: .daily)
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 5
        #expect(draft.effectiveSeriesEndMode == .afterCount)

        draft.repeatRule = .none
        #expect(
            draft.effectiveSeriesEndMode == .never,
            "a cleared frequency still reports a bound, which createEvent would forward"
        )
    }

    // MARK: - The forwarding, read off the two iOS function bodies

    /// `declarationBody` returns what is **between the braces**, so a parameter default has to be
    /// read off the file rather than off the body. Both are returned, and a signature string is
    /// only ever asserted against the first.
    private func strippedManager() throws -> String {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarManager.swift")
        #expect(raw.count > 400, "iOSCalendarManager.swift read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")
        return stripped
    }

    /// The shared recurrence builder, as source: the bound parameters are **defaulted**, which is
    /// the precedent `createEvent`'s own comment set — *"Defaulted, so the two existing callers are
    /// byte-for-byte unchanged."* Without the defaults this is a source-compatible-looking change
    /// that silently rewrites every other call site's meaning. What the rule it builds *is* is run
    /// below, in `theSharedBuilderBuildsEachBound`.
    @Test("The shared recurrence builder takes a defaulted bound and builds both kinds of it")
    func theRecurrenceRuleBuilderCanBoundASeries() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.sharedSupportPath)
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        let body = try #require(
            CadenceSourceScan.declarationBody("static func recurrenceRule(", in: stripped),
            "could not find CadenceEventCreationSupport.recurrenceRule"
        )
        #expect(
            CadenceSourceScan.matchCount(#"static func eventRecurrenceRule\("#, in: try strippedManager()) == 0,
            "iOSCalendarManager spells its own copy of the recurrence mapping again"
        )

        #expect(
            CadenceSourceScan.matchCount(#"endMode: TaskRecurrenceEndMode = \.never"#, in: stripped) == 1,
            "eventRecurrenceRule's end mode is missing, not defaulted, or spelled twice"
        )
        #expect(
            CadenceSourceScan.matchCount(#"endDateKey: String = """#, in: stripped) == 1,
            "eventRecurrenceRule's end date key is missing or not defaulted"
        )
        #expect(
            CadenceSourceScan.matchCount(#"endCount: Int = 0"#, in: stripped) == 1,
            "eventRecurrenceRule's end count is missing or not defaulted"
        )

        #expect(body.contains("EKRecurrenceEnd(end:"), "an .onDate bound is never built")
        #expect(body.contains("EKRecurrenceEnd(occurrenceCount:"), "an .afterCount bound is never built")

        // The bug, exactly: a rule handed a hard-coded `end: nil` no matter what was asked for.
        #expect(
            CadenceSourceScan.matchCount(#"EKRecurrenceRule\(recurrenceWith: frequency, interval: 1, end: nil\)"#, in: body) == 0,
            "eventRecurrenceRule still hard-codes an endless series"
        )
        #expect(
            CadenceSourceScan.matchCount(#"EKRecurrenceRule\(recurrenceWith:"#, in: body) == 1,
            "non-vacuity: the rule is no longer built here"
        )

        // An .onDate key is a `yyyy-MM-dd` day and EKRecurrenceEnd takes an instant, so the day has
        // to be widened or the occurrence the user named is dropped. `startOfDay` alone is that bug.
        #expect(body.contains("DateFormatters.date(from: endDateKey)"), "the stored day key is never parsed")
        #expect(
            body.contains("DateComponents(day: 1, second: -1)"),
            "the .onDate bound no longer reaches the last instant of the named day"
        )
    }

    private static let sharedSupportPath = "Cadence/Shared/CadenceEventCreationSupport.swift"

    // MARK: - The shared builder, run

    /// Each frequency maps to its own EventKit frequency at interval 1, `.none` to no rule, and the
    /// default bound is none at all.
    @Test("The shared builder maps every frequency and defaults to an endless series")
    func theSharedBuilderMapsEveryFrequency() throws {
        #expect(CadenceEventCreationSupport.recurrenceRule(for: .none) == nil)
        let pairs: [(TaskRecurrenceRule, EKRecurrenceFrequency)] = [
            (.daily, .daily), (.weekly, .weekly), (.monthly, .monthly), (.yearly, .yearly),
        ]
        for (rule, frequency) in pairs {
            let built = try #require(CadenceEventCreationSupport.recurrenceRule(for: rule), "\(rule) built no rule")
            #expect(built.frequency == frequency, "\(rule) maps to the wrong frequency")
            #expect(built.interval == 1)
            #expect(built.recurrenceEnd == nil, "an unbounded \(rule) was given a bound")
        }
    }

    /// Both bounds reach the rule: a count as a count, and a day as its **last instant**.
    @Test("The shared builder carries an occurrence count and an end day")
    func theSharedBuilderBuildsEachBound() throws {
        let counted = try #require(
            CadenceEventCreationSupport.recurrenceRule(for: .weekly, endMode: .afterCount, endCount: 7)
        )
        #expect(counted.recurrenceEnd?.occurrenceCount == 7)

        let dated = try #require(
            CadenceEventCreationSupport.recurrenceRule(for: .daily, endMode: .onDate, endDateKey: "2026-12-24")
        )
        let end = try #require(dated.recurrenceEnd?.endDate, "an .onDate bound was dropped")
        // Read back through the same parse the builder uses, so the relation holds in whatever zone
        // the host runs: the bound is on the named day, and after that day's midnight.
        let midnight = try #require(DateFormatters.date(from: "2026-12-24"))
        #expect(DateFormatters.dateKey(from: end) == "2026-12-24", "the bound is not on the named day")
        #expect(end > midnight, "the bound is the named day's midnight, which drops its occurrence")
        #expect(end.timeIntervalSince(midnight) > 23 * 3600, "the bound is not the day's last instant")

        // A value it cannot spell falls back to no bound, never a wrong one.
        let unspellable = try #require(
            CadenceEventCreationSupport.recurrenceRule(for: .daily, endMode: .afterCount, endCount: 0)
        )
        #expect(unspellable.recurrenceEnd == nil)
    }

    /// The save span and the stored location, the other two pieces both platforms' writes share.
    @Test("A new series saves whole and a blank location is no location")
    func theSpanAndLocationRules() {
        #expect(CadenceEventCreationSupport.creationSpan(for: .none) == .thisEvent)
        for rule in TaskRecurrenceRule.allCases where rule != .none {
            #expect(CadenceEventCreationSupport.creationSpan(for: rule) == .futureEvents, "\(rule) saves a detached first occurrence")
        }
        #expect(CadenceEventCreationSupport.storedLocation("  Room 4 \n") == "Room 4")
        #expect(CadenceEventCreationSupport.storedLocation(" \n ") == nil)
        #expect(CadenceEventCreationSupport.storedLocation("") == nil)
    }

    /// `createEvent` forwards all three, and still saves **once**. A second EventKit save after the
    /// create is out of scope by the owner's standing decision on [[T-3195]], and is the swallowed-
    /// save shape this repo has fixed repeatedly — the recurrence rides the original commit.
    @Test("createEvent forwards the bound into the one save it already makes")
    func theEventWriteForwardsTheBoundOnce() throws {
        let stripped = try strippedManager()
        let body = try #require(
            CadenceSourceScan.declarationBody("func createEvent(", in: stripped),
            "could not find iOSCalendarManager.createEvent"
        )

        #expect(
            CadenceSourceScan.matchCount(#"seriesEndMode: TaskRecurrenceEndMode = \.never"#, in: stripped) == 1,
            "createEvent's end mode is missing, not defaulted, or spelled twice"
        )
        #expect(
            CadenceSourceScan.matchCount(#"seriesEndDateKey: String = """#, in: stripped) == 1,
            "createEvent's end date key is missing or not defaulted"
        )
        #expect(
            CadenceSourceScan.matchCount(#"seriesEndCount: Int = 0"#, in: stripped) == 1,
            "createEvent's end count is missing or not defaulted"
        )

        #expect(body.contains("endMode: seriesEndMode"), "the end mode is accepted and dropped")
        #expect(body.contains("endDateKey: seriesEndDateKey"), "the end date key is accepted and dropped")
        #expect(body.contains("endCount: seriesEndCount"), "the end count is accepted and dropped")

        #expect(
            CadenceSourceScan.matchCount(#"store\.save\("#, in: body) == 1,
            "createEvent saves to EventKit more than once"
        )
        #expect(
            CadenceSourceScan.matchCount(#"addRecurrenceRule\("#, in: body) == 1,
            "non-vacuity: the recurrence is no longer attached here"
        )
    }

    /// The draft half: `iOSScheduleDraftCreation.createEvent` hands over the **resolved** mode and
    /// the two values it is paired with. This is the forwarding the capture card's Event mode
    /// depends on — without it the card's `Ends` is still accepted and still dropped, one frame up
    /// from where it used to be.
    @Test("The shared iOS event create forwards the draft's resolved bound")
    func theDraftCreateForwardsTheResolvedBound() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTimelineDraftCreate.swift")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")

        let body = try #require(
            CadenceSourceScan.functionBody(named: "createEvent", in: stripped),
            "could not find iOSScheduleDraftCreation.createEvent"
        )
        #expect(body.contains("calendarManager.createEvent("), "non-vacuity: this is not the event write")
        #expect(body.contains("repeatRule: draft.repeatRule"), "non-vacuity: the frequency is no longer forwarded")

        #expect(
            body.contains("seriesEndMode: draft.effectiveSeriesEndMode"),
            "the draft's bound is not forwarded, or forwards the stored mode instead of the resolved one"
        )
        #expect(body.contains("seriesEndDateKey: draft.seriesEndDateKey"))
        #expect(body.contains("seriesEndCount: draft.seriesEndCount"))
    }

    /// **The repeat vocabulary did not grow.** No schema change and no new interval beyond the five
    /// persisted cases is [[T-3195]]'s standing decision, and carrying an end condition is exactly
    /// the kind of work that tempts a sixth case. Five, and `.none` is one of them.
    @Test("Carrying the bound added no new repeat interval")
    func theRepeatVocabularyIsStillFiveCases() {
        #expect(TaskRecurrenceRule.allCases.count == 5)
        #expect(TaskRecurrenceEndMode.allCases.count == 3)
    }
}
