#if os(iOS)
import SwiftUI
import UIKit

/// Settings > Reminders on iPhone and iPad.
///
/// The decision this screen makes — connect, point at Settings, or offer a refresh — is
/// `RemindersConnectionState` in `Shared/CadenceRemindersPresentationSupport.swift`, the same
/// value macOS's `SettingsRemindersSection` reads, so the two surfaces cannot disagree about
/// what a given EventKit status means. What differs is only the chrome: this follows the mobile
/// settings idiom (`iOSSettingsCard`, `iOSIconTile`, `iOSActionButton`) rather than macOS's
/// `SettingsCard` + `SettingsActionButton`, and stacks the action under the copy so a
/// finger-sized button is not competing with a title for a narrow row.
///
/// One view for both size classes: iPhone and iPad differ in the width this is handed, not in
/// how a card or a row inside it looks.
struct iOSRemindersSettingsSection: View {
    let remindersManager: RemindersManager

    /// **T-254.** One value, resolved once on the manager, rather than a fifth call to the
    /// shared resolver written out beside four others.
    private var state: RemindersConnectionState {
        remindersManager.connectionState
    }

    private var listRows: [RemindersListSummaryRow] {
        RemindersSyncSummary.listRows(from: remindersManager.reminders)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CadenceSettingsSectionLabel(text: "Apple Reminders")

            accessCard

            if state.isConnected {
                CadenceSettingsSectionLabel(text: "Reminder Lists")
                listsCard
            }
        }
        // **T-253.** Access is granted or revoked in the Settings app, so the app is not even
        // foreground when it changes — an appearance hook alone cannot see it, and this screen
        // carried only one. Both halves are the shared modifier now, and macOS's Settings section
        // applies the same one.
        .remindersAuthorizationLifecycle(remindersManager)
    }

    private var accessCard: some View {
        iOSSettingsCard {
            HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                iOSIconTile(
                    systemImage: state.accessIconName,
                    color: state.accessIconTint,
                    size: 34,
                    iconSize: 16
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.accessTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text(state.accessMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action = state.accessAction {
                        iOSActionButton(
                            title: action.title,
                            systemImage: action == .requestAccess ? "checkmark.circle.fill" : "gear",
                            role: .primary,
                            size: .compact,
                            action: { perform(action) }
                        )
                        .padding(.top, 2)
                    } else if state.isConnected {
                        iOSActionButton(
                            title: "Refresh",
                            systemImage: "arrow.clockwise",
                            role: .secondary,
                            size: .compact,
                            action: remindersManager.reload
                        )
                        .padding(.top, 2)
                    }
                    // `.restricted` offers neither button: no action can help, and there is
                    // nothing connected yet to refresh. See T-256.
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var listsCard: some View {
        iOSSettingsCard {
            VStack(spacing: 0) {
                if remindersManager.isLoading && remindersManager.reminders.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading reminders...")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.dim)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                } else if listRows.isEmpty {
                    iOSSettingsEmptyInlineRow(
                        systemImage: "checklist",
                        title: CadenceSettingsEmptyStateCopy.remindersTitle,
                        subtitle: CadenceSettingsEmptyStateCopy.remindersSubtitle
                    )
                } else {
                    ForEach(Array(listRows.enumerated()), id: \.element.id) { index, row in
                        iOSRemindersListRow(row: row)

                        if index < listRows.count - 1 {
                            iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                        }
                    }
                }
            }
        }
    }

    private func perform(_ action: RemindersAccessAction) {
        switch action {
        case .requestAccess:
            Task { await remindersManager.requestAccess() }
        case .openSystemSettings:
            openSystemSettings()
        }
    }

    /// iOS has no per-pane privacy URL the way macOS does — `openSettingsURLString` lands on
    /// Cadence's own Settings page, which is where the Reminders switch lives, so this is the
    /// deep link rather than a fallback for one.
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct iOSRemindersListRow: View {
    let row: RemindersListSummaryRow

    var body: some View {
        HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: "list.bullet",
                color: Theme.purple,
                size: iOSSettingsMetrics.glyphSlot,
                iconSize: 14
            )

            Text(row.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(row.count == 1 ? "1 open" : "\(row.count) open")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, iOSSettingsMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: iOSSettingsMetrics.minimumTapTarget, alignment: .leading)
    }
}
#endif
