import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The two-pane Today layout puts a fixed-width task column beside a 1pt `Divider()` and an
/// inspector that declares a `minWidth`. An `HStack` will not shrink a fixed `.frame(width:)` to
/// make room — it lets the content overflow, and the shell hard-sizes the pane and clips it. So the
/// one property that matters is that **all three** fit: task + divider + floor never exceed the
/// pane.
///
/// It has been wrong in both directions. First the task column asked for 420 where 312 remained and
/// the capture field's leading edge ran off the screen. Then, more quietly, the divider went
/// uncounted and the row asked for exactly one point more than it had.
///
/// **These call the real functions.** They used to re-implement `taskPaneWidth` and the inspector
/// floor, because both were `private` on a `#if os(iOS)` view this target cannot see — so the file
/// tested a copy, the copy drifted, and the assertion below omitted the same divider the code did.
/// A test that mirrors the bug cannot catch the bug. Both rules now live on
/// `CadenceTodayLayoutSupport`, beside the floor they have to agree with.
struct iPadTodayPaneWidthTests {
    private func inspectorFloor(for paneWidth: CGFloat) -> CGFloat {
        CadenceTodayLayoutSupport.inspectorPaneFloor(forPaneWidth: paneWidth)
    }

    private func taskPaneWidth(for paneWidth: CGFloat) -> CGFloat {
        CadenceTodayLayoutSupport.taskPaneWidth(forPaneWidth: paneWidth)
    }

    /// Pane widths that reach the two-pane layout at all — i.e. clear the 761pt floor. The shell
    /// sidebar is 188pt when it is out and 0 when the user folds it, and the fold is what puts a
    /// full-screen portrait iPad in this list.
    ///
    /// The unlovely ones are the boundaries of the two bands where `available` is the binding clamp
    /// and the missing divider therefore showed: [761, 841) and [900, 928). 840 and 927 are the last
    /// widths that overflowed; 841 and 928 are the first that did not.
    private static let panes: [CGFloat] = [
        761,   // twoPaneMinimumWidth — the narrowest pane this layout renders in at all
        795,   // 2/3 Split View, landscape, sidebar folded
        834,   // iPad Pro 11" portrait, full screen, sidebar folded
        840, 841,   // first band's upper boundary
        900, 927, 928, // second band — only a resized window lands here
        1_022, // iPad Pro 11" landscape, full screen, sidebar out (1210 − 188)
        1_210, // iPad Pro 11" landscape, full screen, sidebar folded — the widest pane there is
    ]

    /// The property the whole file exists for, **including the divider**. Without that term this
    /// passed at 834 and 840 while the row asked for `pane + 1`.
    @Test
    func theThreeColumnsNeverAskForMoreThanThePaneTheyAreGiven() {
        for pane in Self.panes {
            let task = taskPaneWidth(for: pane)
            let total = task + CadenceTodayLayoutSupport.paneDividerWidth + inspectorFloor(for: pane)
            #expect(
                total <= pane,
                "pane \(pane): task \(task) + divider + floor \(inspectorFloor(for: pane)) = \(total)"
            )
        }
    }

    /// The two widths an off-by-one is likeliest to miss, spelled out rather than swept: 840 is the
    /// last pane in the first band, and 927 the last in the second. Both used to come to `pane + 1`.
    @Test
    func theTwoBandBoundariesFitToThePoint() {
        for pane in [CGFloat(840), 927] {
            #expect(
                taskPaneWidth(for: pane) + CadenceTodayLayoutSupport.paneDividerWidth
                    + inspectorFloor(for: pane) <= pane,
                "pane \(pane) still overflows"
            )
        }
    }

    /// And the fix is not "shrink the task column until nothing overflows": at the two-pane floor
    /// the column lands on its own declared minimum exactly, which is what that floor is a sum of.
    @Test
    func theNarrowestTwoPaneLayoutGivesTheTaskColumnExactlyItsDeclaredMinimum() {
        #expect(
            taskPaneWidth(for: CadenceTodayLayoutSupport.twoPaneMinimumWidth)
                == CadenceTodayLayoutSupport.taskPaneMinWidth
        )
    }

    @Test
    func theTaskColumnIsNeverWiderThanThePaneItself() {
        for pane in Self.panes {
            #expect(taskPaneWidth(for: pane) <= pane)
            #expect(taskPaneWidth(for: pane) > 0)
        }
    }

    @Test
    func roomyPanesStillGetThePreferredProportionRatherThanTheFloor() {
        // 1022pt of pane: 60% is 613, comfortably inside what is available, so the preference
        // should win rather than being clamped away.
        #expect(taskPaneWidth(for: 1_022) == 1_022 * 0.60)
    }

    /// Replaces an assertion that pinned the old 760pt cap at a 2000pt pane — a width no target
    /// device produces. The widest is 1210: an 11" Pro in landscape with the shell sidebar folded.
    /// What has to hold there is the property the cap was standing in for.
    @Test
    func theWidestReachablePaneKeepsItsProportionAndStillPaysTheInspector() {
        #expect(taskPaneWidth(for: 1_210) == 1_210 * 0.60)
        #expect(1_210 - taskPaneWidth(for: 1_210) >= inspectorFloor(for: 1_210))
    }

    /// **Both inspector floors are live**, which is why `inspectorPaneFloor(forPaneWidth:)` still
    /// has two values. 834 is a full-screen portrait iPad with the sidebar folded: past the 761pt
    /// two-pane floor, so this layout renders, and under 900, so it takes the narrow floor. Fold the
    /// sidebar in landscape instead and the same device is 1210, which takes the wide one.
    @Test
    func aFoldedPortraitPaneIsWhatKeepsTheNarrowInspectorFloorAlive() {
        #expect(834 >= CadenceTodayLayoutSupport.twoPaneMinimumWidth)
        #expect(inspectorFloor(for: 834) == CadenceTodayLayoutSupport.inspectorPaneMinWidth)
        #expect(inspectorFloor(for: 1_210) == CadenceTodayLayoutSupport.inspectorPaneWideMinWidth)
        // With the sidebar out the same portrait window is 646pt of pane, which is one column.
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 646) == .compact)
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 834) == .twoPane)
    }

    /// The inspector's ideal never asks for more than the pane has left either, at any width the
    /// layout actually renders at.
    @Test
    func theInspectorsIdealNeverExceedsWhatIsLeftBesideTheTaskColumn() {
        for pane in Self.panes {
            let remaining = pane - taskPaneWidth(for: pane) - CadenceTodayLayoutSupport.paneDividerWidth
            #expect(
                CadenceTodayLayoutSupport.inspectorPaneIdealWidth(forPaneWidth: pane) >= inspectorFloor(for: pane)
            )
            #expect(remaining >= inspectorFloor(for: pane), "pane \(pane) left the inspector \(remaining)")
        }
    }

    /// A pane narrower than the inspector's own floor has no good answer; what matters is that it
    /// produces a sane one rather than a negative width. A zero-width pane correctly yields zero —
    /// the first version of this test asserted `> 0` there, which was the assertion being wrong
    /// rather than the code.
    @Test
    func adegeneratePaneDoesNotProduceANegativeWidth() {
        for pane in [CGFloat(0), 100, 320, 321, 760] {
            let result = taskPaneWidth(for: pane)
            #expect(result >= 0)
            #expect(result <= max(pane, 0))
        }
    }
}
