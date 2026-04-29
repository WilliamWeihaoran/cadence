#if os(macOS)
import SwiftUI

struct TaskInspectorRecurrenceControl: View {
    @Bindable var task: AppTask

    var body: some View {
        Menu {
            ForEach(TaskRecurrenceRule.allCases, id: \.self) { rule in
                Button {
                    task.recurrenceRule = rule
                } label: {
                    Label(rule.label, systemImage: rule.systemImage)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: task.recurrenceRule.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(task.isRecurring ? Theme.blue : Theme.dim)
                Text(task.recurrenceRule.shortLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(task.isRecurring ? Theme.text : Theme.dim)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.7))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.surfaceElevated.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
    }
}
#endif
