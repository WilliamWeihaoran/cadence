import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// The Ledger board card's **run** — what a card states, in what order, and which single token is
/// allowed to be coloured ([[T-8181]]).
///
/// The run is the half of this redesign that is a decision rather than a drawing, and it is shared:
/// one builder feeds the macOS card's hover-underlined pickers and the iPad card's inert labels, so
/// a test here is a test of both boards. The geometry — gutter width, radius, the collapsed line —
/// is pinned alongside it, because those were two platforms' separate literals before and the point
/// of the change is that they are now one.
@MainActor
struct CadenceBoardLedgerCardTests {

    private func chip(
        _ kind: CadenceBoardCardChip.Kind,
        _ text: String,
        emphasis: CadenceBoardCardChip.Emphasis = .neutral
    ) -> CadenceBoardCardChip {
        CadenceBoardCardChip(
            kind: kind,
            icon: "circle",
            text: text,
            listColorHex: kind == .list ? Theme.blueHex : nil,
            emphasis: emphasis
        )
    }

    private func task(
        doDate: String = "",
        dueDate: String = "",
        startMinute: Int = -1,
        estimate: Int = 0
    ) -> AppTask {
        let task = AppTask(title: "T")
        task.scheduledDate = doDate
        task.dueDate = dueDate
        task.scheduledStartMin = startMinute
        task.estimatedMinutes = estimate
        return task
    }

    // MARK: - What the run says

    /// Slot, estimate, do day, due day, list, tags — one order, and it is the order the design
    /// states: `9:00a · 45m · Tue · #deep-work`. The two date tokens keep
    /// `CadenceBoardCardMetadata`'s own ordering by arriving as its chips.
    @Test func theRunStatesTheSlotTheEstimateTheDaysTheListThenTheTags() {
        let tokens = CadenceLedgerCardSupport.tokens(
            startMinute: 9 * 60,
            estimatedMinutes: 45,
            chips: [chip(.doDate, "Tue"), chip(.dueDate, "Fri"), chip(.list, "Work")],
            tagNames: ["deep-work", "admin"]
        )

        #expect(tokens.map(\.kind) == [.time, .duration, .doDay, .dueDay, .list, .tag, .tag])
        #expect(tokens.map(\.text).last == "#admin")
    }

    /// The slot is the compact face — `9:00a`, not `9:00 AM`. A run is one line of 11pt text in a
    /// 248pt rail; the two letters are the whole budget.
    @Test func theSlotTokenUsesTheCompactClockFace() {
        let tokens = CadenceLedgerCardSupport.tokens(
            startMinute: 9 * 60,
            estimatedMinutes: 0,
            chips: [],
            tagNames: [],
            locale: Locale(identifier: "en_US")
        )

        #expect(tokens.first?.kind == .time)
        #expect(tokens.first?.text == "9a")
    }

    /// **The run carries no glyphs, so the due token has to name its own field.** The chips it
    /// replaces were identifiable before you read them — a sun and a flag — and a bare
    /// `… · Tue · Fri` states two days and names neither.
    @Test func theDueTokenNamesItsFieldBecauseTheRunCarriesNoGlyph() {
        let tokens = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: [chip(.doDate, "Tue"), chip(.dueDate, "Fri")],
            tagNames: []
        )

        #expect(tokens.map(\.text) == ["Tue", "Due Fri"])
    }

    /// A tag reads as one token. `#deep-work` is a word; `#deep work` is the end of the run plus a
    /// stray, which is why the token takes the slug and not the display name.
    @Test func aTagTokenIsOneWord() {
        let tokens = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: [],
            tagNames: ["deep-work", ""]
        )

        #expect(tokens.map(\.text) == ["#deep-work"])
    }

    /// A field with no value contributes no token — the same rule `CadenceBoardCardMetadata`
    /// applies to its chips, and an estimate of zero is a field with no value rather than a
    /// duration of `0m`.
    @Test func afieldWithNoValueContributesNoToken() {
        let tokens = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: [],
            tagNames: []
        )

        #expect(tokens.isEmpty)
    }

    // MARK: - The placeholders, which are macOS's and only macOS's

    /// **The empty-field affordance, and the reason it is a parameter rather than a rule.** On
    /// macOS every token is a picker, so a field with no value still needs something under the
    /// pointer; on a touch card the same token would say nothing and do nothing. Off by default, so
    /// a new caller cannot acquire placeholders by accident.
    @Test func placeholderTokensAppearOnlyWhenTheCallerAsksForThem() {
        let inert = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: [],
            tagNames: [],
            showsEmptyDueDate: true
        )
        #expect(inert.isEmpty)

        let pickers = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: [],
            tagNames: [],
            placeholders: true,
            showsEmptyDueDate: true
        )
        #expect(pickers.map(\.text) == [CadenceLedgerCardSupport.estimatePlaceholder, CadenceLedgerCardSupport.duePlaceholder])
        // Bound outside the macro: `allSatisfy` is `rethrows`, and `#expect` expands it into a
        // position where the compiler cannot see that the argument does not throw.
        let allArePlaceholders = pickers.allSatisfy { $0.isPlaceholder }
        #expect(allArePlaceholders)
    }

    /// The empty due token lands where a real one would — before the list and the tags — rather
    /// than being appended after them. A run whose tokens move about depending on which fields are
    /// empty is a run you have to read rather than scan.
    @Test func theEmptyDueTokenLandsWhereARealOneWouldRatherThanAtTheEnd() {
        let tokens = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 30,
            chips: [chip(.doDate, "Tue"), chip(.list, "Work")],
            tagNames: ["deep-work"],
            placeholders: true,
            showsEmptyDueDate: true
        )

        #expect(tokens.map(\.kind) == [.duration, .doDay, .dueDay, .list, .tag])
    }

    /// A list that already hides empty due dates gets no placeholder, even on macOS: the card asks
    /// `AppTask.shouldShowDueDateField` exactly as the chip it replaces did.
    @Test func aHiddenDueFieldGetsNoPlaceholderEvenWhereTokensArePickers() {
        let tokens = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 30,
            chips: [],
            tagNames: [],
            placeholders: true,
            showsEmptyDueDate: false
        )

        #expect(tokens.map(\.kind) == [.duration])
    }

    // MARK: - Only the urgent token is coloured

    /// Overdue red, today amber, every ordinary date neutral — and **nothing else in the run is
    /// coloured at all.** The list's identity is the gutter wash now, so a tinted list token would
    /// put a second colour in a run whose whole point is that one of them means something.
    @Test func onlyAnUrgentOrAttentionDayTokenIsColoured() {
        let urgent = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: [chip(.doDate, "Mon", emphasis: .urgent)],
            tagNames: []
        )
        let today = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: [chip(.doDate, "Today", emphasis: .attention)],
            tagNames: []
        )
        let ordinary = CadenceLedgerCardSupport.tokens(
            startMinute: 540,
            estimatedMinutes: 45,
            chips: [chip(.doDate, "Fri"), chip(.list, "Work")],
            tagNames: ["deep-work"]
        )

        #expect(CadenceLedgerCardMetrics.color(for: urgent[0]) == Theme.red)
        #expect(CadenceLedgerCardMetrics.color(for: today[0]) == Theme.amber)
        for token in ordinary {
            #expect(CadenceLedgerCardMetrics.color(for: token) == Theme.dim)
        }
    }

    /// A placeholder is never loud. It stands for a field with no value, so there is nothing about
    /// it to be urgent.
    @Test func aPlaceholderTokenIsNeverColoured() {
        let placeholder = CadenceLedgerToken(
            kind: .dueDay,
            id: "due",
            text: CadenceLedgerCardSupport.duePlaceholder,
            emphasis: .urgent,
            isPlaceholder: true
        )

        #expect(CadenceLedgerCardMetrics.color(for: placeholder) == Theme.dim)
    }

    // MARK: - Both board knobs still reach the run

    /// The run is built on `CadenceBoardCardMetadata.chips`, so `showsContainerChip` and
    /// `dayAlreadyStatedBySurface` keep working without the card re-deciding anything. This is the
    /// test that would go red if a card ever went back to assembling its own list.
    @Test func bothBoardKnobsStillSuppressTheirTokens() {
        let planned = task(doDate: "2026-08-20", dueDate: "2026-08-25")

        let full = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: CadenceBoardCardMetadata.chips(for: planned, showsContainer: true, todayKey: "2026-08-20"),
            tagNames: []
        )
        #expect(full.map(\.kind) == [.doDay, .dueDay, .list])

        let scopedToOneList = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: CadenceBoardCardMetadata.chips(for: planned, showsContainer: false, todayKey: "2026-08-20"),
            tagNames: []
        )
        #expect(scopedToOneList.map(\.kind) == [.doDay, .dueDay])

        let dayColumn = CadenceLedgerCardSupport.tokens(
            startMinute: -1,
            estimatedMinutes: 0,
            chips: CadenceBoardCardMetadata.chips(
                for: planned,
                showsContainer: false,
                dayAlreadyStatedBySurface: "2026-08-20",
                todayKey: "2026-08-20"
            ),
            tagNames: []
        )
        #expect(dayColumn.map(\.kind) == [.dueDay])
    }

    // MARK: - The geometry, which is now one set of numbers

    /// The gutter is **fixed at 30pt**, which is the design's figure, and stays 30 at the app's
    /// default `.fixed` typography scope and at `.large` — a card that is 30pt of gutter on one
    /// reader's screen and 46 on another's is not a fixed gutter.
    @Test func theStateGutterIsThirtyPointsAndStaysThereUnlessTheSurfaceScales() {
        #expect(CadenceLedgerCardMetrics.gutterWidth == 30)
        #expect(CadenceLedgerCardMetrics.gutterWidth(at: .accessibility5, scaling: .fixed) == 30)
        #expect(CadenceLedgerCardMetrics.gutterWidth(at: .large, scaling: .enabled) == 30)
        #expect(CadenceLedgerCardMetrics.gutterWidth(at: .accessibility5, scaling: .enabled) > 30)
    }

    /// One radius for both platforms, where the cards were 7 (macOS) and 18 (iOS).
    ///
    /// **And the chip radius rule stays a rule.** `CadenceBoardMetadataChipMetrics
    /// .cornerRadius(inCardOfRadius:)` reproduced both cards' chip radii from one expression
    /// precisely because the cards differed; unifying the *task* cards without noticing would have
    /// turned it into a constant. Its remaining callers are the **event** cards, which keep their
    /// platforms' radii, so it still returns two answers.
    @Test func theTwoBoardCardsRoundAtOneRadiusAndTheChipRuleIsStillARule() {
        #expect(CadenceLedgerCardMetrics.cornerRadius == Theme.radiusControl)
        #expect(
            CadenceBoardMetadataChipMetrics.cornerRadius(inCardOfRadius: 7)
                != CadenceBoardMetadataChipMetrics.cornerRadius(inCardOfRadius: Theme.radiusCard)
        )
    }

    /// A completed card collapses to a 22pt struck line, and the collapsed line still grows with
    /// the reader's text where a surface has opted in — it is a line of text, not a slot.
    @Test func aCompletedCardCollapsesToATwentyTwoPointLine() {
        #expect(CadenceLedgerCardMetrics.collapsedLineHeight == 22)
        let grown = CadenceTypeScale.height(
            CadenceLedgerCardMetrics.collapsedLineHeight,
            holding: .rowTitle,
            textBase: CadenceLedgerCardMetrics.titleBase,
            at: .accessibility3,
            scaling: .enabled
        )
        #expect(grown > CadenceLedgerCardMetrics.collapsedLineHeight)
    }

    /// The gutter's wash is dimmer once the work is settled, the way the iOS card's leading strip
    /// already dimmed its tint — and it is never zero, because the gutter is where the list colour
    /// lives now that no chip carries it.
    @Test func theGutterWashDimsOnceTheWorkIsSettled() {
        let open = CadenceLedgerCardMetrics.gutterWashOpacity(isSettled: false)
        let settled = CadenceLedgerCardMetrics.gutterWashOpacity(isSettled: true)

        #expect(settled < open)
        #expect(settled > 0)
    }
}
