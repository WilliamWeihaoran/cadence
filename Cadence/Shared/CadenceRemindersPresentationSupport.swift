import EventKit
import SwiftUI

/// The three states the Reminders settings surface can be in, derived from EventKit's
/// authorization status. This is the whole decision the UI makes, kept pure and away from
/// the view so it can be tested without an EventKit grant: `notDetermined` is the only
/// state where a request button does anything, because neither platform re-prompts once the
/// user has denied access — from there the only path is the system Settings app.
///
/// Lives in `Shared/` and outside any platform guard because both Settings surfaces read it:
/// `macOS/Views/SettingsRemindersSection.swift` and `iOS/iOSRemindersSettingsSection.swift`.
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

    /// The only genuinely platform-split strings in this type, and they are split because they
    /// name things that differ: macOS reads reminders in the Inbox and iOS does not (yet), and
    /// the privacy pane is reached through "System Settings" on macOS and "Settings" on iOS.
    /// Telling an iPhone user their reminders will appear in an Inbox they do not have is the
    /// kind of copy that outlives the feature it described.
    var accessMessage: String {
        switch self {
        case .connected:
            #if os(macOS)
            return "Open reminders appear in your Inbox, where you can complete them."
            #else
            return "Your reminder lists and how much is still open appear below."
            #endif
        case .denied:
            #if os(macOS)
            return "Allow Cadence from System Settings, Privacy & Security, Reminders."
            #else
            return "Allow Cadence from Settings, Privacy & Security, Reminders."
            #endif
        case .notDetermined:
            #if os(macOS)
            return "Allow Cadence to read your active reminders and mark them complete."
            #else
            return "Allow Cadence to read your active reminders."
            #endif
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
