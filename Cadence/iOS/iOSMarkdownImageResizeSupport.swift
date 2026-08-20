#if os(iOS)
import UIKit

/// A pan that only exists on an image's resize handle.
///
/// **The whole problem here is not stealing touches from the scroll view and the selection
/// gestures.** A plain `UIPanGestureRecognizer` added to a `UITextView` competes with both, and the
/// usual `panGestureRecognizer.require(toFail:)` fix makes every scroll in the note wait for a pan
/// that only decides at its 10pt movement threshold — a visible hitch on a gesture that had nothing
/// to do with images. Two rules keep it out of the way:
///
/// 1. **It fails at touch-down**, not at the movement threshold, whenever the touch did not land on
///    a handle. `touchesBegan` runs the hit test and goes straight to `.failed`, so the scroll
///    pan's failure requirement is satisfied within the same touch event and scrolling starts
///    exactly as it would with no recognizer attached. Almost every touch in a note takes this
///    path.
/// 2. **On a handle, direction decides.** The first 6pt of travel — below the ~10pt a pan needs to
///    begin — chooses: horizontal-dominant is a resize, vertical-dominant fails and hands the touch
///    back to the scroll view. A note scrolls vertically and never horizontally, so the two
///    meanings never overlap, and a finger that happens to start a scroll on top of a handle still
///    scrolls.
///
/// Selection is handled by refusing simultaneous recognition (see the coordinator): text selection
/// needs a ~0.5s stationary press, which a drag resolves long before, and if the two ever did meet
/// only one of them runs.
final class iOSMarkdownImageResizeGestureRecognizer: UIPanGestureRecognizer {
    struct Hit: Equatable {
        let id: UUID
        /// The width the picture is *currently drawn at*, which is what the drag adds its travel
        /// to. Reading the stored `displayWidth` instead would jump the moment the two differ —
        /// and they differ whenever the text column is narrower than the stored width.
        let startWidth: CGFloat
    }

    /// Supplied by the editor. Nil for a touch that is not on a resize handle.
    var handleHitTest: ((CGPoint) -> Hit?)?

    private(set) var hit: Hit?

    /// Travel, in points, before the gesture's direction is read. Deliberately under
    /// `UIPanGestureRecognizer`'s own begin threshold so the decision is made first.
    static let directionThreshold: CGFloat = 6

    private var startPoint: CGPoint = .zero
    private var didResolveDirection = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1,
              let touch = touches.first,
              let view,
              let hit = handleHitTest?(touch.location(in: view))
        else {
            state = .failed
            return
        }
        self.hit = hit
        didResolveDirection = false
        startPoint = touch.location(in: view)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !didResolveDirection, let touch = touches.first, let view {
            let point = touch.location(in: view)
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            if max(abs(dx), abs(dy)) >= Self.directionThreshold {
                guard abs(dx) > abs(dy) else {
                    state = .failed
                    return
                }
                didResolveDirection = true
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        hit = nil
        didResolveDirection = false
    }
}
#endif
