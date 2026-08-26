import Foundation
import Observation

/// A request to run the focus timer against `target`, made from a surface that is **not** the Focus
/// screen.
///
/// macOS says this with `FocusManager.startFocus(task:)` — one call that sets the session, starts
/// the clock and raises `wantsNavToFocus`. That singleton is deliberately macOS-only (T-242): iOS
/// keeps its stopwatch in `iOSFocusView`'s own `CadenceFocusTimerState`, so a cross-platform
/// `FocusManager` would be a second timer authority with nothing incrementing its `elapsed`. What
/// iOS was missing is not the manager but the *message* — a way for a task row or a block sheet to
/// name a subject and hand it over.
///
/// It carries a `CadenceFocusTarget` rather than a `UUID` for the reason that type exists: a bundle
/// and one of its own members are different sessions that equal ids cannot tell apart.
///
/// It lives in `Shared/` while having **zero** readers under `Cadence/macOS` — a pattern called out
/// in `docs/CLAUDE_REFERENCE.md` — and that is deliberate rather than an oversight: the decisions
/// it names (`timerState(startRequestFor:)`, `endSession(leaving:)`) are already there beside the
/// rest of `CadenceFocusSupport`, and `CadenceTests` is built for macOS, so a type parked under
/// `Cadence/iOS/` would be invisible to every test that pins it.
struct CadenceFocusHandoff: Identifiable, Equatable {
    let target: CadenceFocusTarget
    /// Two requests for the same subject are two separate events.
    ///
    /// Without it, asking to focus the task you are already focused on would be `Equatable`-equal
    /// to the request still sitting in the inbox, so the `onChange` that drives the navigation
    /// would not fire and the tap would do nothing. Same reason `CadenceDeepLinkManager.Route`
    /// carries one.
    let token: UUID

    var id: UUID { token }

    init(target: CadenceFocusTarget, token: UUID = UUID()) {
        self.target = target
        self.token = token
    }

    /// Where a handoff navigates. Read from the shared routing table rather than spelled here, so
    /// the compact shell's answer to "which tab owns Focus" has exactly one source.
    static let destination: CadenceFeatureDestination = .focus
}

/// The one-slot inbox a handoff passes through.
///
/// Same shape as `CadenceDeepLinkManager`, and for the same reason: the surface making the request
/// (a row inside a filtered `ForEach`, a sheet that is about to dismiss itself) cannot reach the
/// shell's navigation state, and the Focus screen it is handing to may not have been built yet.
/// Writers call `request(_:)` through `.shared`; the two views that *observe* it — `iOSRootView`,
/// which routes, and `iOSFocusView`, which adopts — read it from the environment.
///
/// It holds no clock and no session. Everything about what happens to an in-progress session lives
/// in `CadenceFocusSupport.commitElapsed(leaving:switchingTo:…)` and
/// `timerState(startRequestFor:…)`, where it is testable.
@Observable
final class CadenceFocusHandoffCenter {
    static let shared = CadenceFocusHandoffCenter()

    private(set) var pending: CadenceFocusHandoff?

    init() {}

    func request(_ target: CadenceFocusTarget) {
        pending = CadenceFocusHandoff(target: target)
    }

    /// Clear a handoff **by token**, so a request made while the previous one was being adopted is
    /// not swallowed by the adopter of the older one.
    func consume(_ handoff: CadenceFocusHandoff) {
        guard pending?.id == handoff.id else { return }
        pending = nil
    }
}
