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

private struct iOSTasksTabHeader: View {
    @Binding var section: CadenceTasksSection
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(CadenceCompactShellSupport.dateEyebrow(for: Date()))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .textCase(.uppercase)
                        .kerning(0.8)

                    Text(CadenceCompactShellSupport.greeting(for: Date()))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

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
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 11)
    }
}
#endif
