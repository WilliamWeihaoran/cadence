import Foundation

/// What the two mobile shells are looking at, in one vocabulary, so a size-class change can carry
/// the answer across instead of dropping it.
///
/// The iPad sidebar shell and the iPhone tab shell keep their selections in separate stores — a
/// sidebar item on one side, a persisted tab plus Tasks segment on the other — and the root picks a
/// shell from `horizontalSizeClass`. Split View and Stage Manager make that switch an ordinary
/// gesture, so both stores are live and only one of them is being written. Nothing bridged them, so
/// Calendar on iPad narrowed into whatever tab was last tapped and compact Calendar widened back
/// into whatever row was last selected (T-334).
///
/// The forward direction already existed and still has exactly one home:
/// `CadenceFeatureDestination.compactRoute`. This is the **inverse** — the compact shell's state
/// read back as a destination — plus the one rule about which stack's contents may answer.
///
/// It lives in `Shared/` because `Cadence/iOS/` is entirely inside `#if os(iOS)` and therefore
/// invisible to `CadenceTests`, which builds for macOS. A projection that silently answers the
/// wrong screen is precisely the kind of table that has to be pinned rather than eyeballed, and
/// `CadenceSizeClassNavigationTests` pins the round trip in both directions.
nonisolated enum CadenceShellNavigationBridge {
    /// The feature the compact shell is currently showing, or `nil` when it is showing something
    /// the sidebar has no row for.
    ///
    /// `pushedDestination` is what sits on top of the selected tab's stack, when that is a feature
    /// screen at all — a tab's stack can equally be holding an `iOSListRoute`, and the root passes
    /// `nil` in that case. A push is only allowed to answer for the tab that owns it: a stale value
    /// recorded against another tab must not out-vote the tab the user is actually on, which is the
    /// same class of mistake this whole type exists to close.
    static func visibleDestination(
        tab: CadenceCompactTab,
        tasksSection: CadenceTasksSection,
        pushedDestination: CadenceFeatureDestination? = nil
    ) -> CadenceFeatureDestination? {
        if let pushedDestination, pushedDestination.compactTab == tab {
            return pushedDestination
        }
        return tab.rootDestination(tasksSection: tasksSection)
    }

    /// The same question asked of a whole route, which is how the round trip against
    /// `CadenceFeatureDestination.compactRoute` is stated.
    static func visibleDestination(
        for route: CadenceCompactRoute,
        tasksSection: CadenceTasksSection = .defaultSection
    ) -> CadenceFeatureDestination? {
        visibleDestination(
            tab: route.tab,
            tasksSection: route.tasksSection ?? tasksSection,
            pushedDestination: route.pushedDestination
        )
    }
}

nonisolated extension CadenceCompactTab {
    /// The destination a tab shows with nothing pushed, or `nil` for More.
    ///
    /// More is deliberately `nil` rather than being given a stand-in. Its root is a menu of every
    /// other destination, and the sidebar *is* that menu at regular width — there is no row to
    /// point at, so widening out of the More list leaves the sidebar wherever it already was rather
    /// than inventing a screen the user never chose.
    func rootDestination(tasksSection: CadenceTasksSection) -> CadenceFeatureDestination? {
        switch self {
        case .tasks: return tasksSection.destination
        case .calendar: return .calendar
        case .notes: return .notes
        case .more: return nil
        }
    }
}
