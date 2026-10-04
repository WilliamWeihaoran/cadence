#if os(iOS)
import SwiftUI
import UIKit

/// Keeps at most one row open across the whole app.
///
/// A plain class with a `static let shared`, not `@Observable` state, for the same reason
/// `SidebarDragContext` is one on macOS: every visible row would otherwise register an
/// observation on a value that changes only when somebody opens a row, and rows are the one thing
/// on these screens that exist twenty at a time. Rows hand in a closure that closes them; nobody
/// reads anything back.
@MainActor
final class iOSSwipeActionCoordinator {
    static let shared = iOSSwipeActionCoordinator()

    private var openRowID: UUID?
    private var closeOpenRow: (() -> Void)?

    private init() {}

    func rowDidOpen(id: UUID, close: @escaping () -> Void) {
        if let openRowID, openRowID != id {
            closeOpenRow?()
        }
        openRowID = id
        closeOpenRow = close
    }

    func rowDidClose(id: UUID) {
        guard openRowID == id else { return }
        openRowID = nil
        closeOpenRow = nil
    }
}

/// The one swipe container every task row uses, in a `List` and in a `ScrollView` alike.
///
/// `.swipeActions` could not be that container: it is a `List`-row modifier that SwiftUI discards
/// without complaint anywhere else, so the eight `ScrollView`-hosted task-row call sites had rows
/// that simply did not swipe while the `List`-hosted ones did. This draws its own tray and reads
/// its own `DragGesture`, so the host is irrelevant.
///
/// All of the arithmetic — reveal, rubber band, release, which action a full swipe commits —
/// is in `CadenceSwipeActionSupport`, which is outside `#if os(iOS)` and therefore testable by the
/// macOS-built `CadenceTests` target.
struct iOSSwipeActionsModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let leadingActions: [CadenceSwipeAction]
    let trailingActions: [CadenceSwipeAction]
    var metrics: CadenceSwipeActionMetrics = .standard

    @State private var rowID = UUID()
    /// The finger's travel, uncapped. Thresholds read this rather than the drawn offset because
    /// the drawn offset is deliberately rubber-band-capped and would put a full swipe out of reach.
    @State private var rawOffset: CGFloat = 0
    /// What the row is actually drawn at.
    @State private var offset: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    @State private var isFullSwipeArmed = false

    func body(content: Content) -> some View {
        ZStack {
            actionTray
                .allowsHitTesting(!isClosed)

            content
                .accessibilityActions {
                    // Swipe must never be the only route. The context menu is the other one; this
                    // is what puts the same four actions in VoiceOver's rotor.
                    ForEach(leadingActions) { action in
                        Button(action.title) { action.perform() }
                    }
                    ForEach(trailingActions) { action in
                        Button(action.title) { action.perform() }
                    }
                }
                // Before `.offset`, not after, and the ordering is load-bearing. `.offset` shifts
                // rendering and hit testing but *not* layout bounds, so an overlay attached
                // afterwards is sized and placed against the row's unshifted frame — it would sit
                // across the whole row including the strip the tray occupies, swallow every tap
                // meant for an action button, and merely close the row. It did exactly that.
                .overlay {
                    // An open row's tap closes it instead of falling through to the row's own tap,
                    // which would open the detail sheet the user was not reaching for.
                    if !isClosed {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                .offset(x: offset)
        }
        .frame(minHeight: iOSTaskPageTypographyMetrics.swipeTrayHeight(at: dynamicTypeSize, scaling: scaling))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { rowWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in rowWidth = width }
            }
        }
        .clipped()
        // **A `DragGesture` here cannot give a vertical drag back, so there is no `DragGesture`
        // here any more** (T-2059). Measured on the simulator 2026-10-04: one upward 168pt drag
        // starting on a row scrolled the page when its opening sample was dead vertical and
        // scrolled *nothing at all* when the same path opened with 14pt of sideways travel. That
        // is the owner's "scrolling in the tasks page sometimes doesn't work", and the
        // intermittence is just whether the first few points of a thumb's arc happen to be
        // straight. Every SwiftUI-side lever was ruled out by its own build: `.highPriorityGesture`,
        // `.simultaneousGesture` and `minimumDistance: 30` all stayed dead, and the page scrolled
        // again only when the drag gesture itself was switched off. Returning early out of
        // `onChanged` does not hand the touch back, and neither does deciding the drag is vertical:
        // by then the enclosing `ScrollView`'s pan has already stood down for this touch.
        //
        // A `UIGestureRecognizer` can say the one thing `DragGesture` cannot — *I refuse this
        // touch* — while it is still `.possible`, which is before the scroll view is asked to give
        // way. So the axis test moved into `iOSRowHorizontalPanRecognizer`, where it is enforceable,
        // and a vertical drag now scrolls exactly as if this row carried no gesture.
        //
        // This also keeps the bug the old `.simultaneousGesture` shipped from coming back: a swipe
        // begun on the completion circle *completed the task*, because the button stayed tracking
        // and rode along with the offset content so it never saw the finger leave. A UIKit
        // recognizer cancels the touches it takes over (`cancelsTouchesInView`), so the button
        // stops tracking the moment the swipe is claimed — and a plain tap never reaches the
        // decision distance, so tapping the circle and tapping the row still work.
        .gesture(
            iOSRowHorizontalPan(
                metrics: metrics,
                onChanged: { dragChanged(translation: $0) },
                onEnded: { dragEnded(translation: $0, velocity: $1) },
                onCancelled: { dragCancelled() }
            )
        )
    }

    // MARK: - Tray

    private var isClosed: Bool {
        offset == 0
    }

    private var visibleEdge: CadenceSwipeEdge? {
        guard offset != 0 else { return nil }
        return offset > 0 ? .leading : .trailing
    }

    private func actions(for edge: CadenceSwipeEdge) -> [CadenceSwipeAction] {
        edge == .leading ? leadingActions : trailingActions
    }

    private func destructiveFlags(for edge: CadenceSwipeEdge) -> [Bool] {
        actions(for: edge).map(\.isDestructive)
    }

    @ViewBuilder
    private var actionTray: some View {
        if let visibleEdge {
            let edgeActions = actions(for: visibleEdge)
            let widths = CadenceSwipeActionSupport.actionWidths(
                revealedWidth: abs(offset),
                actionCount: edgeActions.count,
                fullSwipeIndex: isFullSwipeArmed
                    ? CadenceSwipeActionSupport.fullSwipeIndex(isDestructive: destructiveFlags(for: visibleEdge))
                    : nil
            )
            // The first-declared action sits *on* the swiped-from edge, which is also the one a
            // full swipe commits — so the action that expands is the one already under the finger.
            let ordered = Array(zip(edgeActions, widths))
            let laidOut = visibleEdge == .leading ? ordered : ordered.reversed()

            HStack(spacing: 0) {
                if visibleEdge == .trailing {
                    Spacer(minLength: 0)
                }

                ForEach(Array(laidOut), id: \.0.id) { action, width in
                    actionButton(action, width: width)
                }

                if visibleEdge == .leading {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func actionButton(_ action: CadenceSwipeAction, width: CGFloat) -> some View {
        Button {
            perform(action)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .cadenceFont(.metadata, base: 16, weight: .semibold)
                if !iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling) {
                    Text(action.title)
                        .cadenceFont(.metadata, base: 11, weight: .semibold)
                        .lineLimit(iOSTaskPageTypographyMetrics.swipeLabelLineLimit(at: dynamicTypeSize, scaling: scaling))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(Theme.onColor(for: action.tint))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(action.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .clipped()
    }

    // MARK: - Gesture

    /// Only ever called for a drag the recognizer has already decided is horizontal.
    private func dragChanged(translation: CGSize) {
        // Always recomputed from `restingOffset`, which only `open`/`close` ever write.
        // That makes an interrupted drag self-healing: whatever offset it stranded, the
        // next drag snaps back to a settled position instead of accumulating drift.
        let raw = restingOffset + translation.width
        rawOffset = raw
        offset = CadenceSwipeActionSupport.resolvedOffset(
            rawOffset: raw,
            leadingActionCount: leadingActions.count,
            trailingActionCount: trailingActions.count,
            metrics: metrics
        )
        isFullSwipeArmed = CadenceSwipeActionSupport.isFullSwipeArmed(
            rawOffset: raw,
            rowWidth: rowWidth,
            leadingActionCount: leadingActions.count,
            trailingActionCount: trailingActions.count,
            leadingIsDestructive: leadingActions.map(\.isDestructive),
            trailingIsDestructive: trailingActions.map(\.isDestructive),
            metrics: metrics
        )
    }

    private func dragEnded(translation: CGSize, velocity: CGFloat) {
        let outcome = CadenceSwipeActionSupport.release(
            rawOffset: restingOffset + translation.width,
            velocity: velocity,
            rowWidth: rowWidth,
            leadingActionCount: leadingActions.count,
            trailingActionCount: trailingActions.count,
            leadingIsDestructive: leadingActions.map(\.isDestructive),
            trailingIsDestructive: trailingActions.map(\.isDestructive),
            metrics: metrics
        )

        switch outcome {
        case .closed:
            close()
        case .open(let edge):
            open(edge)
        case .fullSwipe(let edge):
            commitFullSwipe(edge)
        }
    }

    /// A cancelled drag never reaches `dragEnded`, so without this the row would keep whatever
    /// half-revealed offset the interruption stranded it at. Settling on `restingOffset` — the
    /// only value `open`/`close` ever write — puts it back on a position the row actually has.
    private func dragCancelled() {
        guard restingOffset != 0 else {
            close()
            return
        }
        open(restingOffset > 0 ? .leading : .trailing)
    }

    // MARK: - State transitions

    private func open(_ edge: CadenceSwipeEdge) {
        let width = CadenceSwipeActionSupport.openWidth(
            actionCount: actions(for: edge).count,
            metrics: metrics
        )
        let target = width * edge.direction
        isFullSwipeArmed = false
        restingOffset = target
        rawOffset = target
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            offset = target
        }
        iOSSwipeActionCoordinator.shared.rowDidOpen(id: rowID) { close() }
    }

    private func close() {
        isFullSwipeArmed = false
        restingOffset = 0
        rawOffset = 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            offset = 0
        }
        iOSSwipeActionCoordinator.shared.rowDidClose(id: rowID)
    }

    private func commitFullSwipe(_ edge: CadenceSwipeEdge) {
        let edgeActions = actions(for: edge)
        guard
            let index = CadenceSwipeActionSupport.fullSwipeIndex(isDestructive: destructiveFlags(for: edge)),
            index < edgeActions.count
        else {
            close()
            return
        }
        perform(edgeActions[index])
    }

    private func perform(_ action: CadenceSwipeAction) {
        close()
        action.perform()
    }
}

/// The axis arbitration, in the one place it can be enforced.
///
/// `DragGesture` has no way to decline a touch: by the time its `onChanged` can look at the
/// translation, the enclosing `ScrollView` has already given the touch up for good. A
/// `UIGestureRecognizer` fails itself while it is still `.possible`, which the scroll view's own
/// pan treats as "never happened" — so a vertical drag over a row scrolls the page.
///
/// It holds no geometry of its own: the direction test is
/// `CadenceSwipeActionSupport.isHorizontal`, the same function the macOS-built `CadenceTests`
/// target already pins, so the threshold has exactly one definition.
final class iOSRowHorizontalPanRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// The finger's travel since touch-down, in this row's own coordinates.
    private(set) var translation: CGSize = .zero
    /// Horizontal speed in points per second, which is what `release` arbitrates a flick on.
    private(set) var horizontalVelocity: CGFloat = 0

    var metrics: CadenceSwipeActionMetrics = .standard

    private var startLocation: CGPoint = .zero
    private var lastLocation: CGPoint = .zero
    private var lastTimestamp: TimeInterval = 0

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // The arbitration this recognizer needs is not the same against the scroll view as against
        // the row's own controls, and both halves were measured rather than assumed.
        delegate = self
    }

    /// The scroll view's pan must keep tracking while this recognizer is still undecided —
    /// that is the whole point of failing from `.possible` — but the row's own controls must not.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        other is UIPanGestureRecognizer
    }

    /// **A swipe begun on a chip must be a swipe.** Measured: with no relationship at all, an
    /// identical 260pt swipe left committed the full swipe from the row's text and was *ignored*
    /// from the "45m" estimate chip — which sits at the trailing edge, exactly where a
    /// right-to-left swipe starts. Letting the two recognize simultaneously fixed that and
    /// re-opened the bug this container was built to close: the swipe opened the tray *and* the
    /// chip's popover. So the control waits for this recognizer instead. On a tap there is no
    /// movement, this fails at touch-up, and the control fires as it always did.
    ///
    /// The scroll view is exempt: making a vertical pan wait on a row would undo the fix above.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        !(other is UIPanGestureRecognizer)
    }

    override func reset() {
        super.reset()
        translation = .zero
        horizontalVelocity = 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard numberOfTouches == 1, let touch = touches.first else {
            // A second finger is a pinch or a system gesture, never a row swipe.
            state = .failed
            return
        }
        startLocation = touch.location(in: view)
        lastLocation = startLocation
        lastTimestamp = touch.timestamp
        translation = .zero
        horizontalVelocity = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }

        let location = touch.location(in: view)
        translation = CGSize(
            width: location.x - startLocation.x,
            height: location.y - startLocation.y
        )

        let elapsed = touch.timestamp - lastTimestamp
        if elapsed > 0 {
            horizontalVelocity = (location.x - lastLocation.x) / CGFloat(elapsed)
        }
        lastLocation = location
        lastTimestamp = touch.timestamp

        switch state {
        case .possible:
            // The decision itself is `CadenceSwipeActionSupport.axisClaim`, where the macOS-built
            // test target can reach it. All this adds is the thing only a UIKit recognizer can do:
            // `.failed` from `.possible` never asks the scroll view's pan to stand down, so a drag
            // this row declines scrolls the page as if the row carried no gesture at all.
            switch CadenceSwipeActionSupport.axisClaim(translation: translation, metrics: metrics) {
            case .horizontal: state = .began
            case .vertical: state = .failed
            case .undecided: break
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }
}

/// Bridges `iOSRowHorizontalPanRecognizer` into the row. `.gesture` is the only priority this
/// bridge offers and it is the right one: UIKit arbitration, not SwiftUI's, is what decides
/// between this recognizer and the row's own controls.
private struct iOSRowHorizontalPan: UIGestureRecognizerRepresentable {
    typealias UIGestureRecognizerType = iOSRowHorizontalPanRecognizer
    typealias Coordinator = Void

    var metrics: CadenceSwipeActionMetrics
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize, CGFloat) -> Void
    var onCancelled: () -> Void

    func makeUIGestureRecognizer(
        context: UIGestureRecognizerRepresentableContext<iOSRowHorizontalPan>
    ) -> iOSRowHorizontalPanRecognizer {
        let recognizer = iOSRowHorizontalPanRecognizer()
        recognizer.metrics = metrics
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: iOSRowHorizontalPanRecognizer,
        context: UIGestureRecognizerRepresentableContext<iOSRowHorizontalPan>
    ) {
        recognizer.metrics = metrics
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: iOSRowHorizontalPanRecognizer,
        context: UIGestureRecognizerRepresentableContext<iOSRowHorizontalPan>
    ) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.translation)
        case .ended:
            onEnded(recognizer.translation, recognizer.horizontalVelocity)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }
}

extension View {
    /// Swipe actions that work in a `ScrollView` as well as in a `List`. Two actions an edge is
    /// the ceiling — a tray that needs a third is a context menu.
    func iOSSwipeActions(
        leading: [CadenceSwipeAction] = [],
        trailing: [CadenceSwipeAction] = []
    ) -> some View {
        modifier(iOSSwipeActionsModifier(leadingActions: leading, trailingActions: trailing))
    }
}
#endif
