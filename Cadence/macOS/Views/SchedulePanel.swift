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

let schedStartHour = 0
let schedEndHour   = 24
let timeLabelWidth: CGFloat = 36
let timeLabelPad:   CGFloat = 6
let blockInset:     CGFloat = timeLabelWidth + timeLabelPad  // 42

enum SchedulePanelPresentation {
    case standard
    case compact
}

struct SchedulePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(TodayTimelineFocusManager.self) private var todayTimelineFocusManager
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
            SchedulePanelHeader(
                presentation: presentation,
                zoomLevel: $zoomLevel,
                onExport: exportTodayPlan
            )
            .frame(height: headerHeight, alignment: .top)

            Divider().background(Theme.borderSubtle)

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
                                SchedulingActions.createTask(
                                    title: title,
                                    dateKey: todayKey,
                                    startMin: startMin,
                                    endMin: endMin,
                                    containerSelection: containerSelection,
                                    sectionName: sectionName,
                                    notes: notes,
                                    subtaskTitles: subtaskTitles,
                                    areas: areas,
                                    projects: projects,
                                    in: modelContext
                                )
                            },
                            onDropTaskAtMinute: { task, startMin in
                                SchedulingActions.dropTask(task, to: todayKey, startMin: startMin)
                            },
                            onCreateBundle: { title, startMin, endMin, selectedTasks in
                                let bundle = SchedulingActions.createBundle(title: title, dateKey: todayKey, startMin: startMin, endMin: endMin, in: modelContext)
                                selectedTasks.forEach { SchedulingActions.addTask($0, to: bundle) }
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
                .stroke(Theme.blue.opacity(isFocusHighlighted ? 0.95 : 0), lineWidth: 2)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
        }
        .onChange(of: calendarManager.storeVersion) {
            SchedulePanelDataSupport.syncLinkedTasks(
                allTasks: allTasks,
                modelContext: modelContext
            )
        }
    }

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
                "- \(TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledStartMin + max(task.estimatedMinutes, 30))) • \(task.title.isEmpty ? "Untitled Task" : task.title)"
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
