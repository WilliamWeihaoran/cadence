#if os(macOS)
import SwiftUI

/// Apple Reminders, inline in the Inbox view of the Tasks page.
///
/// This is what makes the Inbox an *inbox* rather than a filter: unprocessed things, including
/// ones captured outside Cadence. It survived All Tasks and Inbox being merged into one page
/// precisely because losing it would have turned that merge into a deletion —
/// `TasksListView.showsRemindersSection` gates it on the **scope**, not on the destination.
///
/// It was "the only place in the app that shows Apple Reminders" until T-163, which built
/// `iOSInboxRemindersSection` against the same `CadenceTasksPageScope.showsRemindersStrip` gate and
/// the same `AppleReminderRowPresentation` tints. The two rows are drawn in their own platform's
/// vocabulary and share every decision behind them; change one of those decisions here and change
/// it for both, or the shipped `NSRemindersFullAccessUsageDescription` goes back to being true on
/// one platform only.
///
/// It is a `VStack` rather than a `Group` of `List` rows now. It used to carry
/// `.listRowBackground(.clear)`, `.listRowSeparator(.hidden)` and `.listRowInsets(.init())` on
/// every child — three modifiers switching off services the host was providing — and the merged
/// list is a `LazyVStack`, where they do nothing at all. The rows draw their own hairline and
/// hover, as they always did.
struct InboxAppleRemindersSectionView: View {
    let reminders: [AppleReminderItem]
    let isAuthorized: Bool
    let isDenied: Bool
    /// **T-256.** A device restriction (Screen Time, an MDM profile) rather than a user refusal —
    /// `isDenied` is still `true` here too (see `RemindersManager.isDenied`), so this is checked
    /// first, exactly as `RemindersConnectionState.resolve` checks it first.
    let isRestricted: Bool
    let isLoading: Bool
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void
    let onComplete: (String) -> AppleReminderCompletionOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskListGroupHeader(
                title: "Apple Reminders",
                isCollapsed: false,
                // **T-264.** `nil`, not `0`, whenever Cadence has not been allowed to look —
                // matching `iOSInboxRemindersSection`'s `state.isConnected` gate.
                regularCount: isAuthorized ? reminders.count : nil,
                accent: Theme.purple,
                isToggleEnabled: false,
                onToggle: { }
            )
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if isAuthorized {
                if isLoading && reminders.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading reminders...")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(.leading, TaskListDisplayMetrics.taskLeadingInset)
                    .padding(.vertical, 12)
                } else {
                    ForEach(reminders) { reminder in
                        AppleReminderTaskRow(reminder: reminder, onComplete: onComplete)
                            .padding(.leading, TaskListDisplayMetrics.taskLeadingInset)
                            .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } else {
                AppleRemindersAccessRow(
                    isDenied: isDenied,
                    isRestricted: isRestricted,
                    action: isDenied ? onOpenSettings : onRequestAccess
                )
                .padding(.leading, TaskListDisplayMetrics.taskLeadingInset)
                .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
            }
        }
    }
}

private struct AppleReminderTaskRow: View {
    let reminder: AppleReminderItem
    let onComplete: (String) -> AppleReminderCompletionOutcome
    @State private var isHovered = false
    /// **T-255, reshaped by T-268.** The optimistic tick and the sentence a refused write leaves
    /// behind used to be two `@State` properties this row moved by hand. They are one value now,
    /// and the move is `AppleReminderRowState.applying(_:)` — shared with `iOSInboxReminderRow`, so
    /// the two rows cannot come to disagree, and testable, which two `withAnimation` blocks inside
    /// a `private` view were not.
    @State private var rowState = AppleReminderRowState.idle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row

            // **T-255.** Only ever present after a refused write, so the row keeps its single-line
            // shape in the state it is in almost all of the time.
            if let failureNotice = rowState.failureNotice {
                Text(failureNotice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
                    // Aligned under the title rather than under the priority strip: 8 + 3 for the
                    // strip and its inset, 8 + 18 + 8 for the completion button and its padding.
                    .padding(.leading, 45)
                    .padding(.trailing, 6)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Theme.purple.opacity(0.06) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Theme.purple.opacity(0.18) : Color.clear, lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.22)).frame(height: 0.5)
        }
        .opacity(rowState.isCompleting ? 0.65 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: rowState)
    }

    private var row: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(priorityColor)
                .frame(width: 3)
                .padding(.leading, 8)
                .padding(.vertical, 3)

            Button(action: complete) {
                ZStack {
                    Circle()
                        .strokeBorder(rowState.isCompleting ? Theme.green : Theme.muted, lineWidth: 1.8)
                    if rowState.isCompleting {
                        Circle().fill(Theme.green)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.bg)
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
            }
            .buttonStyle(.cadencePlain)
            .disabled(!reminder.allowsCompletion || rowState.isCompleting)
            .help(reminder.allowsCompletion ? "Complete in Apple Reminders" : "This reminder list is read-only")
            .padding(.horizontal, 8)

            Text(reminder.title.isEmpty ? "Untitled Reminder" : reminder.title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let dueDate = reminder.dueDate {
                reminderDueDateBadge(dueDate)
            }

            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 9, weight: .semibold))
                Text(reminder.listTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.purple)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.purple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.leading, 6)
            .padding(.trailing, 6)
        }
    }

    /// Both tints are `AppleReminderRowPresentation`'s rather than this row's own. They were
    /// written out here — an inverted 1...4 / 5 / 6...9 ramp and a three-stop date rule — and iOS
    /// growing its own reminders row (T-163) is exactly the moment a private ramp becomes two
    /// ramps. The values are unchanged: the priority stops resolve through `Theme.priorityColor`,
    /// which is red / amber / blue / dim.
    private var priorityColor: Color {
        AppleReminderRowPresentation.priorityTint(reminder.priority)
    }

    private func reminderDueDateBadge(_ date: Date) -> some View {
        let dateKey = DateFormatters.dateKey(from: date)
        let color = AppleReminderRowPresentation.dueTint(
            dayOffset: DateFormatters.dayOffset(from: dateKey)
        )

        return HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 9, weight: .semibold))
            Text(DateFormatters.relativeDate(from: dateKey))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    /// The tick leads the write and the write answers: the circle settles first, because the row is
    /// about to be removed from a list it does not own, and then whatever EventKit said moves the
    /// row's state through the shared reducer.
    ///
    /// **T-255 built that reconcile and T-268 made it fail when it is gone.** There is no local
    /// `apply` any more — a private helper is exactly what the mutation left defined and
    /// unreachable while every string the test was scanning for stayed in the file.
    private func complete() {
        guard reminder.allowsCompletion, !rowState.isCompleting else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            rowState = .attempting
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            let outcome = onComplete(reminder.id)
            withAnimation(.easeOut(duration: 0.16)) {
                rowState = rowState.applying(outcome)
            }
        }
    }
}

private struct AppleRemindersAccessRow: View {
    let isDenied: Bool
    /// **T-256.** Checked ahead of `isDenied` — see `InboxAppleRemindersSectionView.isRestricted`.
    /// A restricted device gets its own copy and no button, the same decision every other
    /// reminders surface now makes, borrowed from the canonical `RemindersConnectionState.restricted`
    /// strings rather than a fourth hand-written pair that could drift from them.
    let isRestricted: Bool
    let action: () -> Void

    private var title: String {
        if isRestricted { return RemindersConnectionState.restricted.accessTitle }
        return isDenied ? "Reminders access is off" : "Show Apple Reminders in Inbox"
    }

    private var message: String {
        if isRestricted { return RemindersConnectionState.restricted.accessMessage }
        return isDenied
            ? "Allow Cadence in Privacy & Security to show your active reminders."
            : "Cadence can display active reminders and mark them complete here."
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.purple)
                .frame(width: 32, height: 32)
                .background(Theme.purple.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 12)

            // No button at all when restricted: there is no settings pane that can lift a
            // device restriction, so offering one would be the dead-button bug T-256 exists to
            // close, not fix it a third time.
            if !isRestricted {
                CadenceActionButton(
                    title: isDenied ? "Open Settings" : "Connect",
                    role: .primary,
                    size: .compact,
                    action: action
                )
            }
        }
        .padding(16)
        .cadenceCard(background: Theme.surface.opacity(0.72), cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
    }
}


/// The Inbox scope's empty state. Carries no button of its own: the floating "+" is on screen
/// behind it, so a second create control here would be a third shape for the same action. The copy
/// still says what the screen is for, which the page header deliberately does not — and it says
/// "Apple Reminders" too, which the All Tasks scope's empty state must not.
struct InboxEmptyStateView: View {
    var body: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.blue.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "tray")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.blue.opacity(0.6))
                }
                VStack(spacing: 6) {
                    Text("Inbox is empty")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Unsorted tasks and Apple Reminders appear here.\nCreate something to get started.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
