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

    private var enabledCard: some View {
        CadenceSettingsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 34, height: 34)
                    .background(Theme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable reminders")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("A task's scheduled start and due date, and a habit's reminder time, notify you locally.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $notificationsEnabled)
                    .labelsHidden()
            }
        }
    }

    private var accessCard: some View {
        CadenceSettingsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 34, height: 34)
                    .background(Theme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notification access required")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text("Allow Cadence to notify you about scheduled tasks, due dates, and habit reminders.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        requestAuthorization()
                    } label: {
                        Label("Enable Notifications", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
                    .padding(.top, 6)
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
