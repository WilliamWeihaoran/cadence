// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and this
// suite reaches macOS-only app types (`SchedulePanelDataSupport`, `QuickCreateTaskDraft`) that do
// not exist there.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-3171]]'s eighth slice, and the last of the owner's drag-create report that was still
/// visible in a shipped build.**
///
/// *"on at least ios and possibly mac os too, the task and event creation from the calendar view
/// (that is, dragging to create an event or task) is still using the old task and event creation
/// sheet. fix that."*
///
/// The seventh slice made the macOS **Calendar** page's drag-create the shared schedule panel, and
/// that page composes in place. The macOS **Today** timeline hosts the same
/// `QuickCreateChoicePopover` through `SchedulePanelShellViews`, and its Task arm handed the draft
/// to `TaskCreationManager.present(…)` — which raises `CreateTaskPanelSurface`, the old create-task
/// sheet, over the whole window. So on that one page the owner's complaint survived in the most
/// literal possible form: drag a slot, type a title into the new panel, press Add, and **a second
/// sheet opens** carrying what you just typed, with nothing stored until you confirm again.
///
/// **What these tests hold is the presentation state**, because that is what the defect was. It was
/// never a layout or a copy bug: both surfaces drew correctly: it was two presentations alive at
/// once, driven from `TaskCreationManager.isPresented`, which `SchedulePanel` reached through an
/// `@Environment` and set from the popover's commit. The panel no longer reaches that state at all,
/// and the write it does instead is asserted against the real store.
///
/// **Not seen on screen.** [[T-3259]]: the owner's running `/Applications/Cadence.app` refuses
/// `scripts/run-macos-app.sh`, and a window capture draws a view rather than driving a flow, so no
/// agent can perform this drag. These assertions are the sighting's replacement, not a claim of one.
@MainActor
struct CadenceTodayTimelineCreateInPlaceTests {

    private static let panelPath = "Cadence/macOS/Views/SchedulePanel.swift"
    private static let shellPath = "Cadence/macOS/Views/SchedulePanelShellViews.swift"
    private static let columnPath = "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"

    private func code(_ relativePath: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(relativePath)
        #expect(raw.count > 1_000, "\(relativePath) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "\(relativePath): the comment stripper removed nothing")
        return stripped
    }

    /// A draft of the shape `QuickCreateChoicePopover.create()` hands back, on a day that is
    /// deliberately **not** today, so a host that files it under its own column's day is visible.
    private func draft(
        title: String = "Dragged on the Today timeline",
        dateKey: String,
        startMin: Int = 795,
        endMin: Int = 840,
        priority: TaskPriority = .high,
        notes: String = "Typed into the panel, not into a second sheet."
    ) -> QuickCreateTaskDraft {
        QuickCreateTaskDraft(
            title: title,
            dateKey: dateKey,
            startMin: startMin,
            endMin: endMin,
            container: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            priority: priority,
            notes: notes,
            subtaskTitles: []
        )
    }

    // MARK: - The second sheet

    /// **The presentation state the second sheet was driven from is no longer reachable here.**
    ///
    /// Three claims, because any one of them alone passes for the wrong reason: the panel holds no
    /// `@Environment(TaskCreationManager.self)` (so it cannot read or set `isPresented`), it names
    /// the type nowhere at all (so it cannot reach the shared singleton round the environment), and
    /// it commits the drag through the write helper instead. The same sweep over
    /// `SchedulePanelShellViews.swift`, the file that builds the canvas, so the handoff cannot
    /// reappear one frame out.
    @Test("The Today timeline opens no second task surface")
    func theTodayTimelineOpensNoSecondTaskSurface() throws {
        for path in [Self.panelPath, Self.shellPath] {
            let source = try code(path)
            #expect(source.contains("onCreateTask"), "non-vacuity: \(path) read as the wrong file")
            #expect(
                CadenceSourceScan.matchCount(#"TaskCreationManager"#, in: source) == 0,
                "\(path) still reaches the presentation state the second sheet was driven from"
            )
            #expect(
                CadenceSourceScan.matchCount(#"\.present\("#, in: source) == 0,
                "\(path) still presents a second surface for a drag-created task"
            )
            #expect(
                CadenceSourceScan.matchCount(#"CreateTaskPanelSurface|CreateTaskSheet"#, in: source) == 0,
                "\(path) names the old create-task sheet"
            )
        }
        let panel = try code(Self.panelPath)
        #expect(panel.contains("onCreateTask: createTask"))
        #expect(panel.contains("SchedulePanelDataSupport.insertDragCreatedTask("))
    }

    /// **Both macOS hosts of the drag-create popover now write, and neither presents.** A relation
    /// across the two hosts rather than a fact about one: the Calendar page's column has composed
    /// in place since [[T-655]], and the point of this slice is that the two pages stopped
    /// disagreeing about what pressing Add does.
    @Test("Both macOS drag-create hosts commit the task themselves")
    func bothMacHostsCommitTheTaskThemselves() throws {
        var presenting: [String] = []
        var committing: [String] = []
        for path in [Self.panelPath, Self.columnPath] {
            let source = try code(path)
            #expect(source.contains("onCreateTask"), "non-vacuity: \(path) read as the wrong file")
            if CadenceSourceScan.matchCount(#"TaskCreationManager|\.present\("#, in: source) > 0 {
                presenting.append(path)
            }
            if CadenceSourceScan.matchCount(#"taskCreateFailed = true"#, in: source) > 0 {
                committing.append(path)
            }
        }
        #expect(presenting.isEmpty, "a macOS drag-create host still hands the draft to a second surface: \(presenting)")
        #expect(committing.count == 2, "a macOS drag-create host names no refused write: \(committing)")
    }

    // MARK: - What it writes instead

    /// **Behavioural, through the real write path and read back through a second context**, so the
    /// creating context's own memory cannot satisfy it: pressing Add stores the task, rather than
    /// seeding a sheet that will store it later.
    @Test("Add stores the drag-created task rather than seeding a sheet")
    func addStoresTheDragCreatedTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let created = try SchedulePanelDataSupport.insertDragCreatedTask(
            draft(dateKey: "2026-05-01"),
            areas: [],
            projects: [],
            in: context
        )

        let createdTask = try #require(created)
        #expect(createdTask.priority == TaskPriority.high)

        let reader = ModelContext(container)
        let stored = try #require(try reader.fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.title == "Dragged on the Today timeline")
        #expect(stored.scheduledStartMin == 795)
        #expect(stored.estimatedMinutes == 45)
        #expect(stored.priority == .high)
        #expect(stored.notes == "Typed into the panel, not into a second sheet.")
    }

    /// **The day the panel names is the day the task lands on** — the one behaviour the handoff was
    /// carrying that a careless in-place write would drop.
    ///
    /// T-1433 gave the popover editable date and time fields, and both hosts honour them since
    /// [[T-3171]] (iv): a slot dragged on a timeline and then moved to another day in the panel
    /// must be created there. Asserted as a **relation** between two drafts that differ only in `dateKey`, so a
    /// write that pins every task to the host's own day fails here however that day is spelled.
    @Test("A drafted day is the day the task is created on")
    func aDraftedDayIsTheDayTheTaskIsCreatedOn() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let earlier = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
            draft(title: "Dragged, left where it was", dateKey: "2026-05-01"),
            areas: [],
            projects: [],
            in: context
        ))
        let moved = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
            draft(title: "Dragged, then moved a day on", dateKey: "2026-05-02"),
            areas: [],
            projects: [],
            in: context
        ))

        #expect(earlier.scheduledDate == "2026-05-01")
        #expect(moved.scheduledDate == "2026-05-02")
        #expect(earlier.scheduledDate != moved.scheduledDate, "both drafts were filed under one day")

        let reader = ModelContext(container)
        let days = Set(try reader.fetch(FetchDescriptor<AppTask>()).map(\.scheduledDate))
        #expect(days.count == 2, "the store holds one day for two drafted days: \(days)")
    }

    /// The length the drag drew survives the new write path, including the five-minute floor a
    /// degenerate slot lands on — asserted as a relation between a drawn slot and a collapsed one
    /// rather than as two pinned figures.
    @Test("The dragged length is the task's estimate, floored at five minutes")
    func theDraggedLengthIsTheTasksEstimate() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let drawn = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
            draft(title: "A drawn slot", dateKey: "2026-05-03", startMin: 600, endMin: 690),
            areas: [],
            projects: [],
            in: context
        ))
        let collapsed = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
            draft(title: "A collapsed slot", dateKey: "2026-05-03", startMin: 600, endMin: 600),
            areas: [],
            projects: [],
            in: context
        ))

        #expect(drawn.estimatedMinutes == 90)
        #expect(collapsed.estimatedMinutes > 0, "a collapsed slot created a task with no length")
        #expect(collapsed.estimatedMinutes < drawn.estimatedMinutes)
    }

    // MARK: - [[T-6581]]: All day and Estimate None on a drag-created task

    /// **An untimed task is stored with no time, on its day** — read back through a second context.
    /// Built through the popover's own boundary (`QuickCreateTaskDraft(scheduleDraft:)`), so the
    /// value, the forwarding site and the write are all on the path. The timed sibling from the same
    /// opener keeps its minute, so `-1` is not a default the assertion is reading.
    @Test("All day on a drag-created task stores it with no time")
    func allDayStoresTheTaskWithNoTime() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        var untimed = QuickCreateChoicePopover.openingDraft(
            dateKey: "2026-05-05", startMin: 600, endMin: 660, defaultsToCalendarEvent: false
        )
        untimed.title = "Dragged, then made all day"
        untimed.isAllDay = true
        var timed = untimed
        timed.title = "Dragged and left timed"
        timed.isAllDay = false

        for scheduleDraft in [untimed, timed] {
            _ = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
                QuickCreateTaskDraft(scheduleDraft: scheduleDraft),
                areas: [],
                projects: [],
                in: context
            ))
        }

        let reader = ModelContext(container)
        let stored = try reader.fetch(FetchDescriptor<AppTask>())
        let storedUntimed = try #require(stored.first { $0.title == "Dragged, then made all day" })
        let storedTimed = try #require(stored.first { $0.title == "Dragged and left timed" })
        #expect(storedUntimed.scheduledDate == "2026-05-05")
        #expect(storedUntimed.scheduledStartMin == -1, "All day was accepted and stored at the slot's minute")
        #expect(storedTimed.scheduledStartMin == 600)
    }

    /// **Estimate: None is stored as `0`**, not floored to five minutes; a named estimate is stored
    /// as named rather than read off the slot. Read back through a second context.
    @Test("Estimate None on a drag-created task is stored as no estimate")
    func estimateNoneIsStoredAsNoEstimate() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        var none = QuickCreateChoicePopover.openingDraft(
            dateKey: "2026-05-06", startMin: 600, endMin: 690, defaultsToCalendarEvent: false
        )
        none.title = "Dragged with no estimate"
        none.setEstimate(0)
        var named = none
        named.title = "Dragged with a twenty-minute estimate"
        named.setEstimate(20)

        for scheduleDraft in [none, named] {
            _ = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
                QuickCreateTaskDraft(scheduleDraft: scheduleDraft),
                areas: [],
                projects: [],
                in: context
            ))
        }

        let reader = ModelContext(container)
        let stored = try reader.fetch(FetchDescriptor<AppTask>())
        let storedNone = try #require(stored.first { $0.title == "Dragged with no estimate" })
        let storedNamed = try #require(stored.first { $0.title == "Dragged with a twenty-minute estimate" })
        #expect(storedNone.estimatedMinutes == 0, "None was stored as \(storedNone.estimatedMinutes) minutes")
        #expect(storedNamed.estimatedMinutes == 20, "a named estimate was replaced by the slot's length")
        #expect(storedNone.scheduledStartMin == storedNamed.scheduledStartMin, "None moved the task's time")
    }

    // MARK: - [[T-3171]] (iii), (iv): Due, Repeat and the Calendar page's column

    /// **Due and Repeat reach the store**, through the same write and read back through a second
    /// context. The popover used to withhold both rows because this write had nowhere to put them.
    @Test("Due and Repeat on a drag-created task are stored")
    func dueAndRepeatAreStored() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        var payload = draft(title: "Dragged with a deadline and a series", dateKey: "2026-05-04")
        payload.dueDateKey = "2026-05-08"
        payload.repeatRule = .weekly
        payload.seriesEndMode = .afterCount
        payload.seriesEndCount = 3

        _ = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
            payload,
            areas: [],
            projects: [],
            in: context
        ))

        let reader = ModelContext(container)
        let stored = try #require(try reader.fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.dueDate == "2026-05-08")
        #expect(stored.recurrenceRule == .weekly)
        #expect(stored.recurrenceEndCount == 3)

        // Non-vacuity: the same draft without them stores neither, so the assertions above are not
        // reading a default.
        let bare = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
            draft(title: "Dragged plain", dateKey: "2026-05-04"),
            areas: [],
            projects: [],
            in: context
        ))
        #expect(bare.dueDate.isEmpty)
        #expect(bare.recurrenceRule == .none)
    }

    /// **The Calendar page's column writes the draft whole** — it used to unpack the fields and
    /// supply its own column's `dateKey`, which is why the popover had to refuse a moved day.
    @Test("The Calendar page's day column writes the draft's own day")
    func theCalendarColumnWritesTheDraftsOwnDay() throws {
        let column = try code(Self.columnPath)
        #expect(column.contains("struct CalDayColumn: View"), "non-vacuity: column file unread")
        #expect(column.contains("onCreateTask: createTask,"))
        #expect(column.contains("private func createTask(_ draft: QuickCreateTaskDraft)"))
        let body = try #require(CadenceSourceScan.functionBody(named: "createTask", in: column))
        #expect(body.contains("SchedulePanelDataSupport.insertDragCreatedTask("))
        #expect(
            CadenceSourceScan.matchCount(#"\bdateKey\b"#, in: body) == 0,
            "the column still writes its own day over the draft's"
        )
    }
}
#endif
