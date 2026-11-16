#if os(iOS)
import SwiftData
import SwiftUI

/// [[T-18227]]. **An editor a page opens for itself is presented by the root, not by the page.**
///
/// `iOSRootView` builds one of two whole shells from `horizontalSizeClass`, so a Split View or
/// Stage Manager resize across the compact/regular boundary destroys every view inside the shell
/// -- and SwiftUI dismisses any sheet such a view was presenting, half-typed draft and all. The
/// [[T-5174]] swipe guard never sees that dismissal. [[T-18157]] moved the capture composers and the
/// iPad sidebar's list editor above the switch; this host is the same move for the editors a page
/// opens from its own controls: the Lists page's New List, a list's Edit (Lists page, list detail,
/// the iPhone Tasks tab's list rows), Settings' New / Edit Context, and the Calendar's empty-slot
/// quick create. Each holds a draft in its own `@State`, which now lives as long as the root.
///
/// The shape is `iOSTaskInspectorHost`'s: a callable action in the environment, so a page cannot
/// hold the presentation; the request is `@State` on a modifier `iOSRootView` applies once, outside
/// the shell `Group`. Pinned by `CadenceShellSwapWiringTests`.
///
/// **One host, one editor at a time** -- the capture host's rule: a request that arrives while an
/// editor is up is dropped rather than swapped in, since replacing the item would throw the draft
/// on screen away. A page under a presented editor cannot be tapped, so nothing reaches that guard
/// by hand.
///
/// **What is not here, and why** -- the census is [[T-18227]]'s ledger entry; its residuals are
/// [[T-18252]].
enum iOSPageEditorRequest: Identifiable {
    /// New List / Edit, from a page or the iPad sidebar.
    case list(iOSSidebarListEditorRequest)
    /// Settings' New / Edit Context.
    case context(iOSContextEditorMode)
    /// The Calendar's tap on an empty day or slot. `press` makes every tap a new presentation, as
    /// the per-press id of the page's former seed did for a second tap on another slot.
    case calendarQuickCreate(dateKey: String, startMinute: Int?, press: UUID = UUID())

    var id: String {
        switch self {
        case .list(let request): return "list-\(request.id)"
        case .context(let mode): return "context-\(mode.id)"
        case .calendarQuickCreate(_, _, let press): return "calendar-\(press)"
        }
    }
}

/// Opens an editor on the root's host. A callable action rather than a binding, so a call site
/// cannot hold the presentation -- the whole point of [[T-18227]].
nonisolated struct iOSPageEditorPresentAction {
    private let present: (@MainActor (iOSPageEditorRequest) -> Void)?

    init(present: (@MainActor (iOSPageEditorRequest) -> Void)? = nil) {
        self.present = present
    }

    /// A missing host asserts in debug rather than failing silently, as the task inspector's does:
    /// every route into this UI passes through `iOSRootView`.
    @MainActor
    func callAsFunction(_ request: iOSPageEditorRequest) {
        guard let present else {
            assertionFailure("No iOSPageEditorHost above this view -- the editor cannot open")
            return
        }
        present(request)
    }

    /// For a control that takes a `Binding` to the list editor's mode (`iOSListCreateButtonsRow`):
    /// it reads `nil`, and a write opens the editor here.
    @MainActor
    var listEditorMode: Binding<iOSListEditorMode?> {
        Binding(
            get: { nil },
            set: { mode in
                guard let mode else { return }
                self(.list(iOSSidebarListEditorRequest(mode: mode)))
            }
        )
    }
}

private struct iOSPageEditorHostKey: EnvironmentKey {
    static var defaultValue: iOSPageEditorPresentAction { iOSPageEditorPresentAction() }
}

extension EnvironmentValues {
    var iOSPageEditor: iOSPageEditorPresentAction {
        get { self[iOSPageEditorHostKey.self] }
        set { self[iOSPageEditorHostKey.self] = newValue }
    }
}

private struct iOSPageEditorHostModifier: ViewModifier {
    @State private var request: iOSPageEditorRequest?

    func body(content: Content) -> some View {
        content
            .environment(\.iOSPageEditor, iOSPageEditorPresentAction { next in
                guard request == nil else { return }
                request = next
            })
            .sheet(item: $request) { request in
                switch request {
                case .list(let list):
                    // Fixed, as each page's own presentation declared it: the editor's form is not
                    // laid out for larger text, and the pages above it are.
                    iOSListEditorSheet(mode: list.mode, seededContext: list.seededContext)
                        .cadenceFixedTypography()
                case .context(let mode):
                    iOSContextEditorSheet(mode: mode)
                case .calendarQuickCreate(let dateKey, let startMinute, _):
                    iOSCalendarQuickCreateSheet(dateKey: dateKey, initialStartMinute: startMinute)
                }
            }
    }
}

extension View {
    /// [[T-18227]]: presents every page-opened editor. `iOSRootView` applies it exactly once,
    /// OUTSIDE the `horizontalSizeClass` shell switch.
    func iOSPageEditorHost() -> some View {
        modifier(iOSPageEditorHostModifier())
    }
}
#endif
