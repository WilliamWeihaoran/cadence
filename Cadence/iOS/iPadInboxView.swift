#if os(iOS)
import SwiftData
import SwiftUI

struct iPadInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var newTitle = ""
    @AppStorage("ios.inbox.sortMode") private var sortModeRaw = iOSTaskSortMode.listOrder.rawValue
    @AppStorage("ios.inbox.showCompleted") private var showCompleted = false

    private var sortMode: iOSTaskSortMode {
        get { iOSTaskSortMode(rawValue: sortModeRaw) ?? .listOrder }
        set { sortModeRaw = newValue.rawValue }
    }

    private var inboxTasks: [AppTask] {
        CadenceTaskQuerySupport.activeInboxTasks(
            from: allTasks,
            sortMode: sortMode.cadenceSortMode
        )
    }

    private var completedInboxTasks: [AppTask] {
        CadenceTaskQuerySupport.completedInboxTasks(from: allTasks)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                ScrollView {
                    VStack(spacing: 16) {
                        iOSCompactPageHeader(
                            eyebrow: "Capture",
                            title: "Inbox",
                            subtitle: "Fast capture before you decide where things belong.",
                            systemImage: "tray.fill",
                            color: Theme.blue
                        )

                        inboxColumn
                            .frame(minHeight: 520)
                            .iOSCompactPanelCard()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
            } else {
                inboxColumn
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.large)
    }

    private var inboxColumn: some View {
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
            .padding(.horizontal, 16)
            .padding(.top, 16)

            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedInboxTasks.count
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            if inboxTasks.isEmpty && (!showCompleted || completedInboxTasks.isEmpty) {
                iOSEmptyPanel(
                    systemImage: "tray",
                    title: "Inbox is clear",
                    subtitle: "Fast capture lives here before you decide where things belong."
                )
            } else {
                List {
                    if !inboxTasks.isEmpty {
                        Section {
                            ForEach(inboxTasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Active", color: Theme.dim)
                        }
                    }

                    if showCompleted && !completedInboxTasks.isEmpty {
                        Section {
                            ForEach(completedInboxTasks.prefix(12)) { task in
                                iOSTaskListRow(task: task, opacity: 0.62)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Completed", color: Theme.green)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
            }
        }
        .background(Theme.bg)
    }

    private func captureInboxTask() {
        guard let task = CadenceTaskQuerySupport.makeTask(title: newTitle, allTasks: allTasks) else {
            return
        }
        modelContext.insert(task)
        try? modelContext.save()
        newTitle = ""
    }
}
#endif
