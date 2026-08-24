import EventKit
import SwiftUI

/// The four states the Reminders settings surface can be in, derived from EventKit's
/// authorization status. This is the whole decision the UI makes, kept pure and away from
/// the view so it can be tested without an EventKit grant: `notDetermined` is the only
/// state where a request button does anything, because neither platform re-prompts once the
/// user has denied access — from there the only path is the system Settings app, and even
/// that path is closed under `.restricted` (T-256), which offers no action at all.
///
/// Lives in `Shared/` and outside any platform guard because both Settings surfaces read it:
/// `macOS/Views/SettingsRemindersSection.swift` and `iOS/iOSRemindersSettingsSection.swift`.
enum RemindersConnectionState: Equatable {
    case notDetermined
    case connected
    case denied
    /// A device restriction — Screen Time, an MDM profile, a managed device — is blocking
    /// Reminders access. **T-256:** this used to fold into `.denied`, which told the user
    /// "Allow Cadence from Settings, Privacy & Security, Reminders" over a pane that a
    /// restriction will not let them act on. Restricted and denied need different second
    /// halves for exactly the reason `.notDetermined` and `.denied` do: one names something
    /// the user can do about it, and the other two do not — and they don't agree on which one.
    case restricted

    /// EventKit's own status is the source of truth. `.authorized` is the pre-macOS-14
    /// spelling of `.fullAccess` (same case), so matching `.fullAccess` covers both;
    /// `.writeOnly` is never returned for reminders, and would not let Cadence read them
    /// anyway, so it is deliberately not treated as connected.
    static func resolve(status: EKAuthorizationStatus) -> RemindersConnectionState {
        switch status {
        case .fullAccess:
            return .connected
        case .restricted:
            return .restricted
        case .denied:
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
    ///
    /// `isRestricted` is checked first, ahead of `isDenied`: `RemindersManager.isDenied` folds
    /// `.restricted` into its own answer too (a restriction means no request button will do
    /// anything, which is the question *that* flag answers), so the two can both be `true` at
    /// once and restricted has to win, or its own presentation would never be reachable.
    /// `isRestricted` defaults to `false` so every existing caller — every test written before
    /// T-256 and any surface that genuinely cannot distinguish the two — keeps resolving exactly
    /// as it did.
    static func resolve(isAuthorized: Bool, isDenied: Bool, isRestricted: Bool = false) -> RemindersConnectionState {
        if isRestricted { return .restricted }
        if isDenied { return .denied }
        return isAuthorized ? .connected : .notDetermined
    }

    var isConnected: Bool { self == .connected }

    var badgeTitle: String {
        switch self {
        case .connected: return "Connected"
        case .denied: return "Access denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not connected"
        }
    }

    var accessTitle: String {
        switch self {
        case .connected: return "Apple Reminders connected"
        case .denied: return "Reminders access denied"
        case .restricted: return "Reminders access restricted"
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
        case .restricted:
            // No `#if` split: unlike `.denied`, this never names a settings pane to visit,
            // because there isn't one that will help — a restriction is imposed by whoever
            // manages the device, not by a toggle either OS exposes to this user.
            return "A restriction on this device — Screen Time, a management profile — is blocking Reminders access, and it is not Cadence's to lift."
        case .notDetermined:
            #if os(macOS)
            return "Allow Cadence to read your active reminders and mark them complete."
            #else
            return "Allow Cadence to read your active reminders."
            #endif
        }
    }

    /// `nil` for `.connected` — nothing to ask for — and never a request button once denied,
    /// which would silently do nothing. `nil` for `.restricted` too, and for the same reason:
    /// there is no pane `.openSystemSettings` could send this user to that would let them lift
    /// the restriction, so offering the button would be [[T-256]]'s dead-`.denied`-button bug in
    /// a state Cadence cannot even ask the user to fix themselves.
    var accessAction: RemindersAccessAction? {
        switch self {
        case .connected: return nil
        case .denied: return .openSystemSettings
        case .restricted: return nil
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

/// What `RemindersManager.completeReminder(id:)` actually did.
///
/// **T-255.** That method used to return `Void` and had four ways to do nothing: not authorized,
/// the identifier no longer resolving, a calendar that refuses content modifications, and a
/// `store.save` throw that only `print`ed. Both Inbox rows tick optimistically — set
/// `isCompleting`, animate to struck-through at 0.65 opacity, then call through 220ms later — and
/// `isCompleting` is local `@State` that nothing ever resets, so every one of those four exits left
/// a row visibly ticked over a reminder Apple Reminders still had open. The next relaunch un-ticked
/// it silently.
///
/// Optimistic is still the right shape here: the success path is the common one, and the tick has
/// to land *before* the reload removes the row or the gesture has no visible result at all. What
/// was missing is the reconcile, so the write now answers and the row applies
/// `AppleReminderCompletionResolution` to that answer.
/// `nonisolated`, unlike its neighbours in this file: both of these are pure decisions over their
/// arguments, and the default `MainActor` isolation would otherwise put the synthesized `Equatable`
/// conformance on the main actor and warn at every `#expect` that compares one from a nonisolated
/// test context. Same spelling and same reason as `TaskOrdering` and `TaskDragPayload`.
nonisolated enum AppleReminderCompletionOutcome: Equatable, Sendable {
    /// EventKit saved it. This is the **only** outcome that may leave the tick standing.
    case completed
    /// Access is gone — most often revoked from the Settings app while this page stayed open.
    case notAuthorized
    /// The identifier no longer resolves to a reminder: completed or deleted somewhere else.
    case reminderUnavailable
    /// The reminder's list refuses content modifications. The row disables its button for the
    /// same reason, but that comes from the snapshot taken at fetch time, so a list that turned
    /// read-only afterwards reaches here with an enabled control.
    case listIsReadOnly
    /// EventKit's `save` threw. Transient (a sync conflict) or not; either way nothing was written.
    case saveFailed

    /// The three refusals reachable before `store.save` is ever called, in the order the manager
    /// has to ask them: authorization first (an unauthorized store cannot be trusted to resolve
    /// anything), then whether the item is still there, then whether its list will take a write.
    /// `nil` means the write may proceed.
    ///
    /// Extracted from the manager for the same reason `isDenied(status:deniedInThisSession:)` is:
    /// it is the decision, EventKit is not available to the test target without a real grant, and
    /// a `guard` chain inside a method returning `Void` is exactly what hid this bug.
    static func refusal(
        isAuthorized: Bool,
        reminderResolves: Bool,
        allowsContentModifications: Bool
    ) -> AppleReminderCompletionOutcome? {
        if !isAuthorized { return .notAuthorized }
        if !reminderResolves { return .reminderUnavailable }
        if !allowsContentModifications { return .listIsReadOnly }
        return nil
    }
}

/// What the row does with that answer: whether the tick stands, and what — if anything — the row
/// says about it.
///
/// **The rule is that the tick may not assert an outcome EventKit did not confirm**, so everything
/// but `.completed` reverts. The interesting half is the second one, and it is deliberately not
/// uniform:
///
/// - **Revert alone is confusing.** A tick that quietly undoes itself reads as a misclick, and the
///   user's next move is to tap it again, which fails again.
/// - **An alert on every failure is noise, and worse than noise here.** Three of these arrive in
///   bursts — a revoked grant, or an iCloud sync conflict, hits every visible row at once — so a
///   modal per row is a queue of sheets over a list the user was only scanning. It also steals
///   focus for something a second tap may well fix.
///
/// So: revert always, and speak only when nothing else on screen will. `.notAuthorized` is the one
/// case where something else does — the section replaces every row with its access card, which says
/// far more than a line under one row could — so that one reverts silently. The rest carry a short
/// inline notice on the row itself: non-modal, tied to the thing that failed, and gone as soon as
/// the row is tapped again or reloaded away.
nonisolated enum AppleReminderCompletionResolution: Equatable, Sendable {
    /// Leave the tick. The row is on its way out of a list it does not own.
    case keepCompleted
    /// Undo the tick and say nothing — the surface around the row is already explaining it.
    case revertSilently
    /// Undo the tick and show this sentence on the row.
    case revertWithNotice(String)

    static func resolve(_ outcome: AppleReminderCompletionOutcome) -> AppleReminderCompletionResolution {
        switch outcome {
        case .completed:
            return .keepCompleted
        case .notAuthorized:
            return .revertSilently
        case .reminderUnavailable:
            // Honest about the one thing Cadence knows: the item is not there to complete. If it
            // really is gone the reload takes the row with it and this is never read; if the
            // lookup was merely stale, the row stays and un-ticked is the truthful state.
            return .revertWithNotice("That reminder is no longer in Apple Reminders.")
        case .listIsReadOnly:
            return .revertWithNotice("Apple Reminders will not let Cadence change this list.")
        case .saveFailed:
            return .revertWithNotice("Apple Reminders did not save that. Try again.")
        }
    }

    /// `false` only for `.completed`. Read by both rows so neither can invent a fifth policy.
    var revertsTick: Bool {
        self != .keepCompleted
    }

    var notice: String? {
        guard case let .revertWithNotice(text) = self else { return nil }
        return text
    }
}
