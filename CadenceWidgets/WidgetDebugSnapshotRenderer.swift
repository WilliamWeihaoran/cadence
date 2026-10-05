#if DEBUG && os(macOS)
import AppKit
import SwiftUI
import WidgetKit

@MainActor
public enum CadenceWidgetDebugSnapshotRenderer {
    public struct RenderedSnapshot {
        public let name: String
        public let fileURL: URL
    }

    public static func renderAll(to directory: URL) throws -> [RenderedSnapshot] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let rendered = try snapshotDefinitions().map { definition in
            let fileURL = directory.appendingPathComponent("\(definition.name).png")
            try render(
                definition.view
                    .frame(width: definition.size.width, height: definition.size.height)
                    .clipped(),
                to: fileURL,
                size: definition.size
            )
            return RenderedSnapshot(name: definition.name, fileURL: fileURL)
        }

        return rendered
    }

    private struct SnapshotDefinition {
        let name: String
        let size: CGSize
        let view: AnyView
    }

    private static func snapshotDefinitions() -> [SnapshotDefinition] {
        let todayDate = Date()
        let todayKey = CadenceWidgetDateSupport.dateKey(from: todayDate)

        let todayTasks = [
            CadenceTodayWidgetTask(id: UUID(), title: "Finish polishing widget hierarchy", priorityRaw: TaskPriority.high.rawValue, dueDate: todayKey, scheduledDate: todayKey, containerName: "Cadence"),
            CadenceTodayWidgetTask(id: UUID(), title: "Audit today list ordering pacing", priorityRaw: TaskPriority.medium.rawValue, dueDate: todayKey, scheduledDate: todayKey, containerName: "Today"),
            CadenceTodayWidgetTask(id: UUID(), title: "Trim calendar overflow copy", priorityRaw: TaskPriority.medium.rawValue, dueDate: "", scheduledDate: todayKey, containerName: "Roadmap"),
            CadenceTodayWidgetTask(id: UUID(), title: "Review calendar heat map density", priorityRaw: TaskPriority.low.rawValue, dueDate: "", scheduledDate: todayKey, containerName: "Planning"),
            CadenceTodayWidgetTask(id: UUID(), title: "Close quick follow-up tasks", priorityRaw: TaskPriority.none.rawValue, dueDate: "", scheduledDate: todayKey, containerName: "Ops"),
            CadenceTodayWidgetTask(id: UUID(), title: "Capture tomorrow's opener", priorityRaw: TaskPriority.none.rawValue, dueDate: "", scheduledDate: todayKey, containerName: "Inbox"),
            CadenceTodayWidgetTask(id: UUID(), title: "Stage release candidate notes", priorityRaw: TaskPriority.low.rawValue, dueDate: "", scheduledDate: todayKey, containerName: "Team"),
            CadenceTodayWidgetTask(id: UUID(), title: "Check archive migration edge cases", priorityRaw: TaskPriority.medium.rawValue, dueDate: "", scheduledDate: todayKey, containerName: "QA"),
        ]

        let todaySnapshot = CadenceTodayWidgetSnapshot(
            date: todayDate,
            dateKey: todayKey,
            state: .ready,
            statusMessage: nil,
            totalCount: todayTasks.count,
            overdueCount: 1,
            dueTodayCount: 2,
            scheduledTodayCount: 5,
            tasks: todayTasks
        )

        let calendarDays = (0..<14).compactMap { offset -> CadenceCalendarWidgetDay? in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: todayDate)) else {
                return nil
            }
            let scheduledCount = offset % 3 == 0 ? 2 : (offset % 2 == 0 ? 1 : 0)
            let dueCount = offset == 0 || offset == 2 || offset == 6 ? 1 : 0
            return CadenceCalendarWidgetDay(
                dateKey: CadenceWidgetDateSupport.dateKey(from: date),
                weekdayLabel: CadenceWidgetDateSupport.weekdayLabel(from: date),
                dayNumberLabel: CadenceWidgetDateSupport.dayNumberLabel(from: date),
                dueCount: dueCount,
                scheduledCount: scheduledCount,
                totalCount: dueCount + scheduledCount,
                isToday: offset == 0
            )
        }

        let calendarSnapshot = CadenceCalendarWidgetSnapshot(
            date: todayDate,
            state: .ready,
            statusMessage: nil,
            days: calendarDays,
            overdueCount: 2,
            upcomingTitle: "Finish weekly planning review and prep tomorrow's opener"
        )

        let todayEntry = TodayTasksWidgetEntry(date: todayDate, snapshot: todaySnapshot)
        let calendarEntry = CalendarSnapshotWidgetEntry(date: todayDate, snapshot: calendarSnapshot)

        return [
            definition(name: "today-small", size: .init(width: 170, height: 170), family: .systemSmall) {
                TodayTasksWidgetView(entry: todayEntry)
            },
            definition(name: "today-medium", size: .init(width: 364, height: 170), family: .systemMedium) {
                TodayTasksWidgetView(entry: todayEntry)
            },
            definition(name: "today-large", size: .init(width: 364, height: 382), family: .systemLarge) {
                TodayTasksWidgetView(entry: todayEntry)
            },
            definition(name: "today-extra-large", size: .init(width: 782, height: 382), family: .systemExtraLarge) {
                TodayTasksWidgetView(entry: todayEntry)
            },
            definition(name: "calendar-small", size: .init(width: 170, height: 170), family: .systemSmall) {
                CalendarSnapshotWidgetView(entry: calendarEntry)
            },
            definition(name: "calendar-medium", size: .init(width: 364, height: 170), family: .systemMedium) {
                CalendarSnapshotWidgetView(entry: calendarEntry)
            },
            definition(name: "calendar-large", size: .init(width: 364, height: 382), family: .systemLarge) {
                CalendarSnapshotWidgetView(entry: calendarEntry)
            },
            definition(name: "calendar-extra-large", size: .init(width: 782, height: 382), family: .systemExtraLarge) {
                CalendarSnapshotWidgetView(entry: calendarEntry)
            },
        ]
    }

    private static func definition<Content: View>(
        name: String,
        size: CGSize,
        family: WidgetFamily,
        @ViewBuilder content: () -> Content
    ) -> SnapshotDefinition {
        SnapshotDefinition(
            name: name,
            size: size,
            view: AnyView(
                content()
                    .previewContext(WidgetPreviewContext(family: family))
            )
        )
    }

    private static func render(
        _ view: some View,
        to fileURL: URL,
        size: CGSize
    ) throws {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(size)
        renderer.scale = 2

        guard let nsImage = renderer.nsImage else {
            throw RenderError.imageCreationFailed
        }
        guard let tiffData = nsImage.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData),
              let pngData = representation.representation(using: .png, properties: [:]) else {
            throw RenderError.pngEncodingFailed
        }

        try pngData.write(to: fileURL, options: .atomic)
    }

    private enum RenderError: Error {
        case imageCreationFailed
        case pngEncodingFailed
    }
}
#endif
