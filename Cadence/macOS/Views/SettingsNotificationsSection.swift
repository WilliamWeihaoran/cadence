#if os(macOS)
import SwiftUI
import AppKit

struct SettingsNotificationsSection: View {
    let notificationManager: NotificationManager
    @Binding var notificationsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if notificationManager.isAuthorized {
                enabledCard
            } else {
                notAuthorizedCard
            }
        }
    }

    private var enabledCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(Theme.amber)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable reminders")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("A task's scheduled start and due date, and a habit's reminder time, notify you locally.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var notAuthorizedCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.amber)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notification access required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Allow Cadence to notify you about scheduled tasks, due dates, and habit reminders.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                SettingsActionButton(tone: .filled(Theme.blue), action: requestAuthorization) {
                    Text("Enable Notifications")
                }
            }
        }
    }

    private func requestAuthorization() {
        Task {
            let granted = await notificationManager.requestAuthorization()
            if !granted {
                await MainActor.run {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
                    )
                }
            }
        }
    }
}
#endif
