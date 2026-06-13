#if os(iOS)
import SwiftUI

struct iOSMoreView: View {
    private let featureSections: [iOSMoreFeatureSection] = [
        iOSMoreFeatureSection(
            title: "Plan",
            rows: [
                iOSMoreFeatureRow(title: "All Tasks", subtitle: "Review every active and completed task.", icon: "checklist", color: Theme.blue, destination: .allTasks),
                iOSMoreFeatureRow(title: "Lists", subtitle: "Browse areas, projects, and custom task lists.", icon: "folder.fill", color: Theme.green, destination: .lists),
                iOSMoreFeatureRow(title: "Calendar", subtitle: "Review schedule, month, and board views.", icon: "calendar", color: Theme.purple, destination: .calendar)
            ]
        ),
        iOSMoreFeatureSection(
            title: "Progress",
            rows: [
                iOSMoreFeatureRow(title: "Focus", subtitle: "Work through today's scheduled tasks.", icon: "timer", color: Theme.red, destination: .focus),
                iOSMoreFeatureRow(title: "Pursuits", subtitle: "See pursuits with linked milestones and habits.", icon: "sparkles", color: Theme.purple, destination: .pursuits),
                iOSMoreFeatureRow(title: "Milestones", subtitle: "Track goal progress and linked work.", icon: "flag.fill", color: Theme.green, destination: .milestones),
                iOSMoreFeatureRow(title: "Habits", subtitle: "Check habit status and mark today complete.", icon: "flame.fill", color: Theme.amber, destination: .habits)
            ]
        ),
        iOSMoreFeatureSection(
            title: "Workspace",
            rows: [
                iOSMoreFeatureRow(title: "Settings", subtitle: "Manage workspace lists, sync, and app options.", icon: "gearshape.fill", color: Theme.blue, destination: .settings)
            ]
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                iOSCompactPageHeader(
                    eyebrow: "Cadence",
                    title: "More",
                    subtitle: "Planning, progress, and workspace tools.",
                    systemImage: "ellipsis",
                    color: Theme.blue
                )

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(featureSections) { section in
                        iOSMoreFeatureSectionView(section: section)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
        .navigationDestination(for: iOSMoreDestination.self) { destination in
            switch destination {
            case .allTasks:
                iOSAllTasksView()
            case .lists:
                iOSListsView()
            case .focus:
                iOSFocusView()
            case .calendar:
                iOSCalendarView()
            case .pursuits:
                iOSPursuitsView()
            case .milestones:
                iOSMilestonesView()
            case .habits:
                iOSHabitsView()
            case .settings:
                iOSSettingsView()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

private struct iOSMoreFeatureSection: Identifiable {
    let title: String
    let rows: [iOSMoreFeatureRow]

    var id: String { title }
}

private struct iOSMoreFeatureRow: Identifiable {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let destination: iOSMoreDestination

    var id: iOSMoreDestination { destination }
}

private struct iOSMoreFeatureSectionView: View {
    let section: iOSMoreFeatureSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(section.rows) { row in
                    NavigationLink(value: row.destination) {
                        iOSMoreFeatureNavigationRow(row: row)
                    }
                    .buttonStyle(.plain)

                    if row.id != section.rows.last?.id {
                        Divider()
                            .background(Theme.borderSubtle.opacity(0.72))
                            .padding(.leading, 54)
                    }
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.48), lineWidth: 1)
            }
        }
    }
}

private struct iOSMoreFeatureNavigationRow: View {
    let row: iOSMoreFeatureRow

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: row.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.color)
                .frame(width: 31, height: 31)
                .background(row.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

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

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private enum iOSMoreDestination: Hashable {
    case allTasks
    case lists
    case focus
    case calendar
    case pursuits
    case milestones
    case habits
    case settings
}
#endif
