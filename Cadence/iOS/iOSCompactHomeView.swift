#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCompactHomeView: View {
    @Query private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]

    private var badgeSnapshot: CadenceFeatureBadgeSupport.Snapshot {
        CadenceFeatureBadgeSupport.Snapshot(
            tasks: allTasks,
            activeGoalCount: activeGoals.count,
            habitCount: habits.count,
            activeListCount: areas.filter(\.isActive).count + projects.filter(\.isActive).count
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                iOSCompactPageHeader(
                    eyebrow: "Cadence",
                    title: "Home",
                    subtitle: "Today's plan, notes, and everything else.",
                    systemImage: "sun.max.fill",
                    color: Theme.blue
                )

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(CadenceFeatureDestination.compactHomeSections) { section in
                        iOSHomeFeatureSectionView(section: section, badgeSnapshot: badgeSnapshot)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: CadenceFeatureDestination.settings) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Theme.dim)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: CadenceFeatureDestination.search) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

private struct iOSHomeFeatureRow: Identifiable {
    let destination: CadenceFeatureDestination
    let count: Int?

    var id: CadenceFeatureDestination { destination }
    var title: String { destination.title }
    var subtitle: String { destination.subtitle }
    var icon: String { destination.systemImage }
    var color: Color { destination.tint }
}

private struct iOSHomeFeatureSectionView: View {
    let section: CadenceFeatureSection
    let badgeSnapshot: CadenceFeatureBadgeSupport.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    NavigationLink(value: row.destination) {
                        iOSHomeFeatureNavigationRow(row: row)
                    }
                    .buttonStyle(.plain)

                    if row.id != section.destinations.last {
                        Divider()
                            .background(Theme.borderSubtle.opacity(0.72))
                            .padding(.leading, 54)
                    }
                }
            }
            .cadenceCard(cornerRadius: Theme.radiusCard)
        }
    }

    private var rows: [iOSHomeFeatureRow] {
        section.destinations.map { destination in
            iOSHomeFeatureRow(
                destination: destination,
                count: badgeSnapshot.count(for: destination)
            )
        }
    }
}

private struct iOSHomeFeatureNavigationRow: View {
    let row: iOSHomeFeatureRow

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: row.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.color)
                .frame(width: 31, height: 31)
                .background(row.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let count = row.count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(row.color)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(row.color.opacity(0.12))
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
#endif
