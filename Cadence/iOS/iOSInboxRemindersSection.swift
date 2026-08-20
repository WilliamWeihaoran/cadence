#if os(iOS)
import SwiftUI
import UIKit

/// Apple Reminders, inline in the Inbox on iPhone and iPad.
///
/// **T-163, and the fix for T-167.** The app ships
/// `NSRemindersFullAccessUsageDescription` reading "Cadence uses Reminders to show your active
/// reminders in Inbox and mark them complete when you check them off." On macOS that described
/// `InboxAppleRemindersSectionView`. On iOS it described nothing: there was no reminders surface
/// anywhere outside Settings, and `RemindersManager.completeReminder(id:)` had no iOS caller, so
/// both halves of the sentence were false on the platform the string was mostly being read on.
/// This view is the surface, and its completion circle is that method's first iOS caller.
///
/// **It is the mobile idiom, not a port of the macOS card.** The access state is
/// `iOSIconTile` + copy + `iOSActionButton`, exactly as `iOSRemindersSettingsSection` draws it, and
/// the rows are `iOSTaskRow`'s vocabulary — a completion circle carrying priority, a title, and
/// `iOSTaskMetaLabel` metadata that is `Theme.dim` unless it has earned a colour. What *is* shared
/// with macOS is everything that is a decision rather than a drawing:
/// `CadenceTasksPageScope.showsRemindersStrip` decides whether this appears at all, and
/// `AppleReminderRowPresentation` decides the two tints, so the two platforms' rows cannot come to
/// disagree about what "high priority" or "late" looks like.
///
/// **One view for both size classes.** iPhone and iPad differ in the width this is handed and in
/// nothing else; the row's paddings come from `CadenceTaskRowMetrics`, read from the size class,
/// which is the same ramp every other task row on iOS reads.
struct iOSInboxRemindersSection: View {
    let remindersManager: RemindersManager
    /// The page's own measurements, so this card is inset exactly as the group card above it is.
    let metrics: iOSTaskCollectionMetrics

    private var state: RemindersConnectionState {
        RemindersConnectionState.resolve(
            isAuthorized: remindersManager.isAuthorized,
            isDenied: remindersManager.isDenied
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // The Inbox's own group header, not a second heading vocabulary: this reads as one more
            // group of unprocessed things, which is what it is. No drop identity — a new Cadence
            // task cannot inherit "is an Apple Reminder".
            iOSTaskGroupHeader(
                title: "Apple Reminders",
                color: Theme.purple,
                count: remindersManager.reminders.count
            )

            if state.isConnected {
                connectedContent
            } else {
                accessRow
            }
        }
        .padding(metrics.cardPadding)
    }

    @ViewBuilder
    private var connectedContent: some View {
        if remindersManager.isLoading && remindersManager.reminders.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading reminders...")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        } else {
            // 7pt between rows, which is `iOSTaskGroupSection`'s: these sit under a group header in
            // the same card as the task groups and must stack at the same rhythm.
            VStack(spacing: 7) {
                ForEach(remindersManager.reminders) { reminder in
                    iOSInboxReminderRow(
                        reminder: reminder,
                        onComplete: remindersManager.completeReminder
                    )
                }
            }
        }
    }

    /// The same three-state access block Settings draws, minus the card — this section already is
    /// one. `RemindersConnectionState` supplies the title, the sentence and which action is
    /// offered, so "denied never gets a request button that silently does nothing" is decided once.
    private var accessRow: some View {
        HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: "exclamationmark.triangle.fill",
                color: Theme.amber,
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
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func perform(_ action: RemindersAccessAction) {
        switch action {
        case .requestAccess:
            // `requestAccess()` and nothing after it. It trusts EventKit's own `granted` answer and
            // resets the store, because `EKEventStore.authorizationStatus` is cached per process on
            // iOS and keeps reporting `.notDetermined` for the rest of the launch after the user
            // taps Allow. Re-reading the status here — or calling `refreshAuthorizationState()` to
            // "confirm" the grant — is the bug that made connecting look like it had failed until
            // the app was relaunched.
            Task { await remindersManager.requestAccess() }
        case .openSystemSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }
    }
}

/// One Apple Reminder, drawn as an iOS task row.
///
/// Not `iOSTaskRow` itself: that takes an `AppTask` and offers a detail sheet, swipe actions, a
/// context menu and a drop target, none of which an EventKit item has. What it shares is the
/// vocabulary — the completion circle carrying priority, `CadenceTaskRowMetrics` for every
/// measurement, `iOSTaskMetaLabel` for read-only metadata, and the row's own bottom hairline as its
/// only chrome. One layer, at one radius.
private struct iOSInboxReminderRow: View {
    let reminder: AppleReminderItem
    let onComplete: (String) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isCompleting = false

    private var metrics: CadenceTaskRowMetrics {
        .metrics(isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        HStack(alignment: .top, spacing: metrics.contentSpacing) {
            completionButton

            VStack(alignment: .leading, spacing: metrics.summarySpacing) {
                Text(reminder.title.isEmpty ? "Untitled Reminder" : reminder.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isCompleting ? Theme.dim : Theme.text)
                    .strikethrough(isCompleting, color: Theme.dim)
                    .lineLimit(CadenceTaskRowMetrics.titleLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)

                metadata
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.22))
                .frame(height: 1)
        }
        .opacity(isCompleting ? 0.65 : 1)
        .animation(.easeOut(duration: 0.16), value: isCompleting)
    }

    /// The circle carries priority and nothing else, exactly as `iOSTaskRow`'s does — and it is the
    /// only control on the row. A read-only reminder list gets a disabled one rather than a hidden
    /// one, so the row still reads as a checkable thing that this particular list will not let you
    /// check.
    private var completionButton: some View {
        Button(action: complete) {
            iOSTaskCompletionCircle(
                glyph: .binary(
                    isDone: isCompleting,
                    tint: AppleReminderRowPresentation.priorityTint(reminder.priority)
                ),
                diameter: CadenceTaskRowMetrics.completionCircleDiameter
            )
            .frame(width: metrics.completionGlyphSize, height: metrics.completionGlyphSize)
            .iOSExpandedHitArea((44 - metrics.completionGlyphSize) / 2)
        }
        .buttonStyle(.iosPressable)
        .disabled(!reminder.allowsCompletion || isCompleting)
        .opacity(reminder.allowsCompletion ? 1 : 0.4)
        .accessibilityLabel(
            reminder.allowsCompletion
                ? "Complete reminder in Apple Reminders"
                : "This reminder list is read-only"
        )
    }

    /// The list it came from, and when it is due. Both are `iOSTaskMetaLabel` — unfilled, one
    /// colour for icon and text — because neither is tappable here: this row edits exactly one
    /// field, and everything else about a reminder belongs to Apple Reminders.
    ///
    /// The list name is purple, and it is the one exception to "colour is reserved for the
    /// exceptional": in a card that otherwise holds Cadence tasks, it is what says these rows are
    /// somebody else's. It is the same purple the section header above it carries.
    @ViewBuilder
    private var metadata: some View {
        let dueDateKey = reminder.dueDate.map(DateFormatters.dateKey(from:))

        // `lineSpacing` is the ordinary badge gap here, not `iOSTaskRow`'s doubled chip inset. That
        // number is derived from the expanded touch region of a *tappable* chip, so that a chip on
        // the second line cannot overlap and steal taps from the one above it; these labels have no
        // touch region to overlap.
        CadenceWrappingHStack(
            spacing: metrics.badgeSpacing,
            lineSpacing: metrics.badgeSpacing
        ) {
            if let dueDateKey {
                iOSTaskMetaLabel(
                    systemImage: "calendar",
                    text: DateFormatters.relativeDate(from: dueDateKey),
                    tint: AppleReminderRowPresentation.dueTint(
                        dayOffset: DateFormatters.dayOffset(from: dueDateKey)
                    )
                )
            }

            iOSTaskMetaLabel(
                systemImage: "list.bullet",
                text: reminder.listTitle,
                tint: Theme.purple
            )
        }
    }

    /// The circle settles first and the write follows, which is `AppleReminderTaskRow`'s timing on
    /// macOS: the row is about to be removed from a list it does not own, so the tick has to land
    /// before the fetch that makes it disappear.
    private func complete() {
        guard reminder.allowsCompletion, !isCompleting else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            isCompleting = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onComplete(reminder.id)
        }
    }
}
#endif
