#if os(macOS)
import SwiftUI
import AppKit
import EventKit

/// The three states the Reminders settings surface can be in, derived from EventKit's
/// authorization status. This is the whole decision the UI makes, kept pure and away from
/// the view so it can be tested without an EventKit grant: `notDetermined` is the only
/// state where a request button does anything, because macOS never re-prompts once the
/// user has denied access — from there the only path is System Settings.
enum RemindersConnectionState: Equatable {
    case notDetermined
    case connected
    case denied

    /// EventKit's own status is the source of truth. `.authorized` is the pre-macOS-14
    /// spelling of `.fullAccess` (same case), so matching `.fullAccess` covers both;
    /// `.writeOnly` is never returned for reminders, and would not let Cadence read them
    /// anyway, so it is deliberately not treated as connected.
    static func resolve(status: EKAuthorizationStatus) -> RemindersConnectionState {
        switch status {
        case .fullAccess:
            return .connected
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    /// The view reads `RemindersManager`'s published flags rather than EventKit directly,
    /// because only `isAuthorized` is observable. `isDenied` is evaluated live, so it wins
    /// over a stale `isAuthorized` when access is revoked from System Settings mid-session.
    static func resolve(isAuthorized: Bool, isDenied: Bool) -> RemindersConnectionState {
        if isDenied { return .denied }
        return isAuthorized ? .connected : .notDetermined
    }

    var isConnected: Bool { self == .connected }

    var badgeTitle: String {
        switch self {
        case .connected: return "Connected"
        case .denied: return "Access denied"
        case .notDetermined: return "Not connected"
        }
    }

    var accessTitle: String {
        switch self {
        case .connected: return "Apple Reminders connected"
        case .denied: return "Reminders access denied"
        case .notDetermined: return "Reminders access required"
        }
    }

    var accessMessage: String {
        switch self {
        case .connected:
            return "Open reminders appear in your Inbox, where you can complete them."
        case .denied:
            return "Allow Cadence from System Settings, Privacy & Security, Reminders."
        case .notDetermined:
            return "Allow Cadence to read your active reminders and mark them complete."
        }
    }

    /// `nil` for `.connected` — nothing to ask for — and never a request button once denied,
    /// which would silently do nothing.
    var accessAction: RemindersAccessAction? {
        switch self {
        case .connected: return nil
        case .denied: return .openSystemSettings
        case .notDetermined: return .requestAccess
        }
    }
}

enum RemindersAccessAction: Equatable {
    case requestAccess
    case openSystemSettings

    var title: String {
        switch self {
        case .requestAccess: return "Allow Access"
        case .openSystemSettings: return "Open Reminders Settings"
        }
    }
}

/// One Apple Reminders list and how many of the currently loaded reminders came from it.
/// Purely a read-out of what `RemindersManager` already fetched — no extra fetching.
struct RemindersListSummaryRow: Identifiable, Equatable {
    let title: String
    let count: Int

    var id: String { title }
}

enum RemindersSyncSummary {
    static func listRows(from reminders: [AppleReminderItem]) -> [RemindersListSummaryRow] {
        Dictionary(grouping: reminders, by: \.listTitle)
            .map { RemindersListSummaryRow(title: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }
}

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
