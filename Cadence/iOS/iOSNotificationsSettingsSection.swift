#if os(iOS)
import SwiftUI
import UIKit

struct iOSNotificationsSettingsSection: View {
    let notificationManager: NotificationManager
    @Binding var notificationsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Reminders")

            if notificationManager.isAuthorized {
                enabledCard
            } else {
                accessCard
            }
        }
        .onAppear {
            Task { await notificationManager.refreshAuthorizationState() }
        }
    }

    // Both cards are `iOSSettingsCard`, not the shared `CadenceSettingsCard`: this section
    // was the last one on iOS still wearing the hard-bordered radius-12 card while every
    // other settings section had moved to the soft-elevation card on the radius scale.
    private var enabledCard: some View {
        iOSSettingsCard {
            HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                iOSIconTile(
                    systemImage: "bell.fill",
                    color: Theme.amber,
                    size: 34,
                    iconSize: 16
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable reminders")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("A task's scheduled start and due date, and a habit's reminder time, notify you locally.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .tint(Theme.blue)
            }
        }
    }

    private var accessCard: some View {
        iOSSettingsCard {
            HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                iOSIconTile(
                    systemImage: "exclamationmark.triangle.fill",
                    color: Theme.amber,
                    size: 34,
                    iconSize: 16
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notification access required")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text("Allow Cadence to notify you about scheduled tasks, due dates, and habit reminders.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)

                    iOSActionButton(
                        title: "Enable Notifications",
                        systemImage: "checkmark.circle.fill",
                        role: .primary,
                        size: .compact,
                        action: requestAuthorization
                    )
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func requestAuthorization() {
        Task {
            let granted = await notificationManager.requestAuthorization()
            if !granted {
                await MainActor.run { openSystemSettings() }
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
