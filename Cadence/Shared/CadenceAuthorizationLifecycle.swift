import SwiftUI

/// When a surface that shows a system permission re-derives it.
///
/// **T-253, then T-576.** This began as `RemindersAuthorizationLifecycle`, a hook written for the
/// four Apple Reminders surfaces after two of them turned out to carry only half of it. The rule it
/// encodes is not about EventKit: any card that says "access required" and sends the reader to
/// System Settings is stale the moment they come back, because macOS does not terminate the app on
/// a permission change and `.onAppear` does not fire a second time on a view that never
/// disappeared.
///
/// Settings → Notifications was the surface that proved it. macOS had **no** refresh of any kind —
/// deny, press "Enable Notifications", get sent to System Settings, enable, return, and the card
/// still read "Notification access required" until the next relaunch — and iOS had the appearance
/// half alone. So the hook is generic now rather than duplicated: one pair of lifecycle events, one
/// answer to which scene phase counts, and a thin `View` extension per permission that supplies its
/// own re-derive.
nonisolated enum CadenceAuthorizationLifecycle {
    /// Only a return to `.active` re-derives. `.inactive` and `.background` are the *leaving*
    /// halves of the same transition — re-reading the permission on the way out costs a query and
    /// tells the user nothing, because the change they are about to make has not happened yet.
    static func shouldRefresh(onScenePhaseChangeTo phase: ScenePhase) -> Bool {
        phase == .active
    }
}

/// The modifier itself. Applied by all four reminders surfaces and both notifications surfaces;
/// see `CadenceAuthorizationLifecycle` for why there is only one of it.
struct CadenceAuthorizationLifecycleModifier: ViewModifier {
    /// `false` where the host view exists on more than one page and only one of them shows the
    /// permission — the iOS Tasks page is All Tasks as well as Inbox, and touching EventKit from a
    /// page with no reminders surface on it is work with nothing behind it.
    let isEnabled: Bool

    /// The re-derive. A closure rather than a manager, because the two managers do not share a
    /// protocol and do not even agree on async-ness: `RemindersManager.refreshAuthorizationState()`
    /// is synchronous, `NotificationManager`'s is `async`. What they share is *when*, which is the
    /// part worth having once.
    let refresh: @MainActor () -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { refreshIfEnabled() }
            .onChange(of: scenePhase) { _, phase in
                guard CadenceAuthorizationLifecycle.shouldRefresh(onScenePhaseChangeTo: phase) else { return }
                refreshIfEnabled()
            }
    }

    /// Internal rather than private so a test can watch it happen: `RemindersManager` counts its
    /// own re-derives in `reconcileLedger`, so "disabled means no EventKit read" is an assertion
    /// about an effect rather than about the text of a view body.
    func refreshIfEnabled() {
        guard isEnabled else { return }
        refresh()
    }
}

extension View {
    /// Re-derive reminders authorization when this surface appears **and** whenever the app comes
    /// back to the foreground. See `CadenceAuthorizationLifecycle`.
    func remindersAuthorizationLifecycle(_ manager: RemindersManager, isEnabled: Bool = true) -> some View {
        modifier(
            CadenceAuthorizationLifecycleModifier(isEnabled: isEnabled) {
                manager.refreshAuthorizationState()
            }
        )
    }

    /// The same two halves for local notifications (T-576). macOS carried neither and iOS carried
    /// only the first, which is the exact gap this hook was built to close one permission over.
    ///
    /// `NotificationManager.refreshAuthorizationState()` is `async`, so the re-derive is spawned
    /// rather than awaited — nothing downstream reports success, the only effect is an
    /// `@Observable` flag the card re-reads, and a lifecycle event is not a place to suspend.
    func notificationsAuthorizationLifecycle(_ manager: NotificationManager, isEnabled: Bool = true) -> some View {
        modifier(
            CadenceAuthorizationLifecycleModifier(isEnabled: isEnabled) {
                Task { await manager.refreshAuthorizationState() }
            }
        )
    }
}
