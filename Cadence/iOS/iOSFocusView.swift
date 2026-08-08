#if os(iOS)
import SwiftData
import SwiftUI

struct iOSFocusView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \MarkdownImageAsset.createdAt) private var imageAssets: [MarkdownImageAsset]
    @State private var selectedTaskID: UUID?
    @State private var selectedReferenceNote: Note?
    @State private var selectedReferenceTask: AppTask?
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

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            selectedTaskID = selectedTaskID ?? readyTasks.first?.id
        }
        .iOSMarkdownReferenceSheets(
            selectedNote: $selectedReferenceNote,
            selectedTask: $selectedReferenceTask,
            referenceNotes: allNotes,
            referenceTasks: allTasks
        )
    }

    private var horizontalLayout: some View {
        HStack(spacing: 0) {
            taskListPane
                .frame(minWidth: 300, idealWidth: 360)

            Divider().background(Theme.borderSubtle)

            focusDetailPane
        }
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                iOSCompactPageHeader(
                    eyebrow: "Focus",
                    title: "Focus",
                    subtitle: "Pick one scheduled task and keep the timer close.",
                    systemImage: "timer",
                    color: Theme.red
                )

                if readyTasks.isEmpty {
                    // A single consolidated empty state avoids showing two
                    // near-duplicate "nothing here" messages stacked on top
                    // of each other (task list pane + focus detail pane).
                    iOSEmptyPanel(
                        systemImage: "timer",
                        title: "No focus tasks",
                        subtitle: "Schedule a task for today and it will appear here, ready to focus on."
                    )
                    .frame(minHeight: 360)
                    .iOSCompactPanelCard()
                } else {
                    taskListPane
                        .frame(minHeight: 280, maxHeight: 360)
                        .iOSCompactPanelCard()

                    focusDetailPane
                        .frame(minHeight: 430)
                        .iOSCompactPanelCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var taskListPane: some View {
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
                        select(task)
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
        .background(Theme.surface)
    }

    private var focusDetailPane: some View {
        VStack(spacing: isCompact ? 18 : 22) {
            if let task = selectedTask {
                selectedTaskHeader(task)
                focusClock
                focusControls(for: task)
                taskNotes(task)
            } else {
                iOSEmptyPanel(
                    systemImage: "timer",
                    title: "Ready when you are",
                    subtitle: "Today tasks will appear here."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(isCompact ? 18 : 24)
        .background(Theme.bg)
    }

    private func selectedTaskHeader(_ task: AppTask) -> some View {
        VStack(spacing: 6) {
            Text(task.title.isEmpty ? "Untitled Task" : task.title)
                .font(.system(size: isCompact ? 22 : 24, weight: .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(task.containerName.isEmpty ? task.priority.label : task.containerName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
    }

    private var focusClock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(CadenceFocusSupport.clockDisplay(elapsedSeconds: elapsedSeconds))
                .font(.system(size: isCompact ? 54 : 62, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
    }

    private func focusControls(for task: AppTask) -> some View {
        HStack(spacing: 12) {
            Button {
                toggleTimer()
            } label: {
                Label(timerState.isRunning ? "Pause" : "Start", systemImage: timerState.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onColor)
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
    }

    @ViewBuilder
    private func taskNotes(_ task: AppTask) -> some View {
        if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            iOSMarkdownPreview(
                markdown: task.notes,
                imageAssets: imageAssets,
                taskEmbeds: taskEmbedInfos,
                onOpenReference: openMarkdownReference
            )
            .frame(maxWidth: 560, minHeight: 140, maxHeight: isCompact ? 260 : 320, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .shadow(color: Theme.cardElevationShadow, radius: 10, x: 0, y: 4)
        }
    }

    private var taskEmbedInfos: [UUID: MarkdownTaskEmbedRenderInfo] {
        Dictionary(uniqueKeysWithValues: allTasks.map { task in
            (task.id, MarkdownTaskEmbedRenderInfo.task(task))
        })
    }

    private func openMarkdownReference(_ target: MarkdownReferenceDisplayTarget) {
        switch target.kind {
        case .note:
            selectedReferenceNote = iOSMarkdownReferenceResolver.note(for: target, in: allNotes)
        case .task:
            selectedReferenceTask = iOSMarkdownReferenceResolver.task(for: target, in: allTasks)
        }
    }

    private func select(_ task: AppTask) {
        selectedTaskID = task.id
        resetTimer()
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
