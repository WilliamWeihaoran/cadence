#if os(iOS)
import SwiftUI
import UIKit

struct iOSNotificationsSettingsSection: View {
    let notificationManager: NotificationManager
    @Binding var notificationsEnabled: Bool

    /// No section heading, the same as macOS's `SettingsNotificationsSection` (`title: nil`).
    /// This pane holds one card and the page header directly above it already reads
    /// "Notifications". The heading it used to carry read "Reminders" (T-578) — which on iOS is
    /// the name of the *Apple Reminders* category two rows away in the same settings list, whose
    /// own section is headed "Apple Reminders". One word, two meanings, two rows apart.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if notificationManager.isAuthorized {
                enabledCard
            } else {
                accessCard
            }
        }
        // `.onAppear` alone before T-576. Returning from the iOS Settings app is a foreground
        // transition, not a fresh appearance, so the half this adds is the half that matters after
        // the user actually grants the permission.
        .notificationsAuthorizationLifecycle(notificationManager)
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
                    Text(CadenceNotificationSettingsCopy.remindersToggleTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(CadenceNotificationSettingsCopy.remindersToggleDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                // The macOS pane's own shape (T-484): the label is hidden from the layout by
                // `.labelsHidden()` and kept as the control's accessible name.
                Toggle(CadenceNotificationSettingsCopy.remindersToggleTitle, isOn: $notificationsEnabled)
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
                    Text(CadenceNotificationSettingsCopy.accessRequiredTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text(CadenceNotificationSettingsCopy.accessRequiredDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)

                    iOSActionButton(
                        title: CadenceNotificationSettingsCopy.enableNotificationsAction,
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
