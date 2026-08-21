#if os(iOS)
import SwiftData
import SwiftUI

/// T-217. **The bundle panel is presented by a host, never by a card.**
///
/// `iOSCalendarBundleDetailSheet` used to be presented by the card that opened it — `@State
/// showDetail` plus `.sheet(isPresented:)` on `iOSCalendarBoardBundleCard` and
/// `iOSTimelineBundleBlock`. Both live inside a `ForEach(bundles)` that has already been filtered by
/// day, and the timeline one is filtered by *hour* as well on Today's schedule pane, so the panel's
/// own Save — the one that writes a new date or start time — moved the card out of the collection
/// drawing it, SwiftUI removed the card, and the sheet went with it. Exactly T-201's defect on a
/// different sheet: the panel closed itself at the moment the edit succeeded, and nothing in the
/// panel called `dismiss()`.
///
/// So presentation moves to a host whose lifetime outlives any card's, applied once in `iOSRootView`
/// above both shells, beside `iOSTaskInspectorHost()` and for the same reason: "every page has a
/// host" is worth having by construction rather than by remembering.
///
/// **What is deliberately not converted.** Two other surfaces present this sheet, and both already
/// own their presentation on a view that does not re-filter under it: `iOSCalendarDayInspector` and
/// `iOSCalendarMonthAgendaList` each hold a `@State selectedBundle` and a `.sheet(item:)` on the
/// pane root, above the conditional that decides whether the pane has anything to list. A bundle
/// edited out of that day or month empties a section inside those panes; it does not remove the pane.
/// Converting them would trade a correct pattern for no gain — and unlike T-201's four exceptions,
/// neither of these presents from inside a sheet, so a host above them *would* work. They keep
/// ownership because ownership is not the bug there, not because a host could not reach them.
///
/// Note that `iOSCalendarBundleDetailSheet` itself presents `iOSTaskDetailSheet` from inside a sheet
/// — that one *is* one of T-201's deliberate exceptions, and it stays as it is.

/// Opens the bundle panel on the nearest host. Written as a callable action rather than a binding so
/// a call site cannot hold the selection, which is the whole point of the change.
nonisolated struct iOSBundleInspectorPresentAction {
    private let present: (@MainActor (TaskBundle) -> Void)?

    init(present: (@MainActor (TaskBundle) -> Void)? = nil) {
        self.present = present
    }

    /// A missing host asserts in debug rather than failing silently, exactly as the task inspector's
    /// action does: it cannot happen through `iOSRootView`, which is every route into this UI, and a
    /// surface built outside it should be loud during development instead of reported as "tapping the
    /// block does nothing".
    @MainActor
    func callAsFunction(_ bundle: TaskBundle) {
        guard let present else {
            assertionFailure("No iOSBundleInspectorHost above this view — the block panel cannot open")
            return
        }
        present(bundle)
    }
}

private struct iOSBundleInspectorHostKey: EnvironmentKey {
    static var defaultValue: iOSBundleInspectorPresentAction { iOSBundleInspectorPresentAction() }
}

extension EnvironmentValues {
    var iOSBundleInspector: iOSBundleInspectorPresentAction {
        get { self[iOSBundleInspectorHostKey.self] }
        set { self[iOSBundleInspectorHostKey.self] = newValue }
    }
}

private struct iOSBundleInspectorHostModifier: ViewModifier {
    @State private var selection: TaskBundle?

    func body(content: Content) -> some View {
        content
            .environment(\.iOSBundleInspector, iOSBundleInspectorPresentAction { selection = $0 })
            .sheet(item: $selection) { bundle in
                iOSBundleInspectorSheet(bundle: bundle) { selection = nil }
            }
    }
}

/// The selection outliving the card is the fix; the selection outliving the *model* is the sharp edge
/// that comes with it. `CadenceDetailPanelPresentation` — in `Shared/`, where the macOS-built test
/// target can reach it — is where that decision lives, and it is the same instance of it the task
/// inspector reads rather than a second copy: a bundle that has merely left the day's query keeps its
/// panel, a deleted one closes it.
private struct iOSBundleInspectorSheet: View {
    @Bindable var bundle: TaskBundle
    let close: () -> Void

    var body: some View {
        switch CadenceDetailPanelPresentation.resolveHeldSubject(
            isDeleted: bundle.isDeleted,
            hasNoModelContext: bundle.modelContext == nil
        ) {
        case .stay:
            iOSCalendarBundleDetailSheet(bundle: bundle)
        case .close:
            // Nothing to draw and nothing to bind to. `onAppear` rather than a synchronous clear:
            // the selection cannot be written during the body evaluation that reads it.
            Color.clear.onAppear(perform: close)
        }
    }
}

extension View {
    /// Gives everything below it one bundle panel, presented above the page rather than by a card.
    func iOSBundleInspectorHost() -> some View {
        modifier(iOSBundleInspectorHostModifier())
    }
}
#endif
