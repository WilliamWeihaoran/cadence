#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// **T-8092: a resting pointer does not take the Cmd+K highlight back from the keyboard.**
///
/// Since T-8063 the palette's list scrolls to follow the keyboard highlight, so Down past the
/// bottom edge can slide a different row under a pointer that never moved. `GlobalSearchHoverGate`
/// is the rule the rows' hover-enter now goes through: after the keyboard takes the highlight, a
/// hover from the same screen point is ignored, and the first hover from anywhere else hands the
/// highlight back to the pointer.
struct CadenceGlobalSearchHoverGateTests {
    private let resting = CGPoint(x: 640, y: 420)

    @Test func aHoverCountsWhileTheKeyboardHasNotTakenTheHighlight() {
        var gate = GlobalSearchHoverGate()
        let admitted1 = gate.admitsHover(pointerAt: resting)
        #expect(admitted1)
        #expect(gate.keyboardPointerAnchor == nil)
    }

    @Test func aHoverFromTheSpotTheKeyboardLeftThePointerAtIsIgnored() {
        var gate = GlobalSearchHoverGate()
        gate.keyboardTookHighlight(pointerAt: resting)
        let admitted2 = gate.admitsHover(pointerAt: resting)
        #expect(!admitted2)
        // Still ignored on the next scroll step: the pointer has not moved.
        let admitted3 = gate.admitsHover(pointerAt: resting)
        #expect(!admitted3)
        #expect(gate.keyboardPointerAnchor == resting)
    }

    @Test func aHoverAfterThePointerMovesCountsAndHandsTheHighlightBack() {
        var gate = GlobalSearchHoverGate()
        gate.keyboardTookHighlight(pointerAt: resting)
        let admitted4 = gate.admitsHover(pointerAt: CGPoint(x: resting.x, y: resting.y + 12))
        #expect(admitted4)
        #expect(gate.keyboardPointerAnchor == nil)
        // The pointer owns the highlight now, wherever it rests next.
        let admitted5 = gate.admitsHover(pointerAt: resting)
        #expect(admitted5)
    }

    @Test func movementWithinTheToleranceIsNotMovement() {
        var gate = GlobalSearchHoverGate()
        gate.keyboardTookHighlight(pointerAt: resting)
        let jitter = GlobalSearchHoverGate.movementTolerance / 2
        let admitted6 = gate.admitsHover(pointerAt: CGPoint(x: resting.x + jitter, y: resting.y - jitter))
        #expect(!admitted6)
    }

    @Test func theNextKeyPressTakesTheHighlightAgainFromWhereverThePointerIs() {
        var gate = GlobalSearchHoverGate()
        gate.keyboardTookHighlight(pointerAt: resting)
        let moved = CGPoint(x: 300, y: 200)
        let admitted7 = gate.admitsHover(pointerAt: moved)
        #expect(admitted7)
        gate.keyboardTookHighlight(pointerAt: moved)
        let admitted8 = gate.admitsHover(pointerAt: moved)
        #expect(!admitted8)
    }

    /// The gate is only worth anything if every row's hover goes through it: the list hands rows
    /// `onHover`, and the one place that answers it must ask the gate before writing the highlight.
    @Test func thePaletteRoutesEveryHoverThroughTheGate() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchView.swift")
        )
        let list = try #require(CadenceSourceScan.declarationBody("struct GlobalSearchHighlightList: View", in: source))
        let compact = list.filter { !$0.isWhitespace }
        #expect(compact.contains("onHover:hover,"))
        #expect(compact.contains("guardgate.admitsHover(pointerAt:NSEvent.mouseLocation)else{return}"))
        #expect(compact.components(separatedBy: "highlightedResultID=").count - 1 == 1)

        let overlay = try #require(CadenceSourceScan.declarationBody("struct GlobalSearchOverlay: View", in: source))
        let overlayCompact = overlay.filter { !$0.isWhitespace }
        #expect(overlayCompact.contains(".onMoveCommand{directioninkeyboardTookHighlight()"))
    }
}
#endif
