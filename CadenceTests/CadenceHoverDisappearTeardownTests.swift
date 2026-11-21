#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// [[T-18718]] / [[T-18719]]: a Mac Timeline task block, a list's Board column and the Calendar
/// Board day column registered their Cmd-key hover targets in `.onHover` and tore them down only
/// in `.onHover(false)` -- which never fires when the view leaves the screen under a parked
/// pointer (Cmd+T unschedules the block, Cmd+Shift+] switches the board away). The managers then
/// kept the gone view's closures, so the next Cmd+Return / Cmd+N / Cmd+Delete acted on something
/// not on screen. The task row (`TasksPanelComponents`) and the board card (`KanbanCardView`)
/// already carried the `.onDisappear` teardown this suite pins for the other three.
///
/// The teardowns are exercised as values against the real managers; that each view's body calls
/// its teardown from `.onDisappear` is pinned as source text, because the bodies are SwiftUI
/// views whose hover cannot be driven from a unit test.
@Suite(.serialized)
@MainActor
struct CadenceHoverDisappearTeardownTests {

    // MARK: - Timeline task block (T-18718)

    @Test func aHoveredTimelineBlockThatDisappearsReleasesBothRegistrations() async throws {
        let tasks = HoveredTaskManager.shared
        let editables = HoveredEditableManager.shared
        tasks.clear(); editables.clear()
        defer { tasks.clear(); editables.clear() }
        let task = AppTask(title: "Timed block")
        var edits = 0
        tasks.beginHovering(task, source: .timeline)
        editables.beginHovering(id: "timeline-task-\(task.id.uuidString)") { edits += 1 }

        var isHovered = true
        TimelineTaskBlockInteractionSupport.endHoverOnDisappear(
            isHovered: &isHovered, task: task,
            hoveredTaskManager: tasks, hoveredEditableManager: editables
        )
        try await Task.sleep(for: .milliseconds(250))

        #expect(!isHovered)
        #expect(tasks.hoveredTask == nil, "the gone block must not stay the hovered task")
        #expect(!editables.triggerEdit(), "Cmd+E must no longer reach the gone block")
        #expect(edits == 0)
    }

    /// The same task can be a row in the list beside the timeline. A block that was never hovered
    /// must not end that row's hover when it disappears.
    @Test func aTimelineBlockThatWasNotHoveredLeavesAnotherSurfacesHoverAlone() async throws {
        let tasks = HoveredTaskManager.shared
        let editables = HoveredEditableManager.shared
        tasks.clear(); editables.clear()
        defer { tasks.clear(); editables.clear() }
        let task = AppTask(title: "Listed and timed")
        tasks.beginHovering(task, source: .list)

        var isHovered = false
        TimelineTaskBlockInteractionSupport.endHoverOnDisappear(
            isHovered: &isHovered, task: task,
            hoveredTaskManager: tasks, hoveredEditableManager: editables
        )
        try await Task.sleep(for: .milliseconds(250))

        #expect(tasks.hoveredTask?.id == task.id)
        #expect(tasks.hoveredSource == .list)
    }

    // MARK: - List Board column (T-18719)

    @Test func aHoveredBoardColumnThatDisappearsReleasesAllThreeRegistrations() {
        let columns = HoveredKanbanColumnManager.shared
        let sections = HoveredSectionManager.shared
        let editables = HoveredEditableManager.shared
        columns.clear(); sections.clear(); editables.clear()
        defer { columns.clear(); sections.clear(); editables.clear() }
        let sectionID = UUID()
        var calls = 0
        columns.beginHovering(id: ListSectionKanbanColumn.columnHoverID(sectionID: sectionID)) { calls += 1 }
        sections.beginHovering(id: sectionID) { calls += 1 }
        editables.beginHovering(id: ListSectionKanbanColumn.editHoverID(sectionID: sectionID)) { calls += 1 }

        var isHovered = true
        ListSectionKanbanColumn.endHoverRegistrationsOnDisappear(
            isHovered: &isHovered, sectionID: sectionID,
            hoveredKanbanColumnManager: columns, hoveredSectionManager: sections,
            hoveredEditableManager: editables
        )

        #expect(!isHovered)
        #expect(!columns.triggerCreateTask(), "Cmd+N must no longer reach the gone column")
        #expect(!sections.triggerToggleComplete(), "Cmd+Return must no longer complete the gone column")
        #expect(!editables.triggerEdit(), "Cmd+E must no longer reach the gone column's header")
        #expect(calls == 0)
    }

    /// The pointer moved to the next column before this one disappeared: the replacement
    /// registered first, and the teardown must leave it in place.
    @Test func aDisappearingBoardColumnLeavesTheNextColumnsRegistrations() {
        let columns = HoveredKanbanColumnManager.shared
        let sections = HoveredSectionManager.shared
        let editables = HoveredEditableManager.shared
        columns.clear(); sections.clear(); editables.clear()
        defer { columns.clear(); sections.clear(); editables.clear() }
        let gone = UUID()
        let next = UUID()
        var calls = 0
        columns.beginHovering(id: ListSectionKanbanColumn.columnHoverID(sectionID: next)) { calls += 1 }
        sections.beginHovering(id: next) { calls += 1 }
        editables.beginHovering(id: ListSectionKanbanColumn.editHoverID(sectionID: next)) { calls += 1 }

        var isHovered = true
        ListSectionKanbanColumn.endHoverRegistrationsOnDisappear(
            isHovered: &isHovered, sectionID: gone,
            hoveredKanbanColumnManager: columns, hoveredSectionManager: sections,
            hoveredEditableManager: editables
        )

        #expect(columns.triggerCreateTask())
        #expect(sections.triggerToggleComplete())
        #expect(editables.triggerEdit())
        #expect(calls == 3)
    }

    @Test func aBoardColumnThatWasNotHoveredTouchesNothing() {
        let columns = HoveredKanbanColumnManager.shared
        let sections = HoveredSectionManager.shared
        let editables = HoveredEditableManager.shared
        columns.clear(); sections.clear(); editables.clear()
        defer { columns.clear(); sections.clear(); editables.clear() }
        let sectionID = UUID()
        columns.beginHovering(id: ListSectionKanbanColumn.columnHoverID(sectionID: sectionID)) {}
        sections.beginHovering(id: sectionID) {}

        var isHovered = false
        ListSectionKanbanColumn.endHoverRegistrationsOnDisappear(
            isHovered: &isHovered, sectionID: sectionID,
            hoveredKanbanColumnManager: columns, hoveredSectionManager: sections,
            hoveredEditableManager: editables
        )

        #expect(columns.triggerCreateTask())
        #expect(sections.triggerToggleComplete())
    }

    // MARK: - Calendar Board day column (T-18719)

    @Test func aHoveredDayColumnThatDisappearsReleasesItsCmdNRegistration() {
        let columns = HoveredKanbanColumnManager.shared
        columns.clear()
        defer { columns.clear() }
        var calls = 0
        columns.beginHovering(id: CalendarBoardDayColumn.hoverID(dateKey: "2026-11-20")) { calls += 1 }

        var isHovered = true
        CalendarBoardDayColumn.endHoverRegistrationOnDisappear(
            isHovered: &isHovered, dateKey: "2026-11-20", hoveredKanbanColumnManager: columns
        )

        #expect(!isHovered)
        #expect(!columns.triggerCreateTask())
        #expect(calls == 0)
    }

    @Test func aDisappearingDayColumnLeavesTheNextDaysRegistration() {
        let columns = HoveredKanbanColumnManager.shared
        columns.clear()
        defer { columns.clear() }
        var calls = 0
        columns.beginHovering(id: CalendarBoardDayColumn.hoverID(dateKey: "2026-11-21")) { calls += 1 }

        var isHovered = true
        CalendarBoardDayColumn.endHoverRegistrationOnDisappear(
            isHovered: &isHovered, dateKey: "2026-11-20", hoveredKanbanColumnManager: columns
        )

        #expect(columns.triggerCreateTask())
        #expect(calls == 1)
    }

    // MARK: - Each body calls its teardown from `.onDisappear`

    @Test func eachViewTearsItsHoverDownFromOnDisappear() throws {
        let pins: [(file: String, call: String)] = [
            ("Cadence/macOS/Views/TimelineTaskBlock.swift",
             "TimelineTaskBlockInteractionSupport.endHoverOnDisappear("),
            ("Cadence/macOS/Views/KanbanSectionColumnView.swift",
             "Self.endHoverRegistrationsOnDisappear("),
            ("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift",
             "Self.endHoverRegistrationOnDisappear("),
        ]
        for pin in pins {
            let code = try cadenceTestSource(pin.file)
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let pattern = #"\.onDisappear\s*\{\s*"# + NSRegularExpression.escapedPattern(for: pin.call)
            let regex = try NSRegularExpression(pattern: pattern)
            let hits = regex.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
            #expect(hits == 1, "\(pin.file) must call \(pin.call) from its `.onDisappear`")
        }
    }
}
#endif
