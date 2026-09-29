import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1433, owner-reported: the calendar quick-create popover stops being a signpost.**
///
/// Its Task tab used to open with a blue tile headed *"Use the task panel"*, a recessed card of
/// three read-only `Text` rows built by a private `handoffDetail` helper — the date, the time range and
/// the list name — and a tip saying that typing `~` in the title was how you routed the task to a
/// list *before opening the panel*. None of the three rows could be acted on, and the blurb and
/// the tip existed to say where to go and act on them.
///
/// So the deletions here are not tidying. Making the list editable and adding a priority field is
/// what stops the blurb and the tip being **true**, and that is the thing these tests pin: the
/// four removals and the four fields are one change, and reverting either half leaves the surface
/// lying about itself again.
@MainActor
struct CadenceQuickCreateTaskInspectorTests {

    private static let supportPath = "Cadence/macOS/Views/QuickCreateChoiceSupportViews.swift"
    private static let popoverPath = "Cadence/macOS/Views/QuickCreateChoicePopover.swift"
    private static let createSheetPath = "Cadence/macOS/Sheets/CreateTaskSheet.swift"
    private static let createSheetSupportPath = "Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift"
    private static let tildePickerPath = "Cadence/macOS/Views/TildeContainerPicker.swift"
    private static let monthGridPath = "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"
    private static let schedulingPath = "Cadence/macOS/Services/SchedulingService.swift"

    private func code(_ path: String) throws -> String {
        let raw = try cadenceTestSource(path)
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(raw.count > 500, "\(path) read as \(raw.count) characters")
        return code
    }

    // MARK: - Moving the start moves the slot

    /// The one piece of arithmetic the editable time field introduced. The drag draws a duration;
    /// the field moves only the start, so the end has to follow rather than the block silently
    /// growing or shrinking behind a control that never named a duration.
    @Test func movingTheStartCarriesTheDurationTheDragDrew() {
        // 09:00–10:30 dragged, then moved to 14:00: still ninety minutes.
        #expect(
            QuickCreateTaskDraft.endMinute(forStart: 14 * 60, holdingDuration: 90) == 15 * 60 + 30
        )
        // Moved earlier, same duration.
        #expect(
            QuickCreateTaskDraft.endMinute(forStart: 6 * 60, holdingDuration: 90) == 7 * 60 + 30
        )
        // The identity case: a start that did not move gives the range back unchanged.
        #expect(
            QuickCreateTaskDraft.endMinute(forStart: 9 * 60, holdingDuration: 90) == 10 * 60 + 30
        )
    }

    /// The field offers every quarter hour up to 23:45, and the drag it is seeded from cannot
    /// reach past midnight — so a late start clamps rather than producing a block that ends on
    /// the following day, which no host of this popover knows how to store.
    @Test func aLateStartClampsToTheEndOfTheDayRatherThanRunningPastMidnight() {
        #expect(QuickCreateTaskDraft.endMinute(forStart: 23 * 60 + 45, holdingDuration: 90) == 24 * 60)
        #expect(QuickCreateTaskDraft.endMinute(forStart: 23 * 60, holdingDuration: 60) == 24 * 60)
        // Exactly reaching midnight is not clamping, and must still read as the full duration.
        #expect(QuickCreateTaskDraft.endMinute(forStart: 22 * 60, holdingDuration: 120) == 24 * 60)
    }

    /// `SchedulePanel` derives `estimatedMinutes` from this range, so a zero- or negative-length
    /// slot would seed the panel with an estimate it floors anyway. Floor it once, here.
    @Test func aDegenerateSlotStillYieldsAFiveMinuteBlock() {
        #expect(QuickCreateTaskDraft.endMinute(forStart: 9 * 60, holdingDuration: 0) == 9 * 60 + 5)
        #expect(QuickCreateTaskDraft.endMinute(forStart: 9 * 60, holdingDuration: -30) == 9 * 60 + 5)
    }

    // MARK: - The signpost is gone

    @Test func theHandoffBlurbAndItsReadOnlyRowsAreGone() throws {
        let support = try code(Self.supportPath)
        for needle in [
            "Use the task panel",
            "Continue to the shared task creator",
            "QuickCreateTaskPanelHandoffView",
            "handoffDetail",
            "rectangle.on.rectangle.angled"
        ] {
            #expect(
                CadenceSourceScan.matchCount(NSRegularExpression.escapedPattern(for: needle), in: support) == 0,
                "\(Self.supportPath) still carries the handoff signpost's \(needle)"
            )
        }
    }

    /// The sentence goes; the feature does not. `~` routing is `TildeContainerPicker`, still built
    /// and still reached from the popover's title field — an editable List row is the discoverable
    /// form of the same thing, which is the only reason the advertisement could be retired.
    @Test func theTipSentenceIsGoneButTildeRoutingIsNot() throws {
        let support = try code(Self.supportPath)
        #expect(
            CadenceSourceScan.matchCount(
                NSRegularExpression.escapedPattern(for: "route the task to a list before opening the panel"),
                in: support
            ) == 0,
            "the tip advertising `~` is still in the quick-create card"
        )

        let popover = try code(Self.popoverPath)
        #expect(
            CadenceSourceScan.matchCount(#"TildeContainerPicker\("#, in: popover) == 1,
            "the popover no longer builds the shared `~` panel"
        )
        #expect(
            CadenceSourceScan.matchCount(#"struct TildeContainerPicker: View"#, in: try code(Self.tildePickerPath)) == 1,
            "the `~` picker itself is gone, which T-1433 never asked for"
        )
    }

    // MARK: - The fields the signpost pointed at

    @Test func theTaskTabCarriesEditableDateTimeListAndPriorityFields() throws {
        let support = try code(Self.supportPath)
        let declaration = try #require(
            CadenceSourceScan.declarationBody(
                "struct QuickCreateTaskSlotInspectorView: View",
                in: support
            ),
            "no quick-create task inspector in \(Self.supportPath)"
        )
        let inspector = try #require(
            CadenceSourceScan.declarationBody("var body: some View", in: declaration),
            "no body on the quick-create task inspector"
        )

        // Date and time lead, and both are the app's existing controls.
        #expect(inspector.contains("CadenceDatePicker(selection: dateSelection)"))
        #expect(inspector.contains("CadenceStartTimeFieldRow(minutes: $startMin)"))
        // The list row is a picker now, not a `tray` glyph beside a `Text`.
        #expect(inspector.contains("QuickCreateContainerFieldControls("))
        // And the field the popover never had.
        #expect(inspector.contains("TaskPriorityPicker(selection: $priority, trigger: .value)"))

        let datePosition = try #require(inspector.range(of: "CadenceDatePicker"))
        let timePosition = try #require(inspector.range(of: "CadenceStartTimeFieldRow"))
        let listPosition = try #require(inspector.range(of: "QuickCreateContainerFieldControls"))
        #expect(
            datePosition.lowerBound < timePosition.lowerBound,
            "the date field is not first in the inspector"
        )
        #expect(
            timePosition.lowerBound < listPosition.lowerBound,
            "the date and time fields no longer lead the inspector"
        )
    }

    /// The persisted form is `yyyy-MM-dd`, so the date field writes a key through `DateFormatters`
    /// rather than storing whatever the picker's `Date` stringifies to.
    @Test func theDateFieldRoundTripsThroughTheRepositoryDateKey() throws {
        let support = try code(Self.supportPath)
        let binding = try #require(
            CadenceSourceScan.declarationBody("private var dateSelection: Binding<Date>", in: support),
            "no dateSelection binding on the inspector"
        )
        #expect(binding.contains("DateFormatters.date(from: dateKey)"))
        #expect(binding.contains("DateFormatters.dateKey(from: $0)"))
    }

    // MARK: - One priority control, one time display

    /// A second priority picker on one platform is the drift T-1412 spent a ticket undoing for the
    /// tag chip. The create sheet's private `priorityMarkButton` became `TaskPriorityPicker`, and
    /// both surfaces read it.
    @Test func bothMacOSPrioritySurfacesReadTheOneSharedPicker() throws {
        #expect(
            CadenceSourceScan.matchCount(
                #"struct TaskPriorityPicker: View"#,
                in: try code(Self.createSheetSupportPath)
            ) == 1,
            "the shared priority picker is not declared where the create sheet's spellings live"
        )
        // The create sheet builds it once; the support file builds it once per Task composer,
        // which is twice since T-1436 gave the in-place spelling its own Priority row. What the
        // count guards is that none of them is a *private* copy — the declaration above is still
        // the only one in the app.
        #expect(
            CadenceSourceScan.matchCount(#"TaskPriorityPicker\("#, in: try code(Self.createSheetPath)) == 1,
            "the create sheet does not build the shared priority picker"
        )
        #expect(
            CadenceSourceScan.matchCount(#"TaskPriorityPicker\("#, in: try code(Self.supportPath)) == 2,
            "the two quick-create Task composers do not each build the shared priority picker"
        )
        #expect(
            CadenceSourceScan.matchCount(#"priorityMarkButton"#, in: try code(Self.createSheetPath)) == 0,
            "the create sheet still carries its private priority button"
        )
        // The labelled trigger says the word the composers already agreed on, through the helper
        // whose own note records why a captioned field spells it rather than showing the mark.
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceTaskComposerSupport\.priorityValueLabel\(selection\)"#,
                in: try code(Self.createSheetSupportPath)
            ) == 1,
            "the priority field invents its own wording instead of reading the shared one"
        )
    }

    /// **The dedupe.** The popover printed `TimeFormatters.timeRange` above the Task/Event/Block
    /// control *and* again in every tab below it — the handoff card's `clock` row, and
    /// `QuickCreateSlotSummary` on the other two. Moving the fields up had to remove one of the
    /// two displays, not stack a third. One site now, in the summary that owns it.
    @Test func theTimeRangeIsDrawnOnceAcrossThePopoverAndItsTabs() throws {
        #expect(
            CadenceSourceScan.matchCount(#"TimeFormatters\.timeRange\("#, in: try code(Self.popoverPath)) == 0,
            "the popover header still prints a second copy of the slot's time range"
        )
        #expect(
            CadenceSourceScan.matchCount(#"TimeFormatters\.timeRange\("#, in: try code(Self.supportPath)) == 1,
            "the quick-create tabs no longer draw the time range exactly once"
        )
    }

    // MARK: - T-1436: the third composer can set a priority

    /// **Behavioural, through the real write path.** The Calendar page's day column is the one
    /// macOS Task composer that creates in place, and it writes through
    /// `SchedulingActions.insertTask` — which hardcoded `priority: .none` into the draft it built,
    /// so `QuickCreateTaskDraft.priority` was dropped on the floor no matter what the tab drew.
    ///
    /// Read back through a **second** context, so the creating context's own memory cannot satisfy
    /// it: the priority the composer names is the priority in the store.
    @Test func thePriorityTheCalendarQuickCreateNamesReachesTheStoredTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let created = try SchedulingActions.insertTask(
            title: "Dragged out and marked",
            dateKey: "2026-05-01",
            startMin: 600,
            endMin: 660,
            containerSelection: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            priority: .high,
            areas: [],
            projects: [],
            in: context
        )

        // Unwrapped, not `created?.priority == .high`: a nil subject must fail this rather than
        // be compared away. Every optional in this file's model tests is unwrapped for that
        // reason — an insert that returned nothing is the loudest way for this to break.
        let createdTask = try #require(created)
        #expect(createdTask.priority == TaskPriority.high)
        let reader = ModelContext(container)
        let stored = try #require(try reader.fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.priority == .high)
    }

    /// The other half of the same relation, and the reason the parameter has a default: a drag that
    /// never named a priority still creates a task with none. Asserted as a *relation* between the
    /// two calls rather than as a pinned enum case on one of them, so a future default that is not
    /// `.none` fails here rather than passing on a coincidence.
    @Test func adragThatNamesNoPriorityDiffersFromOneThatDoes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let unmarked = try SchedulingActions.insertTask(
            title: "Dragged out, unmarked",
            dateKey: "2026-05-01",
            startMin: 600,
            endMin: 660,
            containerSelection: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            areas: [],
            projects: [],
            in: context
        )
        let marked = try SchedulingActions.insertTask(
            title: "Dragged out, marked",
            dateKey: "2026-05-01",
            startMin: 660,
            endMin: 720,
            containerSelection: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            priority: .medium,
            areas: [],
            projects: [],
            in: context
        )

        let unmarkedTask = try #require(unmarked)
        let markedTask = try #require(marked)
        // `TaskPriority.none` qualified: bare `.none` against an `Optional<TaskPriority>` means
        // *nil*, which is a different question and one the compiler only warns about.
        #expect(unmarkedTask.priority == TaskPriority.none)
        #expect(markedTask.priority != unmarkedTask.priority)
    }

    /// The typed shortcut still outranks the picker, which is why the picker could be added without
    /// arguing about precedence: `TaskCreationDraft.resolvedPriority` applies `!!` over whatever the
    /// caller passed, and `insertTask` routes through the same draft every other composer does.
    @Test func atypedPriorityShortcutStillOutranksTheComposersPicker() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let created = try SchedulingActions.insertTask(
            title: "Dragged out !!",
            dateKey: "2026-05-01",
            startMin: 600,
            endMin: 660,
            containerSelection: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            priority: .low,
            areas: [],
            projects: [],
            in: context
        )

        // `created?.priority != .low` would have passed on a nil insert, which is the vacuous
        // shape this repository keeps rediscovering: the inequality is *satisfied* by nothing
        // having been created at all.
        let createdTask = try #require(created)
        #expect(createdTask.priority != TaskPriority.low, "the picker's value survived a typed shortcut")
    }

    /// The source half: the tab draws the row, and the host forwards the field. Either alone goes
    /// quietly green — a picker whose value is dropped at the call site looks like a working
    /// control, and a forwarded field with no control to set it is unreachable.
    @Test func theInPlaceTaskComposerDrawsThePriorityRowAndItsHostForwardsIt() throws {
        let inPlaceComposer = try #require(
            CadenceSourceScan.declarationBody(
                "struct QuickCreateTaskDetailsView: View",
                in: try code(Self.supportPath)
            )
        )
        #expect(
            inPlaceComposer.contains("TaskPriorityPicker(selection: $priority, trigger: .value)"),
            "the in-place Task composer draws no priority control"
        )
        #expect(
            inPlaceComposer.contains("@Binding var priority: TaskPriority"),
            "the in-place Task composer cannot write a priority back to the popover"
        )

        let host = try code(Self.monthGridPath)
        let forwarded = try #require(CadenceSourceScan.functionBody(named: "createTask", in: host))
        #expect(
            forwarded.contains("priority: priority"),
            "the calendar day column drops the priority again on the way to the store"
        )
        #expect(
            CadenceSourceScan.matchCount(#"priority: draft\.priority"#, in: host) == 1,
            "the popover's draft priority never reaches the column's createTask"
        )

        // And the write path itself takes one rather than writing the literal back in.
        #expect(
            CadenceSourceScan.matchCount(
                #"priority: TaskPriority = \.none"#,
                in: try code(Self.schedulingPath)
            ) == 1,
            "SchedulingActions.insertTask no longer takes a priority"
        )
    }

    /// The List row's controls are one component read by both Task composers in the file. The
    /// read-only `tray` row this replaces is precisely what drifting from its editable sibling
    /// looks like.
    @Test func bothQuickCreateTaskComposersReadTheOneListField() throws {
        #expect(
            CadenceSourceScan.matchCount(
                #"QuickCreateContainerFieldControls\("#,
                in: try code(Self.supportPath)
            ) == 2,
            "the two quick-create Task composers do not share one List field"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"struct QuickCreateContainerFieldControls: View"#,
                in: try code(Self.supportPath)
            ) == 1
        )
    }
}
