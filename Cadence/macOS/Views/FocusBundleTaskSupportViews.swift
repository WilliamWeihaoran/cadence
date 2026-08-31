#if os(macOS)
import SwiftUI

struct FocusBundleTasksPanel: View {
    let bundle: TaskBundle
    @Binding var selectedTaskIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .frame(width: 24, height: 24)
                        .background(Theme.amber.opacity(0.1))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bundle tasks")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Selected tasks receive logged time from this session.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(spacing: 8) {
                    if bundle.sortedTasks.isEmpty {
                        Text("This bundle is empty.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    } else {
                        ForEach(Array(bundle.sortedTasks.enumerated()), id: \.element.id) { index, task in
                            FocusBundleTaskRow(
                                task: task,
                                isSelected: selectedTaskIDs.contains(task.id),
                                canMoveUp: index > 0,
                                canMoveDown: index < bundle.sortedTasks.count - 1,
                                onToggle: { toggle(task) },
                                onMove: { SchedulingActions.moveTaskInBundle(task, direction: $0) },
                                onRemove: {
                                    selectedTaskIDs.remove(task.id)
                                    SchedulingActions.removeTaskFromBundle(task)
                                }
                            )
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.72), lineWidth: 1)
        }
    }

    private func toggle(_ task: AppTask) {
        if selectedTaskIDs.contains(task.id) {
            selectedTaskIDs.remove(task.id)
        } else {
            selectedTaskIDs.insert(task.id)
        }
    }
}

struct FocusBundleTaskRow: View {
    let task: AppTask
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: () -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // **Not a completion circle.** This control includes the task in the session's time
            // log; it does not finish it. It used to draw `checkmark.circle.fill` in `Theme.green`
            // — the app's completion glyph, in the app's completion colour — beside two other
            // bundle member rows where that same glyph *is* completion state, so the one row in
            // the app where the leading circle means something else was the one you could not
            // tell apart. A square reads as a checkbox, and the amber is this panel's own accent,
            // the tint on the "Bundle tasks" header above it.
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Theme.amber : Theme.dim)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .accessibilityLabel("Include in time log")
            .accessibilityValue(isSelected ? "On" : "Off")
            .help(isSelected ? "Exclude from time log" : "Include in time log")

            VStack(alignment: .leading, spacing: CadenceBundleTaskRowMetrics.summarySpacing) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: CadenceBundleTaskRowMetrics.titleSize, weight: CadenceBundleTaskRowMetrics.titleWeight))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .lineLimit(CadenceBundleTaskRowMetrics.titleLineLimit)
                    .strikethrough(task.isDone, color: Theme.dim.opacity(0.75))
                CadenceTaskDetailLineLabel(
                    parts: detailParts,
                    fontSize: CadenceBundleTaskRowMetrics.detailSize
                )
            }

            Spacer(minLength: 8)

            if task.isDone {
                Text("Done")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.green)
            }

            focusRowIconButton("chevron.up", isDisabled: !canMoveUp) { onMove(-1) }
            focusRowIconButton("chevron.down", isDisabled: !canMoveDown) { onMove(1) }
            focusRowIconButton("xmark", isDisabled: false, action: onRemove)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surfaceElevated.opacity(isSelected ? 0.95 : 0.66))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Theme.amber.opacity(0.18) : Color.clear, lineWidth: 1)
        }
    }

    /// The one row that asks for `includesLoggedTime`. This panel hands the session's minutes to
    /// the tasks you tick, so `45/60m` — logged against estimate — is the number it is about; every
    /// other bundle member row states the estimate alone.
    private var detailParts: CadenceTaskDetailLine {
        CadenceBundleTaskRowSupport.detailParts(for: task, includesLoggedTime: true)
    }

    private func focusRowIconButton(_ systemName: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isDisabled ? Theme.dim.opacity(0.35) : Theme.dim)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .disabled(isDisabled)
    }
}

#endif
