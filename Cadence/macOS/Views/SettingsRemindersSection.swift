#if os(macOS)
import SwiftUI
import AppKit

// The connection-state and list-summary helpers this view is built on moved to
// Shared/CadenceRemindersPresentationSupport.swift when iOS gained its own Reminders
// settings section; `EventKit` is no longer imported here because nothing left in this
// file names an EventKit type.

struct SettingsRemindersSection: View {
    let remindersManager: RemindersManager

    /// **T-254.** One value, resolved once on the manager, rather than a fourth call to the
    /// shared resolver written out beside three others.
    private var state: RemindersConnectionState {
        remindersManager.connectionState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            accessCard

            if state.isConnected {
                CadenceFieldSection(title: "Reminder Lists") {
                    listsContent
                }
            }
        }
        // **T-253.** This page's own **Open Reminders Settings** button sends the user to
        // System Settings to revoke, and macOS does not terminate the app on the way back — so
        // the view never disappears and an appearance hook alone never fires a second time. The
        // shared modifier carries both halves; all four reminders surfaces apply the same one.
        .remindersAuthorizationLifecycle(remindersManager)
    }

    /// The access verdict, on the row Notifications and Sync also draw (T-286).
    private var accessCard: some View {
        CadenceFieldSection(title: nil) {
            CadenceSettingsNoticeRow(
                systemImage: state.isConnected ? "checklist" : "exclamationmark.triangle.fill",
                tint: state.isConnected ? Theme.purple : Theme.amber,
                title: state.accessTitle,
                detail: state.accessMessage
            ) {
                if let action = state.accessAction {
                    SettingsActionButton(
                        tone: action == .requestAccess ? .filled(Theme.blue) : .filled(Theme.dim),
                        action: { perform(action) }
                    ) {
                        Text(action.title)
                    }
                } else if state.isConnected {
                    SettingsActionButton(tone: .tinted(Theme.blue), action: remindersManager.reload) {
                        Text("Refresh")
                    }
                }
                // `.restricted` falls through both branches above: `accessAction` is `nil` and the
                // state is not connected, so there is neither an action to offer nor a fetch to
                // refresh. Rendering nothing here is deliberate — see T-256.
            }
        }
    }

    @ViewBuilder
    private var listsContent: some View {
        if remindersManager.isLoading && remindersManager.reminders.isEmpty {
            summaryRow {
                ProgressView().controlSize(.small)
                Text("Loading reminders...")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                Spacer()
            }
        } else if remindersManager.reminders.isEmpty {
            // The shared status row rather than a private one-liner (T-600(b)): this card already
            // draws `CadenceSettingsNoticeRow` for the access verdict twenty lines up, and the
            // empty state is the same shape — a glyph, what the state is, one sentence of why.
            CadenceSettingsNoticeRow(
                systemImage: "checklist",
                title: CadenceSettingsEmptyStateCopy.remindersTitle,
                detail: CadenceSettingsEmptyStateCopy.remindersSubtitle
            ) {
                EmptyView()
            }
        } else {
            let rows = RemindersSyncSummary.listRows(from: remindersManager.reminders)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                SettingsRemindersListRow(row: row)

                // Was a two-line `Divider().background(Theme.borderSubtle)`, which is how it
                // outlived the sweep written for the one-line spelling (T-286).
                if index < rows.count - 1 {
                    CadenceRowDivider(leadingInset: 24)
                }
            }
        }
    }

    private func summaryRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .frame(minHeight: CadenceSettingsRowMetrics.rowHeight)
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
        .frame(minHeight: CadenceSettingsRowMetrics.rowHeight)
    }
}
#endif
