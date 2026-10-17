#if os(iOS)
import SwiftUI

/// **Nothing is left of the Block panel but this modifier's name** ([[T-3170]]).
///
/// T-217 put the Block panel behind a host rather than behind the card that opened it: the card sat
/// in a `ForEach(bundles)` filtered by day — and by *hour* on Today's schedule pane — so the panel's
/// own Save moved the card out of the collection drawing it and SwiftUI tore the sheet down at the
/// moment the edit succeeded. The host outlived the card, which fixed it.
///
/// The Block feature is gone from every iOS surface, so there is no card, no panel and no selection
/// to hold. `iOSBundleInspectorPresentAction`, the `\.iOSBundleInspector` environment value,
/// `iOSBundleInspectorSheet` and `iOSCalendarBundleDetailSheet` are all deleted.
///
/// **This stub is a residue with a named owner, not a decision.** `iOSRootView.swift` applies
/// `.iOSBundleInspectorHost()` at the root and that file is Codex-leased, so the last line of the
/// Block panel cannot be deleted in the same pass as the panel. The next agent holding a grant on
/// `Cadence/iOS/iOSRootView.swift` deletes the call there and this file with it.
/// `CadenceBundleInspectorHostTests` pins that this is all that is left, so it cannot quietly
/// re-grow a subject.
extension View {
    /// Applies nothing. See the type note: it exists for one leased call site.
    func iOSBundleInspectorHost() -> some View { self }
}
#endif
