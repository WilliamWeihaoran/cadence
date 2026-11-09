#if os(macOS)
import SwiftUI

private struct FocusSurfaceHeader<Metadata: View>: View {
    let eyebrow: String
    let title: String
    let onClose: () -> Void
    @ViewBuilder let metadata: () -> Metadata

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrowLabel(text: eyebrow)

                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                metadata()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.cadencePlain(.circle))
            .cadenceControlLabel("Close focus session")
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
    }
}

private struct FocusMetaSeparator: View {
    var body: some View {
        Text("/")
            .foregroundStyle(Theme.dim.opacity(0.42))
    }
}

struct FocusSessionHeader: View {
    let task: AppTask
    let estimateLabel: String?
    /// [[T-14353]]: the Focus page's observed day, so the due chip turns at midnight.
    let todayKey: String
    let onClose: () -> Void

    var body: some View {
        let hasContainer = !task.containerName.isEmpty
        let hasPriority = task.priority != .none
        let dueLabel = CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: task.dueDate, todayKey: todayKey)
        let hasDueDate = dueLabel != nil
        let hasEstimate = estimateLabel != nil
        // [[T-11211]] (b): the shared helper decides whether the task repeats.
        let recurrence = CadenceFocusSupport.sessionHeaderRecurrence(for: task.recurrenceRule)
        let hasRecurrence = recurrence != nil

        FocusSurfaceHeader(
            eyebrow: "Focus Session",
            title: TaskTitleSupport.displayTitle(task.title),
            onClose: onClose
        ) {
            HStack(spacing: 7) {
                if hasContainer {
                    Label {
                        Text(task.containerName)
                    } icon: {
                        Circle()
                            .fill(Color(hex: task.containerColor))
                            .frame(width: 6, height: 6)
                    }
                    if hasPriority || hasDueDate || hasEstimate || hasRecurrence { FocusMetaSeparator() }
                }

                if hasPriority {
                    Label {
                        Text(task.priority.label)
                    } icon: {
                        Circle()
                            .fill(Theme.priorityColor(task.priority))
                            .frame(width: 6, height: 6)
                    }
                    if hasDueDate || hasEstimate || hasRecurrence { FocusMetaSeparator() }
                }

                if let dueLabel {
                    // [[T-11209]]: red when overdue, the rule iOS's due chip in the same header
                    // reads, through the same predicate.
                    Text(dueLabel)
                        .foregroundStyle(
                            CadenceFocusSupport.isOverdue(dueDateKey: task.dueDate, todayKey: todayKey)
                                ? Theme.red : Theme.dim
                        )
                    if hasEstimate || hasRecurrence { FocusMetaSeparator() }
                }

                if let estimateLabel {
                    Text(estimateLabel)
                        .lineLimit(1)
                    if hasRecurrence { FocusMetaSeparator() }
                }

                if let recurrence {
                    // The glyph takes the Mac sidebar repeat chip's blue, as the dots take their
                    // list and priority colours; the words stay the row's dim.
                    Label {
                        Text(recurrence.label)
                    } icon: {
                        Image(systemName: recurrence.systemImage)
                            .foregroundStyle(Theme.blue)
                    }
                }
            }
        }
    }
}

struct FocusTimerPanel<Controls: View>: View {
    let clockDisplay: String
    /// What finishing will bank, under the clock -- `CadenceFocusSupport.logHint`, the line iOS's
    /// timer card draws in the same place ([[T-11209]], under [[T-8201]]).
    let logHint: String
    /// Running, paused, or never started -- the iOS card's three words (T-7018).
    let phase: CadenceFocusTimerPhase
    let accent: Color
    @ViewBuilder let controls: () -> Controls

    private var isRunning: Bool { phase == .running }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(phase.label, systemImage: phase.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isRunning ? accent : Theme.dim)
                Spacer()
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text(clockDisplay)
                    .font(.system(size: 78, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(isRunning ? Theme.text : Theme.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .contentTransition(.numericText())
                    .shadow(color: accent.opacity(isRunning ? 0.34 : 0), radius: 24)
                Text(logHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
            }

            controls()

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(isRunning ? 0.72 : 0.24))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusFocusCard, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 16, x: 0, y: 6)
    }
}

struct FocusIconButton: View {
    let systemName: String
    let foreground: Color
    let background: Color
    let size: CGFloat
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size > 44 ? 18 : 14, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
                .shadow(color: shadowColor, radius: shadowRadius)
        }
        .buttonStyle(.cadencePlain(.circle))
        .cadenceControlLabel(accessibilityLabel)
    }
}

#endif
