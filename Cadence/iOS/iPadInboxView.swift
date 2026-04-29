#if os(iOS)
import SwiftData
import SwiftUI

struct iPadInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var newTitle = ""

    private var inboxTasks: [AppTask] {
        allTasks
            .filter { $0.area == nil && $0.project == nil && !$0.isDone && !$0.isCancelled }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(
                eyebrow: "Capture",
                title: "Inbox",
                count: inboxTasks.count
            )

            Divider().background(Theme.borderSubtle)

            iOSTaskCaptureBar(
                placeholder: "Add an inbox task...",
                title: $newTitle,
                action: captureInboxTask
            )
            .padding(16)

            if inboxTasks.isEmpty {
                iOSEmptyPanel(
                    systemImage: "tray",
                    title: "Inbox is clear",
                    subtitle: "Fast capture lives here before you decide where things belong."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(inboxTasks) { task in
                            iOSTaskRow(task: task)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.large)
    }

    private func captureInboxTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let task = AppTask(title: trimmed)
        task.estimatedMinutes = 30
        task.order = nextTaskOrder()
        modelContext.insert(task)
        try? modelContext.save()
        newTitle = ""
    }

    private func nextTaskOrder() -> Int {
        (allTasks.map(\.order).max() ?? -1) + 1
    }
}
#endif
