#if os(macOS)
import SwiftUI

struct LogSessionPopover: View {
    let task: AppTask
    let onLog: (Int, Int, Bool) -> Void
    let onDiscard: () -> Void

    @State private var logHours: Int
    @State private var logMinutes: Int
    @State private var markComplete: Bool = false

    init(task: AppTask, elapsedSeconds: Int, onLog: @escaping (Int, Int, Bool) -> Void, onDiscard: @escaping () -> Void) {
        self.task = task
        self.onLog = onLog
        self.onDiscard = onDiscard
        let totalMins = (elapsedSeconds + 59) / 60
        _logHours = State(initialValue: totalMins / 60)
        _logMinutes = State(initialValue: totalMins % 60)
    }

    private var totalMinutes: Int { logHours * 60 + logMinutes }

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
                    Text(task.title)
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
                        timeField(label: "h", value: $logHours)
                        timeField(label: "min", value: $logMinutes)
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
                    onLog(logHours, max(0, logMinutes), markComplete)
                } label: {
                    Text(totalMinutes > 0 ? "Log \(formatTotal())" : "Log")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.onColor)
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
    private func timeField(label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            TextField("0", value: value, format: .number)
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

    private func formatTotal() -> String {
        if logHours > 0 && logMinutes > 0 { return "\(logHours)h \(logMinutes)m" }
        if logHours > 0 { return "\(logHours)h" }
        return "\(logMinutes)m"
    }
}

struct BundleLogSessionPopover: View {
    let bundle: TaskBundle
    let selectedTasks: [AppTask]
    let onLog: (Int, Int) -> Void
    let onDiscard: () -> Void

    @State private var logHours: Int
    @State private var logMinutes: Int

    init(
        bundle: TaskBundle,
        elapsedSeconds: Int,
        selectedTasks: [AppTask],
        onLog: @escaping (Int, Int) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.bundle = bundle
        self.selectedTasks = selectedTasks
        self.onLog = onLog
        self.onDiscard = onDiscard
        let totalMins = (elapsedSeconds + 59) / 60
        _logHours = State(initialValue: totalMins / 60)
        _logMinutes = State(initialValue: totalMins % 60)
    }

    private var totalMinutes: Int { logHours * 60 + logMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Log Bundle Session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(selectedTasks.count) selected tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
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
                        timeField(label: "h", value: $logHours)
                        timeField(label: "min", value: $logMinutes)
                        Spacer()
                    }
                }

                Text("Time is distributed by each task's estimate.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            .padding(16)

            Divider().background(Theme.borderSubtle)

            HStack {
                Button("Discard", action: onDiscard)
                    .buttonStyle(.cadencePlain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                Spacer()
                Button {
                    onLog(logHours, logMinutes)
                } label: {
                    Text(totalMinutes > 0 ? "Log \(formatTotal())" : "Log")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.onColor)
                }
                .buttonStyle(.cadencePlain)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selectedTasks.isEmpty ? Theme.dim.opacity(0.35) : Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .disabled(selectedTasks.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 270)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func timeField(label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            TextField("0", value: value, format: .number)
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

    private func formatTotal() -> String {
        if logHours > 0 && logMinutes > 0 { return "\(logHours)h \(logMinutes)m" }
        if logHours > 0 { return "\(logHours)h" }
        return "\(logMinutes)m"
    }
}
#endif
