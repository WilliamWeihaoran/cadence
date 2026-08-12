#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCompactTodayView: View {
    let todayTasks: [AppTask]
    let completedTodayTasks: [AppTask]
    let compactScheduleTasks: [AppTask]
    let todayTaskGroups: [CadenceTodayTaskGroup]
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool
    @Binding var newTitle: String
    @Binding var saveError: String?
    let captureTodayTask: () -> Void
    #if DEBUG
    let sampleDataStatus: String?
    let seedSampleData: () -> Void
    #endif

    private var summary: CadenceTodaySummary {
        CadenceTodayPresentationSupport.summary(
            activeTasks: todayTasks,
            timedTasks: compactScheduleTasks,
            completedTasks: completedTodayTasks
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                header
                captureCard
                stats
                taskSections
                iOSCompactTodayNotesCard()

                if !compactScheduleTasks.isEmpty {
                    iOSCompactTodaySchedulePreview(tasks: compactScheduleTasks)
                }
            }
            .frame(maxWidth: 520, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 132)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            iOSIconTile(systemImage: "sun.max.fill", color: Theme.amber, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormatters.longDate.string(from: Date()))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text("Today")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(todayTasks.count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.blue.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.top, 2)
        .padding(.bottom, 1)
    }

    private var stats: some View {
        HStack(spacing: 7) {
            ForEach(summary.metrics) { metric in
                iOSCompactTodayMetric(metric: metric)
            }
        }
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            iOSTaskCaptureBar(
                placeholder: "Add a task...",
                title: $newTitle,
                action: captureTodayTask
            )

            if let saveError {
                iOSInlineErrorBanner(message: saveError) {
                    self.saveError = nil
                }
            }

            iOSTaskViewOptionsBar(
                sortMode: $sortMode,
                showCompleted: $showCompleted,
                completedCount: completedTodayTasks.count
            )
        }
        .padding(10)
        .cadenceCard(background: Theme.surface.opacity(0.94), cornerRadius: Theme.radiusCard)
    }

    @ViewBuilder
    private var taskSections: some View {
        if todayTasks.isEmpty && (!showCompleted || completedTodayTasks.isEmpty) {
            iOSCompactTodayEmptyState()
                .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)

            #if DEBUG
            iOSCompactSampleDataCard(
                status: sampleDataStatus,
                action: seedSampleData
            )
            #endif
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(todayTaskGroups, id: \.title) { group in
                    iOSCompactTodayTaskGroup(
                        group: group,
                        color: CadenceTodayPresentationSupport.accent(for: group.kind)
                    )
                }

                if showCompleted && !completedTodayTasks.isEmpty {
                    iOSCompactCompletedTasks(tasks: Array(completedTodayTasks.prefix(12)))
                }
            }
            .padding(12)
            .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)
        }
    }

}

private struct iOSCompactTodayNotesCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var todayNote: Note?
    @AppStorage(iOSMarkdownEditorPreferences.modeKey) private var editorModeRaw = iOSMarkdownEditorPreferences.defaultMode.rawValue
    @FocusState private var isEditorFocused: Bool

    private var editorMode: iOSMarkdownEditorMode {
        iOSMarkdownEditorPreferences.mode(from: editorModeRaw)
    }

    private var editorModeBinding: Binding<iOSMarkdownEditorMode> {
        iOSMarkdownEditorPreferences.binding(for: $editorModeRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(Theme.borderSubtle.opacity(0.65))

            if let todayNote {
                iOSMarkdownEditingSurface(
                    text: Binding(
                        get: { todayNote.content },
                        set: { update(todayNote, content: $0) }
                    ),
                    isFocused: Binding(
                        get: { isEditorFocused },
                        set: { isEditorFocused = $0 }
                    ),
                    mode: editorModeBinding,
                    placeholder: "Start today's note...",
                    referenceNotes: allNotes,
                    referenceTasks: allTasks
                )
                .frame(height: editorMode == .live ? 280 : 260)
            } else {
                ProgressView()
                    .tint(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
            }
        }
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)
        .onAppear(perform: loadTodayNote)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            loadTodayNote()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isEditorFocused = false
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            iOSIconTile(systemImage: "note.text", color: Theme.purple)

            // "Quick daily context" under a card headed "Today Note" restates the card.
            Text("Today Note")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            iOSMarkdownModePicker(mode: editorModeBinding, compact: true)

            if let todayNote {
                iOSNoteTemplateMenu(kind: .daily, compact: true) { template in
                    apply(template, to: todayNote)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
    }

    private func loadTodayNote() {
        todayNote = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: modelContext).today
    }

    private func update(_ note: Note, content: String) {
        CadenceCoreNoteSupport.update(note, content: content, in: modelContext)
    }

    private func apply(_ template: NoteTemplate, to note: Note) {
        CadenceNoteTemplateInsertionSupport.apply(template, to: note, in: modelContext)
    }
}

private struct iOSCompactTodayEmptyState: View {
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 42, height: 42)
                .background(Theme.surfaceElevated.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.42), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(CadenceTodayPresentationSupport.emptyCompactTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(CadenceTodayPresentationSupport.emptySubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

#if DEBUG
private struct iOSCompactSampleDataCard: View {
    let status: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            iOSIconTile(systemImage: "wand.and.stars", color: Theme.amber, bordered: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(status ?? "Need realistic rows?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                Text("Seed local simulator tasks for Today, Inbox, and Timeline.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 34, height: 34)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .accessibilityLabel("Seed sample tasks")
        }
        .padding(12)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)
    }
}
#endif

private struct iOSCompactTodayMetric: View {
    let metric: CadenceTodaySummaryMetric

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(metric.tint)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(metric.value)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
                Text(metric.label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated.opacity(0.36))
        .clipShape(Capsule())
    }
}

private struct iOSCompactTodayTaskGroup: View {
    let group: CadenceTodayTaskGroup
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                iOSTaskSectionHeader(title: group.title, color: color)
                Spacer()
                Text("\(group.tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.11))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(group.tasks) { task in
                    iOSTaskRow(task: task, density: .compact)
                }
            }
        }
    }
}

private struct iOSCompactCompletedTasks: View {
    let tasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                iOSTaskSectionHeader(title: "Completed Today", color: Theme.green)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.green.opacity(0.11))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(tasks) { task in
                    iOSTaskRow(task: task, density: .compact)
                        .opacity(0.62)
                }
            }
        }
    }
}

private struct iOSCompactTodaySchedulePreview: View {
    let tasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .textCase(.uppercase)
                        .kerning(0.8)
                    Text("Timeline")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                }

                Spacer()

                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.purple.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    iOSCompactScheduleTaskRow(task: task)
                }
            }
        }
        .padding(14)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard)
    }
}

private struct iOSCompactScheduleTaskRow: View {
    let task: AppTask

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(startLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.purple)
                    .monospacedDigit()
                    .lineLimit(1)

                if !endLabel.isEmpty {
                    Text(endLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.purple.opacity(0.72))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "Untitled Task" : task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(task.containerName.isEmpty ? "Inbox" : task.containerName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.35))
                .frame(height: 1)
        }
    }

    private var startLabel: String {
        TimeFormatters.timeString(from: task.scheduledStartMin)
    }

    private var endLabel: String {
        guard task.scheduledEndMin > task.scheduledStartMin else { return "" }
        return TimeFormatters.timeString(from: task.scheduledEndMin)
    }
}

#endif
