#if os(iOS)
import SwiftData
import SwiftUI

struct iPadInboxView: View {
    /// Off when the Tasks tab hosts this as its Inbox segment — see
    /// `iPadTodayView.showsCompactHeader`. Still on when Inbox is reached as a pushed screen.
    var showsCompactHeader = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
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

    /// **One full-width column.** The iPad layout used to be an `HStack` of the list and an
    /// "Overview" pane, which spent about a third of the screen on "0 ACTIVE", "0 DONE" and an
    /// "OLDEST ITEM" that read "Clear" whenever there was nothing to be oldest. Every one of those
    /// three was already on screen: the active count is the badge in the page header, and the oldest
    /// item is the last row of a list sorted by list order.
    ///
    /// Deleting it also removed the last pane on this surface that declared a `minWidth` with no way
    /// to honour it — `440 + 1 + 280` against 632pt of detail on an 11" iPad — which is what
    /// overflowed the root shell and pushed the sidebar off the leading edge of the screen. See
    /// `CadenceRootShellLayout`, which now stops that at the shell regardless.
    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                iOSCompactInboxView(
                    showsHeader: showsCompactHeader,
                    inboxTasks: inboxTasks,
                    completedInboxTasks: completedInboxTasks,
                    sortMode: Binding(
                        get: { sortMode },
                        set: { sortModeRaw = $0.rawValue }
                    ),
                    showCompleted: $showCompleted
                )
            } else {
                inboxColumn
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        // No seed: the Inbox is where a task goes when it has no list yet, so seeding one would
        // contradict the surface it was captured from.
        .iOSFloatingCreateTaskButton()
        // Both layouts head themselves with "CAPTURE / Inbox", so a nav title repeated the word
        // one row higher. See `iOSHidesCompactNavigationBar()`.
        .iOSHidesCompactNavigationBar()
    }

    private var inboxColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(
                eyebrow: "Capture",
                title: "Inbox",
                count: inboxTasks.count
            )

            Divider().background(Theme.borderSubtle)

            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedInboxTasks.count
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if inboxTasks.isEmpty && (!showCompleted || completedInboxTasks.isEmpty) {
                iOSEmptyPanel(
                    systemImage: "tray",
                    title: CadenceEmptyStateCopy.inboxTitle,
                    subtitle: CadenceEmptyStateCopy.inboxSubtitle
                )
            } else {
                List {
                    if !inboxTasks.isEmpty {
                        Section {
                            ForEach(inboxTasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            // Blue, and counted, exactly as on the phone and on All Tasks at both
                            // widths. This one header was grey, so "Active" meant something
                            // different here than three taps away.
                            iOSTaskGroupHeader(title: "Active", color: Theme.blue, count: inboxTasks.count)
                        }
                    }

                    if showCompleted && !completedInboxTasks.isEmpty {
                        Section {
                            ForEach(CadenceTaskSurfaceOptions.completedRows(from: completedInboxTasks)) { task in
                                iOSTaskListRow(task: task, opacity: 0.62)
                            }
                        } header: {
                            iOSTaskGroupHeader(
                                title: "Completed",
                                color: Theme.green,
                                count: CadenceTaskSurfaceOptions.completedRows(from: completedInboxTasks).count
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }
}
#endif
