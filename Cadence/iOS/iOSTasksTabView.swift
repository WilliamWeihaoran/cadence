#if os(iOS)
import SwiftData
import SwiftUI

/// The Tasks tab: one header carrying the day and a Today / All / Inbox switcher, over whichever of
/// the three the switcher selects.
///
/// The switcher is `iOSSegmentedPillGroup`, the same control the Calendar tab uses for
/// Week / Month / Board, so the two tabs are learned once instead of twice.
///
/// The title is the greeting rather than the word "Tasks". The bar below already says Tasks and the
/// segment below that already says which slice you are looking at; a third restatement is the
/// subtitle rule wearing a different hat. The greeting and the date are the two things on this row
/// the screen does not otherwise state — and they are what the deleted Home screen opened with.
struct iOSTasksTabView: View {
    @Binding var section: CadenceTasksSection
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 0) {
            iOSTasksTabHeader(section: $section) {
                path.append(CadenceFeatureDestination.search)
            }

            Divider().background(Theme.borderSubtle)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .iOSHidesCompactNavigationBar()
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .today:
            iPadTodayView(showsCompactHeader: false)
        case .all:
            iOSAllTasksView(showsCompactHeader: false)
        case .inbox:
            iPadInboxView(showsCompactHeader: false)
        }
    }
}

/// The tab's own header row, over the segmented switcher.
///
/// The row **is** `iOSPageHeader`, at `.page` role. It used to re-spell that vocabulary by hand — a
/// 10pt uppercase kerned eyebrow over a 26pt bold title, with its own `Spacer(minLength: 8)` before
/// a trailing control — which are the header's exact compact `.page` figures, arrived at
/// independently. It survived the pass that collapsed six of these into one because it is
/// compact-only and so is not an iPhone-against-iPad divergence; being the *seventh* copy of a
/// vocabulary is what makes it worth closing anyway, since six copies is what a seventh becomes.
///
/// The eyebrow and title are the greeting and the date rather than the word "Tasks": the switcher
/// below already says which slice you are on, and the tab bar below that already says Tasks.
private struct iOSTasksTabHeader: View {
    @Binding var section: CadenceTasksSection
    let onSearch: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // The switcher's gutter is the header's own, read from the same ramp rather than typed
        // beside it — the two are one row of chrome and must share an edge.
        let metrics = iOSPageHeaderMetrics.metrics(
            role: .page,
            isRegularWidth: horizontalSizeClass == .regular
        )

        VStack(alignment: .leading, spacing: 0) {
            iOSPageHeader(
                eyebrow: CadenceCompactShellSupport.dateEyebrow(for: Date()),
                title: CadenceCompactShellSupport.greeting(for: Date())
            ) {
                iOSIconButton(
                    systemImage: "magnifyingglass",
                    accessibilityLabel: "Search",
                    plateSize: 38,
                    iconSize: 14,
                    action: onSearch
                )
            }

            iOSSegmentedPillGroup {
                ForEach(CadenceTasksSection.allCases) { option in
                    iOSSegmentedPill(
                        title: option.title,
                        isSelected: section == option
                    ) {
                        section = option
                    }
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.bottom, metrics.bottomPadding)
        }
    }
}
#endif
