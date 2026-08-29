#if os(iOS)
import SwiftUI

/// The iPad shell's **Tasks** destination: one header, an All / Inbox switcher, and whichever of
/// the two the switcher selects.
///
/// The same merge macOS's `TasksPageView` is, in this column's vocabulary. The sidebar dropped
/// Inbox as a row — `CadenceSidebarLayout.primaryDestinations` is four rows on both platforms now —
/// so without this page the iPad would have no door to the Inbox at all.
///
/// The switcher is `iOSSegmentedPillGroup`, the control the Calendar tab uses for Week / Month /
/// Board and the iPhone's Tasks tab uses for Today / All / Inbox, so nothing new is being taught.
/// Its two labels come from `CadenceTasksPageScope`, which takes them from `CadenceTasksSection` —
/// the phone's segments — so the two shells cannot end up calling the same view different things.
///
/// **No mode switcher.** The List / Kanban axis is macOS-only: iOS has never had the All Tasks
/// board, and adding one is a feature rather than a merge.
struct iOSTasksPageView: View {
    /// Non-`nil` when the selection named a view outright, the way `TasksPageView` takes it.
    var requestedScope: CadenceTasksPageScope?

    @AppStorage("ios.tasksPage.scope") private var scopeRaw = CadenceTasksPageScope.defaultScope.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var scope: CadenceTasksPageScope { CadenceTasksPageScope.resolved(scopeRaw) }

    var body: some View {
        VStack(spacing: 0) {
            header

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: requestedScope, initial: true) { _, requested in
            guard let requested else { return }
            scopeRaw = requested.rawValue
        }
    }

    /// Header over switcher, the shape `iOSTasksTabView` already uses on the phone. The two
    /// children draw with `showsCompactHeader: false` so the page heads itself once — the
    /// alternative, letting each keep its own header under the segment, would put the words
    /// "All Tasks" one row below a segment already reading "All".
    private var header: some View {
        let metrics = CadencePageHeaderMetrics.metrics(
            role: .page,
            isRegularWidth: horizontalSizeClass == .regular
        )

        return VStack(alignment: .leading, spacing: 0) {
            iOSPageHeader(
                eyebrow: "Tasks",
                title: scope.pageTitle,
                color: Theme.blue
            )

            iOSSegmentedPillGroup {
                ForEach(CadenceTasksPageScope.allCases) { option in
                    iOSSegmentedPill(
                        title: option.title,
                        isSelected: scope == option
                    ) {
                        scopeRaw = option.rawValue
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.bottom, metrics.bottomPadding)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .all:
            iOSAllTasksView(showsCompactHeader: false)
        case .inbox:
            iOSInboxView(showsCompactHeader: false)
        }
    }
}
#endif
