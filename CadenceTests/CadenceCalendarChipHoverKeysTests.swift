#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// [[T-18884]]: on Mac the hover keys (Cmd+Return, Cmd+T, Cmd+P, Cmd+E, Cmd+Delete) answered over a
/// task's timeline block and board card but were dead over the same task's Month-grid and all-day
/// chips, and over an event's Month chip, all-day chip and Calendar Board card. The keys act only
/// on what `HoveredTaskManager` / `HoveredEditableManager` hold, and those surfaces registered
/// nothing.
///
/// The registrations are exercised as values against the real managers; that each surface's body
/// applies them is pinned as source text, because SwiftUI hover cannot be driven from a unit test.
@Suite(.serialized)
@MainActor
struct CadenceCalendarChipHoverKeysTests {

    // MARK: - Task chips

    @Test func aHoveredTaskChipIsWhatTheTaskKeysAndEditActOn() async throws {
        let tasks = HoveredTaskManager.shared
        let editables = HoveredEditableManager.shared
        tasks.clear(); editables.clear()
        defer { tasks.clear(); editables.clear() }
        let task = AppTask(title: "Month chip")
        var edits = 0
        var deletes = 0

        CalendarTaskChipHoverSupport.beginHover(
            task: task, hoveredTaskManager: tasks, hoveredEditableManager: editables,
            onEdit: { edits += 1 }, onDelete: { deletes += 1 }
        )
        #expect(tasks.hoveredTask?.id == task.id, "Cmd+Return / Cmd+T / Cmd+P read the hovered task")
        #expect(editables.triggerEdit())
        #expect(editables.triggerDelete())
        #expect(edits == 1 && deletes == 1)

        // Leaving the chip releases both registrations.
        CalendarTaskChipHoverSupport.endHover(task: task, hoveredTaskManager: tasks, hoveredEditableManager: editables)
        try await Task.sleep(for: .milliseconds(250))
        #expect(tasks.hoveredTask == nil)
        #expect(!editables.triggerEdit())
    }

    @Test func aHoveredTaskChipThatDisappearsReleasesBothRegistrations() async throws {
        let tasks = HoveredTaskManager.shared
        let editables = HoveredEditableManager.shared
        tasks.clear(); editables.clear()
        defer { tasks.clear(); editables.clear() }
        let task = AppTask(title: "Moved off the day")
        CalendarTaskChipHoverSupport.beginHover(
            task: task, hoveredTaskManager: tasks, hoveredEditableManager: editables,
            onEdit: {}, onDelete: {}
        )

        var isHovered = true
        CalendarTaskChipHoverSupport.endHoverOnDisappear(
            isHovered: &isHovered, task: task, hoveredTaskManager: tasks, hoveredEditableManager: editables
        )
        try await Task.sleep(for: .milliseconds(250))
        #expect(!isHovered)
        #expect(tasks.hoveredTask == nil)
        #expect(!editables.triggerDelete())
    }

    /// The same task can be a row in the list beside the calendar, or a timeline block. A chip that
    /// was never hovered must not end that surface's hover when it disappears.
    @Test func aTaskChipThatWasNotHoveredLeavesTheTimelineBlocksHoverAlone() async throws {
        let tasks = HoveredTaskManager.shared
        let editables = HoveredEditableManager.shared
        tasks.clear(); editables.clear()
        defer { tasks.clear(); editables.clear() }
        let task = AppTask(title: "Chip and block")
        var blockEdits = 0
        tasks.beginHovering(task, source: .list)
        editables.beginHovering(id: "timeline-task-\(task.id.uuidString)") { blockEdits += 1 }

        var isHovered = false
        CalendarTaskChipHoverSupport.endHoverOnDisappear(
            isHovered: &isHovered, task: task, hoveredTaskManager: tasks, hoveredEditableManager: editables
        )
        try await Task.sleep(for: .milliseconds(250))
        #expect(tasks.hoveredTask?.id == task.id, "an unhovered chip ended another surface's hover")
        #expect(tasks.hoveredSource == .list)
        #expect(editables.triggerEdit())
        #expect(blockEdits == 1)
        #expect(CalendarTaskChipHoverSupport.editableID(for: task) != "timeline-task-\(task.id.uuidString)")
    }

    @Test func aHoverDeleteClearsTheGoneTask() {
        let tasks = HoveredTaskManager.shared
        let editables = HoveredEditableManager.shared
        tasks.clear(); editables.clear()
        defer { tasks.clear(); editables.clear() }
        let task = AppTask(title: "Deleted")
        CalendarTaskChipHoverSupport.beginHover(
            task: task, hoveredTaskManager: tasks, hoveredEditableManager: editables,
            onEdit: {}, onDelete: {}
        )
        CalendarTaskChipHoverSupport.clearAfterDelete(task: task, hoveredTaskManager: tasks, hoveredEditableManager: editables)
        #expect(tasks.hoveredTask == nil)
        #expect(!editables.triggerEdit())
    }

    // MARK: - Event surfaces

    @Test func anEventSurfaceRegistersDeleteOnlyWhereTheEventTakesOne() {
        let editables = HoveredEditableManager.shared
        editables.clear()
        defer { editables.clear() }
        var edits = 0
        var deletes = 0

        CalendarEventHoverKeysSupport.beginHover(
            id: CalendarEventHoverKeysSupport.chipHoverID(eventID: "view-only"), allowsDelete: false,
            hoveredEditableManager: editables, onEdit: { edits += 1 }, onDelete: { deletes += 1 }
        )
        #expect(editables.triggerEdit())
        #expect(!editables.triggerDelete(), "a view-only event must let Cmd+Delete fall through")

        CalendarEventHoverKeysSupport.beginHover(
            id: CalendarEventHoverKeysSupport.boardHoverID(eventID: "writable"), allowsDelete: true,
            hoveredEditableManager: editables, onEdit: { edits += 1 }, onDelete: { deletes += 1 }
        )
        #expect(editables.triggerDelete())
        #expect(edits == 1 && deletes == 1)
    }

    @Test func aHoveredEventSurfaceThatDisappearsReleasesItsRegistration() {
        let editables = HoveredEditableManager.shared
        editables.clear()
        defer { editables.clear() }
        let id = CalendarEventHoverKeysSupport.chipHoverID(eventID: "e1")
        CalendarEventHoverKeysSupport.beginHover(
            id: id, allowsDelete: true, hoveredEditableManager: editables, onEdit: {}, onDelete: {}
        )
        var isHovered = true
        CalendarEventHoverKeysSupport.endHoverOnDisappear(isHovered: &isHovered, id: id, hoveredEditableManager: editables)
        #expect(!isHovered)
        #expect(!editables.triggerEdit())

        // Not hovered: another surface's registration stays.
        editables.beginHovering(id: "timeline-event-e1") {}
        var notHovered = false
        CalendarEventHoverKeysSupport.endHoverOnDisappear(isHovered: &notHovered, id: id, hoveredEditableManager: editables)
        #expect(editables.triggerEdit())
    }

    // MARK: - Wiring

    /// Every Mac task surface whose menu names the hover keys registers the hover that runs them.
    @Test func everySurfaceThatNamesTheHoverKeysRegistersTheHover() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence/macOS")
        var namers = 0
        for path in files {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            guard source.contains("MacTaskContextMenuHost("), source.contains("namesHoverKeys: true") else { continue }
            namers += 1
            #expect(source.contains("beginHover"), "\(path) names the hover keys but registers no hover")
        }
        #expect(namers >= 2, "non-vacuity: the timeline block and the calendar chips both name the keys")
    }

    @Test func theCalendarChipsAndBoardCardApplyTheHoverRegistration() throws {
        let chipFile = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        )
        let taskChips = try #require(CadenceSourceScan.functionBody(named: "calendarTaskChipInteractions", in: chipFile))
        #expect(CadenceSourceScan.matchCount(
            #"\.modifier\(CalendarTaskChipHoverKeys\(task: task, showInspector: showInspector\)\)"#, in: taskChips
        ) == 1)
        let taskModifier = try #require(CadenceSourceScan.declarationBody("struct CalendarTaskChipHoverKeys: ViewModifier", in: chipFile))
        #expect(taskModifier.contains(".onHover"))
        #expect(taskModifier.contains("CalendarTaskChipHoverSupport.beginHover("))
        #expect(CadenceSourceScan.matchCount(#"\.onDisappear \{\s*CalendarTaskChipHoverSupport\.endHoverOnDisappear\("#, in: taskModifier) == 1)

        let eventFile = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarEventChipPopoverSupport.swift")
        )
        let eventChips = try #require(CadenceSourceScan.functionBody(named: "calendarEventChipEditor", in: eventFile))
        #expect(CadenceSourceScan.matchCount(#"\.modifier\(CalendarEventHoverKeys\("#, in: eventChips) == 1)
        let eventModifier = try #require(CadenceSourceScan.declarationBody("struct CalendarEventHoverKeys: ViewModifier", in: eventFile))
        #expect(eventModifier.contains("allowsDelete: CalendarEventHoverKeysSupport.allowsDelete(item.ekEvent)"))
        #expect(CadenceSourceScan.matchCount(#"\.onDisappear \{\s*CalendarEventHoverKeysSupport\.endHoverOnDisappear\("#, in: eventModifier) == 1)

        let boardFile = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarBoardItemSupportViews.swift")
        )
        let board = try #require(CadenceSourceScan.declarationBody("struct CalendarBoardEventCard: View", in: boardFile))
        #expect(CadenceSourceScan.matchCount(#"\.modifier\(CalendarEventHoverKeys\("#, in: board) == 1)
        #expect(board.contains("onHoverChanged: { isHovered = $0 }"), "the card's plate still answers the pointer")
    }
}
#endif
