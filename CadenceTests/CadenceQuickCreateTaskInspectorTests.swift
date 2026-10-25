// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and
// this suite reaches macOS-only app types (or AppKit) that do not exist there. The gate preserves
// exactly the coverage this file had before; narrowing it so any cross-platform half runs on iOS
// too is follow-up, not part of making the target iOS-capable.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-3171]]'s seventh adoption slice, owner-reported: the macOS calendar's drag-to-create is
/// the shared schedule panel.**
///
/// *"on at least ios and possibly mac os too, the task and event creation from the calendar view
/// (that is, dragging to create an event or task) is still using the old task and event creation
/// sheet. fix that."* — and on macOS it genuinely was: `QuickCreateChoicePopover` carried its own
/// Task/Event tabs, two near-duplicate Task composers in a 394-line support file, a second copy of
/// the `~` list flow, and an `enum Mode { case timeBlock, calendarEvent }` that outlived the Block
/// feature [[T-3170]] removed, because every Block pass hunted surfaces that *display* a block and
/// this one only creates.
///
/// This file is what T-1433's and T-1436's tests became. The claims those tickets pinned —
/// *the quick-create Task arm can set a date, a time, a list, a section and a priority*, and
/// *the priority it names reaches the stored task* — are still here; they are asserted against the
/// panel and the write path rather than against the two composers that drew them.
///
/// The new claims are this slice's: the draft opens on the **drag's own length**, the notes slots
/// stay per-kind across a kind switch ([[T-1610]], re-keyed off the retired kind enum), and **every
/// field the panel offers that this host's two fixed write closures cannot carry is either
/// withheld or refused out loud** (T-470).
@MainActor
struct CadenceQuickCreateTaskInspectorTests {

    private static let popoverPath = "Cadence/macOS/Views/QuickCreateChoicePopover.swift"
    private static let canvasPath = "Cadence/macOS/Views/TimelineDayCanvas.swift"
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

    /// Through the popover's own opener, not a hand-built draft: what a dragged slot hands the
    /// panel is the thing under test.
    private func dragDraft(
        dateKey: String = "2026-05-01",
        startMin: Int = 9 * 60,
        endMin: Int = 10 * 60 + 30,
        kind: CadenceScheduleDraftKind = .task
    ) -> CadenceScheduleDraft {
        QuickCreateChoicePopover.openingDraft(
            dateKey: dateKey,
            startMin: startMin,
            endMin: endMin,
            defaultsToCalendarEvent: kind == .event
        )
    }

    // MARK: - The draft opens on the slot the user drew

    /// **The seed is the drag's own length**, not `CadenceScheduleDraft.quickCreateLengthMinutes`.
    /// That half hour is the calendar *sheet*'s opening length, for a surface whose slot is a tap;
    /// a popover opened by a range the user dragged would redraw their block the instant it
    /// appeared.
    @Test func theDragCreateDraftOpensOnTheLengthTheDragDrew() {
        let draft = dragDraft()
        #expect(draft.startMin == 9 * 60)
        #expect(draft.endMin == 10 * 60 + 30)
        #expect(draft.durationMinutes == 90)
        // And the task's own Estimate says the same, rather than the sheet's figure.
        #expect(draft.estimateMinutes == 90)
        #expect(draft.estimateMinutes != CadenceScheduleDraft.quickCreateLengthMinutes)
        #expect(draft.startDateKey == "2026-05-01")
        #expect(draft.endDateKey == "2026-05-01")
        #expect(draft.isAllDay == false)
        // Creating, so the panel draws no Delete and no Clear on the Do grid.
        #expect(draft.subject == CadenceScheduleDraft.Subject.creating)
    }

    /// `defaultsToCalendarEvent` is the Calendar page's "treat a dragged slot as an event first";
    /// the Today timeline passes nothing and opens on Task. The opener is where that is decided,
    /// so a kind switch afterwards is the user's and not the host's.
    @Test func theOpeningKindFollowsTheHostsPreference() {
        #expect(
            QuickCreateChoicePopover.openingDraft(
                dateKey: "2026-05-01",
                startMin: 9 * 60,
                endMin: 10 * 60,
                defaultsToCalendarEvent: true
            ).kind == .event
        )
        #expect(
            QuickCreateChoicePopover.openingDraft(
                dateKey: "2026-05-01",
                startMin: 9 * 60,
                endMin: 10 * 60,
                defaultsToCalendarEvent: false
            ).kind == .task
        )
    }

    /// An Event arm with no event host behind it is never opened on: `onCreateEvent == nil` means
    /// the canvas cannot create one, and `create()` refuses rather than looking as though it had.
    @Test func thePopoverOnlyOpensOnEventWhereThereIsAnEventHost() throws {
        let popover = try code(Self.popoverPath)
        #expect(
            popover.contains("defaultsToCalendarEvent: defaultsToCalendarEvent && onCreateEvent != nil"),
            "the popover can open on Event on a canvas that cannot create one"
        )
        let create = try #require(CadenceSourceScan.functionBody(named: "create", in: popover))
        #expect(create.contains("guard let onCreateEvent else { return"), "the Event arm commits into nothing")
    }

    /// **T-1433's arithmetic, now the draft's.** The popover's time control moves only the start,
    /// so the end has to follow rather than the block silently growing or shrinking behind a
    /// control that never named a duration. It was a static on the task draft, which the popover
    /// kept because its own date and time were drawn as text and could not do it; the panel's
    /// Start roller writes `moveStart(toMinute:)`, which is the same rule at the roller's finer
    /// grid.
    @Test func movingTheStartCarriesTheDurationTheDragDrew() {
        var draft = dragDraft()
        draft.moveStart(toMinute: 14 * 60)
        #expect(draft.startMin == 14 * 60)
        #expect(draft.endMin == 15 * 60 + 30)

        // Moved earlier, same duration.
        draft.moveStart(toMinute: 6 * 60)
        #expect(draft.endMin == 7 * 60 + 30)

        // The identity case: a start that did not move gives the range back unchanged.
        draft.moveStart(toMinute: 9 * 60)
        #expect(draft.startMin == 9 * 60)
        #expect(draft.endMin == 10 * 60 + 30)
    }

    /// A late start clamps rather than producing a block that ends on the following day, which no
    /// host of this popover knows how to store.
    @Test func aLateStartClampsToTheEndOfTheDayRatherThanRunningPastMidnight() {
        var draft = dragDraft()
        draft.moveStart(toMinute: 23 * 60 + 45)
        #expect(draft.endMin == 24 * 60)
        #expect(draft.spansMultipleDays == false)

        var hourLong = dragDraft(startMin: 9 * 60, endMin: 10 * 60)
        hourLong.moveStart(toMinute: 23 * 60)
        #expect(hourLong.endMin == 24 * 60)

        // Exactly reaching midnight is not clamping, and must still read as the full duration.
        var twoHours = dragDraft(startMin: 9 * 60, endMin: 11 * 60)
        twoHours.moveStart(toMinute: 22 * 60)
        #expect(twoHours.endMin == 24 * 60)
        #expect(twoHours.durationMinutes == 120)
    }

    /// A click that drew no range at all still opens a block one snap step tall, so the popover is
    /// never anchored to a zero-height ghost and the host's `max(5, endMin - startMin)` is never
    /// asked to floor a negative.
    @Test func aDegenerateSlotStillYieldsABlockOfOneSnapStep() {
        #expect(dragDraft(startMin: 9 * 60, endMin: 9 * 60).durationMinutes == CadenceScheduleDraft.minimumDurationMinutes)
        #expect(dragDraft(startMin: 9 * 60, endMin: 8 * 60 + 30).endMin == 9 * 60 + CadenceScheduleDraft.minimumDurationMinutes)
    }

    // MARK: - What the two write closures cannot carry is refused, never dropped

    /// **[[T-3171]] (iv): a moved day is honoured, not refused.** Both hosts now create on the
    /// draft's own day — tasks through `SchedulePanelDataSupport.insertDragCreatedTask`, events
    /// through `QuickCreateEventDraft.day(or:)` — so the popover has no day gate left. It used to
    /// refuse this exact draft on the Calendar page's column.
    @Test func aMovedDayIsAcceptedOnBothKinds() {
        for kind in [CadenceScheduleDraftKind.task, .event] {
            var moved = dragDraft(kind: kind)
            moved.startDateKey = "2026-05-04"
            moved.endDateKey = "2026-05-04"
            #expect(
                QuickCreateChoicePopover.hostLimitNotice(for: moved) == nil,
                "a \(kind.title) moved to another day is still refused"
            )
        }
    }

    /// The event value carries the panel's day, and `day(or:)` resolves **that** day rather than
    /// the host's. Asserted as a relation against a host day that differs, so a write that answers
    /// the host's day however it is spelled fails here.
    @Test func theEventDraftCarriesThePanelsDayNotTheHosts() throws {
        var moved = dragDraft(kind: .event)
        moved.startDateKey = "2026-05-04"
        moved.endDateKey = "2026-05-04"
        let event = QuickCreateEventDraft(scheduleDraft: moved)
        #expect(event.dateKey == "2026-05-04")
        #expect(event.startMin == moved.startMin)
        #expect(event.endMin == moved.endMin)

        let hostDay = try #require(DateFormatters.date(from: "2026-05-01"))
        let resolved = event.day(or: hostDay)
        #expect(DateFormatters.dateKey(from: resolved) == "2026-05-04")
        #expect(DateFormatters.dateKey(from: resolved) != DateFormatters.dateKey(from: hostDay))

        // The fallback is for a key that does not parse, and only then.
        var broken = event
        broken.dateKey = "not a day"
        #expect(DateFormatters.dateKey(from: broken.day(or: hostDay)) == "2026-05-01")
    }

    /// Both hosts hand `createStandaloneEvent` the draft's day, never their own `date` alone.
    @Test func bothEventHostsCreateOnTheDraftsDay() throws {
        for path in [Self.monthGridPath, "Cadence/macOS/Views/SchedulePanel.swift"] {
            let source = try code(path)
            #expect(source.contains("calendarManager.createStandaloneEvent("), "non-vacuity: \(path)")
            #expect(
                CadenceSourceScan.matchCount(#"createStandaloneEvent\([^\n]*date: draft\.day\(or: "#, in: source) == 1,
                "\(path) creates the event on its own day rather than the draft's"
            )
        }
    }

    /// The draft the drag opens with is writable on both kinds — otherwise the gate above would be
    /// refusing the common case and no test here would notice.
    @Test func theDraftADragOpensWithIsAccepted() {
        for kind in [CadenceScheduleDraftKind.task, .event] {
            #expect(
                QuickCreateChoicePopover.hostLimitNotice(for: dragDraft(kind: kind)) == nil,
                "a freshly dragged \(kind.title) is refused"
            )
        }
    }

    /// `createStandaloneEvent` writes `isAllDay = false` and the task hosts take a minute, not a
    /// `-1`. Both spellings of "no time" are refused by name.
    @Test func anAllDayDraftIsRefusedBecauseNeitherWriteCanExpressOne() {
        var allDayEvent = dragDraft(kind: .event)
        allDayEvent.isAllDay = true
        let eventNotice = QuickCreateChoicePopover.hostLimitNotice(for: allDayEvent)
        #expect(eventNotice?.contains("All day") == true, "the all-day event refusal does not name the control: \(eventNotice ?? "nil")")

        var untimedTask = dragDraft()
        untimedTask.isAllDay = true
        let taskNotice = QuickCreateChoicePopover.hostLimitNotice(for: untimedTask)
        #expect(taskNotice != nil, "an untimed task was accepted by a host that stores a minute")
        #expect(taskNotice != eventNotice, "both kinds answered one sentence; the task's control is not All day")
    }

    /// The host takes a day and a length, so a block that crosses a midnight has nowhere to be
    /// written — and the refusal names the day it would have to end on.
    @Test func ablockThatCrossesMidnightIsRefusedWithTheDayItMustEndOn() {
        var spanning = dragDraft(kind: .event)
        spanning.endDateKey = "2026-05-02"
        #expect(spanning.spansMultipleDays)

        let notice = QuickCreateChoicePopover.hostLimitNotice(for: spanning)
        #expect(notice?.contains(DateFormatters.shortDateString(from: "2026-05-01")) == true)
    }

    /// **The event write has no recurrence**, so an event draft that still carries a rule is
    /// refused rather than written as a single event — while the same rule on a task, which the
    /// task write now stores ([[T-3171]] (iii)), is accepted.
    @Test func aRepeatingEventIsRefusedAndARepeatingTaskIsNot() {
        var event = dragDraft(kind: .event)
        event.repeatRule = .weekly
        #expect(QuickCreateChoicePopover.hostLimitNotice(for: event) != nil, "a series was accepted as one event")

        var task = dragDraft()
        task.repeatRule = .weekly
        #expect(QuickCreateChoicePopover.hostLimitNotice(for: task) == nil, "a repeating task is still refused")
    }

    /// A switch to Event drops the task's series — the event arm draws no Repeat row, so a kept
    /// rule would be a field the user could neither see nor clear — and a switch to Task keeps it.
    @Test func aSwitchToEventDropsTheTasksSeries() {
        var task = dragDraft()
        task.repeatRule = .weekly
        task.seriesEndMode = .afterCount
        task.seriesEndCount = 5

        let asEvent = QuickCreateChoicePopover.droppingTaskOnlyFields(from: task, entering: .event)
        #expect(asEvent.repeatRule == .none)
        #expect(asEvent.seriesEndMode == .never)
        #expect(asEvent.seriesEndCount == 0)
        #expect(QuickCreateChoicePopover.hostLimitNotice(for: { var e = asEvent; e.kind = .event; return e }()) == nil)

        let asTask = QuickCreateChoicePopover.droppingTaskOnlyFields(from: task, entering: .task)
        #expect(asTask.repeatRule == .weekly, "a switch to Task dropped the series it can store")
    }

    /// **None is a real estimate everywhere else and cannot be one here.** The task write floors
    /// the length at five minutes (`SchedulingActions.insertTask`), so a task created from a drag
    /// always has one — the panel's Estimate row says so rather than storing a floor over the top
    /// of the user's answer.
    @Test func anEstimateOfNoneIsRefusedBecauseBothTaskWritesFloorTheLength() {
        var noEstimate = dragDraft()
        noEstimate.setEstimate(0)
        #expect(noEstimate.estimateMinutes == 0)
        #expect(
            QuickCreateChoicePopover.hostLimitNotice(for: noEstimate) != nil,
            "Estimate: None was accepted and would have been stored as a quarter hour"
        )
        // An event has no estimate at all, so the same zero must not refuse one.
        var zeroOnAnEvent = dragDraft(kind: .event)
        zeroOnAnEvent.estimateMinutes = 0
        #expect(
            QuickCreateChoicePopover.hostLimitNotice(for: zeroOnAnEvent) == nil,
            "an event was refused for a task's field"
        )
    }

    /// **[[T-3171]] (iii): Due and Repeat reach the task value.** The series end goes through
    /// `effectiveSeriesEndMode`, so an `.onDate` with no day arrives as `.never`.
    @Test func dueAndRepeatTravelIntoTheTaskDraft() {
        var draft = dragDraft()
        draft.dueDateKey = "2026-05-09"
        draft.repeatRule = .weekly
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 4
        let payload = QuickCreateTaskDraft(scheduleDraft: draft)
        #expect(payload.dueDateKey == "2026-05-09")
        #expect(payload.repeatRule == .weekly)
        #expect(payload.seriesEndMode == .afterCount)
        #expect(payload.seriesEndCount == 4)

        draft.seriesEndMode = .onDate
        draft.seriesEndDateKey = ""
        #expect(QuickCreateTaskDraft(scheduleDraft: draft).seriesEndMode == .never)
    }

    // MARK: - [[T-1610]]: the Event arm's prose is not the Task arm's

    /// **The defect, as a value.** A note typed on the Event arm must not come back out of the
    /// draft the Task arm builds — they are not the same field in the first place: one is
    /// `EKEvent.notes` and leaves the store, the other is `AppTask.notes`.
    ///
    /// Both directions, because one alone is satisfiable by a slot that always answers empty.
    /// **Keyed on `CadenceScheduleDraftKind` since [[T-3171]]**: the popover's own kind enum, which
    /// this used to read and whose first case was the last of [[T-3170]]'s Block vocabulary in the
    /// tree, is gone with the popover's own form.
    @Test func theEventArmsProseNeverReachesTheTaskDraft() {
        var draft = QuickCreateNotesDraft()
        draft.set("Bring the referral letter", for: .event)

        #expect(
            draft.notes(for: .task).isEmpty,
            "the Event arm's note rode into the Task draft: \(draft.notes(for: .task))"
        )
        #expect(draft.notes(for: .event) == "Bring the referral letter")

        draft.set("Draft the brief first", for: .task)
        #expect(
            draft.notes(for: .task) == "Draft the brief first",
            "the Task arm cannot keep its own prose, which is not a fix but a second defect"
        )
        #expect(
            draft.notes(for: .event) == "Bring the referral letter",
            "the Task arm's note overwrote the Event arm's"
        )
        #expect(
            draft.notes(for: .task) != draft.notes(for: .event),
            "both arms answered the same prose; this test measures nothing"
        )
    }

    /// The wiring, because the value above is only the fix if the popover is holding it.
    ///
    /// `CadenceScheduleDraft` carries **one** `notes`, so the two slots survive only if the popover
    /// parks the outgoing kind's prose and loads the incoming kind's on every switch. A host that
    /// held `QuickCreateNotesDraft` and never read it back would satisfy a binding assertion and
    /// still carry the note across.
    @Test func thePopoverParksAndRestoresTheNotesSlotOnEveryKindSwitch() throws {
        let popover = try code(Self.popoverPath)
        #expect(
            CadenceSourceScan.matchCount(#"@State private var notesDraft = QuickCreateNotesDraft\(\)"#, in: popover) == 1,
            "the popover no longer holds exactly one notes draft"
        )
        let carry = try #require(
            CadenceSourceScan.functionBody(named: "carryNotes", in: popover),
            "the popover no longer carries notes across a kind switch"
        )
        #expect(carry.contains("notesDraft.set(draft.notes, for: previousKind)"), "the outgoing kind's prose is not parked")
        #expect(carry.contains("draft.notes = notesDraft.notes(for: newKind)"), "the incoming kind's prose is not restored")
        #expect(
            popover.contains("carryNotes(leaving: previousKind, entering: newKind)"),
            "nothing calls the carry when the kind changes"
        )
    }

    // MARK: - The old form is gone

    /// **The Block vocabulary with it.** The popover's kind enum, its two case names and the
    /// selector over them were the twelve occurrences [[T-3170]] never reached, in the one
    /// Block-aware file that creates rather than displays.
    @Test func thePopoverCarriesNoModeEnumAndNoBlockVocabulary() throws {
        let popover = try code(Self.popoverPath)
        #expect(popover.contains("struct QuickCreateChoicePopover: View"), "non-vacuity: file unread")
        for needle in ["enum Mode", "timeBlock", "calendarEvent", "modeSelector", "modeButton", "selectMode"] {
            #expect(
                CadenceSourceScan.matchCount(NSRegularExpression.escapedPattern(for: needle), in: popover) == 0,
                "the drag-create popover still carries \(needle)"
            )
        }
    }

    /// The whole of the old form, and the file it lived in.
    ///
    /// `QuickCreateChoiceSupportViews.swift` declared the two Task composers, the Event composer,
    /// the read-only slot summary and their row/section/value/notes primitives, and **nothing
    /// outside the popover ever constructed one** — which is why adopting the panel deleted the
    /// file rather than leaving it orphaned.
    @Test func theOldQuickCreateComposersAreGoneFromTheWholeTree() throws {
        let files = try cadenceAppSwiftFiles()
        #expect(files.count > 300, "non-vacuity: \(files.count) app sources swept")
        #expect(
            files.contains("Cadence/macOS/Views/QuickCreateChoiceSupportViews.swift") == false,
            "the quick-create support file is still in the tree"
        )
        let symbols = [
            "QuickCreateTaskSlotInspectorView",
            "QuickCreateTaskDetailsView",
            "QuickCreateEventDetailsView",
            "QuickCreateSlotSummary",
            "QuickCreateContainerFieldControls",
            "QuickCreateDetailRow",
            "QuickCreateCompactSection",
            "QuickCreateInspectorValue",
            "QuickCreateNotesEditor"
        ]
        // One read per file, not one per file per symbol: the sweep is ~400 sources wide.
        for path in files {
            let source = CadenceSourceScan.codeOnly(try cadenceTestSource(path))
            for symbol in symbols where source.contains(symbol) {
                Issue.record("\(path) still names the deleted composer \(symbol)")
            }
        }
    }

    /// The `~` shortcut goes with the form; the routing does not. The panel's List row is the
    /// discoverable form of the same choice, and `TildeContainerPicker` itself is untouched — it is
    /// still `TaskTitleEntryField`'s.
    @Test func theSecondCopyOfTheTildeFlowIsGoneAndThePickerIsNot() throws {
        let popover = try code(Self.popoverPath)
        for needle in ["TildeContainerPicker", "tildeSearchQuery", "tildeMode", "selectTildeContainerItem"] {
            #expect(
                CadenceSourceScan.matchCount(NSRegularExpression.escapedPattern(for: needle), in: popover) == 0,
                "the popover still carries its copy of the `~` flow's \(needle)"
            )
        }
        #expect(
            CadenceSourceScan.matchCount(#"struct TildeContainerPicker: View"#, in: try code(Self.tildePickerPath)) == 1,
            "the `~` picker itself is gone, which this slice never asked for"
        )
        // And the panel's List row is what replaces it.
        #expect(popover.contains("listChoices: CadenceScheduleDraftChoices.listChoices("))
        #expect(popover.contains("sectionChoices: CadenceScheduleDraftChoices.sectionChoices("))
    }

    /// The adoption itself, in the shape the six earlier slices landed: the draft goes in, the two
    /// writes come back as `String?`, and **Delete is absent** because nothing exists to delete.
    @Test func thePopoverHostsTheSharedPanelInCreateMode() throws {
        let popover = try code(Self.popoverPath)
        #expect(CadenceSourceScan.matchCount(#"CadenceSchedulePanel\("#, in: popover) == 1)
        #expect(popover.contains("draft: $draft"))
        #expect(popover.contains("CadenceSchedulePanelActions("))
        #expect(popover.contains("delete: nil"), "the creating popover offers a Delete control")
        // Withheld, not drawn-and-dropped: the event write carries neither of these two.
        for flag in ["offersEventRepeat: false", "offersEventLocation: false"] {
            #expect(popover.contains(flag), "the popover offers a field its host cannot write: \(flag) missing")
        }
        // And offered where the write now carries them ([[T-3171]] (iii)).
        for flag in ["offersTaskRepeat: true", "offersTaskDue: true"] {
            #expect(popover.contains(flag), "the popover withholds a task field its host writes: \(flag) missing")
        }
        #expect(popover.contains("canCommit: canCommit"))
        #expect(popover.contains("failureNotice: createFailureNotice ?? hostLimitNotice"))
    }

    /// The canvas forwards the **popover's** minutes. It used to capture the drag's own `start` and
    /// `end` in the event closure, which was right while the Event tab had no time control and is
    /// the displays-one-makes-another split the moment the panel's rollers can move them.
    @Test func theCanvasCreatesTheRangeThePopoverConfirmedNotTheOneTheDragDrew() throws {
        let canvas = try code(Self.canvasPath)
        #expect(canvas.contains("struct TimelineDayCanvas: View"), "non-vacuity: file unread")
        let popoverBody = try #require(CadenceSourceScan.functionBody(named: "quickCreatePopover", in: canvas))
        // The forwarded value is the popover's own `QuickCreateEventDraft` ([[T-3171]] (iv)), with
        // only its title resolved — so neither the drag's `start`/`end` nor its day can be swapped in.
        #expect(
            CadenceSourceScan.matchCount(#"onCreateEvent\?\(stored\)"#, in: popoverBody) == 1,
            "the canvas does not forward the draft the popover confirmed"
        )
        #expect(
            CadenceSourceScan.matchCount(#"onCreateEvent\?\([^)]*\bstart\b"#, in: popoverBody) == 0,
            "the canvas still creates the drag's own range instead of the confirmed one"
        )
        // The seed is still the drag's, which is the half that must not move.
        #expect(popoverBody.contains("startMin: start,"))
        #expect(popoverBody.contains("endMin: end,"))
    }

    // MARK: - T-1436: the priority the composer names reaches the stored task

    /// **Behavioural, through the real write path.** The Calendar page's day column is the macOS
    /// composer that creates in place, and it writes through `SchedulingActions.insertTask` — which
    /// hardcoded `priority: .none` into the draft it built, so `QuickCreateTaskDraft.priority` was
    /// dropped on the floor no matter what the form drew.
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

    /// The source half: the panel carries the priority and the host forwards it. Either alone goes
    /// quietly green — a picker whose value is dropped at the call site looks like a working
    /// control, and a forwarded field with no control to set it is unreachable.
    @Test func theDragCreateDraftCarriesThePriorityAndItsHostForwardsIt() throws {
        let popover = try code(Self.popoverPath)
        #expect(
            popover.contains("priority: draft.priority"),
            "the popover never hands the panel's priority to the host's draft"
        )

        // Both hosts hand the whole draft to one write since [[T-3171]] (iv); the priority is
        // forwarded there, once.
        let host = try code(Self.monthGridPath)
        let forwarded = try #require(CadenceSourceScan.functionBody(named: "createTask", in: host))
        #expect(
            forwarded.contains("SchedulePanelDataSupport.insertDragCreatedTask("),
            "the calendar day column no longer writes the draft through the shared drag-create write"
        )
        let write = try code("Cadence/macOS/Views/SchedulePanelDataSupport.swift")
        let insert = try #require(CadenceSourceScan.functionBody(named: "insertDragCreatedTask", in: write))
        #expect(
            CadenceSourceScan.matchCount(#"priority: draft\.priority"#, in: insert) == 1,
            "the drag-create write drops the draft's priority on the way to the store"
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

    /// A second priority picker on one platform is the drift T-1412 spent a ticket undoing for the
    /// tag chip. The create sheet's private `priorityMarkButton` became `TaskPriorityPicker`; the
    /// drag-create popover's two copies of it went with its form, and the mark control the panel
    /// draws is the shared `TaskPriorityMarkControl` (T-1278's ruling).
    @Test func macOSHasExactlyOneTaskPriorityPickerDeclarationAndNoPrivateCopy() throws {
        #expect(
            CadenceSourceScan.matchCount(
                #"struct TaskPriorityPicker: View"#,
                in: try code(Self.createSheetSupportPath)
            ) == 1,
            "the shared priority picker is not declared where the create sheet's spellings live"
        )
        #expect(
            CadenceSourceScan.matchCount(#"TaskPriorityPicker\("#, in: try code(Self.createSheetPath)) == 1,
            "the create sheet does not build the shared priority picker"
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

    // MARK: - The list rows are the shared, narrowed ones

    /// The panel takes rows, not `[Area]`/`[Project]`, so every creating host has to build them —
    /// and building them per host is how the iPad popover came to offer archived and completed
    /// lists while the sheet beside it did not. macOS reads the shared rule.
    @Test func theDragCreateListRowsAreNarrowedByTheSharedPickableRule() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let live = Area(name: "Operations")
        live.order = 0
        let archived = Area(name: "Archive Me")
        archived.order = 1
        archived.status = .archived
        let shipping = Project(name: "Cadence")
        shipping.order = 0
        shipping.sectionNames = ["Build", "Ship"]
        let shelved = Project(name: "Shelved")
        shelved.order = 1
        shelved.status = .archived
        for model in [live, archived] { context.insert(model) }
        for model in [shipping, shelved] { context.insert(model) }
        try context.save()

        let draft = dragDraft()
        let names = CadenceScheduleDraftChoices.listChoices(
            for: draft,
            areas: [live, archived],
            projects: [shipping, shelved]
        ).map(\.name)

        #expect(names.first == "Inbox", "the Inbox is no longer the first row")
        #expect(names.contains("Operations"))
        #expect(names.contains("Cadence"))
        #expect(names.contains("Archive Me") == false, "an archived list is offered to a new task")
        #expect(names.contains("Shelved") == false, "an archived project is offered to a new task")

        // The Inbox has no sections, so the panel greys its Section row out there.
        #expect(CadenceScheduleDraftChoices.sectionChoices(for: draft, areas: [live], projects: [shipping]).isEmpty)

        var inProject = draft
        inProject.listToken = CadenceTaskComposerSupport.token(for: .project(shipping.id))
        #expect(
            CadenceScheduleDraftChoices.sectionChoices(for: inProject, areas: [live], projects: [shipping])
                == [TaskSectionDefaults.defaultName, "Build", "Ship"],
            "a list's own sections are offered beside the default every task surface shows"
        )
        // A list change re-resolves the section rather than leaving the old list's name behind: a
        // name the new list has survives, one it does not have falls back to that list's first.
        inProject.sectionName = "Ship"
        #expect(
            CadenceScheduleDraftChoices.normalizedSectionName(for: inProject, areas: [live], projects: [shipping]) == "Ship",
            "a section the chosen list really has was re-resolved away"
        )
        inProject.sectionName = "Nowhere"
        #expect(
            CadenceScheduleDraftChoices.normalizedSectionName(for: inProject, areas: [live], projects: [shipping])
                == TaskSectionDefaults.defaultName,
            "a section the chosen list does not have survived the list change"
        )
    }
}

#endif
