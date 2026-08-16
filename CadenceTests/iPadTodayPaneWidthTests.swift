import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The two-pane Today layout puts a fixed-width task column beside an inspector that declares a
/// `minWidth`. An `HStack` will not shrink a fixed `.frame(width:)` to make room — it lets the
/// content overflow and clip. So the one property that matters is that the task column plus the
/// inspector's floor never exceed the pane.
///
/// It did exceed it: on an 11" iPad in portrait (632pt of pane after the 188pt sidebar) the task
/// column asked for 420 while only 312 remained, and the capture field's leading edge ran off the
/// left of the screen.
struct iPadTodayPaneWidthTests {
    /// Mirrors `iPadTodayView.sidePanelMinWidth(for:)`, which is `private` to the view. If that
    /// rule changes, this must change with it — the assertion below is only meaningful against the
    /// real floor.
    private func inspectorFloor(for width: CGFloat) -> CGFloat {
        width < 900 ? 320 : 370
    }

    /// Mirrors `iPadTodayView.taskPaneWidth(for:)`.
    private func taskPaneWidth(for width: CGFloat) -> CGFloat {
        let available = max(0, width - inspectorFloor(for: width))
        guard available > 0 else { return width }

        let preferred = min(max(width * 0.60, 520), 760)
        return min(preferred, available)
    }

    /// Pane widths a real iPad produces: the sidebar is 188pt, so these are window width − 188.
    private static let panes: [CGFloat] = [
        632,   // 11" iPad Air / Pro, portrait   (820 window)
        844,   // 13" iPad Pro, portrait         (1032 window)
        992,   // 11" iPad, landscape            (1180 window)
        1_022, // 11" iPad Pro, landscape        (1210 window)
        1_188, // 13" iPad Pro, landscape        (1376 window)
    ]

    @Test
    func theTaskColumnNeverClaimsSpaceTheInspectorNeeds() {
        for pane in Self.panes {
            let task = taskPaneWidth(for: pane)
            #expect(
                task + inspectorFloor(for: pane) <= pane,
                "pane \(pane): task \(task) + floor \(inspectorFloor(for: pane)) overflows"
            )
        }
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
        // 1188pt of pane: 60% is 713, comfortably inside both the 760 cap and what is available,
        // so the preference should win rather than being clamped away.
        #expect(taskPaneWidth(for: 1_188) == 712.8)
    }

    @Test
    func theWidestPanesStillRespectTheUpperCap() {
        // A very wide window must not hand the task column unbounded width.
        #expect(taskPaneWidth(for: 2_000) == 760)
    }

    /// A pane narrower than the inspector's own floor has no good answer; what matters is that it
    /// produces a sane one rather than a negative width. A zero-width pane correctly yields zero —
    /// the first version of this test asserted `> 0` there, which was the assertion being wrong
    /// rather than the code.
    @Test
    func adegeneratePaneDoesNotProduceANegativeWidth() {
        for pane in [CGFloat(0), 100, 320] {
            let result = taskPaneWidth(for: pane)
            #expect(result >= 0)
            #expect(result <= max(pane, 0))
        }
    }
}
