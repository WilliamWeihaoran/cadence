#if os(iOS)
import SwiftUI

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
    let leadingActions: [CadenceSwipeAction]
    let trailingActions: [CadenceSwipeAction]
    var metrics: CadenceSwipeActionMetrics = .standard

    /// Which axis this drag turned out to be. Undecided until the translation is unambiguous, so
    /// the row never claims a gesture the enclosing scroll view should have had.
    private enum DragClaim {
        case undecided
        case horizontal
        case vertical
    }

    @State private var rowID = UUID()
    /// The finger's travel, uncapped. Thresholds read this rather than the drawn offset because
    /// the drawn offset is deliberately rubber-band-capped and would put a full swipe out of reach.
    @State private var rawOffset: CGFloat = 0
    /// What the row is actually drawn at.
    @State private var offset: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    @State private var claim: DragClaim = .undecided
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
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { rowWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in rowWidth = width }
            }
        }
        .clipped()
        // `.highPriorityGesture`: outrank the row's **own** controls, never the scroll view above.
        //
        // `.simultaneousGesture` was the obvious choice and shipped a real bug — a swipe begun on
        // the completion circle *completed the task*. The button stays tracking under a
        // simultaneous drag, and because it rides along with the offset content it never sees the
        // finger leave its bounds, so it fired on release 190pt from where it started. Gating the
        // content's `allowsHitTesting` on the claim did not help: hit testing is resolved at
        // touch-down, and the button had already taken the touch. Both verified on device.
        //
        // High priority denies descendants the gesture outright, which is the semantic actually
        // wanted here. It does not contest the enclosing `ScrollView`/`List` pan — that is a
        // separate arbitration — and `minimumDistance` means a plain tap never reaches this
        // gesture at all, so the completion circle and the row's detail tap still work. Vertical
        // scrolling was re-verified on Today, Inbox, and All Tasks after this change.
        .highPriorityGesture(dragGesture)
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
                    .font(.system(size: 16, weight: .semibold))
                Text(action.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.onColor)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(action.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipped()
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if claim == .undecided {
                    if CadenceSwipeActionSupport.isHorizontal(translation: value.translation, metrics: metrics) {
                        claim = .horizontal
                    } else if abs(value.translation.height) > abs(value.translation.width) {
                        claim = .vertical
                    }
                }
                guard claim == .horizontal else { return }

                // Always recomputed from `restingOffset`, which only `open`/`close` ever write.
                // That makes an interrupted drag self-healing: whatever offset it stranded, the
                // next drag snaps back to a settled position instead of accumulating drift.
                let raw = restingOffset + value.translation.width
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
            .onEnded { value in
                defer { claim = .undecided }
                guard claim == .horizontal else { return }

                let outcome = CadenceSwipeActionSupport.release(
                    rawOffset: restingOffset + value.translation.width,
                    velocity: value.velocity.width,
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
