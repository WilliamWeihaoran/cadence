#if os(macOS)
import SwiftUI

struct LogSessionPopover: View {
    let task: AppTask
    let onLog: (Int, Int, Bool) -> Void
    let onDiscard: () -> Void

    /// Text, not `Int` (T-5304): a `TextField(value:format:)` writes its value only on commit, so
    /// clicking Log after typing read the pre-filled figure. Parsed on every read instead.
    @State private var logHoursText: String
    @State private var logMinutesText: String
    @State private var markComplete: Bool = false

    init(task: AppTask, elapsedSeconds: Int, onLog: @escaping (Int, Int, Bool) -> Void, onDiscard: @escaping () -> Void) {
        self.task = task
        self.onLog = onLog
        self.onDiscard = onDiscard
        let seed = FocusSessionSupport.logFieldSeed(elapsedSeconds: elapsedSeconds)
        _logHoursText = State(initialValue: String(seed.hours))
        _logMinutesText = State(initialValue: String(seed.minutes))
    }

    private var logHours: Int { logValues.hours }
    private var logMinutes: Int { logValues.minutes }
    private var logValues: (hours: Int, minutes: Int) {
        FocusSessionSupport.logFieldValues(hoursText: logHoursText, minutesText: logMinutesText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Log Session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: task.containerColor))
                        .frame(width: 6, height: 6)
                    // T-7065: the header's spelling, so an untitled task is "Untitled Task" here as
                    // it is on the session header behind this popover, not an empty line.
                    Text(TaskTitleSupport.displayTitle(task.title))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time to log")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    HStack(spacing: 10) {
                        timeField(label: "h", text: $logHoursText)
                        timeField(label: "min", text: $logMinutesText)
                        Spacer()
                    }
                }

                Divider().background(Theme.borderSubtle)

                HStack {
                    Toggle(isOn: $markComplete) {
                        Text("Mark task as complete")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 8) {
                Button("Discard") { onDiscard() }
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

                Spacer()

                Button {
                    onLog(logHours, logMinutes, markComplete)
                } label: {
                    Text(FocusSessionSupport.logButtonTitle(hours: logHours, minutes: logMinutes))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.onColor(for: Theme.blue))
                }
                .buttonStyle(.cadencePlain)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 260)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func timeField(label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
    }
}

#endif
