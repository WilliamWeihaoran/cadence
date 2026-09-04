import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// The half of the row swipe that `CadenceSwipeActionSupportTests` reads only from the **leading**
/// edge, plus the two declarations in `CadenceSwipeActionSupport.swift` that no test named at all.
///
/// The hole this closes is `release`'s `velocity * edge.direction`. Every velocity case in the
/// existing suite drags right, where `direction` is `1` and the factor is invisible; the one
/// trailing-edge case there releases at −100 pt/s, which is under `velocityCommit` and so never
/// reaches either velocity branch. Dropping the factor altogether therefore changed nothing any
/// existing test could see — measured, by mutation — while inverting the trailing edge for the
/// user: a flick left toward open would read as an abandon and snap shut, and a flick back right
/// would commit the full swipe the user was visibly cancelling. Both directions are pinned below.
@MainActor
struct CadenceSwipeEdgeArbitrationTests {
    private let metrics = CadenceSwipeActionMetrics.standard
    /// A plausible iPhone row, matching the sibling suite so the two read against one geometry.
    private let rowWidth: CGFloat = 390

    private var openWidthForTwo: CGFloat {
        CadenceSwipeActionSupport.openWidth(actionCount: 2, metrics: metrics)
    }

    private var fullSwipeThresholdForTwo: CGFloat {
        CadenceSwipeActionSupport.fullSwipeThreshold(rowWidth: rowWidth, actionCount: 2, metrics: metrics)
    }

    // MARK: - Which way "toward open" points

    /// The whole reason the release rule can stay unsigned. Named here because nothing else did:
    /// `direction` is only ever read through `resolvedOffset`'s sign and `release`'s velocity, and
    /// the second of those was unpinned.
    @Test func eachEdgeTravelsInItsOwnDirection() {
        #expect(CadenceSwipeEdge.leading.direction == 1)
        #expect(CadenceSwipeEdge.trailing.direction == -1)
        #expect(CadenceSwipeEdge.leading != CadenceSwipeEdge.trailing)
    }

    // MARK: - Velocity, read from the trailing edge

    /// A flick left is *toward* open on the trailing edge, so it opens on a drag far too short to
    /// have opened on distance alone.
    @Test func aFastFlickLeftOpensTheTrailingEdge() {
        let outcome = releaseTrailing(rawOffset: -30, velocity: -(metrics.velocityCommit + 200))
        #expect(outcome == .open(.trailing))
    }

    /// And a flick back right abandons it — even from past the full-swipe threshold, which is the
    /// case that matters: the trailing edge's first action toggles completion, so getting this
    /// backwards marks a task done at the exact moment the user snatched the row back.
    @Test func aFlickBackRightClosesTheTrailingEdgeEvenPastTheFullSwipeThreshold() {
        let outcome = releaseTrailing(
            rawOffset: -(fullSwipeThresholdForTwo + 30),
            velocity: metrics.velocityCommit + 200
        )
        #expect(outcome == .closed)
    }

    /// The trailing edge's distance rule, with the flick taken out of it: half the tray opens, and
    /// a hair under half does not. Without this the two velocity tests above would still pass on a
    /// rule that had stopped consulting distance at all.
    @Test func theTrailingEdgeStillOpensOnDistanceWithNoFlickAtAll() {
        #expect(releaseTrailing(rawOffset: -openWidthForTwo / 2, velocity: 0) == .open(.trailing))
        #expect(releaseTrailing(rawOffset: -(openWidthForTwo / 2 - 1), velocity: 0) == .closed)
    }

    // MARK: - Tray layout under an index the tray cannot have

    /// `actionWidths` guards its index from **both** ends. The sibling suite pins the too-large
    /// end; a negative index is the one that would silently collapse every action to zero width
    /// rather than falling back to the even split.
    @Test func aNegativeFullSwipeIndexFallsBackToTheEvenSplit() {
        #expect(
            CadenceSwipeActionSupport.actionWidths(revealedWidth: 152, actionCount: 2, fullSwipeIndex: -1)
                == [76, 76]
        )
    }

    // MARK: - Gesture arbitration at the boundary

    /// Exactly at the claim ratio the row takes the drag. The sibling suite reads 3.0 and 1.2, so
    /// the comparison could have been strict and nothing would have said so.
    @Test func aDragExactlyAtTheClaimRatioIsClaimed() {
        let vertical: CGFloat = 25
        let horizontal = vertical * metrics.horizontalClaimRatio
        #expect(CadenceSwipeActionSupport.isHorizontal(
            translation: CGSize(width: horizontal, height: vertical),
            metrics: metrics
        ))
        #expect(CadenceSwipeActionSupport.isHorizontal(
            translation: CGSize(width: horizontal - 0.5, height: vertical),
            metrics: metrics
        ) == false)
    }

    // MARK: - The action value itself

    /// `CadenceSwipeAction` was named by no test in the target. It carries the `isDestructive` flag
    /// the full-swipe rule reads and the closure the tray fires, and it defaults the flag — so a
    /// default flipped to `true` would quietly strip the full swipe from every edge in the app.
    @Test func anActionIsNonDestructiveUnlessItSaysSoAndRunsWhatItWasHanded() {
        var fired = 0
        let done = CadenceSwipeAction(
            id: "done",
            title: "Done",
            systemImage: "checkmark",
            tint: Theme.green
        ) { fired += 1 }

        #expect(done.id == "done")
        #expect(done.title == "Done")
        #expect(done.systemImage == "checkmark")
        #expect(done.isDestructive == false)
        #expect(CadenceSwipeActionSupport.fullSwipeIndex(isDestructive: [done.isDestructive]) == 0)

        #expect(fired == 0)
        done.perform()
        #expect(fired == 1)

        let delete = CadenceSwipeAction(
            id: "delete",
            title: "Delete",
            systemImage: "trash",
            tint: Theme.red,
            isDestructive: true,
            perform: {}
        )
        #expect(delete.isDestructive)
        #expect(CadenceSwipeActionSupport.fullSwipeIndex(isDestructive: [delete.isDestructive]) == nil)
    }

    // MARK: - Helpers

    /// Trailing edge, `[Done, Delete]` — the real row, whose first action is not destructive and so
    /// does have a full swipe.
    private func releaseTrailing(rawOffset: CGFloat, velocity: CGFloat) -> CadenceSwipeRelease {
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
}
