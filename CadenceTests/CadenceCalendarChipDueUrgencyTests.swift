import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-8243]]: an OPEN task chip's circle carries its due urgency on iOS too.**
///
/// macOS's `MonthTaskChip` and `AllDayTaskChip` have tinted an open chip glyph by
/// `CadenceDueUrgency` for as long as the classifier has existed — red for overdue, amber for due
/// today — so a Mac chip says "this is late" at a glance. `iOSCalendarMiniChip` drew every open
/// glyph in one flat `plateTertiaryLabelColor()`, so the channel did not exist on iPhone or iPad
/// at all. Nothing about a finger explains a missing colour, which is [[T-8201]]'s test, so the
/// fix is one decision in `Shared/` that both platforms read rather than a second copy of the
/// ladder on the iOS side — the shape [[T-8243]] asked for in as many words.
///
/// The first tests pin the decision by VALUE; the rest pin that each surface still asks it. Both
/// kinds, because a source scan that said "the chip is tinted" and nothing about *what with*
/// would pass over a chip that painted everything amber.
@MainActor
struct CadenceCalendarChipDueUrgencyTests {
    private static let doneStyleFile = "Cadence/Shared/CadenceCalendarTaskDoneStyle.swift"
    private static let iOSMonthFile = "Cadence/iOS/iOSCalendarMonthViews.swift"
    private static let iOSTimelineFile = "Cadence/iOS/iOSCalendarTimelineViews.swift"
    private static let macOSChipsFile = "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"

    private static let todayKey = "2026-11-03"
    private static let yesterdayKey = "2026-11-02"
    private static let tomorrowKey = "2026-11-04"
    /// A fallback no `Theme` token equals, so "it returned the fallback" cannot be satisfied by a
    /// branch that happened to land on the same colour for another reason.
    private static let neutral = Color(hex: "#5B21B6")

    private func tint(_ state: CadenceTaskCompletionState, due: String) -> Color {
        CadenceCalendarTaskDoneStyle.chipGlyphTint(
            for: state,
            dueDateKey: due,
            todayKey: Self.todayKey,
            open: Self.neutral
        )
    }

    /// **The urgency leg itself.**
    ///
    /// *Failing-first:* deleting the `CadenceDueUrgency.evaluate(...)` line from the shared helper
    /// and returning `open` makes the overdue and due-today expectations fail — which is exactly
    /// the state iOS shipped in.
    @Test func anOpenChipGlyphIsTintedByItsDeadlineAndOnlyByADeadline() {
        #expect(tint(.todo, due: Self.yesterdayKey) == Theme.red, "an overdue open task is not red")
        #expect(tint(.todo, due: Self.todayKey) == Theme.amber, "a task due today is not amber")
        #expect(tint(.todo, due: Self.tomorrowKey) == Theme.dim, "a task due later is not the neutral urgency tint")
        // No deadline at all falls back to the CALLER's tier, which is the whole reason `open` is
        // a parameter: the Mac's plate and the iOS mini chip are solved against different fills.
        #expect(tint(.todo, due: "") == Self.neutral, "a task with no due date took an urgency tint")
        #expect(tint(.todo, due: "") != Theme.red)
        #expect(tint(.todo, due: "") != Theme.amber)
    }

    /// The mid-animation states are still OPEN, so they take the urgency tint rather than falling
    /// through to a settled one. *Failing-first:* treating `.pendingCompletion` as settled makes
    /// this fail while the test above still passes.
    @Test func aChipMidCompletionAnimationIsStillTintedByItsDeadline() {
        for state in [CadenceTaskCompletionState.pendingCompletion, .pendingCancellation] {
            #expect(tint(state, due: Self.yesterdayKey) == Theme.red, "\(state) lost its overdue tint")
            #expect(tint(state, due: Self.todayKey) == Theme.amber, "\(state) lost its due-today tint")
        }
    }

    /// **A settled task never flashes red about a deadline it has already answered**, which is the
    /// one ordering mistake this helper can make. *Failing-first:* asking urgency before the
    /// settled tint — swapping the two statements in the helper — turns a done-but-overdue chip
    /// red and fails here.
    @Test func aSettledChipKeepsItsSettledTintEvenWhenTheDeadlineHasPassed() {
        #expect(tint(.done, due: Self.yesterdayKey) == Theme.green, "a done overdue chip is not green")
        #expect(tint(.done, due: Self.todayKey) == Theme.green)
        #expect(tint(.done, due: Self.yesterdayKey) != Theme.red)
        let cancelledTint = CadenceCalendarEventStyle.plateTertiaryLabelColor()
        #expect(tint(.cancelled, due: Self.yesterdayKey) == cancelledTint, "a cancelled overdue chip went red")
        #expect(tint(.cancelled, due: Self.yesterdayKey) != Theme.red)
    }

    /// The decision is in `Shared/` and outside any platform gate — the thing [[T-8243]] named as
    /// the shape of the fix. *Failing-first:* wrapping the helper in `#if os(macOS)` fails here.
    @Test func theOpenTintRuleLivesInSharedBesideTheDoneStyle() throws {
        let shared = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.doneStyleFile))
        #expect(!shared.contains("#if os("), "the shared chip style went behind a platform gate")
        #expect(
            CadenceSourceScan.matchCount(#"static func chipGlyphTint\("#, in: shared) == 2,
            "the shared style no longer offers both the settled tint and the open ladder over it"
        )
        #expect(shared.contains("CadenceDueUrgency.evaluate("), "the shared ladder lost its urgency leg")
        let dense = shared.filter { !$0.isWhitespace }
        #expect(dense.contains("?.tint??open"), "the shared ladder no longer falls back to the caller's tier")
    }

    /// **Both Mac chips ask it, and neither keeps a copy.** *Failing-first:* restoring either
    /// chip's own `CadenceDueUrgency.evaluate(...)` line fails the negative.
    @Test func bothMacChipsReadTheSharedLadderAndKeepNoCopyOfIt() throws {
        let macOS = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.macOSChipsFile))
        for declaration in ["struct MonthTaskChip: View", "struct AllDayTaskChip: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: macOS), "\(declaration) is gone")
            #expect(body.count > 300, "non-vacuity: \(declaration) read back \(body.count) characters")
            let dense = body.filter { !$0.isWhitespace }
            #expect(
                dense.contains("CadenceCalendarTaskDoneStyle.chipGlyphTint(for:.resolve(task:task),dueDateKey:task.dueDate,todayKey:todayKey,open:CadenceCalendarEventStyle.plateTertiaryLabelColor())"),
                "\(declaration) does not ask the shared ladder"
            )
            #expect(!dense.contains("CadenceDueUrgency.evaluate"), "\(declaration) kept its own urgency ladder")
        }
    }

    /// **The iOS chip takes a deadline and the observed day, and asks the same ladder.**
    ///
    /// *Failing-first:* reverting the glyph to
    /// `completion.flatMap { ...chipGlyphTint(for: $0) } ?? openGlyphTint` — the shipped shape —
    /// fails the `chipGlyphTint(for:dueDateKey:todayKey:open:)` expectation, and an event chip that
    /// lost its flat-tier guard fails the `guard let completion` one.
    @Test func theIOSMiniChipTintsItsOpenGlyphByTheSameLadder() throws {
        let month = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iOSMonthFile))
        let chip = try #require(
            CadenceSourceScan.declarationBody("struct iOSCalendarMiniChip: View", in: month),
            "iOSCalendarMiniChip is gone from \(Self.iOSMonthFile)"
        )
        #expect(chip.count > 400, "non-vacuity: the mini chip read back \(chip.count) characters")
        #expect(chip.contains("var dueDateKey: String = \"\""), "the chip takes no deadline")
        #expect(chip.contains("var todayKey: String = DateFormatters.todayKey()"), "the chip takes no observed day")

        let dense = chip.filter { !$0.isWhitespace }
        #expect(
            dense.contains("guardletcompletionelse{returnopenGlyphTint}"),
            "an event chip no longer keeps the flat tier, so an event would be tinted by a deadline it has not got"
        )
        #expect(
            dense.contains("CadenceCalendarTaskDoneStyle.chipGlyphTint(for:completion,dueDateKey:dueDateKey,todayKey:todayKey,open:openGlyphTint)"),
            "the mini chip does not ask the shared ladder"
        )
        #expect(dense.contains(".foregroundStyle(glyphTint)"), "the glyph is tinted some other way")
        #expect(!dense.contains("CadenceDueUrgency.evaluate"), "the mini chip grew its own urgency ladder")
    }

    /// **Both iOS task-chip call sites hand it the task's deadline and the surface's observed day**
    /// — the month cell and the Week/Day all-day band. A chip that is given no key is tinted by
    /// nothing, so wiring the chip without wiring its callers would ship the same defect.
    ///
    /// *Failing-first:* dropping `dueDateKey: task.dueDate` from either call site fails its half,
    /// and replacing `todayKey: todayKey` with a fresh `DateFormatters.todayKey()` fails the
    /// observed-day half ([[T-5010]]: a grid left open overnight keeps yesterday's red otherwise).
    @Test func bothIOSTaskChipCallSitesPassTheDeadlineAndTheObservedDay() throws {
        for file in [Self.iOSMonthFile, Self.iOSTimelineFile] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
            let dense = source.filter { !$0.isWhitespace }
            #expect(
                CadenceSourceScan.matchCount(#"completion: \.resolve\(task: task\)"#, in: source) == 1,
                "\(file) draws a different number of task chips than this test knows about"
            )
            #expect(
                dense.contains("completion:.resolve(task:task),dueDateKey:task.dueDate,todayKey:todayKey"),
                "\(file)'s task chip is given no deadline, or reads the clock instead of the surface's day"
            )
        }

        // The band is handed the header's day rather than reading one of its own, so every chip in
        // a week of columns turns over at the same midnight.
        let timeline = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iOSTimelineFile))
        let band = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarAllDayBandChips: View", in: timeline),
            "iOSCalendarAllDayBandChips is gone"
        )
        #expect(band.contains("var todayKey: String = DateFormatters.todayKey()"), "the band takes no observed day")
        let header = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayHeader: View", in: timeline),
            "iOSCalendarTimelineDayHeader is gone"
        )
        #expect(header.contains("todayKey: todayKey,"), "the day header hands the band no observed day")
    }

    /// **[[T-10821]], owner call (a): the second channel draws wherever the chip is wide enough.**
    ///
    /// macOS's `CalendarChipDueMarker` is a 9pt date that takes layout priority OVER the title. A
    /// chip in a seven-column grid on a 393pt iPhone has about 56pt to spend, so there the marker
    /// would win that contest and leave no title; a regular-width iPad column has the room. The
    /// width is the one reason [[T-8201]] accepts, so it is decided by the size class in one
    /// shared rule, not by a device check, and the iPhone keeps the tint alone.
    @Test func theDueMarkerDrawsOnlyWhereTheColumnIsWideEnough() {
        #expect(CalendarChipDueMarkerSupport.drawsMarker(isCompactWidth: false), "the iPad's wide cell lost the marker")
        #expect(!CalendarChipDueMarkerSupport.drawsMarker(isCompactWidth: true), "the iPhone's column now loses its title")
    }

    /// The marker and its wording are declared once, in `Shared/`, and the Mac no longer holds a
    /// copy -- the shape the tint rule took ([[T-8243]]).
    @Test func theDueMarkerIsDeclaredOnceInShared() throws {
        let shared = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarChipDueMarker.swift")
        )
        #expect(shared.contains("struct CalendarChipDueMarker: View"))
        #expect(shared.contains("enum CalendarChipDueMarkerSupport"))
        let mac = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.macOSChipsFile))
        #expect(!mac.contains("struct CalendarChipDueMarker"), "the Mac kept a second copy of the marker")
        #expect(!mac.contains("enum CalendarChipDueMarkerSupport"), "the Mac kept a second copy of the wording")
        #expect(mac.contains("CalendarChipDueMarker(dueDateKey:"), "non-vacuity: the Mac chips stopped drawing it")
    }

    /// The iOS chip draws the shared marker when its host hands it a day, and both task-chip hosts
    /// hand one only through the shared width rule, fed the size class.
    @Test func theIOSChipHostsGateTheDueMarkerOnTheSharedWidthRule() throws {
        let month = try CadenceSourceScan.sourceFile(Self.iOSMonthFile)
        let timeline = try CadenceSourceScan.sourceFile(Self.iOSTimelineFile)

        let chip = try #require(
            CadenceSourceScan.declarationBody("struct iOSCalendarMiniChip: View", in: month),
            "iOSCalendarMiniChip is gone"
        )
        #expect(chip.contains("if let dueMarkerDayKey, let completion {"))
        #expect(chip.contains("CalendarChipDueMarker("))
        #expect(chip.contains("isDone: completion == .done"), "the marker reads a different done than the Mac's task.isDone")

        // The width reason is still written at the chip, now naming both sides of the call.
        let property = try #require(month.range(of: "    var dueDateKey: String = \"\""),
                                    "the chip takes no deadline, so there is no decision to explain")
        let doc = String(month[month.startIndex..<property.lowerBound].suffix(2600))
        #expect(doc.contains("[[T-10821]]"))
        #expect(doc.contains("[[T-8201]]"), "the width reason does not say which rule it answers")

        let rule = "CalendarChipDueMarkerSupport.drawsMarker(isCompactWidth: horizontalSizeClass == .compact)"
        for (source, declaration) in [
            (month, "private struct iOSCalendarMonthDayCell: View"),
            (timeline, "private struct iOSCalendarAllDayBandChips: View")
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source), "\(declaration) is gone")
            #expect(body.contains(rule), "\(declaration) decides the marker without the shared width rule")
            #expect(body.contains("dueMarkerDayKey: dueMarkerDayKey"), "\(declaration) never hands its chips the marker")
        }
        let header = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayHeader: View", in: timeline)
        )
        #expect(header.contains("dayKey: DateFormatters.dateKey(from: date),"), "the band names deadlines against no day")
    }
}
