#if os(iOS)
import SwiftData
import SwiftUI

/// The fourth tab: everything the bar has no room for, under quiet eyebrows.
///
/// No page title. The bar item under your thumb already says More, and a heading repeating it is
/// the case the subtitle rule was written for. The eyebrows are the headings this screen needs —
/// they say what each group *is*, which the rows below them do not.
///
/// Rows carry a count only where a number means something (`CadenceCompactShellSupport.countLabel`),
/// and habits read as `2/5` rather than as a total, because being behind on two of today's habits
/// is a different fact from owning five of them.
struct iOSMoreTabView: View {
    @Query private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]

    private var badges: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: allTasks,
            activeGoalCount: activeGoals.count,
            habitCount: habits.count,
            activeListCount: areas.filter(\.isActive).count + projects.filter(\.isActive).count
        )
    }

    private var habitProgress: CadenceCompactShellSupport.HabitProgress? {
        CadenceCompactShellSupport.habitProgress(for: habits)
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
                                            badges: badges,
                                            habitProgress: habitProgress
                                        ),
                                        icon: destination.systemImage,
                                        color: destination.tint
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
