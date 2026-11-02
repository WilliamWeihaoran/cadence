#if os(iOS)
import SwiftUI

/// **The Mac's Log Session form, on iOS** ([[T-8732]], under [[T-8201]]).
///
/// The Focus check control used to be "Log session and mark done" and completed the task in one
/// tap, so a session started on a phone or an iPad could never be logged *without* finishing the
/// task, and the minutes it banked could not be corrected. macOS has offered the choice since it
/// had a Focus page: editable hours and minutes, an optional completion, and a Discard that throws
/// the stopwatch away. The owner chose the Mac's model for iOS on 2026-10-31 — iOS today can do
/// neither of the two things the form buys — so this is that form, and only its container differs.
///
/// The container is the half [[T-8201]] allows to differ, and it is the half that does: macOS
/// anchors a popover to the control, which has no meaning under a finger, so this is a detented
/// sheet sized to what it draws. Everything the user can *choose* is the same, read from the same
/// `CadenceFocusSupport` seed, parse, labels and confirm title the popover reads, because a second
/// copy of "what does 90 in the minutes field mean" is how the two drifted apart in the first place.
struct iOSFocusLogSessionSheet: View {
    let task: AppTask
    /// Hours, minutes, and whether to finish the task — the popover's own `onLog` shape.
    let onLog: (Int, Int, Bool) -> Void
    let onDiscard: () -> Void

    /// Text, not `Int`, for the reason T-5304 gives on the Mac: a field bound to a number writes it
    /// only on commit, and the confirm button never ends editing, so a typed figure was on screen
    /// while the button logged the pre-filled one. The text is parsed at the moment it is read.
    @State private var logHoursText: String
    @State private var logMinutesText: String
    /// Off when the form opens, as it is on the Mac: logging the time is the act, and finishing the
    /// task is the extra the user has to ask for. That is the whole point of this ticket.
    @State private var markComplete = false
    /// The sheet is as tall as what it draws, the house rule for a card-shaped presentation.
    @State private var cardHeight: CGFloat = 300

    init(
        task: AppTask,
        elapsedSeconds: Int,
        onLog: @escaping (Int, Int, Bool) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.task = task
        self.onLog = onLog
        self.onDiscard = onDiscard
        let seed = CadenceFocusSupport.logFieldSeed(elapsedSeconds: elapsedSeconds)
        _logHoursText = State(initialValue: String(seed.hours))
        _logMinutesText = State(initialValue: String(seed.minutes))
    }

    private var logValues: (hours: Int, minutes: Int) {
        CadenceFocusSupport.logFieldValues(hoursText: logHoursText, minutesText: logMinutesText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Theme.borderSubtle)
            fields
            Divider().background(Theme.borderSubtle)
            footer
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 + 24 }
        .frame(maxWidth: 420)
        .padding(12)
        .frame(maxWidth: .infinity)
        .presentationBackground(.clear)
        .presentationDetents([.height(cardHeight)])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CadenceFocusSupport.logFormTitle)
                .cadenceFont(.composerTitle, base: 17, weight: .semibold)
                .foregroundStyle(Theme.text)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: task.containerColor))
                    .frame(width: 7, height: 7)
                // T-7065's spelling, so an untitled task reads "Untitled Task" here as it does on
                // the session header behind this sheet, not as an empty line.
                Text(TaskTitleSupport.displayTitle(task.title))
                    .cadenceFont(.metadata, base: 12)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(CadenceFocusSupport.logFormFieldsLabel)
                    .cadenceFont(.fieldLabel, base: 12, weight: .medium)
                    .foregroundStyle(Theme.dim)
                HStack(spacing: 12) {
                    timeField(label: "h", text: $logHoursText, accessibilityLabel: "Hours to log")
                    timeField(label: "min", text: $logMinutesText, accessibilityLabel: "Minutes to log")
                    Spacer(minLength: 0)
                }
            }

            // A row, not a `Toggle`'s own label: the sentence takes the width it needs and the
            // switch stays at the trailing edge where every other iOS switch in the app sits.
            Toggle(isOn: $markComplete) {
                Text(CadenceFocusSupport.logFormCompleteLabel)
                    .cadenceFont(.rowTitle, base: 14)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(Theme.green)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            iOSActionButton(
                title: CadenceFocusSupport.logFormDiscardTitle,
                role: .ghost,
                size: .compact,
                action: onDiscard
            )

            Spacer(minLength: 0)

            iOSActionButton(
                title: CadenceFocusSupport.logButtonTitle(hours: logValues.hours, minutes: logValues.minutes),
                role: .primary,
                size: .compact,
                action: submitLog
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// The Log button's action and Return's in either field ([[T-10037]]): one read of the typed
    /// figures, so the two cannot log different totals -- the Mac popover's `submitLog()`
    /// ([[T-10017]]).
    private func submitLog() {
        onLog(logValues.hours, logValues.minutes, markComplete)
    }

    @ViewBuilder
    private func timeField(label: String, text: Binding<String>, accessibilityLabel: String) -> some View {
        HStack(spacing: 5) {
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .cadenceFont(.fieldValue, base: 16, weight: .medium)
                .foregroundStyle(Theme.text)
                .frame(width: 62, height: 44)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .accessibilityLabel(accessibilityLabel)
                // [[T-10037]]: the number pad has no Return, but an iPad's hardware keyboard does,
                // and Return there did nothing while the Mac popover's same fields log
                // ([[T-10017]]). Discard takes no key -- it throws the session away.
                .onSubmit(submitLog)
            Text(label)
                .cadenceFont(.metadata, base: 12)
                .foregroundStyle(Theme.dim)
        }
    }
}

#endif
