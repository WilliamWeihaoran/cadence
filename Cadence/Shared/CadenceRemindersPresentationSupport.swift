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

    /// Whether reminders access is denied, given EventKit's cached answer **and** whether this
    /// launch already watched the user refuse the in-app prompt.
    ///
    /// **`EKEventStore.authorizationStatus` is cached per process, in both directions.** The grant
    /// direction is already worked around in `RemindersManager.requestAccess()`, which trusts
    /// EventKit's own `granted` answer and resets the store because the class method keeps
    /// reporting `.notDetermined` for the rest of the launch after the user taps Allow. The denial
    /// direction is the mirror image and was left on the cached path: after **Don't Allow** the
    /// status still reads `.notDetermined`, so the surface stayed on "Reminders access required"
    /// and kept a live **Allow Access** button that can never prompt again — measured on the iOS 26
    /// simulator, on Settings > Reminders and on the Inbox strip, with the simulator's TCC row
    /// already recording the denial and a relaunch of the same build rendering it correctly.
    ///
    /// So the request's `false` is the denial, and has to be carried for the rest of the launch the
    /// same way its `true` is. `deniedInThisSession` is that record; it is cleared the moment a
    /// real grant lands, so it can only ever add a denial the cached status has not caught up with.
    static func isDenied(status: EKAuthorizationStatus, deniedInThisSession: Bool) -> Bool {
        if deniedInThisSession { return true }
        return status == .denied || status == .restricted
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

    /// The only genuinely platform-split strings in this type, and the split is smaller than it
    /// was. The privacy pane is still reached through "System Settings" on macOS and "Settings" on
    /// iOS, which is a real difference in what the sentence has to name.
    ///
    /// The `.connected` pair is **not** that any more. It used to be split because macOS read
    /// reminders in the Inbox and iOS did not, so telling an iPhone user their reminders would
    /// appear in an Inbox they did not have was copy that outlived the feature it described. T-163
    /// built that Inbox surface on iOS, so both platforms now show reminders in the Inbox; the two
    /// sentences differ only because this screen — Settings — shows a per-list summary underneath
    /// itself on iOS and does not on macOS, which is what each is describing.
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

/// The two tints an Apple Reminder row draws, as pure functions of the reminder.
///
/// Both were written out inside macOS's `AppleReminderTaskRow` and would have been written out a
/// second time the moment iOS grew a reminders row — which is what T-163 is. They are here for the
/// same reason `RemindersConnectionState` is: outside every platform guard, so the macOS-built test
/// target can pin them, and in one place, so the two rows cannot disagree about what "urgent" or
/// "late" looks like.
enum AppleReminderRowPresentation {
    /// EventKit's priority is 0 (unset) or 1–9, **low number = high priority** — the inverse of
    /// how it reads. 1–4 is "high", 5 is "medium", 6–9 is "low", and 0 has no opinion, so it draws
    /// as ordinary chrome rather than as a fourth priority.
    ///
    /// The colours are `Theme.priorityColor`'s, not a second ramp: an Apple Reminder marked high
    /// should look exactly as high as a Cadence task marked high, in a list that mixes the two.
    static func priorityTint(_ priority: Int) -> Color {
        switch priority {
        case 1...4: return Theme.priorityColor(.high)
        case 5: return Theme.priorityColor(.medium)
        case 6...9: return Theme.priorityColor(.low)
        default: return Theme.priorityColor(.none)
        }
    }

    /// Red for a due date that has gone by, amber for today, and neutral for anything still ahead.
    /// `nil` — an unparseable date key — is neutral rather than late.
    ///
    /// The same three stops the task row uses, and the same rule behind them: colour is reserved
    /// for the exceptional, so a reminder due next week is chrome.
    static func dueTint(dayOffset: Int?) -> Color {
        guard let dayOffset else { return Theme.dim }
        if dayOffset < 0 { return Theme.red }
        return dayOffset == 0 ? Theme.amber : Theme.dim
    }
}
