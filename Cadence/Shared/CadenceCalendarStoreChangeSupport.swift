import Foundation

/// What handling one `EKEventStoreChanged` notification actually did.
///
/// EventKit cannot be driven from a unit test — there is no way to make it post the notification,
/// and no way to revoke a grant mid-run — so the effects are counted here instead, the same way
/// `CadenceRemindersManager.reconcileLedger` makes its reconcile visible. A test can then watch a
/// store change happen against a stand-in manager rather than assert on the shape of the source.
nonisolated struct CadenceCalendarStoreChangeEffects: Equatable {
    var versionBumps = 0
    var authorizationRefreshes = 0
}

/// The one definition of what an EventKit store change has to do.
///
/// **T-323.** EventKit posts `EKEventStoreChanged` for two different things: an ordinary data
/// change (something created, edited or deleted, here or elsewhere), and the user granting or
/// revoking Calendar access in Settings while Cadence keeps running. A handler that only bumps a
/// version answers the first and misses the second, so `isAuthorized` stays stale-true until the
/// next launch — the same failure T-253 fixed for Reminders, where a permission was read once and
/// never re-derived. macOS's `CalendarManager` grew the two-step handler; `iOSCalendarManager`
/// incremented `storeVersion` and stopped there.
///
/// Both effects are parameters rather than two statements repeated at each call site, so a
/// platform cannot quietly keep half of the handler: dropping either one is a compile error, not
/// a behaviour difference nobody notices for a release.
nonisolated enum CadenceCalendarStoreChangeSupport {

    /// Bumps the store version, then re-derives authorization, and reports both.
    ///
    /// The order is deliberate. `refreshAuthorization` is the step that can tear the observer down
    /// (a revocation stops observing from inside the notification handler), so the version bump
    /// that tells every view to refetch is published first.
    @discardableResult
    static func apply(
        bumpVersion: () -> Void,
        refreshAuthorization: () -> Void
    ) -> CadenceCalendarStoreChangeEffects {
        var effects = CadenceCalendarStoreChangeEffects()
        bumpVersion()
        effects.versionBumps += 1
        refreshAuthorization()
        effects.authorizationRefreshes += 1
        return effects
    }
}
