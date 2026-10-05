#if os(iOS)
import SwiftData
import SwiftUI

/// The fourth tab: everything the bar has no room for, under quiet eyebrows.
///
/// No page title. The bar item under your thumb already says More, and a heading repeating it is
/// the case the subtitle rule was written for. The eyebrows are the headings this screen needs —
/// they say what each group *is*, which the rows below them do not.
///
/// Rows carry a count only where a number means something (`CadenceCompactShellSupport.countLabel`).
/// The one row whose count was a fraction rather than a tally was Habits — `2/5`, today's
/// check-ins over the habits due today — and it left with T-2076.
struct iOSMoreTabView: View {
    @Query private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    private var badges: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: allTasks,
            activeListCount: areas.filter(\.isActive).count + projects.filter(\.isActive).count
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(CadenceFeatureDestination.compactMoreSections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrowLabel(text: section.title)
                            .padding(.horizontal, 2)

                        VStack(spacing: 8) {
                            ForEach(section.destinations) { destination in
                                NavigationLink(value: destination) {
                                    iOSFeatureSummaryRow(
                                        title: destination.title,
                                        subtitle: destination.subtitle,
                                        detail: CadenceCompactShellSupport.countLabel(
                                            for: destination,
                                            badges: badges
                                        ),
                                        icon: destination.systemImage,
                                        // Chrome, not a colour code — the same call the iPad
                                        // sidebar makes in `iOSSidebarButton`, so the two lists of
                                        // the same destinations read alike. The hues encoded
                                        // nothing anyway: Notes and Calendar shared purple.
                                        color: Theme.dim,
                                        detailTint: Theme.muted
                                    )
                                }
                                .buttonStyle(.iosPressable)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .iOSHidesCompactNavigationBar()
    }
}
#endif
