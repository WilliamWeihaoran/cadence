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
/// Board, so nothing new is being taught. Its two labels come from `CadenceTasksPageScope`, which
/// takes them from `CadenceTasksSection` — the three slices the phone's Tasks index lists — so the
/// two shells cannot end up calling the same view different things.
///
/// **No mode switcher.** The List / Kanban axis is macOS-only: iOS has never had the All Tasks
/// board, and adding one is a feature rather than a merge.
///
/// **Since T-2072 the iPhone pushes it too.** The Tasks tab's index has a Tasks row and an Inbox
/// row, and both open this page — so the phone stopped drawing the two halves as bare views under
/// a three-segment control that existed nowhere else. That is why the header takes a back control
/// at compact width and none at regular: pushed on the phone, hosted with no stack around it on
/// the iPad, exactly the rule `iOSTaskCollectionPage` and `iOSCompactTodayView` already follow.
struct iOSTasksPageView: View {
    /// Non-`nil` when the selection named a view outright, the way `TasksPageView` takes it.
    var requestedScope: CadenceTasksPageScope?

    @AppStorage("ios.tasksPage.scope") private var scopeRaw = CadenceTasksPageScope.defaultScope.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    private var scope: CadenceTasksPageScope { CadenceTasksPageScope.resolved(scopeRaw) }

    var body: some View {
        VStack(spacing: 0) {
            header

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .cadenceScaledTypography()
        // Pushed on the phone since T-2072, where the header above carries the back control, so
        // the navigation bar would be a 44pt row holding a second one. No-op at regular width,
        // where the iPad shell hosts this page with no stack around it.
        .iOSHidesCompactNavigationBar()
        .onChange(of: requestedScope, initial: true) { _, requested in
            guard let requested else { return }
            scopeRaw = requested.rawValue
        }
    }

    /// Header **row**, switcher at its trailing end. The two children draw with
    /// `showsCompactHeader: false` so the page heads itself once — the alternative, letting each
    /// keep its own header beside the segment, would put the words "All Tasks" next to a segment
    /// already reading "All".
    ///
    /// **It used to be header *over* switcher**, which is the shape the phone's Tasks tab still
    /// uses. One row is what the owner chose for both this page and the Calendar's, and the reason
    /// is the same on each: a full-width row carrying two short pills is a row of chrome spent on
    /// a control that fits in the slack an `iOSPageHeader` already has. `trailing` is that slack —
    /// a single deliberate slot, documented as such — so this is the header row doing the job it
    /// was built for rather than a second row being tolerated beneath it.
    ///
    /// The group is `.compact` at compact width for the reason `iOSSegmentedPillDensity` gives:
    /// an iPhone row cannot pay for the standard density beside a title, and this page is reachable
    /// at compact width whenever an iPad shell is in a narrow split.
    private var header: some View {
        iOSPageHeader(
            eyebrow: "Tasks",
            title: scope.pageTitle,
            color: Theme.blue,
            onBack: horizontalSizeClass == .compact ? { dismiss() } : nil
        ) {
            iOSSegmentedPillGroup(density: horizontalSizeClass == .regular ? .standard : .compact) {
                ForEach(CadenceTasksPageScope.allCases) { option in
                    iOSSegmentedPill(
                        title: option.title,
                        isSelected: scope == option
                    ) {
                        scopeRaw = option.rawValue
                    }
                }
            }
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
