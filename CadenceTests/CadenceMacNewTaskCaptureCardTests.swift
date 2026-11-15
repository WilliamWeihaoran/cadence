#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-13792]]: the Mac's Cmd+N / `+` composer is the shared capture card.**
///
/// It was its own form, and its `createTask()` set no repeat rule at all and took the time and the
/// estimate straight from the seed, so a new Mac task could not be given a repeat, a time or an
/// estimate, and could not be an event. It hosts `CadenceSchedulePanel` + `.capturePresentation`
/// now, as `iOSCreateTaskSheet` does, with the Mac keyboard layer on top.
@MainActor
struct CadenceMacNewTaskCaptureCardTests {

    // MARK: - What the card's task draft writes

    @Test func theCreationDraftCarriesTheRepeatTheTimeAndTheEstimate() {
        var draft = CadenceScheduleDraft.quickCreate(dateKey: "2026-11-10", startMin: 14 * 60, opensTimed: true, kind: .task)
        draft.title = "Water the plants"
        draft.repeatRule = .weekly
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 4
        draft.setEstimate(45)

        let creation = CadenceTaskComposerSupport.creationDraft(
            from: draft, container: .inbox, tags: [], subtaskTitles: ["Fern", "Basil"]
        )

        #expect(creation.repeatRule == .weekly)
        #expect(creation.seriesEndMode == .afterCount)
        #expect(creation.seriesEndCount == 4)
        #expect(creation.scheduledDateKey == "2026-11-10")
        #expect(creation.scheduledStartMin == 14 * 60)
        #expect(creation.estimatedMinutes == 45)
        #expect(creation.subtaskTitles == ["Fern", "Basil"])
    }

    /// An `.onDate` end with no day is no end at all, as the drag-create popover's draft says it.
    @Test func anEndDateWithNoDayIsWrittenAsNever() {
        var draft = CadenceScheduleDraft.quickCreate(dateKey: "2026-11-10", startMin: 9 * 60, opensTimed: false, kind: .task)
        draft.repeatRule = .daily
        draft.seriesEndMode = .onDate
        draft.seriesEndDateKey = ""

        let creation = CadenceTaskComposerSupport.creationDraft(from: draft, container: .inbox, tags: [], subtaskTitles: [])

        #expect(creation.repeatRule == .daily)
        #expect(creation.seriesEndMode == .never)
        #expect(creation.scheduledStartMin == -1, "an untimed task writes no minute")
    }

    // MARK: - What a seed opens

    @Test func aBareSeedOpensATaskWithNoDoDate() {
        let draft = CadenceTaskComposerSupport.captureDraft(seed: TaskCreationSeed().composerSeed)
        #expect(draft.kind == .task)
        #expect(draft.startDateKey.isEmpty)
        #expect(draft.scheduledStartMin == -1)
        #expect(draft.repeatRule == .none)
    }

    @Test func aSeededSlotOpensTimedAtItWithTheSeedsFields() {
        var seed = TaskCreationSeed()
        seed.title = "Standup"
        seed.doDateKey = "2026-11-12"
        seed.scheduledStartMin = 10 * 60
        seed.estimatedMinutes = 15
        seed.priority = .high
        seed.dueDateKey = "2026-11-14"

        let draft = CadenceTaskComposerSupport.captureDraft(seed: seed.composerSeed, subtaskTitles: ["Notes"])

        #expect(draft.title == "Standup")
        #expect(draft.startDateKey == "2026-11-12")
        #expect(draft.scheduledStartMin == 10 * 60)
        #expect(draft.estimateMinutes == 15)
        #expect(draft.estimateIsExplicit)
        #expect(draft.priority == .high)
        #expect(draft.dueDateKey == "2026-11-14")
        #expect(draft.subtaskTitles == ["Notes"])
    }

    // MARK: - The keyboard layer

    private static func blankTask() -> CadenceScheduleDraft {
        CadenceTaskComposerSupport.captureDraft(seed: TaskCreationSeed().composerSeed)
    }

    @Test func commandTSetsTodayThenClearsIt() {
        var draft = Self.blankTask()
        CreateTaskKeyboardCommands.toggleDoToday(&draft, today: "2026-11-08")
        #expect(draft.startDateKey == "2026-11-08")
        #expect(draft.endDateKey == "2026-11-08")
        #expect(draft.scheduledStartMin == -1, "a keyed do date adds no time")
        CreateTaskKeyboardCommands.toggleDoToday(&draft, today: "2026-11-08")
        #expect(draft.startDateKey.isEmpty)
    }

    @Test func commandDSetsTodayAsDueThenClearsIt() {
        var draft = Self.blankTask()
        CreateTaskKeyboardCommands.toggleDueToday(&draft, today: "2026-11-08")
        #expect(draft.dueDateKey == "2026-11-08")
        CreateTaskKeyboardCommands.toggleDueToday(&draft, today: "2026-11-08")
        #expect(draft.dueDateKey.isEmpty)
    }

    @Test func theNudgeStartsFromTodayAndMovesADay() {
        var draft = Self.blankTask()
        CreateTaskKeyboardCommands.nudgeDoDate(&draft, by: 1, today: "2026-11-08")
        #expect(draft.startDateKey == "2026-11-09")
        CreateTaskKeyboardCommands.nudgeDoDate(&draft, by: -2, today: "2026-11-08")
        #expect(draft.startDateKey == "2026-11-07")
        #expect(draft.endDateKey == draft.startDateKey)
    }

    @Test func commandPCyclesPriorityAndWraps() {
        var draft = Self.blankTask()
        let all = TaskPriority.allCases
        for step in 1...all.count {
            CreateTaskKeyboardCommands.cyclePriority(&draft)
            #expect(draft.priority == all[step % all.count])
        }
    }

    /// [[T-14041]]: with `!!` typed in the title the card shows medium, and Cmd+P has to move what
    /// the card shows -- and what the task will be created with -- rather than a `draft.priority`
    /// the title mark overrules on both.
    @Test func commandPStepsFromATitleMarkAndTakesItOut() {
        var draft = Self.blankTask()
        draft.title = "Call mom !!"
        #expect(CadenceCaptureFieldInventory.priority(for: draft) == .medium)

        CreateTaskKeyboardCommands.cyclePriority(&draft)

        #expect(draft.title == "Call mom")
        #expect(draft.priority == .high)
        #expect(CadenceCaptureFieldInventory.priority(for: draft) == .high)
        let creation = CadenceTaskComposerSupport.creationDraft(
            from: draft, container: .inbox, tags: [], subtaskTitles: []
        )
        #expect(creation.resolvedPriority == .high)
    }

    /// A title with no mark keeps its text exactly, trailing space included: the caret is in it.
    @Test func commandPLeavesAnUnmarkedTitleAsTyped() {
        var draft = Self.blankTask()
        draft.title = "Call mom "
        CreateTaskKeyboardCommands.cyclePriority(&draft)
        #expect(draft.title == "Call mom ")
        #expect(draft.priority == .low)
    }

    /// The date chords are the task's: an event's start is a range the card's Starts row moves.
    @Test func theChordsLeaveAnEventAlone() {
        var event = CadenceTaskComposerSupport.captureDraft(seed: TaskCreationSeed().composerSeed, initialKind: .event)
        let opened = event
        CreateTaskKeyboardCommands.toggleDoToday(&event, today: "2026-01-01")
        CreateTaskKeyboardCommands.toggleDueToday(&event, today: "2026-01-01")
        CreateTaskKeyboardCommands.nudgeDoDate(&event, by: 3, today: "2026-01-01")
        CreateTaskKeyboardCommands.cyclePriority(&event)
        #expect(event == opened)
    }

    // MARK: - Source shape

    /// No unit test can present a SwiftUI sheet, so the hosting is read from source.
    @Test func theSheetHostsTheSharedCaptureCardWithTheKeyboardLayerOnTop() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/CreateTaskSheet.swift")
        )
        let body = try #require(CadenceSourceScan.declarationBody("struct CreateTaskSheet: View", in: source))
        #expect(CadenceSourceScan.matchCount(#"CadenceSchedulePanel\("#, in: body) == 1)
        #expect(body.contains(".capturePresentation(CadenceScheduleCaptureOptions("))
        #expect(body.contains("CadenceTaskComposerSupport.creationDraft("))
        #expect(body.contains("calendarManager.createStandaloneEvent("), "the Event arm has no write")
        #expect(!body.contains("TaskDateChip("), "the old badge toolbar is back")
        let compact = body.filter { !$0.isWhitespace }
        for chord in [
            #".keyboardShortcut("t",modifiers:.command)"#,
            #".keyboardShortcut("t",modifiers:[.command,.shift])"#,
            #".keyboardShortcut("d",modifiers:.command)"#,
            #".keyboardShortcut("d",modifiers:[.command,.shift])"#,
            #".keyboardShortcut("p",modifiers:.command)"#,
            #".keyboardShortcut("=",modifiers:[.command,.shift])"#,
            #".keyboardShortcut("-",modifiers:[.command,.shift])"#,
            ".keyboardShortcut(.return,modifiers:[.command])",
        ] {
            #expect(compact.contains(chord), "\(chord) is gone from the keyboard layer")
        }
        #expect(compact.contains("fieldRequest=.doDate"))
        #expect(compact.contains("fieldRequest=.dueDate"))
    }

    /// **[[T-17746]]: Cmd+Return on a title of marks alone says why, as Return does.** The chord is
    /// the keyboard layer's own button and calls the sheet's `commit()` without passing the card's
    /// title gate, so `!!!` reached the service, which made nothing, and the chord said nothing.
    /// No unit test can press a key, so the gate's place is read from source: first in `commit()`,
    /// ahead of `canCreate`, answering with the card's sentence.
    @Test func commandReturnOnAMarksOnlyTitleSaysAddATitleFirst() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/CreateTaskSheet.swift")
        )
        let body = try #require(CadenceSourceScan.declarationBody("private func commit() -> String?", in: source))
        let compact = body.filter { !$0.isWhitespace }
        let gate = try #require(
            compact.range(of: "guarddraft.hasCommittableTitleelse{returnInlineTaskComposerSupport.noNameNotice}"),
            "commit() does not refuse a title the card would refuse"
        )
        let canCreate = try #require(compact.range(of: "guardcanCreateelse"))
        #expect(gate.lowerBound < canCreate.lowerBound, "the title gate must run before the silent canCreate guard")

        var marksOnly = Self.blankTask()
        marksOnly.title = "!!!"
        #expect(!marksOnly.hasCommittableTitle, "non-vacuity: the gate refuses a marks-only title")
        #expect(InlineTaskComposerSupport.noNameNotice == "Add a title first.")
    }

    /// **[[T-17747]]: a card left open across midnight words its dates from the new day.** The
    /// quick-capture panel keeps its card standing for the next open ([[T-5302]]); its Do and Due
    /// chips read the clock only when something else redrew them, so yesterday's do date still
    /// read "Today". Both chips are worded from the day the card's observer holds
    /// (`CadenceDayChangeAdoptionTests` pins the observer itself).
    @Test func theCardsDateChipsAreWordedFromTheObservedDay() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        )
        let card = try #require(CadenceSourceScan.declarationBody(
            "struct CadenceScheduleCaptureCard<NotesField: View>: View", in: source
        )).filter { !$0.isWhitespace }
        #expect(card.contains("draft.doRowLabel(relativeTo:observedToday)"))
        #expect(card.contains("draft.dueRowLabel(relativeTo:observedToday)"))
        #expect(!card.contains("draft.doRowLabel}"), "a chip still reads the clock's day")
        #expect(!card.contains("returndraft.dueRowLabelcase"),
                "a chip still reads the clock's day")

        // What the reference changes: the same do date, worded from the day it was set and the next.
        var draft = Self.blankTask()
        draft.startDateKey = "2026-11-14"
        draft.endDateKey = "2026-11-14"
        let setOn = try #require(DateFormatters.date(from: "2026-11-14"))
        let nextDay = try #require(DateFormatters.date(from: "2026-11-15"))
        #expect(draft.doRowLabel(relativeTo: setOn) == "Today")
        #expect(draft.doRowLabel(relativeTo: nextDay) != "Today")
    }

    /// The quick-capture panel is its own SwiftUI root, so the card's Event arm needs the calendar
    /// manager handed to it there; the main window's root already installs it.
    @Test func theQuickCapturePanelInstallsTheCalendarManager() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Services/QuickTaskPanelController.swift")
        )
        #expect(source.contains(".environment(CalendarManager.shared)"))
    }
}
#endif
