#if os(macOS)
import SwiftUI
import AppKit

/// Settings → Notifications: one status row, in the state the system has left it in.
///
/// **The two cards are one row (T-286).** This pane wrote the same glyph/title/sentence/action line
/// out twice — once authorized with a toggle on the end, once not with a button — and Reminders and
/// Sync each wrote a third and fourth. They are `CadenceSettingsNoticeRow` now, so the four of them
/// are one height and one type ramp rather than four that happened to agree.
struct SettingsNotificationsSection: View {
    let notificationManager: NotificationManager
    @Binding var notificationsEnabled: Bool

    var body: some View {
        CadenceFieldSection(title: nil) {
            if notificationManager.isAuthorized {
                enabledRow
            } else {
                notAuthorizedRow
            }
        }
    }

    private var enabledRow: some View {
        CadenceSettingsNoticeRow(
            systemImage: "bell.fill",
            tint: Theme.amber,
            title: CadenceNotificationSettingsCopy.remindersToggleTitle,
            detail: CadenceNotificationSettingsCopy.remindersToggleDetail
        ) {
            // Named rather than `Toggle("")`: `.labelsHidden()` hides the label from the layout,
            // not from the accessibility tree, so the switch keeps the row title as its own name
            // instead of borrowing nothing from the `Text` beside it (T-484).
            Toggle(CadenceNotificationSettingsCopy.remindersToggleTitle, isOn: $notificationsEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var notAuthorizedRow: some View {
        CadenceSettingsNoticeRow(
            systemImage: "exclamationmark.triangle.fill",
            tint: Theme.amber,
            title: CadenceNotificationSettingsCopy.accessRequiredTitle,
            detail: CadenceNotificationSettingsCopy.accessRequiredDetail
        ) {
            SettingsActionButton(tone: .filled(Theme.blue), action: requestAuthorization) {
                Text(CadenceNotificationSettingsCopy.enableNotificationsAction)
            }
        }
    }

    private func requestAuthorization() {
        Task {
            let granted = await notificationManager.requestAuthorization()
            guard !granted,
                  let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
            else { return }
            // Already on the main actor: this view is main-actor isolated and the `Task` inherits it,
            // so the `MainActor.run` that used to wrap this was a no-op whose discarded `Bool` was
            // the warning. `open` still returns whether the URL could be handed to a handler.
            _ = NSWorkspace.shared.open(settingsURL)
        }
    }
}
#endif
