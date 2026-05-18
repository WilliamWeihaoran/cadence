#if os(iOS)
import SwiftUI

struct iOSMoreView: View {
    private let featureRows: [iOSMoreFeatureRow] = [
        iOSMoreFeatureRow(title: "Focus", subtitle: "Work through today's scheduled tasks.", icon: "timer", color: Theme.red, destination: .focus),
        iOSMoreFeatureRow(title: "Calendar", subtitle: "Review schedule, month, and board views.", icon: "calendar", color: Theme.purple, destination: .calendar),
        iOSMoreFeatureRow(title: "Pursuits", subtitle: "See pursuits with linked milestones and habits.", icon: "sparkles", color: Theme.purple, destination: .pursuits),
        iOSMoreFeatureRow(title: "Milestones", subtitle: "Track goal progress and linked work.", icon: "flag.fill", color: Theme.green, destination: .milestones),
        iOSMoreFeatureRow(title: "Habits", subtitle: "Check habit status and mark today complete.", icon: "flame.fill", color: Theme.amber, destination: .habits),
        iOSMoreFeatureRow(title: "Settings", subtitle: "Manage workspace lists, sync, and app options.", icon: "gearshape.fill", color: Theme.blue, destination: .settings)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                iOSCompactPageHeader(
                    eyebrow: "Cadence",
                    title: "More",
                    subtitle: "Focus, calendar, goals, habits, and workspace settings.",
                    systemImage: "ellipsis",
                    color: Theme.blue
                )

                VStack(alignment: .leading, spacing: 9) {
                    Text("Features")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .textCase(.uppercase)
                        .kerning(0.8)

                    VStack(spacing: 8) {
                        ForEach(featureRows) { row in
                            NavigationLink(value: row.destination) {
                                iOSMoreFeatureNavigationRow(row: row)
                            }
                            .buttonStyle(.plain)
                        }
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

private struct iOSMoreFeatureRow: Identifiable {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let destination: iOSMoreDestination

    var id: iOSMoreDestination { destination }
}

private struct iOSMoreFeatureNavigationRow: View {
    let row: iOSMoreFeatureRow

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: row.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(row.color)
                .frame(width: 32, height: 32)
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
        .padding(.vertical, 11)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.45), lineWidth: 1)
        }
    }
}

private enum iOSMoreDestination: Hashable {
    case focus
    case calendar
    case pursuits
    case milestones
    case habits
    case settings
}
#endif
