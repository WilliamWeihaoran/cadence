#if os(macOS)
import SwiftUI
import AppKit

// The connection-state and list-summary helpers this view is built on moved to
// Shared/CadenceRemindersPresentationSupport.swift when iOS gained its own Reminders
// settings section; `EventKit` is no longer imported here because nothing left in this
// file names an EventKit type.

struct SettingsRemindersSection: View {
    let remindersManager: RemindersManager

    private var state: RemindersConnectionState {
        RemindersConnectionState.resolve(
            isAuthorized: remindersManager.isAuthorized,
            isDenied: remindersManager.isDenied
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            accessCard

            if state.isConnected {
                SettingsSectionLabel(text: "Reminder Lists")
                listsCard
            }
        }
        // The user can grant or revoke access in System Settings while this page is open,
        // so re-derive on appear the same way the Inbox does.
        .onAppear { remindersManager.refreshAuthorizationState() }
    }

    private var accessCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: state.isConnected ? "checklist" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state.isConnected ? Theme.purple : Theme.amber)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.accessTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(state.accessMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let action = state.accessAction {
                    SettingsActionButton(
                        tone: action == .requestAccess ? .filled(Theme.blue) : .filled(Theme.dim),
                        action: { perform(action) }
                    ) {
                        Text(action.title)
                    }
                } else {
                    SettingsActionButton(tone: .tinted(Theme.blue), action: remindersManager.reload) {
                        Text("Refresh")
                    }
                }
            }
        }
    }

    private var listsCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                if remindersManager.isLoading && remindersManager.reminders.isEmpty {
                    summaryRow {
                        ProgressView().controlSize(.small)
                        Text("Loading reminders...")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                    }
                } else if remindersManager.reminders.isEmpty {
                    summaryRow {
                        Image(systemName: "checklist")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                        Text("No open reminders.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                    }
                } else {
                    let rows = RemindersSyncSummary.listRows(from: remindersManager.reminders)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        SettingsRemindersListRow(row: row)

                        if index < rows.count - 1 {
                            Divider()
                                .background(Theme.borderSubtle)
                                .padding(.leading, 24)
                        }
                    }
                }
            }
        }
    }

    private func summaryRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.vertical, 10)
    }

    private func perform(_ action: RemindersAccessAction) {
        switch action {
        case .requestAccess:
            Task { await remindersManager.requestAccess() }
        case .openSystemSettings:
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

private struct SettingsRemindersListRow: View {
    let row: RemindersListSummaryRow

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.purple)
                .frame(width: 12, height: 12)

            Text(row.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(row.count == 1 ? "1 open" : "\(row.count) open")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 10)
    }
}
#endif
