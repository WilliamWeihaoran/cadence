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
        List {
            Section {
                ForEach(featureRows) { row in
                    NavigationLink(value: row.destination) {
                        iOSFeatureSummaryRow(
                            title: row.title,
                            subtitle: row.subtitle,
                            icon: row.icon,
                            color: row.color
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                }
            } header: {
                Text("Features")
            }
        }
        .navigationTitle("More")
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
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
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

private enum iOSMoreDestination: Hashable {
    case focus
    case calendar
    case pursuits
    case milestones
    case habits
    case settings
}
#endif
