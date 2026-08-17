import CoreGraphics
import SwiftUI

/// Asserting a scroll position **once the lazy stack has actually laid out**.
///
/// A `@State` seeded in `init` is not a scroll position. It is the value a scroll position ought to
/// have, handed to `.scrollPosition(id:)` before the `LazyVStack`/`LazyHStack` under it has built a
/// single row. A lazy stack resolves an id against the rows it has, and at that moment it has none:
/// the offset comes out of estimates that are not yet estimates of anything, and the scroll lands
/// somewhere with no content. Nothing reports the failure, because nothing failed — the id was
/// simply asked for too early.
///
/// This is the third time the repo has paid for that shape. `ecaf80f` was `onAppear` →
/// `proxy.scrollTo(210)` into a 420-column board whose columns did not exist yet, and it landed the
/// Board seven months in the past. `8a316c4` built the month agenda on a `@State` seeded in `init`.
/// `42de745` found what that costs — Month → Agenda opens on a blank pane at iPad regular width, and
/// the only gesture that fixes it is stepping a month, because *that* re-assigns the same binding
/// after first layout — and left it for its own pass. This is that pass, and the rule is shared
/// rather than repaired in place:
///
/// **Seed the binding for the frame that can be right, and re-assert it once the stack reports that
/// it has laid out.** The seed is still worth having: where the initial resolution does work, the
/// first render is already correct instead of visibly corrected, and a board that starts at index 0
/// writes that index straight back into the selection, which is `ecaf80f` all over again.
///
/// Re-asserting has to be a *change*. Writing the target a second time is a no-op, because the
/// binding still holds it: a scroll that resolved to nothing never wrote anything back. So the
/// assertion releases the binding and drives it on the next turn of the run loop, which is the
/// transition `.scrollPosition(id:)` acts on.
enum CadenceLazyScrollAnchor {

    /// Whether the one-shot assertion is owed.
    ///
    /// `contentExtent` is the scroll view's content height (or width, on a horizontal board). Zero
    /// is the lazy stack before it has laid out anything — precisely the state whose scroll gets
    /// dropped — so a non-zero extent is a *signal* that layout has happened, not a delay standing
    /// in for one. `ecaf80f` had already tried the delay: a 0.08s guard meant to ignore the initial
    /// settle expired before the settle arrived, and the board wrote a garbage day into persisted
    /// state as though the user had scrolled there.
    ///
    /// Once is enough, and once is the point: after the first assertion the binding belongs to the
    /// finger, and re-asserting a target the user has scrolled away from would fight it.
    static func shouldAssert(hasAsserted: Bool, hasTarget: Bool, contentExtent: CGFloat) -> Bool {
        guard !hasAsserted, hasTarget else { return false }
        return contentExtent > 0
    }

    /// What a scroll view's *reported* position is worth.
    ///
    /// Asserting a position is only half the rule; the other half is not believing the readings that
    /// arrive before the assertion lands. A surface that scrolls itself and then adopts whatever
    /// position comes back has a race with two outcomes, and the losing one is silent: the report
    /// still in flight says the offset the layout started at, the surface takes it for a scroll the
    /// user performed, and writes a day the user never chose into persisted state. `ecaf80f` is that
    /// bug on the Board; `68d78ec`, `8a316c4` and the two the calendar rework hit mid-flight are the
    /// same shape; **T-70** — Week opening on Jan 18 against a real date of Aug 17 — is it again on
    /// the timed grid, which had the assertion and not this.
    ///
    /// The gate is a *confirmation*, not a delay: the first report that equals the target **is** the
    /// assertion arriving back, and everything before it is older than the assertion by definition.
    /// `ecaf80f` had already tried the delay — a 0.08s guard expired before the settle arrived.
    ///
    /// The two callers hold the target differently (Month's is a lazy-stack row id, the timed grid's
    /// is a column index derived from an offset), which is why this takes the comparison rather than
    /// doing the bookkeeping: it is generic over the position, and the flag stays `@State` where it
    /// belongs.
    enum PositionReport: Equatable {
        /// Older than the assertion. Drop it — it names where the layout happened to start.
        case ignore
        /// The assertion, arriving back. Believe every report from here on.
        case confirmsPlacement
        /// A real scroll. Read the date off it.
        case adopt
    }

    static func report<Position: Equatable>(
        _ reported: Position,
        target: Position,
        hasConfirmedPlacement: Bool
    ) -> PositionReport {
        if hasConfirmedPlacement { return .adopt }
        return reported == target ? .confirmsPlacement : .ignore
    }
}

extension View {
    /// Re-assert `position` to `target` once the scroll view under this modifier reports laid-out
    /// content.
    ///
    /// Seed the binding as well — this fixes the frame the seed could not; it does not replace it.
    /// `axis` is the scroll view's own axis, so the modifier watches the content extent that grows.
    func cadenceLazyScrollAnchor<ID: Hashable>(
        _ position: Binding<ID?>,
        target: ID?,
        axis: Axis = .vertical
    ) -> some View {
        modifier(CadenceLazyScrollAnchorModifier(position: position, target: target, axis: axis))
    }
}

private struct CadenceLazyScrollAnchorModifier<ID: Hashable>: ViewModifier {
    @Binding var position: ID?
    let target: ID?
    let axis: Axis
    @State private var hasAsserted = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                axis == .vertical ? geometry.contentSize.height : geometry.contentSize.width
            } action: { _, contentExtent in
                assertIfOwed(contentExtent: contentExtent)
            }
    }

    private func assertIfOwed(contentExtent: CGFloat) {
        guard CadenceLazyScrollAnchor.shouldAssert(
            hasAsserted: hasAsserted,
            hasTarget: target != nil,
            contentExtent: contentExtent
        ) else { return }

        hasAsserted = true
        // Two turns of the run loop, deliberately. `.scrollPosition(id:)` scrolls on a *change* of
        // the value bound to it, and the value it is already holding is the one we want — so a
        // single re-assignment would be read as "nothing happened".
        position = nil
        Task { @MainActor in
            position = target
        }
    }
}
