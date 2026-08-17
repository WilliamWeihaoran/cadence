import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The row swipe gesture replaced `.swipeActions`, which only ever worked in a `List`. These pin
/// the arithmetic the replacement runs on — the part that used to be untestable because it lived
/// behind `#if os(iOS)` and this target builds for macOS.
@MainActor
struct CadenceSwipeActionSupportTests {
    private let metrics = CadenceSwipeActionMetrics.standard
    /// A plausible iPhone row.
    private let rowWidth: CGFloat = 390

    private var openWidthForTwo: CGFloat {
        CadenceSwipeActionSupport.openWidth(actionCount: 2, metrics: metrics)
    }

    private var fullSwipeThresholdForTwo: CGFloat {
        CadenceSwipeActionSupport.fullSwipeThreshold(rowWidth: rowWidth, actionCount: 2, metrics: metrics)
    }

    // MARK: - Open width

    @Test func openWidthScalesWithActionCount() {
        #expect(CadenceSwipeActionSupport.openWidth(actionCount: 0, metrics: metrics) == 0)
        #expect(CadenceSwipeActionSupport.openWidth(actionCount: 1, metrics: metrics) == metrics.actionWidth)
        #expect(openWidthForTwo == metrics.actionWidth * 2)
    }

    // MARK: - Reveal

    @Test func revealTracksTheFingerUntilFullyOpen() {
        let offset = CadenceSwipeActionSupport.resolvedOffset(
            rawOffset: 100,
            leadingActionCount: 2,
            trailingActionCount: 2,
            metrics: metrics
        )
        #expect(offset == 100)
    }

    @Test func revealKeepsTheSignOfTheDraggedEdge() {
        let trailing = CadenceSwipeActionSupport.resolvedOffset(
            rawOffset: -100,
            leadingActionCount: 2,
            trailingActionCount: 2,
            metrics: metrics
        )
        #expect(trailing == -100)
    }

    @Test func revealRubberBandsPastFullyOpen() {
        let raw = openWidthForTwo + 100
        let offset = CadenceSwipeActionSupport.resolvedOffset(
            rawOffset: raw,
            leadingActionCount: 2,
            trailingActionCount: 2,
            metrics: metrics
        )

        // Past the stop the row still moves, but less than the finger does, and never past the cap.
        #expect(offset > openWidthForTwo)
        #expect(offset < raw)
        #expect(offset < openWidthForTwo + metrics.rubberBandLimit)
    }

    @Test func rubberBandIsBoundedNoMatterHowFarTheDragGoes() {
        let offset = CadenceSwipeActionSupport.resolvedOffset(
            rawOffset: openWidthForTwo + 10_000,
            leadingActionCount: 2,
            trailingActionCount: 2,
            metrics: metrics
        )
        #expect(offset <= openWidthForTwo + metrics.rubberBandLimit)
        #expect(offset > openWidthForTwo + metrics.rubberBandLimit - 0.001)
    }

    @Test func rubberBandStartsAtSlopeOneSoTheRowDoesNotJudder() {
        // One point past the stop should move very nearly one point, or the row visibly snags at
        // the moment it crosses fully-open.
        let give = CadenceSwipeActionSupport.rubberBand(excess: 1, limit: metrics.rubberBandLimit)
        #expect(give > 0.98)
        #expect(give < 1)
        #expect(CadenceSwipeActionSupport.rubberBand(excess: 0, limit: metrics.rubberBandLimit) == 0)
        #expect(CadenceSwipeActionSupport.rubberBand(excess: -20, limit: metrics.rubberBandLimit) == 0)
    }

    @Test func anEdgeWithNoActionsDoesNotMove() {
        let offset = CadenceSwipeActionSupport.resolvedOffset(
            rawOffset: 200,
            leadingActionCount: 0,
            trailingActionCount: 2,
            metrics: metrics
        )
        #expect(offset == 0)
    }

    @Test func revealedWidthIsTheMagnitudeOfTheOffset() {
        let width = CadenceSwipeActionSupport.revealedWidth(
            rawOffset: -100,
            leadingActionCount: 2,
            trailingActionCount: 2,
            metrics: metrics
        )
        #expect(width == 100)
    }

    // MARK: - Full swipe threshold

    @Test func fullSwipeThresholdNeverFallsBelowMeaningfullyPastFullyOpen() {
        // A narrow host — an iPad task column, the calendar inspector — must not make a full swipe
        // easier to trigger than merely opening the tray.
        let narrow = CadenceSwipeActionSupport.fullSwipeThreshold(rowWidth: 240, actionCount: 2, metrics: metrics)
        #expect(narrow >= openWidthForTwo * metrics.fullSwipeOpenWidthMultiple)

        let wide = CadenceSwipeActionSupport.fullSwipeThreshold(rowWidth: 900, actionCount: 2, metrics: metrics)
        #expect(wide == 900 * metrics.fullSwipeFraction)
    }

    // MARK: - Release

    @Test func aShortDragSnapsClosed() {
        #expect(releaseLeading(rawOffset: 60, velocity: 0) == .closed)
    }

    @Test func draggingPastHalfTheTrayOpensIt() {
        #expect(releaseLeading(rawOffset: openWidthForTwo / 2, velocity: 0) == .open(.leading))
    }

    @Test func aFastFlickOpensEvenOnAShortDrag() {
        #expect(releaseLeading(rawOffset: 30, velocity: metrics.velocityCommit + 200) == .open(.leading))
    }

    @Test func aFlickBackClosesEvenPastTheFullSwipeThreshold() {
        // The user visibly abandoned the gesture; committing an action here is the one outcome
        // that cannot be undone by simply not letting go.
        let raw = fullSwipeThresholdForTwo + 30
        #expect(releaseLeading(rawOffset: raw, velocity: -(metrics.velocityCommit + 200)) == .closed)
    }

    @Test func draggingPastTheThresholdCommitsAFullSwipe() {
        #expect(releaseLeading(rawOffset: fullSwipeThresholdForTwo + 10, velocity: 0) == .fullSwipe(.leading))
    }

    @Test func theTrailingEdgeCommitsItsOwnFullSwipe() {
        let outcome = CadenceSwipeActionSupport.release(
            rawOffset: -(fullSwipeThresholdForTwo + 10),
            velocity: -100,
            rowWidth: rowWidth,
            leadingActionCount: 2,
            trailingActionCount: 2,
            leadingIsDestructive: [false, false],
            trailingIsDestructive: [false, true],
            metrics: metrics
        )
        #expect(outcome == .fullSwipe(.trailing))
    }

    @Test func anEdgeLedByADestructiveActionOnlyEverOpens() {
        // A full swipe that deletes is the accident this rules out by construction.
        let outcome = CadenceSwipeActionSupport.release(
            rawOffset: -(fullSwipeThresholdForTwo + 200),
            velocity: 0,
            rowWidth: rowWidth,
            leadingActionCount: 2,
            trailingActionCount: 2,
            leadingIsDestructive: [false, false],
            trailingIsDestructive: [true, false],
            metrics: metrics
        )
        #expect(outcome == .open(.trailing))
    }

    @Test func releasingOnAnEmptyEdgeIsAlwaysClosed() {
        let outcome = CadenceSwipeActionSupport.release(
            rawOffset: 400,
            velocity: 900,
            rowWidth: rowWidth,
            leadingActionCount: 0,
            trailingActionCount: 2,
            leadingIsDestructive: [],
            trailingIsDestructive: [false, true],
            metrics: metrics
        )
        #expect(outcome == .closed)
        #expect(releaseLeading(rawOffset: 0, velocity: 0) == .closed)
    }

    // MARK: - Which action a full swipe commits

    @Test func theFullSwipeActionIsTheFirstOne() {
        #expect(CadenceSwipeActionSupport.fullSwipeIndex(isDestructive: [false, true]) == 0)
        #expect(CadenceSwipeActionSupport.fullSwipeIndex(isDestructive: [false]) == 0)
    }

    @Test func thereIsNoFullSwipeWhenTheFirstActionIsDestructive() {
        #expect(CadenceSwipeActionSupport.fullSwipeIndex(isDestructive: [true, false]) == nil)
        #expect(CadenceSwipeActionSupport.fullSwipeIndex(isDestructive: []) == nil)
    }

    @Test func armingFollowsTheSameRuleAsCommitting() {
        #expect(isArmed(rawOffset: fullSwipeThresholdForTwo - 10) == false)
        #expect(isArmed(rawOffset: fullSwipeThresholdForTwo + 10) == true)
        #expect(isArmed(rawOffset: -(fullSwipeThresholdForTwo + 10), trailingIsDestructive: [true, false]) == false)
        #expect(isArmed(rawOffset: 0) == false)
    }

    // MARK: - Tray layout

    @Test func anUnarmedTrayIsSplitEvenly() {
        let widths = CadenceSwipeActionSupport.actionWidths(
            revealedWidth: 152,
            actionCount: 2,
            fullSwipeIndex: nil
        )
        #expect(widths == [76, 76])
    }

    @Test func anArmedTrayGivesTheWholeWidthToTheCommittedAction() {
        let widths = CadenceSwipeActionSupport.actionWidths(
            revealedWidth: 152,
            actionCount: 2,
            fullSwipeIndex: 0
        )
        #expect(widths == [152, 0])
    }

    @Test func trayLayoutSurvivesDegenerateInput() {
        #expect(CadenceSwipeActionSupport.actionWidths(revealedWidth: 100, actionCount: 0, fullSwipeIndex: nil).isEmpty)
        #expect(CadenceSwipeActionSupport.actionWidths(revealedWidth: -40, actionCount: 2, fullSwipeIndex: nil) == [0, 0])
        // An index the tray does not have falls back to the even split rather than vanishing.
        #expect(CadenceSwipeActionSupport.actionWidths(revealedWidth: 152, actionCount: 2, fullSwipeIndex: 5) == [76, 76])
    }

    // MARK: - Gesture arbitration

    @Test func onlyClearlyHorizontalDragsAreClaimed() {
        // The whole reason vertical scrolling still works: anything flatter than the ratio is
        // handed back to the enclosing ScrollView or List.
        #expect(CadenceSwipeActionSupport.isHorizontal(translation: CGSize(width: 30, height: 10), metrics: metrics))
        #expect(CadenceSwipeActionSupport.isHorizontal(translation: CGSize(width: -30, height: 10), metrics: metrics))
        #expect(CadenceSwipeActionSupport.isHorizontal(translation: CGSize(width: 30, height: 25), metrics: metrics) == false)
        #expect(CadenceSwipeActionSupport.isHorizontal(translation: CGSize(width: 4, height: 60), metrics: metrics) == false)
        #expect(CadenceSwipeActionSupport.isHorizontal(translation: CGSize(width: 0, height: 0), metrics: metrics) == false)
    }

    // MARK: - Helpers

    private func releaseLeading(rawOffset: CGFloat, velocity: CGFloat) -> CadenceSwipeRelease {
        CadenceSwipeActionSupport.release(
            rawOffset: rawOffset,
            velocity: velocity,
            rowWidth: rowWidth,
            leadingActionCount: 2,
            trailingActionCount: 2,
            leadingIsDestructive: [false, false],
            trailingIsDestructive: [false, true],
            metrics: metrics
        )
    }

    private func isArmed(
        rawOffset: CGFloat,
        trailingIsDestructive: [Bool] = [false, true]
    ) -> Bool {
        CadenceSwipeActionSupport.isFullSwipeArmed(
            rawOffset: rawOffset,
            rowWidth: rowWidth,
            leadingActionCount: 2,
            trailingActionCount: 2,
            leadingIsDestructive: [false, false],
            trailingIsDestructive: trailingIsDestructive,
            metrics: metrics
        )
    }
}
