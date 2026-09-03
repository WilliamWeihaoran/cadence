#if os(macOS)
import SwiftUI
import SwiftData
import EventKit
import AppKit
import UniformTypeIdentifiers

private struct PlainTextExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// The hours this panel draws. Aliases, not literals: this was one of three independent spellings
// of the same range, and the iOS one had drifted to `6..<23`.
let schedStartHour = CadenceScheduleSupport.calendarStartHour
let schedEndHour   = CadenceScheduleSupport.calendarEndHour
let timeLabelWidth: CGFloat = 36
let timeLabelPad:   CGFloat = 6
let blockInset:     CGFloat = timeLabelWidth + timeLabelPad  // 42

enum SchedulePanelPresentation {
    /// Today's schedule column: the panel is the page's own third column and nothing above it says
    /// what it is, so it draws its own "Timeline" header.
    case standard
    /// The focus screen and the focus sidebar: same job, tighter header.
    case compact
    /// Hosted inside a pane that has **already** named it — today only `RootTimelineSidebarPane`,
    /// which titles itself "Today Timeline" and draws its own rule underneath that title.
    ///
    /// **T-615.** The pane said "timeline" twice, one line apart, and before T-602 three times. A
    /// page header does not describe the page the user is already on, and that rule does not stop
    /// at the outermost header: the second one is the one to drop, because the first is the one the
    /// user read. The divider goes with the header — the host draws that rule itself, so keeping
    /// the panel's would leave two hairlines with nothing between them.
    ///
    /// Opt-in, not a default, and that is the load-bearing half: the other three hosts have nothing
    /// above them naming the column, so a panel that dropped its heading unconditionally would
    /// leave three unnamed columns to fix one named twice.
    case hosted

    /// Whether the panel draws its own heading and the rule under it.
    var drawsOwnHeader: Bool { self != .hosted }
}

struct SchedulePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(TodayTimelineFocusManager.self) private var todayTimelineFocusManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    var presentation: SchedulePanelPresentation = .standard
    var useStandardHeaderHeight = false
    @Query private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @AppStorage("scheduleZoomLevel") private var zoomLevel: Int = 1
    @AppStorage("scheduleRememberedScrollHour") private var rememberedScrollHour: Int = -1
    @State private var isRestoringScroll = true
    @State private var didRestoreScroll = false
    @State private var isFocusHighlighted = false
    @State private var exportDocument: PlainTextExportDocument?
    @State private var isExportingTimeline = false
    /// Set when a block the timeline offered to create was refused by the store. See
    /// `createBundle(title:startMin:endMin:adding:)`.
    @State private var bundleCreateFailed = false

    private var todayKey: String { DateFormatters.todayKey() }

    private var scheduledTasks: [AppTask] {
        SchedulePanelDataSupport.scheduledTasks(from: allTasks, todayKey: todayKey)
    }

    private var todayBundles: [TaskBundle] {
        allBundles.filter { $0.dateKey == todayKey && !$0.isCompleted }
    }

    /// iCal events for today. Raw tasks are never treated as event attachments.
    private var externalEventItems: [CalendarEventItem] {
        let _ = calendarManager.storeVersion  // subscribe to store change refreshes
        return SchedulePanelDataSupport.externalEventItems(
            calendarManager: calendarManager,
            date: Date()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if presentation.drawsOwnHeader {
                SchedulePanelHeader(
                    presentation: presentation,
                    zoomLevel: $zoomLevel,
                    onExport: exportTodayPlan
                )
                .frame(height: headerHeight, alignment: .top)

                Divider().background(Theme.borderSubtle)
            }

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        SchedulePanelTimelineViewport(
                            geoSize: geo.size,
                            zoomLevel: zoomLevel,
                            allTasks: allTasks,
                            allBundles: allBundles,
                            areas: areas,
                            projects: projects,
                            scheduledTasks: scheduledTasks,
                            bundles: todayBundles,
                            todayKey: todayKey,
                            externalEventItems: externalEventItems,
                            onCreateTask: { title, startMin, endMin, containerSelection, sectionName, notes, subtaskTitles in
                                taskCreationManager.present(
                                    title: title,
                                    notes: notes,
                                    doDateKey: todayKey,
                                    scheduledStartMin: startMin,
                                    estimatedMinutes: max(5, endMin - startMin),
                                    container: containerSelection,
                                    sectionName: sectionName,
                                    subtaskTitles: subtaskTitles
                                )
                            },
                            onDropTaskAtMinute: { task, startMin in
                                SchedulingActions.dropTask(task, to: todayKey, startMin: startMin)
                            },
                            onCreateBundle: { title, startMin, endMin, selectedTasks in
                                createBundle(title: title, startMin: startMin, endMin: endMin, adding: selectedTasks)
                            },
                            onDropBundleAtMinute: { bundle, startMin in
                                SchedulingActions.dropBundle(bundle, to: todayKey, startMin: startMin)
                            },
                            onDropTaskOnBundle: { task, bundle in
                                SchedulingActions.addTask(task, to: bundle)
                            },
                            onCreateEvent: { title, startMin, endMin, calendarID, notes in
                                calendarManager.createStandaloneEvent(title: title, startMin: startMin, durationMinutes: endMin - startMin, calendarID: calendarID, date: Date(), notes: notes)
                            }
                        )
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                        SchedulePanelInteractionSupport.persistRememberedHour(
                            yOffset: y,
                            geoHeight: geo.size.height,
                            zoomLevel: zoomLevel,
                            didRestoreScroll: didRestoreScroll,
                            isRestoringScroll: isRestoringScroll
                        ) {
                            rememberedScrollHour = $0
                        }
                    }
                    .onAppear {
                        SchedulePanelDataSupport.restoreScroll(
                            proxy: proxy,
                            rememberedScrollHour: rememberedScrollHour,
                            setRestoring: { isRestoringScroll = $0 },
                            setDidRestore: { didRestoreScroll = $0 }
                        )
                    }
                    .onChange(of: todayTimelineFocusManager.focusRequestID) { _, _ in
                        focusTimeline(using: proxy)
                    }
                }
            }
        }
        .background(Theme.bg)
        .fileExporter(
            isPresented: $isExportingTimeline,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "Cadence Schedule \(todayKey)"
        ) { _ in
            exportDocument = nil
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.blue.opacity(isFocusHighlighted ? 0.95 : 0), lineWidth: 2)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .calendarWriteFailureAlert()
        // The event branch beside this panel's block branch has reported its refusals since T-238;
        // this is the block branch saying the same thing in the same place (T-636(e)).
        .alert(
            CadenceTaskMutationSupport.bundleCreateFailureAlertTitle,
            isPresented: $bundleCreateFailed
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(CadenceTaskMutationSupport.bundleSaveFailureNotice)
        }
        .onChange(of: calendarManager.storeVersion) {
            SchedulePanelDataSupport.syncLinkedTasks(
                allTasks: allTasks,
                modelContext: modelContext,
                calendarManager: calendarManager
            )
        }
    }

    /// **The block and its members are one commit, and a refusal is named here (T-636(e)).**
    ///
    /// The closure this replaces ran `SchedulingActions.createBundle` — which inserts into the
    /// context it is handed and commits nothing, correctly, because its caller owns the unit of
    /// work — then `addTask` per selection, and then the canvas dismissed its draft popover. This
    /// panel *is* that caller, so the commit is here; the popover is gone by the time the store
    /// answers, so the report is an alert on the panel rather than an inline notice.
    ///
    /// The event branch beside it in `body` is deliberately left alone: EventKit failures already
    /// travel through `CalendarManager.lastWriteFailure` to `.calendarWriteFailureAlert()`.
    private func createBundle(title: String, startMin: Int, endMin: Int, adding tasks: [AppTask]) {
        do {
            try SchedulingActions.insertBundle(
                title: title,
                dateKey: todayKey,
                startMin: startMin,
                endMin: endMin,
                adding: tasks,
                in: modelContext
            )
        } catch {
            bundleCreateFailed = true
        }
    }

    /// Only asked when `presentation.drawsOwnHeader`; `.hosted` draws no header to size.
    private var headerHeight: CGFloat? {
        if presentation == .compact { return 58 }
        return useStandardHeaderHeight ? todayPanelHeaderHeight : nil
    }

    private func focusTimeline(using proxy: ScrollViewProxy) {
        SchedulePanelInteractionSupport.focusTimeline(
            proxy: proxy,
            clearAppEditingFocus: clearAppEditingFocus
        ) {
            isFocusHighlighted = $0
        }
    }

    private func exportTodayPlan() {
        let taskLines = scheduledTasks
            .sorted { $0.scheduledStartMin < $1.scheduledStartMin }
            .map { task in
                "- \(TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledEndMin)) • \(TaskTitleSupport.displayTitle(task.title))"
            }

        let eventLines = externalEventItems
            .sorted { $0.startMin < $1.startMin }
            .map { event in
                "- \(TimeFormatters.timeRange(startMin: event.startMin, endMin: event.startMin + max(event.durationMinutes, 5))) • \(event.title)"
            }

        let markdown = """
        # Schedule for \(todayKey)

        ## Tasks
        \(taskLines.isEmpty ? "- None" : taskLines.joined(separator: "\n"))

        ## Calendar Events
        \(eventLines.isEmpty ? "- None" : eventLines.joined(separator: "\n"))
        """
        exportDocument = PlainTextExportDocument(text: markdown)
        isExportingTimeline = true
    }
}
#endif
