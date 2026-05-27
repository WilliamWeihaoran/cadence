#if os(iOS)
import SwiftData
import SwiftUI

struct iPadInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var newTitle = ""
    @State private var saveError: String?
    @AppStorage("ios.inbox.sortMode") private var sortModeRaw = CadenceTaskSortMode.listOrder.rawValue
    @AppStorage("ios.inbox.showCompleted") private var showCompleted = false

    private var sortMode: CadenceTaskSortMode {
        get { CadenceTaskSortMode(rawValue: sortModeRaw) ?? .listOrder }
        set { sortModeRaw = newValue.rawValue }
    }

    private var inboxTasks: [AppTask] {
        CadenceTaskQuerySupport.activeInboxTasks(
            from: allTasks,
            sortMode: sortMode
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
                HStack(spacing: 0) {
                    inboxColumn
                        .frame(minWidth: 440, idealWidth: 560, maxWidth: 680)
                        .layoutPriority(0.62)

                    Divider().background(Theme.borderSubtle)

                    iPadInboxStatusPanel(
                        activeCount: inboxTasks.count,
                        completedCount: completedInboxTasks.count,
                        oldestTask: inboxTasks.min { $0.createdAt < $1.createdAt }
                    )
                    .frame(minWidth: 280, idealWidth: 340)
                    .layoutPriority(0.38)
                }
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

            if let saveError {
                iOSInlineErrorBanner(message: saveError) {
                    self.saveError = nil
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

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
        let pendingTitle = newTitle
        do {
            _ = try CadenceTaskMutationSupport.insertTask(
                title: newTitle,
                allTasks: allTasks,
                modelContext: modelContext
            )
            saveError = nil
            newTitle = ""
        } catch {
            newTitle = pendingTitle
            saveError = "Couldn't save this inbox task. Try again in a moment."
        }
    }
}

private struct iPadInboxStatusPanel: View {
    let activeCount: Int
    let completedCount: Int
    let oldestTask: AppTask?

    private var oldestLabel: String {
        guard let oldestTask else { return "Clear" }
        return DateFormatters.relativeDate(from: DateFormatters.dateKey(from: oldestTask.createdAt))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(eyebrow: "Workspace", title: "Inbox")

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        iOSMetricTile(title: "Active", value: "\(activeCount)", icon: "tray.full.fill", color: Theme.blue)
                        iOSMetricTile(title: "Done", value: "\(completedCount)", icon: "checkmark.circle.fill", color: Theme.green)
                    }

                    CadenceSettingsCard {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Oldest item")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .textCase(.uppercase)
                                .kerning(0.8)

                            Text(oldestLabel)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }
}
#endif
