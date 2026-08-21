#if os(iOS)
import SwiftData
import SwiftUI

/// T-201. **The task inspector is presented by a host, never by a row.**
///
/// `iOSTaskDetailSheet` used to be presented by `iOSTaskRow` — `@State showDetail` plus
/// `.sheet(isPresented:)` on the row itself. A row lives inside a filtered `ForEach`, so any write
/// that changes which group a task belongs to removes the row, and a sheet is torn down with the
/// view that presents it. Cancel, Restore and mark-done all did that; **Start** did not, only because
/// an in-progress task stays in the same section. That asymmetry is what proved no status path was
/// calling `dismiss()` — the fix is ownership, not a missing guard.
///
/// So presentation moves to a host whose lifetime outlives any row's. `iOSRootView` applies it once,
/// above both shells, exactly as it applies `cadenceStartupIssueBanner` — one call rather than one
/// per page, because "every page has a host" is a property worth having by construction instead of
/// by remembering. A page or sheet that needs a nearer owner can apply its own; the environment
/// resolves to the innermost one.
///
/// **What is deliberately not converted.** Four other surfaces present `iOSTaskDetailSheet`, and all
/// four already own their presentation on a view that does not re-filter under it —
/// `iOSSearchView`, `iOSMarkdownEditingSurface`, `iOSMarkdownReferenceSupport` and
/// `iOSCalendarBundleDetailSheet`, each with a `.sheet(item:)` on the surface. Three of those present
/// from *inside* a sheet, where a host above the sheet is the wrong owner: it is already presenting,
/// so a second request from it would do nothing at all. Converting them would trade a correct
/// pattern for a broken one in the name of uniformity.
///
/// What *was* converted is the set that owned presentation from a row or a card: `iOSTaskRow`,
/// `iOSBoardTaskCard`, `iOSTimelineTaskBlock` and Today's `iOSScheduleReadyTaskRow`.

/// Opens the task inspector on the nearest host. Written as a callable action rather than a binding
/// so a call site cannot hold the selection, which is the whole point of the change.
nonisolated struct iOSTaskInspectorPresentAction {
    private let present: (@MainActor (AppTask) -> Void)?

    init(present: (@MainActor (AppTask) -> Void)? = nil) {
        self.present = present
    }

    /// A missing host asserts in debug rather than failing silently. It cannot happen through
    /// `iOSRootView`, which is every route into this UI; the assertion is here so that if some
    /// future surface is built outside it, the dead tap is loud during development instead of
    /// being reported as "tapping the row does nothing".
    @MainActor
    func callAsFunction(_ task: AppTask) {
        guard let present else {
            assertionFailure("No iOSTaskInspectorHost above this view — the inspector cannot open")
            return
        }
        present(task)
    }
}

private struct iOSTaskInspectorHostKey: EnvironmentKey {
    static var defaultValue: iOSTaskInspectorPresentAction { iOSTaskInspectorPresentAction() }
}

extension EnvironmentValues {
    var iOSTaskInspector: iOSTaskInspectorPresentAction {
        get { self[iOSTaskInspectorHostKey.self] }
        set { self[iOSTaskInspectorHostKey.self] = newValue }
    }
}

private struct iOSTaskInspectorHostModifier: ViewModifier {
    @State private var selection: AppTask?

    func body(content: Content) -> some View {
        content
            .environment(\.iOSTaskInspector, iOSTaskInspectorPresentAction { selection = $0 })
            .sheet(item: $selection) { task in
                iOSTaskInspectorSheet(task: task) { selection = nil }
            }
    }
}

/// The selection outliving the row is the fix; the selection outliving the *model* is the sharp edge
/// that comes with it. `CadenceTaskInspectorPresentation` — in `Shared/`, where the macOS-built test
/// target can reach it — is where that decision lives: a task that has merely left the page's query
/// keeps its panel, a deleted one closes it.
private struct iOSTaskInspectorSheet: View {
    @Bindable var task: AppTask
    let close: () -> Void

    var body: some View {
        switch CadenceTaskInspectorPresentation.resolveHeldTask(
            isDeleted: task.isDeleted,
            hasNoModelContext: task.modelContext == nil
        ) {
        case .stay:
            iOSTaskDetailSheet(task: task)
        case .close:
            // Nothing to draw and nothing to bind to. `onAppear` rather than a synchronous clear:
            // the selection cannot be written during the body evaluation that reads it.
            Color.clear.onAppear(perform: close)
        }
    }
}

extension View {
    /// Gives everything below it one task inspector, presented above the page rather than by a row.
    func iOSTaskInspectorHost() -> some View {
        modifier(iOSTaskInspectorHostModifier())
    }
}
#endif
