import Foundation
import SwiftUI

/// The pure half of the row swipe gesture: how far a drag reveals, whether releasing opens,
/// closes, or commits a full swipe, and which action a full swipe runs.
///
/// It lives here, not beside the iOS container that draws it, for one reason: everything under
/// `Cadence/iOS/` is wrapped in `#if os(iOS)` and therefore invisible to the macOS-built
/// `CadenceTests` target. Swipe arithmetic — rubber-banding, velocity arbitration, threshold
/// crossing — is exactly the kind of thing that should be pinned by tests rather than by a
/// screenshot, so the arithmetic is here and only the `DragGesture` plumbing is over there.
///
/// This replaced `.swipeActions`, which is a `List`-row modifier that SwiftUI silently discards
/// anywhere else — half the task-row call sites render inside a `ScrollView`/`LazyVStack`, so the
/// same row swiped on one screen and not on another.

/// Which side of the row is being revealed. Positive offsets reveal the leading edge (the row
/// moves right), negative offsets reveal the trailing edge.
nonisolated enum CadenceSwipeEdge: Equatable, Hashable {
    case leading
    case trailing

    /// The sign a drag on this edge travels in, so distance math can stay unsigned.
    var direction: CGFloat {
        self == .leading ? 1 : -1
    }
}

/// What a drag in progress has turned out to be. `undecided` is not a failure: it is the state a
/// drag is in before either axis has travelled far enough to mean anything, and the row draws
/// nothing while it lasts.
nonisolated enum CadenceSwipeAxisClaim: Equatable {
    case undecided
    case horizontal
    case vertical
}

/// What releasing the finger means. Kept separate from "which edge is open" because a full swipe
/// is a one-shot commit, not a resting state.
nonisolated enum CadenceSwipeRelease: Equatable {
    case closed
    case open(CadenceSwipeEdge)
    case fullSwipe(CadenceSwipeEdge)
}

/// One swipe action: what it says, what it looks like, and what it does.
///
/// `tint` is a `Theme` colour at every call site — the type takes a `Color` rather than a
/// `Theme` case so the value stays dumb, but no call site should be inventing one.
struct CadenceSwipeAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    /// A destructive action is never the one a full swipe commits — see `fullSwipeIndex`. It also
    /// must not perform the destruction itself; `perform` should raise the row's existing
    /// confirmation.
    let isDestructive: Bool
    let perform: () -> Void

    init(
        id: String,
        title: String,
        systemImage: String,
        tint: Color,
        isDestructive: Bool = false,
        perform: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isDestructive = isDestructive
        self.perform = perform
    }
}

/// Tunable geometry. Defaults are `.standard`; the type exists so tests can pin behaviour against
/// numbers they name rather than against whatever the container happens to use today.
nonisolated struct CadenceSwipeActionMetrics: Equatable {
    /// Wide enough that a single action is well past the 44pt touch minimum even when two of them
    /// share a partially-revealed tray.
    var actionWidth: CGFloat = 76
    /// How far past fully-open the row can be dragged. The reveal approaches this asymptotically,
    /// so the row never stops responding to the finger but also never runs away.
    var rubberBandLimit: CGFloat = 56
    /// Fraction of the fully-open width a release has to have travelled to stay open.
    var openCommitFraction: CGFloat = 0.5
    /// Fraction of the row's own width a release has to have travelled to commit a full swipe.
    var fullSwipeFraction: CGFloat = 0.55
    /// A full swipe also has to clear this multiple of the open width, so a narrow row (an iPad
    /// column, a compact inspector) cannot make a full swipe easier to hit than merely opening.
    var fullSwipeOpenWidthMultiple: CGFloat = 1.5
    /// Points per second. A flick this fast decides the release on its own, in whichever
    /// direction it points.
    var velocityCommit: CGFloat = 320
    /// How much more horizontal than vertical a drag has to be before the row claims it. Anything
    /// flatter than this belongs to the enclosing scroll view.
    var horizontalClaimRatio: CGFloat = 1.4
    /// How far the finger has to travel **along one axis** before that axis may claim the drag.
    ///
    /// The ratio above is only half the arbitration; this is the other half, and it is the one the
    /// owner's "scrolling sometimes doesn't work" turned on (T-2059). A thumb swiping up the page
    /// pivots at its base, so the opening points of its arc are sideways even though the gesture is
    /// a scroll: read the axis at 12pt and that drag is *horizontal*, read it at 24 and it is
    /// vertical, and only the second reading is what the user meant. A deliberate swipe travels
    /// 76pt to open a single action, so waiting for 24 costs it nothing.
    var claimDistance: CGFloat = 24

    static let standard = CadenceSwipeActionMetrics()
}

nonisolated enum CadenceSwipeActionSupport {
    // MARK: - Geometry

    /// Width of the tray when an edge is fully open. Zero actions means the edge does not open at
    /// all, which is how a row with only one populated edge refuses to move the other way.
    static func openWidth(
        actionCount: Int,
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> CGFloat {
        guard actionCount > 0 else { return 0 }
        return CGFloat(actionCount) * metrics.actionWidth
    }

    /// The asymptotic give past fully-open: starts at slope 1 so the row keeps tracking the finger
    /// exactly at the moment it passes the stop, then tapers to `limit` and never exceeds it.
    static func rubberBand(excess: CGFloat, limit: CGFloat) -> CGFloat {
        guard excess > 0, limit > 0 else { return 0 }
        return limit * (1 - exp(-excess / limit))
    }

    /// Turns the finger's raw travel into the row's actual x offset: clamped to the open width,
    /// then rubber-banded past it, and pinned to zero on an edge that has no actions.
    static func resolvedOffset(
        rawOffset: CGFloat,
        leadingActionCount: Int,
        trailingActionCount: Int,
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> CGFloat {
        guard rawOffset != 0 else { return 0 }
        let edge: CadenceSwipeEdge = rawOffset > 0 ? .leading : .trailing
        let count = edge == .leading ? leadingActionCount : trailingActionCount
        guard count > 0 else { return 0 }

        let open = openWidth(actionCount: count, metrics: metrics)
        let distance = abs(rawOffset)
        let resolved = distance <= open
            ? distance
            : open + rubberBand(excess: distance - open, limit: metrics.rubberBandLimit)
        return resolved * edge.direction
    }

    /// How wide the visible tray is — the magnitude of `resolvedOffset`, named for what it draws.
    static func revealedWidth(
        rawOffset: CGFloat,
        leadingActionCount: Int,
        trailingActionCount: Int,
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> CGFloat {
        abs(resolvedOffset(
            rawOffset: rawOffset,
            leadingActionCount: leadingActionCount,
            trailingActionCount: trailingActionCount,
            metrics: metrics
        ))
    }

    /// Measured against the finger's raw travel rather than the rubber-banded reveal: the reveal
    /// is deliberately capped, so if the threshold were expressed in revealed points a full swipe
    /// would become unreachable.
    static func fullSwipeThreshold(
        rowWidth: CGFloat,
        actionCount: Int,
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> CGFloat {
        let open = openWidth(actionCount: actionCount, metrics: metrics)
        return max(rowWidth * metrics.fullSwipeFraction, open * metrics.fullSwipeOpenWidthMultiple)
    }

    /// True while a drag has travelled far enough that letting go now would commit the full swipe.
    /// The container uses this to expand the committed action across the whole tray, which is the
    /// only signal the user gets once the reveal itself has stopped growing.
    static func isFullSwipeArmed(
        rawOffset: CGFloat,
        rowWidth: CGFloat,
        leadingActionCount: Int,
        trailingActionCount: Int,
        leadingIsDestructive: [Bool],
        trailingIsDestructive: [Bool],
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> Bool {
        guard rawOffset != 0 else { return false }
        let edge: CadenceSwipeEdge = rawOffset > 0 ? .leading : .trailing
        let count = edge == .leading ? leadingActionCount : trailingActionCount
        guard count > 0 else { return false }
        let destructive = edge == .leading ? leadingIsDestructive : trailingIsDestructive
        guard fullSwipeIndex(isDestructive: destructive) != nil else { return false }

        let threshold = fullSwipeThreshold(rowWidth: rowWidth, actionCount: count, metrics: metrics)
        return abs(rawOffset) >= threshold
    }

    // MARK: - Release

    /// The whole release decision in one place: distance decides, and a fast flick overrides
    /// distance in whichever direction it points — including *back*, so a long drag that ends in a
    /// snap toward closed does not fire an action the user was visibly abandoning.
    static func release(
        rawOffset: CGFloat,
        velocity: CGFloat,
        rowWidth: CGFloat,
        leadingActionCount: Int,
        trailingActionCount: Int,
        leadingIsDestructive: [Bool],
        trailingIsDestructive: [Bool],
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> CadenceSwipeRelease {
        guard rawOffset != 0 else { return .closed }
        let edge: CadenceSwipeEdge = rawOffset > 0 ? .leading : .trailing
        let count = edge == .leading ? leadingActionCount : trailingActionCount
        guard count > 0 else { return .closed }

        let distance = abs(rawOffset)
        // Signed so that "toward open" is always positive regardless of which edge is showing.
        let directedVelocity = velocity * edge.direction

        if directedVelocity <= -metrics.velocityCommit { return .closed }

        let destructive = edge == .leading ? leadingIsDestructive : trailingIsDestructive
        let fullSwipeAvailable = fullSwipeIndex(isDestructive: destructive) != nil
        let fullThreshold = fullSwipeThreshold(rowWidth: rowWidth, actionCount: count, metrics: metrics)
        if fullSwipeAvailable, distance >= fullThreshold { return .fullSwipe(edge) }

        if directedVelocity >= metrics.velocityCommit { return .open(edge) }

        let open = openWidth(actionCount: count, metrics: metrics)
        return distance >= open * metrics.openCommitFraction ? .open(edge) : .closed
    }

    /// Which action a full swipe runs: always the edge's **first**, and never a destructive one.
    /// Trailing is `[Done, Delete]`, so a full swipe left toggles completion and cannot delete;
    /// an edge whose first action is destructive simply has no full swipe rather than a
    /// surprising one.
    static func fullSwipeIndex(isDestructive: [Bool]) -> Int? {
        guard let first = isDestructive.first, !first else { return nil }
        return 0
    }

    // MARK: - Layout

    /// Splits the revealed tray between the actions. While a full swipe is armed the committed
    /// action takes the whole width and the others collapse — the tray becomes a preview of what
    /// letting go will do.
    static func actionWidths(
        revealedWidth: CGFloat,
        actionCount: Int,
        fullSwipeIndex: Int?
    ) -> [CGFloat] {
        guard actionCount > 0 else { return [] }
        let width = max(0, revealedWidth)
        guard let fullSwipeIndex, fullSwipeIndex >= 0, fullSwipeIndex < actionCount else {
            return Array(repeating: width / CGFloat(actionCount), count: actionCount)
        }
        return (0..<actionCount).map { $0 == fullSwipeIndex ? width : 0 }
    }

    // MARK: - Gesture arbitration

    /// The whole axis decision: which way a drag has turned out to go, or that it is still too
    /// short to say.
    ///
    /// **`horizontalClaimRatio` decides the direction; `claimDistance` decides when.** The two
    /// branches below are mutually exclusive — they disagree about nothing, because both read the
    /// same ratio — and each waits only on the axis it is about. That is the part a single radius
    /// gets wrong: a radius reads the direction at whatever angle the finger happened to be at
    /// when it crossed the circle, which for an arcing thumb is its sideways opening rather than
    /// its intent, and 12pt of circle is nearly all opening.
    ///
    /// Note what this does **not** say: a drag that is horizontal by the ratio stays horizontal
    /// however far up the page it has also travelled. `(60, -40)` is a swipe. A test asserting
    /// otherwise was written here first and was wrong — the measured behaviour is this one.
    ///
    /// `vertical` and `undecided` both mean *the row does not take this touch*, and on iOS that
    /// distinction is enforced by `iOSRowHorizontalPanRecognizer` failing while it is still
    /// `.possible`. A SwiftUI `DragGesture` cannot express it: measured 2026-10-04, by the time its
    /// `onChanged` can look at the translation the enclosing `ScrollView` has already given the
    /// touch up for the rest of the gesture, at every gesture priority.
    static func axisClaim(
        translation: CGSize,
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> CadenceSwipeAxisClaim {
        let horizontal = isHorizontal(translation: translation, metrics: metrics)
        if abs(translation.height) >= metrics.claimDistance, !horizontal { return .vertical }
        if abs(translation.width) >= metrics.claimDistance, horizontal { return .horizontal }
        return .undecided
    }

    /// Whether a drag is horizontal enough for the row to claim it. Everything else is handed back
    /// to the enclosing `ScrollView`/`List`, which is what keeps vertical scrolling alive.
    static func isHorizontal(
        translation: CGSize,
        metrics: CadenceSwipeActionMetrics = .standard
    ) -> Bool {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard horizontal > 0 else { return false }
        return horizontal >= vertical * metrics.horizontalClaimRatio
    }
}
