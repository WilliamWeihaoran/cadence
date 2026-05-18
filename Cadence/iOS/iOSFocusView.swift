#if os(iOS)
import SwiftData
import SwiftUI

struct iOSFocusView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var selectedTaskID: UUID?
    @State private var timerState = CadenceFocusTimerState()

    private var todayKey: String { DateFormatters.todayKey() }

    private var readyTasks: [AppTask] {
        CadenceFocusSupport.readyTasks(from: allTasks, todayKey: todayKey)
    }

    private var selectedTask: AppTask? {
        if let selectedTaskID {
            return readyTasks.first { $0.id == selectedTaskID } ?? allTasks.first { $0.id == selectedTaskID }
        }
        return readyTasks.first
    }

    private var elapsedSeconds: Int {
        timerState.elapsedSeconds()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                iOSPanelHeader(eyebrow: "Focus", title: "Focus", count: readyTasks.count)
                Divider().background(Theme.borderSubtle)

                if readyTasks.isEmpty {
                    iOSEmptyPanel(
                        systemImage: "timer",
                        title: "No focus tasks",
                        subtitle: "Schedule a task for today to focus it here."
                    )
                } else {
                    List(readyTasks) { task in
                        Button {
                            selectedTaskID = task.id
                            resetTimer()
                        } label: {
                            iOSFeatureTaskSummaryRow(
                                title: task.title.isEmpty ? "Untitled Task" : task.title,
                                subtitle: CadenceFocusSupport.sidebarDetail(for: task, todayKey: todayKey),
                                detail: task.estimatedMinutes > 0 ? "\(task.estimatedMinutes)m" : task.priority.label,
                                icon: task.priority == .high ? "exclamationmark.circle.fill" : "circle",
                                color: Theme.priorityColor(task.priority),
                                isSelected: selectedTask?.id == task.id
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 300, idealWidth: 360)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 22) {
                if let task = selectedTask {
                    VStack(spacing: 6) {
                        Text(task.title.isEmpty ? "Untitled Task" : task.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                        Text(task.containerName.isEmpty ? task.priority.label : task.containerName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }

                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(CadenceFocusSupport.clockDisplay(elapsedSeconds: elapsedSeconds))
                            .font(.system(size: 62, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }

                    HStack(spacing: 12) {
                        Button {
                            toggleTimer()
                        } label: {
                            Label(timerState.isRunning ? "Pause" : "Start", systemImage: timerState.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(timerState.isRunning ? Theme.amber : Theme.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            resetTimer()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .frame(width: 40, height: 38)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            complete(task)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.green)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Theme.green.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(task.notes)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: 520, alignment: .leading)
                            .padding(14)
                            .background(Theme.surfaceElevated.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                } else {
                    iOSEmptyPanel(
                        systemImage: "timer",
                        title: "Ready when you are",
                        subtitle: "Today tasks will appear here."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(Theme.bg)
        }
        .onAppear {
            selectedTaskID = selectedTaskID ?? readyTasks.first?.id
        }
    }

    private func toggleTimer() {
        timerState.toggle()
    }

    private func resetTimer() {
        timerState.reset()
    }

    private func complete(_ task: AppTask) {
        CadenceFocusSupport.complete(task, elapsedSeconds: elapsedSeconds, modelContext: modelContext)
        resetTimer()
        selectedTaskID = readyTasks.first { $0.id != task.id }?.id
    }
}
#endif
