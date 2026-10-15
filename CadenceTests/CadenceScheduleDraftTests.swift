import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The shared schedule draft — the model half of the one panel that creates and edits, tasks and
/// events, on both platforms ([[T-3169]], for [[T-3171]]).
///
/// **What is pinned here is what a screenshot cannot see.** The panel is a SwiftUI body and this
/// target is macOS-built, so these are the rules that could be wrong silently: that an all-day task
/// is an *untimed* task rather than a 24-hour one, that a drag handle cannot invert a block, that
/// switching kind does not carry a field the other kind has nowhere to put, and that the Do-after-
/// Due warning counts the actual days rather than printing a generic sentence.
@Suite("Schedule draft")
@MainActor
struct CadenceScheduleDraftTests {

    private func draft(
        day: String = "2026-10-16",
        startMin: Int = 16 * 60,
        kind: CadenceScheduleDraftKind = .task
    ) -> CadenceScheduleDraft {
        CadenceScheduleDraft(dateKey: day, startMin: startMin, kind: kind)
    }

    // MARK: Creating

    /// A press-and-hold leaves an hour-long block at the pressed quarter-hour, not the 30-minute
    /// task the docked bar hard-coded.
    @Test("A new draft is an hour at the pressed snap")
    func newDraftIsAnHourAtThePressedSnap() {
        let pressed = draft(startMin: 16 * 60 + 7)
        #expect(pressed.startMin == 16 * 60, "the press did not snap to the touch grid")
        #expect(pressed.durationMinutes == CadenceScheduleDraft.defaultDurationMinutes)
        #expect(pressed.subject == .creating)
        #expect(!pressed.subject.isEditing)
        #expect(!pressed.spansMultipleDays)
    }

    /// Creating and editing differ by `subject` and by the Delete control — nothing else about the
    /// form moves, which is the whole claim of T-3171.
    @Test("Editing is the same draft with a subject")
    func editingIsTheSameDraftWithASubject() {
        var task = draft()
        task.subject = .editingTask(UUID())
        #expect(task.subject.isEditing)

        var event = draft(kind: .event)
        event.subject = .editingEvent("event-id")
        #expect(event.subject.isEditing)
    }

    // MARK: All-day is untimed, for a task

    /// `AppTask.scheduledStartMin == -1` is the app's existing spelling of "planned for this day,
    /// at no particular time". A task pinned 00:00–24:00 would put a block across the whole canvas
    /// for something every other surface draws in the untimed column.
    @Test("An all-day task is an untimed task, not a twenty-four hour one")
    func allDayTaskIsUntimed() {
        var task = draft()
        #expect(task.scheduledStartMin == 16 * 60)
        task.isAllDay = true
        #expect(task.scheduledStartMin == -1)
        #expect(task.doTimeLabel == "Add time")
    }

    /// The Do row's quiet Time line says what it holds once it holds something — a time *and* a
    /// length, which is the mock's "3:00 PM · 1h".
    @Test("The Do time row names the time and the length once there is one")
    func doTimeRowNamesTimeAndLength() {
        let task = draft(startMin: 15 * 60)
        #expect(task.doTimeLabel.contains(TimeFormatters.timeString(from: 15 * 60)))
        #expect(task.doTimeLabel.contains(CadenceTaskPresentationSupport.estimateLabel(minutes: 60)))
    }

    // MARK: Edge handles

    /// Dragging the top handle past the bottom one shortens the block to one snap step. It never
    /// inverts, and it never swaps its own ends under the finger.
    @Test("An edge handle cannot invert the block")
    func edgeHandleCannotInvertTheBlock() {
        var block = draft()
        block.moveStartEdge(toMinute: 23 * 60)
        #expect(block.startMin < block.endMin)
        #expect(block.durationMinutes == CadenceScheduleDraft.minimumDurationMinutes)

        var other = draft()
        other.moveEndEdge(toMinute: 0)
        #expect(other.endMin > other.startMin)
        #expect(other.durationMinutes == CadenceScheduleDraft.minimumDurationMinutes)
    }

    /// Moving the **start** carries the length with it, which is what a user dragging a start time
    /// means by it — as against stretching the block against a pinned end.
    @Test("Moving the start carries the length")
    func movingTheStartCarriesTheLength() {
        var block = draft(startMin: 9 * 60)
        let length = block.durationMinutes
        block.moveStart(toMinute: 13 * 60)
        #expect(block.startMin == 13 * 60)
        #expect(block.durationMinutes == length)
    }

    /// A handle cannot push a block outside the canvas it is drawn on.
    @Test("Edges stay inside the drawn day")
    func edgesStayInsideTheDrawnDay() {
        var block = draft(startMin: 23 * 60 + 45)
        block.moveEndEdge(toMinute: 40 * 60)
        #expect(block.endMin <= CadenceScheduleSupport.calendarEndHour * 60)

        var early = draft(startMin: 0)
        early.moveStartEdge(toMinute: -600)
        #expect(early.startMin >= CadenceScheduleSupport.calendarStartHour * 60)
    }

    // MARK: Switching kind

    /// A field the other kind cannot store must not survive the switch, or the panel is holding
    /// text with nowhere to go — the shape of a field that looks saved and is not.
    @Test("Switching kind drops what the other kind cannot hold")
    func switchingKindDropsWhatTheOtherCannotHold() {
        var event = draft(kind: .event)
        event.location = "Room 4"
        event.endDateKey = "2026-10-18"
        event.kind = .task
        event.normalizeForKind()
        #expect(event.location.isEmpty)
        #expect(event.endDateKey == event.startDateKey, "a task has one scheduledDate")

        var task = draft()
        task.dueDateKey = "2026-10-20"
        task.priority = .high
        task.kind = .event
        task.normalizeForKind()
        #expect(task.dueDateKey.isEmpty)
        #expect(task.priority == .none)
    }

    /// The **schedule** survives the switch on purpose: the draft block is in the same place on the
    /// canvas before and after, and moving it would make the switch look like it had done something
    /// to the time.
    @Test("Switching kind leaves the block where it is")
    func switchingKindLeavesTheBlockWhereItIs() {
        var block = draft(startMin: 16 * 60)
        let start = block.startMin
        let end = block.endMin
        block.kind = .event
        block.normalizeForKind()
        #expect(block.startMin == start)
        #expect(block.endMin == end)
    }

    // MARK: Do after Due

    /// The gap is counted, not asserted. A specific number is the whole value of the warning; "this
    /// is scheduled after its due date" is a sentence the user could have read off the two rows
    /// above it.
    @Test("The Do-after-Due warning counts the days")
    func doAfterDueWarningCountsTheDays() {
        var task = draft(day: "2026-10-19")
        task.dueDateKey = "2026-10-16"
        let notice = task.doAfterDueNotice
        #expect(notice != nil)
        #expect(notice?.contains("3 days") == true, "notice was \(notice ?? "nil")")
    }

    /// One day is singular. A warning that says "1 days" is a warning that was not written for the
    /// case it fires on most often.
    @Test("One day reads as a day")
    func oneDayReadsAsADay() {
        var task = draft(day: "2026-10-17")
        task.dueDateKey = "2026-10-16"
        #expect(task.doAfterDueNotice?.contains("1 day ") == true)
        #expect(task.doAfterDueNotice?.contains("1 days") == false)
    }

    /// It fires only when it is true, and never on an event — an `EKEvent` has no due date for a
    /// start to be after.
    @Test("The warning is silent when there is nothing to warn about")
    func warningIsSilentWhenThereIsNothingToWarnAbout() {
        #expect(draft().doAfterDueNotice == nil, "no due date set")

        var onTime = draft(day: "2026-10-16")
        onTime.dueDateKey = "2026-10-16"
        #expect(onTime.doAfterDueNotice == nil, "same day is not late")

        var early = draft(day: "2026-10-14")
        early.dueDateKey = "2026-10-16"
        #expect(early.doAfterDueNotice == nil, "before the deadline is not late")

        var event = draft(day: "2026-10-19", kind: .event)
        event.dueDateKey = "2026-10-16"
        #expect(event.doAfterDueNotice == nil, "an event has no due date")
    }

    /// **Warn, never block.** The panel's Save gate is `hasCommittableTitle` alone, so a late plan
    /// is saveable — the user is told, and nothing they chose is rewritten.
    @Test("A late plan is still committable")
    func aLatePlanIsStillCommittable() {
        var task = draft(day: "2026-10-19")
        task.dueDateKey = "2026-10-16"
        task.title = "Ship it"
        #expect(task.doAfterDueNotice != nil)
        #expect(task.hasCommittableTitle, "the warning must not gate the save")
        #expect(task.startDateKey == "2026-10-19", "nothing was clamped")
        #expect(task.dueDateKey == "2026-10-16")
    }

    // MARK: Labels

    /// Three shapes, because the thing being described has three.
    @Test("The schedule label names what it is describing")
    func scheduleLabelNamesWhatItIsDescribing() {
        let timed = draft(kind: .event)
        #expect(timed.scheduleLabel.contains("Oct 16"))
        #expect(timed.scheduleLabel.contains("–"), "a same-day timed block reads as a range")

        var allDay = draft(kind: .event)
        allDay.isAllDay = true
        #expect(allDay.scheduleLabel.contains("All day"))

        var multiDay = draft(kind: .event)
        multiDay.endDateKey = "2026-10-18"
        #expect(multiDay.spansMultipleDays)
        #expect(multiDay.scheduleLabel.contains("Oct 16"))
        #expect(multiDay.scheduleLabel.contains("Oct 18"), "a multi-day block must name both days")
    }

    /// A draft is visible before it is named, so it needs a word — an empty block would read as a
    /// rendering fault rather than as an unnamed one.
    @Test("An unnamed draft still says what it is")
    func unnamedDraftStillSaysWhatItIs() {
        #expect(draft().displayTitle == "New Task")
        #expect(draft(kind: .event).displayTitle == "New Event")
        #expect(!draft().hasCommittableTitle)

        var named = draft()
        named.title = "   "
        #expect(!named.hasCommittableTitle, "whitespace is not a name")
        #expect(named.displayTitle == "New Task")
    }
}

/// The iPad Today timeline no longer creates through a bar bolted under the canvas ([[T-3169]]).
///
/// Source-text checks, because what is being asserted is *that a surface is gone* and *that one
/// panel serves both platforms* — neither of which any runtime value reports.
@Suite("Today timeline draft creation")
@MainActor
struct CadenceTodayTimelineDraftCreationTests {

    private func source(_ relativePath: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("The docked quick-create bar is gone from Today's pane")
    func dockedQuickCreateBarIsGone() {
        let panel = source("Cadence/iOS/iOSTodaySchedulePanel.swift")
        #expect(!panel.isEmpty)
        #expect(!panel.contains("struct iOSScheduleQuickCreateBar"))
        #expect(!panel.contains("quickCreateComposer\n"))
        #expect(panel.contains("drawsDraftBlocks: true"))
    }

    /// The press-and-hold the owner asked for, and the reason it is sequenced before a drag: the
    /// long press alone carries no location, and the drag that follows it does.
    @Test("The timeline column answers a press-and-hold")
    func timelineColumnAnswersAPressAndHold() {
        let timeline = source("Cadence/iOS/iOSCalendarTimelineViews.swift")
        #expect(timeline.contains("LongPressGesture(minimumDuration:"))
        #expect(timeline.contains(".sequenced(before: DragGesture(minimumDistance: 0))"))
        #expect(timeline.contains("iOSTimelineDraftBlock("))
        #expect(timeline.contains("iOSTimelineDraftPanelHost("))
    }

    /// **The panel is shared, and that is checkable.** A single `iOS` type inside it would be the
    /// thing that stops macOS adopting it under T-3171, so the file is swept for the prefix rather
    /// than trusted to stay clean.
    @Test("The schedule panel names no iOS-only type")
    func schedulePanelNamesNoIOSOnlyType() {
        let panel = source("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        #expect(!panel.isEmpty)
        // A **directive**, not the characters. The file's own prose explains why the priority
        // hint was reworded by saying the sheet it came from sits under `#if os(iOS)`, and a bare
        // substring search reads that sentence as a conditional. What matters is that no line of
        // this file is a preprocessor directive, because one would mean the panel compiles
        // differently on the two platforms it is supposed to be the same on.
        let directives = panel
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#if") }
        #expect(directives.isEmpty, "the shared panel is conditionally compiled: \(directives)")
        // The `iOS`-prefixed vocabulary by name rather than by prefix: the file's own prose says
        // "four on iOS, four on macOS", and a bare substring sweep would read that sentence as a
        // type. These six are what the panel would most plausibly have reached for.
        for symbol in [
            "iOSCalendarManager",
            "iOSSegmentedChoice",
            "iOSEditorSection",
            "iOSEditorFieldRow",
            "iOSChoicePopoverList",
            "iOSContainerChoicePopover",
            "iOSActionButton"
        ] {
            #expect(!panel.contains(symbol), "the shared panel reaches for \(symbol)")
        }
        // Cadence's own date grid, never a system picker — the owner's ruling. `CadenceDatePicker`
        // ends in the same eleven characters, so it is removed before the sweep rather than
        // matched by it.
        #expect(panel.contains("CadenceQuickDatePopover("))
        #expect(panel.contains("CadenceDatePicker("))
        let withoutCadenceOwn = panel.replacingOccurrences(of: "CadenceDatePicker", with: "")
        #expect(!withoutCadenceOwn.contains("DatePicker("), "a system DatePicker reached the shared panel")
        // The roller, for every clock time.
        #expect(panel.contains("CadenceTimeRoller"))
    }

    /// Delete is the one control that separates creating from editing.
    @Test("Delete is present only when a record exists")
    func deleteIsPresentOnlyWhenARecordExists() {
        let panel = source("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        // [[T-3171]] added the read-only arm: a record that cannot be written has no Delete either.
        #expect(panel.contains("if !isReadOnly, let delete = actions.delete"))
        let host = source("Cadence/iOS/iOSTimelineDraftCreate.swift")
        #expect(host.contains("delete: nil"), "a draft has nothing to delete")
    }

    /// The draft block wears the real treatments, not an approximation of them — so it repaints
    /// with the committed blocks whenever either treatment is re-solved (T-3160).
    @Test("The draft block reads the shared calendar paint")
    func draftBlockReadsTheSharedCalendarPaint() {
        let block = source("Cadence/iOS/iOSTimelineDraftCreate.swift")
        #expect(block.contains("CadenceCalendarEventStyle.railFill(for:"))
        #expect(block.contains("CadenceCalendarEventStyle.plateFill(for:"))
        #expect(block.contains("CadenceCalendarEventStyle.railColor(for:"))
        #expect(block.contains("CadenceCalendarEventStyle.platePrimaryLabelColor"))
    }
}

/// The draft over an event that **already exists** — the model half of [[T-3171]]'s first
/// adoption, `iOSCalendarEventEditSheet` hosting the shared panel in edit mode.
///
/// Behavioural, on explicit calendars: the scheme pins `TZ=UTC` ([[T-1116]]), in which the
/// spring-forward hour this file has to reason about does not exist, so every zone is named.
@Suite("Schedule draft over an existing event")
@MainActor
struct CadenceScheduleDraftEventEditingTests {

    private func newYork() throws -> Calendar {
        try CadenceTestTimeZones.calendar("America/New_York")
    }

    private func instant(_ key: String, _ minute: Int, _ calendar: Calendar) throws -> Date {
        let day = try #require(DateFormatters.date(from: key, in: calendar))
        return try #require(CadenceCalendarEventTiming.startDate(day: day, startMin: minute, calendar: calendar))
    }

    private func editing(start: Date, end: Date, isAllDay: Bool = false, _ calendar: Calendar) -> CadenceScheduleDraft {
        CadenceScheduleDraft(
            editingEventID: "event-1",
            title: "Standup",
            notes: "Agenda",
            location: "Room 4",
            calendarID: "cal-1",
            start: start,
            end: end,
            isAllDay: isAllDay,
            calendar: calendar
        )
    }

    /// Opening an event and writing it back unchanged names the instants it was opened with — the
    /// round trip every save of a renamed event takes.
    @Test("An event opens as itself and writes back as itself")
    func anEventRoundTripsThroughTheDraft() throws {
        let calendar = try newYork()
        let start = try instant("2026-06-15", 10 * 60 + 5, calendar)
        let end = try instant("2026-06-15", 11 * 60 + 40, calendar)
        let draft = editing(start: start, end: end, calendar)

        #expect(draft.subject == .editingEvent("event-1"))
        #expect(draft.subject.isEditing)
        #expect(draft.kind == .event)
        #expect(draft.title == "Standup")
        #expect(draft.notes == "Agenda")
        #expect(draft.location == "Room 4")
        #expect(draft.calendarID == "cal-1")
        #expect(draft.startDateKey == "2026-06-15")
        #expect(draft.endDateKey == draft.startDateKey)
        #expect(draft.startMin == 10 * 60 + 5, "an off-grid start was snapped on the way in")
        #expect(draft.endMin == 11 * 60 + 40)

        let range = try #require(draft.eventDateRange(calendar: calendar))
        #expect(range.start == start)
        #expect(range.end == end)
    }

    /// The drag floor is a rule for a block being sized by a finger. A five-minute event opened to
    /// rename it is still five minutes long when it is saved.
    @Test("A short event is not lengthened to the drag floor")
    func aShortEventKeepsItsLength() throws {
        let calendar = try newYork()
        let start = try instant("2026-06-15", 9 * 60, calendar)
        let end = try instant("2026-06-15", 9 * 60 + 5, calendar)
        let range = try #require(editing(start: start, end: end, calendar).eventDateRange(calendar: calendar))
        #expect(range.end.timeIntervalSince(range.start) == 5 * 60)
        #expect(5 < CadenceScheduleDraft.minimumDurationMinutes, "the case is not below the floor")
    }

    /// EventKit's all-day end is exclusive, so a three-day event on the 16th–18th ends at 00:00 on
    /// the 19th. The panel's Ends row names the 18th — a day the event is on.
    @Test("An all-day event's end date is the last day it covers")
    func allDayEndIsTheLastCoveredDay() throws {
        let calendar = try newYork()
        let start = try #require(DateFormatters.date(from: "2026-10-16", in: calendar))
        let end = try #require(DateFormatters.date(from: "2026-10-19", in: calendar))
        let draft = editing(start: start, end: end, isAllDay: true, calendar)

        #expect(draft.isAllDay)
        #expect(draft.startDateKey == "2026-10-16")
        #expect(draft.endDateKey == "2026-10-18")
        #expect(draft.spansMultipleDays)

        let range = try #require(draft.eventDateRange(calendar: calendar))
        #expect(range.start == start)
        #expect(range.end == end)

        // And a one-day event is one day, not zero.
        let oneDayEnd = try #require(DateFormatters.date(from: "2026-10-17", in: calendar))
        let single = editing(start: start, end: oneDayEnd, isAllDay: true, calendar)
        #expect(single.endDateKey == single.startDateKey)
        #expect(!single.spansMultipleDays)
    }

    /// "4 PM – 12 AM" is one evening, not a two-day event.
    @Test("An event ending at the next midnight reads as one day")
    func anEndAtTheNextMidnightIsTheSameDay() throws {
        let calendar = try newYork()
        let start = try instant("2026-06-15", 16 * 60, calendar)
        let end = try #require(DateFormatters.date(from: "2026-06-16", in: calendar))
        let draft = editing(start: start, end: end, calendar)

        #expect(!draft.spansMultipleDays)
        #expect(draft.endMin == 24 * 60)
        let range = try #require(draft.eventDateRange(calendar: calendar))
        #expect(range.end == end)
    }

    /// A timed event across a midnight keeps its End time writable. The edge handle refuses a
    /// multi-day block — a drag on one day's canvas cannot name a time on another — and before
    /// `setEndMinute` the panel's End row on such an event wrote nowhere.
    @Test("The End time of a multi-day event is writable")
    func aMultiDayEndTimeIsWritable() throws {
        let calendar = try newYork()
        let start = try instant("2026-06-15", 22 * 60, calendar)
        let end = try instant("2026-06-16", 90, calendar)
        var draft = editing(start: start, end: end, calendar)
        #expect(draft.spansMultipleDays)
        #expect(draft.endDateKey == "2026-06-16")
        #expect(draft.endMin == 90)

        var handle = draft
        handle.moveEndEdge(toMinute: 3 * 60)
        #expect(handle.endMin == 90, "the drag rule changed; this test's contrast no longer holds")

        draft.setEndMinute(3 * 60)
        #expect(draft.endMin == 3 * 60)
        let range = try #require(draft.eventDateRange(calendar: calendar))
        #expect(range.end == (try instant("2026-06-16", 3 * 60, calendar)))

        // Inside one day the same call is the bottom handle, non-inversion rule and all.
        var sameDay = editing(
            start: try instant("2026-06-15", 9 * 60, calendar),
            end: try instant("2026-06-15", 10 * 60, calendar),
            calendar
        )
        sameDay.setEndMinute(8 * 60)
        #expect(sameDay.endMin == 9 * 60 + CadenceScheduleDraft.minimumDurationMinutes)
    }

    /// Pulling the end date back onto the start date leaves 10 PM – 1 AM on one day. The block
    /// gets its minimum length rather than an inverted range for the write to refuse.
    @Test("Moving the end day back never leaves the end before the start")
    func moveTheEndDayBackKeepsTheEndAfterTheStart() throws {
        let calendar = try newYork()
        var draft = editing(
            start: try instant("2026-06-15", 22 * 60, calendar),
            end: try instant("2026-06-16", 60, calendar),
            calendar
        )
        draft.endDateKey = draft.startDateKey
        #expect(draft.endMin < draft.startMin, "the case does not invert")
        #expect(draft.eventDateRange(calendar: calendar) == nil, "an inverted range is refused, not written")

        draft.keepEndAfterStart()
        #expect(draft.endMin == 22 * 60 + CadenceScheduleDraft.minimumDurationMinutes)
        #expect(draft.eventDateRange(calendar: calendar) != nil)

        // An end day before the start day is carried forward, too.
        draft.endDateKey = "2026-06-14"
        draft.keepEndAfterStart()
        #expect(draft.endDateKey == draft.startDateKey)
    }

    /// Both ends are wall-clock readings. On 2026-03-08 New York skips 02:00–02:59: a start chosen
    /// at 02:30 opens at 03:00, as every start in the app does (T-3119), and an End chosen at 03:00
    /// after a 01:00 start is 03:00 on the wall — one elapsed hour — not the 04:00 that adding the
    /// two-hour difference as a duration would land on.
    @Test("Both ends are set on the wall clock, gap policy included")
    func bothEndsAreWallClockReadings() throws {
        let calendar = try newYork()
        var draft = CadenceScheduleDraft(dateKey: "2026-03-08", startMin: 60, kind: .event, durationMinutes: 120)
        #expect(draft.endMin == 3 * 60)
        let range = try #require(draft.eventDateRange(calendar: calendar))
        #expect(calendar.component(.hour, from: range.end) == 3)
        #expect(range.end.timeIntervalSince(range.start) == 3600, "the end was added as a duration")

        draft.startMin = 2 * 60 + 30
        draft.endMin = 4 * 60
        let gap = try #require(draft.eventDateRange(calendar: calendar))
        #expect(calendar.component(.hour, from: gap.start) == 3)
        #expect(calendar.component(.minute, from: gap.start) == 0, "02:30 opens when the gap closes, at 03:00")
    }

    /// The editor writes the event's own instants back when nothing about the schedule moved.
    @Test("Schedule equality ignores everything but the schedule")
    func scheduleEqualityIsAboutTheScheduleAlone() throws {
        let calendar = try newYork()
        let opened = editing(
            start: try instant("2026-06-15", 9 * 60, calendar),
            end: try instant("2026-06-15", 10 * 60, calendar),
            calendar
        )
        var renamed = opened
        renamed.title = "Retro"
        renamed.location = "Room 9"
        renamed.notes = "New agenda"
        #expect(renamed.hasSameSchedule(as: opened))

        for change in [
            { (d: inout CadenceScheduleDraft) in d.startMin += 15 },
            { (d: inout CadenceScheduleDraft) in d.endMin += 15 },
            { (d: inout CadenceScheduleDraft) in d.endDateKey = "2026-06-16" },
            { (d: inout CadenceScheduleDraft) in d.startDateKey = "2026-06-14" },
            { (d: inout CadenceScheduleDraft) in d.isAllDay = true },
        ] {
            var moved = opened
            change(&moved)
            #expect(!moved.hasSameSchedule(as: opened))
        }
    }
}

/// The source half of the same adoption: the iOS event editor is a host of the shared panel, and
/// the panel carries what that editor needs without a platform type ([[T-3171]]).
@Suite("Event editor hosts the shared panel")
@MainActor
struct CadenceEventEditorPanelAdoptionTests {

    private func code(_ relativePath: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(relativePath)
        #expect(raw.count > 1_000, "\(relativePath) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "\(relativePath): the comment stripper removed nothing")
        #expect(stripped.count == raw.count)
        return stripped
    }

    @Test("The event editor draws the panel and none of the old form")
    func theEventEditorDrawsThePanel() throws {
        let editor = try code("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        #expect(CadenceSourceScan.matchCount(#"CadenceSchedulePanel\("#, in: editor) == 1)
        // The old form's controls, each now the panel's: a Days list, a Duration estimate, the
        // quarter-hour start list, and the calendar picker built from the platform popover.
        for retired in [
            "showDaysPicker", "allDayDurationDays", "durationMinutes", "EstimatePickerControl(",
            "CadenceStartTimeFieldRow(", "iOSChoicePopoverList(", "iOSChoiceValueButton(",
            "regularFormLayout", "compactFormLayout",
        ] {
            #expect(!editor.contains(retired), "the event editor still draws \(retired)")
        }
        // The two writes it owns, with the panel's fields reaching them.
        #expect(editor.contains("location: draft.location"), "the panel's Location row writes nowhere")
        #expect(editor.contains("draft.eventDateRange()"))
        #expect(editor.contains("draft.hasSameSchedule(as: openedDraft)"))
        // An existing series is not re-ruled from here, so the panel offers no Repeat.
        #expect(editor.contains("offersEventRepeat: false"))
    }

    /// Delete is the one control that separates editing from creating, and a read-only event has
    /// neither it nor Save — absent, not disabled.
    @Test("Delete is offered only on an event that can be written")
    func deleteIsOfferedOnlyOnAWritableEvent() throws {
        let editor = try code("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        let actions = try #require(CadenceSourceScan.declarationBody("private var panelActions: CadenceSchedulePanelActions", in: editor))
        #expect(actions.contains("if isEditable {"))
        #expect(actions.contains("actions.delete = {"))
        #expect(actions.contains("confirmDelete = true"), "Delete skipped its confirmation")
        #expect(editor.contains("readOnlyNotice: isEditable"))

        let panel = try code("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        let footer = try #require(CadenceSourceScan.declarationBody("private var footer: some View", in: panel))
        #expect(footer.contains("if !isReadOnly, let delete = actions.delete {"))
        #expect(CadenceSourceScan.matchCount(#"if !isReadOnly \{\s*Button\(action: commit\)"#, in: footer) == 1,
                "Save is drawn on a record that cannot be written")
        // The panel's own fields go inert on such a record; the host's notes slot does not, so the
        // Cadence event note stays reachable.
        #expect(CadenceSourceScan.matchCount(#"\.disabled\(isReadOnly\)"#, in: panel) == 2)
    }

    /// The End row is drawn whenever the event is timed — including across a midnight — and it
    /// writes through the rule that can reach a later day.
    @Test("The panel's End time is drawn and writable on a multi-day event")
    func theEndTimeIsDrawnOnAMultiDayEvent() throws {
        let panel = try code("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        let schedule = try #require(CadenceSourceScan.declarationBody("private var eventSchedule: some View", in: panel))
        #expect(CadenceSourceScan.matchCount(#"if !draft\.isAllDay \{\s*CadenceTimeRollerFieldRow\(\s*label: "End""#, in: schedule) == 1)
        #expect(!schedule.contains("spansMultipleDays"), "the End row is hidden across a midnight again")
        #expect(CadenceSourceScan.matchCount(#"if offersEventRepeat \{"#, in: schedule) == 1)
        let end = try #require(CadenceSourceScan.declarationBody("private var eventEndMinuteBinding: Binding<Int>", in: panel))
        #expect(end.contains("draft.setEndMinute($0)"))
    }
}

/// The draft over a task that **already exists**, and the one commit that writes it back
/// ([[T-3171]], the task editor's slice).
///
/// Behavioural, against an in-memory store: the iOS task sheet that hosts this is behind
/// `#if os(iOS)`, but what it reads and writes is shared, so the claims that could be wrong
/// silently — that opening writes nothing, that an untouched save changes nothing, that a refusal
/// puts every field back, that a list that did not change is not re-asserted — are asserted on
/// real models rather than scanned for.
@Suite("Schedule draft over an existing task")
@MainActor
struct CadenceScheduleDraftTaskEditingTests {

    private struct CommitRefused: Error {}

    private func store() throws -> (ModelContainer, ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (container, ModelContext(container))
    }

    /// A task with every field the panel edits set to something other than its default, and the
    /// two figures the panel's geometry cannot hold: a minute off the quarter-hour and an
    /// estimate off it.
    private func filedTask(in context: ModelContext, area: Area) throws -> AppTask {
        let task = AppTask(title: "Ship the fix")
        task.notes = "Before"
        task.priority = .medium
        task.scheduledDate = "2026-10-16"
        task.scheduledStartMin = 10 * 60 + 5
        task.estimatedMinutes = 20
        task.dueDate = "2026-10-18"
        task.order = 3
        task.area = area
        task.context = area.context
        context.insert(task)
        try context.save()
        return task
    }

    @Test("Opening a task reads its own figures, unsnapped and unfloored")
    func openingATaskReadsItsOwnFigures() throws {
        let (_, context) = try store()
        let area = Area(name: "Work")
        context.insert(area)
        let task = try filedTask(in: context, area: area)

        let draft = CadenceScheduleDraft(editing: task)
        #expect(draft.subject == .editingTask(task.id))
        #expect(draft.kind == .task)
        #expect(draft.title == "Ship the fix")
        #expect(draft.notes == "Before")
        #expect(draft.priority == .medium)
        #expect(draft.startDateKey == "2026-10-16")
        #expect(draft.startMin == 10 * 60 + 5, "the start was snapped to the drag grid on open")
        #expect(draft.scheduledStartMin == 10 * 60 + 5)
        #expect(draft.estimateMinutes == 20, "the estimate was snapped or floored on open")
        #expect(draft.dueDateKey == "2026-10-18")
        #expect(draft.listToken == CadenceTaskComposerSupport.token(for: .area(area.id)))

        task.estimatedMinutes = 0
        task.scheduledStartMin = -1
        let untimed = CadenceScheduleDraft(editing: task)
        #expect(untimed.estimateMinutes == 0, "no estimate opened as one")
        #expect(untimed.isAllDay)
        #expect(untimed.scheduledStartMin == -1)
    }

    /// Opening is not an edit (T-726's ground): the draft is built, nothing in the store moves and
    /// nothing is left pending.
    @Test("Opening a task writes nothing")
    func openingATaskWritesNothing() throws {
        let (_, context) = try store()
        let area = Area(name: "Work")
        context.insert(area)
        let task = try filedTask(in: context, area: area)
        #expect(!context.hasChanges)

        _ = CadenceScheduleDraft(editing: task)
        #expect(!context.hasChanges, "building the draft wrote to the task")
    }

    /// A save of what was opened changes nothing — including the two figures the geometry cannot
    /// hold, the task's place in its list, and a context the user set by hand.
    @Test("An untouched save writes the task back as it was")
    func anUntouchedSaveWritesTheTaskBackAsItWas() throws {
        let (container, context) = try store()
        let home = Context(name: "Home")
        let office = Context(name: "Office")
        let area = Area(name: "Work", context: home)
        for model in [home, office] { context.insert(model) }
        context.insert(area)
        let task = try filedTask(in: context, area: area)
        task.context = office
        task.estimatedMinutes = 0
        try context.save()

        let opened = CadenceScheduleDraft(editing: task)
        let landed = CadenceTaskEditDraftCommit.save(
            opened, opened: opened, to: task, area: area, project: nil,
            allTasks: [task], scope: .thisTask, in: context, reconciler: .inert
        )
        #expect(landed)

        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.scheduledStartMin == 10 * 60 + 5)
        #expect(stored.estimatedMinutes == 0, "an untouched save gave a task with no estimate one")
        #expect(stored.order == 3, "re-asserting the list it was already in moved it to the tail")
        #expect(stored.context?.name == "Office", "re-asserting the list overwrote a hand-set context")
        #expect(stored.title == "Ship the fix")
    }

    /// Every drafted field reaches the store in the one commit, a list move included.
    @Test("A saved draft writes every field it holds")
    func aSavedDraftWritesEveryFieldItHolds() throws {
        let (container, context) = try store()
        let work = Area(name: "Work")
        let home = Area(name: "Home")
        context.insert(work)
        context.insert(home)
        let task = try filedTask(in: context, area: work)

        let opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.title = "Ship the beta"
        draft.notes = "After"
        draft.priority = .high
        draft.setEstimate(45)
        draft.startDateKey = "2026-10-20"
        draft.moveStart(toMinute: 14 * 60)
        draft.dueDateKey = ""
        draft.listToken = CadenceTaskComposerSupport.token(for: .area(home.id))

        let landed = CadenceTaskEditDraftCommit.save(
            draft, opened: opened, to: task, area: home, project: nil,
            allTasks: [task], scope: .thisTask, in: context, reconciler: .inert
        )
        #expect(landed)
        #expect(!context.hasChanges, "the save left part of the edit pending")

        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.title == "Ship the beta")
        #expect(stored.notes == "After")
        #expect(stored.priority == .high)
        #expect(stored.estimatedMinutes == 45)
        #expect(stored.scheduledDate == "2026-10-20")
        #expect(stored.scheduledStartMin == 14 * 60)
        #expect(stored.dueDate == "")
        #expect(stored.area?.id == home.id, "the list move did not land")
    }

    /// The refusal half: every field the save wrote comes back, the series end condition and the
    /// note included, and the draft — which the panel is still showing — keeps what was chosen.
    @Test("A refused save puts every field back and leaves the draft as chosen")
    func aRefusedSavePutsEveryFieldBack() throws {
        let (_, context) = try store()
        let work = Area(name: "Work")
        let home = Area(name: "Home")
        context.insert(work)
        context.insert(home)
        let task = try filedTask(in: context, area: work)
        task.recurrenceRule = .daily
        try context.save()

        let opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.title = "Ship the beta"
        draft.notes = "After"
        draft.setEstimate(90)
        draft.clearDoDate()
        draft.listToken = CadenceTaskComposerSupport.token(for: .area(home.id))
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 4
        let chosen = draft

        let landed = CadenceTaskEditDraftCommit.save(
            draft, opened: opened, to: task, area: home, project: nil,
            allTasks: [task], scope: .thisTask, in: context, reconciler: .inert,
            commit: { _ in throw CommitRefused() }
        )
        #expect(!landed)
        #expect(task.title == "Ship the fix")
        #expect(task.notes == "Before", "a refused save left the note it wrote")
        #expect(task.estimatedMinutes == 20)
        #expect(task.scheduledDate == "2026-10-16")
        #expect(task.scheduledStartMin == 10 * 60 + 5)
        #expect(task.area?.id == work.id, "a refused save left the task in the list it was moved to")
        #expect(task.order == 3)
        #expect(task.recurrenceEndMode == .never, "a refused save left the series bound it wrote")
        #expect(task.recurrenceEndCount == 0)
        #expect(draft == chosen, "the refusal touched the draft the panel is still showing")
    }

    /// A series edit reaches later occurrences only when asked to, and the rule is applied only
    /// when it moved — applying it stamps series metadata.
    @Test("A series edit reaches the later occurrences only for this-and-future")
    func aSeriesEditReachesLaterOccurrencesOnlyWhenAsked() throws {
        func series() throws -> (ModelContext, AppTask, AppTask) {
            let (_, context) = try store()
            let first = AppTask(title: "Water plants")
            let second = AppTask(title: "Water plants")
            first.recurrenceRule = .daily
            second.recurrenceRule = .daily
            first.recurrenceSeriesIDRaw = first.id.uuidString
            second.recurrenceSeriesIDRaw = first.id.uuidString
            first.recurrenceSpawnedTaskID = second.id
            context.insert(first)
            context.insert(second)
            try context.save()
            return (context, first, second)
        }

        for (scope, reachesSecond) in [(CadenceTaskRecurrenceEditScope.thisTask, false), (.thisAndFuture, true)] {
            let (context, first, second) = try series()
            let opened = CadenceScheduleDraft(editing: first)
            var draft = opened
            draft.seriesEndMode = .afterCount
            draft.seriesEndCount = 3
            #expect(draft.changesRecurrence(from: opened))

            let landed = CadenceTaskEditDraftCommit.save(
                draft, opened: opened, to: first, area: nil, project: nil,
                allTasks: [first, second], scope: scope, in: context, reconciler: .inert
            )
            #expect(landed)
            #expect(first.recurrenceEndCount == 3)
            #expect((second.recurrenceEndCount == 3) == reachesSecond, "scope \(scope) reached the wrong occurrences")
        }

        let (_, first, _) = try series()
        let opened = CadenceScheduleDraft(editing: first)
        var renamed = opened
        renamed.title = "Water the plants"
        #expect(!renamed.changesRecurrence(from: opened), "a rename asks the series-scope question")
        var ruled = opened
        ruled.repeatRule = .weekly
        #expect(ruled.changesRecurrence(from: opened))
    }

    /// Switching repeating off clears the bound with it, so it cannot re-arm later.
    @Test("Turning repeat off clears the end condition")
    func turningRepeatOffClearsTheEndCondition() throws {
        let (_, context) = try store()
        let task = AppTask(title: "Water plants")
        task.recurrenceRule = .daily
        task.recurrenceEndMode = .afterCount
        task.recurrenceEndCount = 5
        context.insert(task)
        try context.save()

        let opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.repeatRule = .none
        #expect(CadenceTaskEditDraftCommit.save(
            draft, opened: opened, to: task, area: nil, project: nil,
            allTasks: [task], scope: .thisTask, in: context, reconciler: .inert
        ))
        #expect(task.recurrenceRule == .none)
        #expect(task.recurrenceEndMode == .never)
        #expect(task.recurrenceEndCount == 0)
    }

    /// The estimate is its own figure: None and an off-grid length survive, and a drag on a
    /// creating block still moves it.
    @Test("The estimate keeps None and an off-grid length, and follows a drag")
    func theEstimateKeepsNoneAndOffGridAndFollowsADrag() {
        var draft = CadenceScheduleDraft(dateKey: "2026-10-16", startMin: 9 * 60, kind: .task)
        #expect(draft.estimateMinutes == CadenceScheduleDraft.defaultDurationMinutes)
        draft.setEstimate(0)
        #expect(draft.estimateMinutes == 0)
        #expect(draft.durationMinutes == CadenceScheduleDraft.minimumDurationMinutes, "the drawn block inverted")
        draft.setEstimate(20)
        #expect(draft.estimateMinutes == 20)
        draft.moveEndEdge(toMinute: 11 * 60)
        #expect(draft.estimateMinutes == 2 * 60, "a drag on the block left the estimate behind")
        draft.moveStartEdge(toMinute: 10 * 60)
        #expect(draft.estimateMinutes == 60)
    }

    /// Clearing the do date takes the time with it; adding a time to an undated task adopts today.
    @Test("A time needs a day, and a day cleared takes its time")
    func aTimeNeedsADay() {
        var draft = CadenceScheduleDraft(dateKey: "2026-10-16", startMin: 9 * 60, kind: .task)
        draft.clearDoDate()
        #expect(draft.startDateKey.isEmpty)
        #expect(draft.scheduledStartMin == -1)
        #expect(draft.doTimeLabel == "Add time")

        draft.addTime(today: "2026-10-15")
        #expect(draft.startDateKey == "2026-10-15")
        #expect(draft.scheduledStartMin == 9 * 60)

        // A time on a draft whose day is gone is still no slot.
        draft.startDateKey = ""
        #expect(draft.scheduledStartMin == -1)
    }

    /// Colour is spent on what is wrong, and a finished task has nothing wrong with its dates.
    @Test("Past dates are flagged only on an open task")
    func pastDatesAreFlaggedOnlyOnAnOpenTask() {
        var draft = CadenceScheduleDraft(dateKey: "2020-01-01", startMin: 9 * 60, kind: .task)
        draft.dueDateKey = "2020-01-02"
        #expect(draft.isDoDateOverdue)
        #expect(draft.isDueDateOverdue)
        draft.isDone = true
        #expect(!draft.isDoDateOverdue)
        #expect(!draft.isDueDateOverdue)
        draft.isDone = false
        draft.startDateKey = "2999-01-01"
        draft.dueDateKey = "2999-01-02"
        #expect(!draft.isDoDateOverdue)
        #expect(!draft.isDueDateOverdue)
    }
}

/// The source half: the iOS task editor is a host of the shared panel and keeps what the panel
/// cannot hold ([[T-3171]]).
@Suite("Task editor hosts the shared panel")
@MainActor
struct CadenceTaskEditorPanelAdoptionTests {

    private func code(_ relativePath: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(relativePath)
        #expect(raw.count > 1_000, "\(relativePath) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "\(relativePath): the comment stripper removed nothing")
        #expect(stripped.count == raw.count)
        return stripped
    }

    @Test("The task editor draws the panel and none of the old form")
    func theTaskEditorDrawsThePanel() throws {
        let sheet = try code("Cadence/iOS/iOSTaskDetailSheet.swift")
        #expect(CadenceSourceScan.matchCount(#"CadenceSchedulePanel\("#, in: sheet) == 1)
        #expect(sheet.contains("CadenceScheduleDraft(editing: task)"))
        // The series is drawn by the host, with its end condition — not twice.
        #expect(sheet.contains("offersTaskRepeat: false"))
        // The old write-through form: a token picker, two date flags, and a flush on Done.
        for retired in [
            "containerSelection", "hasScheduledDate", "hasDueDate", "applyDates", "finishEditingAndDismiss",
            "iOSTaskPlacementBreadcrumb(", "iOSTaskEditorTitleCard(", "try? modelContext.save()",
            "onChange(of: task.title)",
        ] {
            #expect(!sheet.contains(retired), "the task editor still carries \(retired)")
        }
        // The note is drafted with everything else.
        #expect(sheet.contains("notesText: $draft.notes"))
        // An unsaved draft is not discarded by a swipe.
        #expect(sheet.contains(".interactiveDismissDisabled(draft != openedDraft)"))
    }

    /// Save is one commit, asks the series question only where there is a series, and closes only
    /// below its refusal.
    @Test("Save asks the series question only for a series and closes below its refusal")
    func saveAsksTheSeriesQuestionOnlyForASeries() throws {
        let sheet = try code("Cadence/iOS/iOSTaskDetailSheet.swift")
        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: sheet))
        #expect(save.contains("if draft.changesRecurrence(from: openedDraft) && task.isRecurrenceSeriesMember {"))
        #expect(save.contains("isAskingRecurrenceScope = true"))
        let apply = try #require(CadenceSourceScan.functionBody(named: "applySave", in: sheet))
        #expect(apply.contains("guard CadenceTaskEditDraftCommit.save("))
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: apply) == 1)
        #expect(sheet.contains("failureNotice: saveFailureNotice"), "the refusal is set and never drawn")
        // Both scopes are offered, and each reaches the one save.
        #expect(CadenceSourceScan.matchCount(#"applySave\(scope: \.thisAndFuture\)"#, in: sheet) == 1)
    }

    /// Delete is the panel's, and still stops at its confirmation.
    @Test("Delete is the panel's and keeps its confirmation")
    func deleteIsThePanelsAndKeepsItsConfirmation() throws {
        let sheet = try code("Cadence/iOS/iOSTaskDetailSheet.swift")
        let actions = try #require(CadenceSourceScan.declarationBody("private var panelActions: CadenceSchedulePanelActions", in: sheet))
        #expect(actions.contains("showDeleteConfirmation = true"), "Delete skipped its confirmation")
        #expect(!sheet.contains("ToolbarItem("), "a second Delete or Done is still in the toolbar")
        #expect(sheet.contains("Button(\"Delete\", role: .destructive, action: deleteTask)"))
    }

    /// The panel's task rows carry what the inspector had: a Clear on an existing task's do date,
    /// an Estimate row of the task's own, and the overdue tints.
    @Test("The panel's task rows carry the inspector's behaviours")
    func thePanelsTaskRowsCarryTheInspectorsBehaviours() throws {
        let panel = try code("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        let schedule = try #require(CadenceSourceScan.declarationBody("private var taskSchedule: some View", in: panel))
        #expect(schedule.contains("showsClear: draft.subject.isEditing && !draft.startDateKey.isEmpty"))
        #expect(schedule.contains("draft.isDoDateOverdue ? Theme.red : Theme.blue"))
        #expect(schedule.contains("draft.isDueDateOverdue ? Theme.red : Theme.amber"))
        #expect(CadenceSourceScan.matchCount(#"if offersTaskRepeat \{"#, in: schedule) == 1)
        let list = try #require(CadenceSourceScan.declarationBody("private var listAndSection: some View", in: panel))
        #expect(list.contains("EstimatePickerControl(value: estimateBinding)"))
        let estimate = try #require(CadenceSourceScan.declarationBody("private var estimateBinding: Binding<Int>", in: panel))
        #expect(estimate.contains("draft.setEstimate($0)"))
        let title = try #require(CadenceSourceScan.declarationBody("private var priorityControl: some View", in: panel))
        #expect(title.contains("TaskPriorityMarkControl(priority: draft.priority)"))
    }
}

/// The draft the calendar's quick-create sheet opens with — [[T-3171]]'s third adoption slice,
/// `iOSCalendarQuickCreateSheet` hosting the shared panel in create mode. Behavioural: the sheet is
/// iOS-only, so what a tapped slot hands the panel was moved into the shared draft to be run here.
@Suite("Quick-create sheet's opening draft")
@MainActor
struct CadenceScheduleDraftQuickCreateTests {

    @Test("A task opened on a slot is timed there, half an hour long")
    func aTaskOpenedOnASlotIsTimedThere() {
        let draft = CadenceScheduleDraft.quickCreate(dateKey: "2026-10-16", startMin: 10 * 60, opensTimed: true, kind: .task)
        #expect(draft.subject == .creating)
        #expect(draft.kind == .task)
        #expect(draft.startDateKey == "2026-10-16")
        #expect(draft.endDateKey == draft.startDateKey)
        #expect(!draft.isAllDay)
        #expect(draft.scheduledStartMin == 10 * 60)
        #expect(draft.endMin - draft.startMin == CadenceScheduleDraft.quickCreateLengthMinutes)
        #expect(draft.estimateMinutes == CadenceScheduleDraft.quickCreateLengthMinutes)
        // Not the press-and-hold block's hour: the sheet always opened at the half hour.
        #expect(CadenceScheduleDraft.quickCreateLengthMinutes == 30)
        #expect(CadenceScheduleDraft.quickCreateLengthMinutes < CadenceScheduleDraft.defaultDurationMinutes)
        #expect(draft.listToken == CadenceTaskComposerSupport.token(for: .inbox))
    }

    /// "Set time" started off when the sheet was opened from no slot, so the task it makes is on
    /// the day and at no particular time — and it still carries the estimate it was given.
    @Test("A task opened from no slot is untimed and keeps its estimate")
    func aTaskOpenedFromNoSlotIsUntimed() {
        let draft = CadenceScheduleDraft.quickCreate(dateKey: "2026-10-16", startMin: 9 * 60, opensTimed: false, kind: .task)
        #expect(draft.isAllDay)
        #expect(draft.scheduledStartMin == -1)
        #expect(draft.startDateKey == "2026-10-16")
        #expect(draft.estimateMinutes == 30)
        #expect(draft.doTimeLabel == "Add time")
    }

    /// "All day" started off whatever opened the sheet, so an event from no slot is a timed one.
    @Test("An event opens timed whether or not a slot opened the sheet")
    func anEventOpensTimedEitherWay() throws {
        let calendar = try CadenceTestTimeZones.calendar("UTC")
        for opensTimed in [true, false] {
            let draft = CadenceScheduleDraft.quickCreate(dateKey: "2026-10-16", startMin: 14 * 60, opensTimed: opensTimed, kind: .event)
            #expect(!draft.isAllDay, "opensTimed \(opensTimed)")
            let range = try #require(draft.eventDateRange(calendar: calendar))
            #expect(range.end.timeIntervalSince(range.start) == 30 * 60)
        }
    }

    /// The drawn block is clipped at midnight; the estimate is not read off it.
    @Test("A slot near midnight keeps the half-hour estimate the block cannot draw")
    func aSlotNearMidnightKeepsItsEstimate() {
        let lateSlot = 23 * 60 + 45
        let draft = CadenceScheduleDraft.quickCreate(dateKey: "2026-10-16", startMin: lateSlot, opensTimed: true, kind: .task)
        #expect(draft.startMin == lateSlot)
        #expect(draft.endMin == 24 * 60)
        #expect(draft.endMin - draft.startMin < draft.estimateMinutes, "non-vacuity: the block really is clipped")
        #expect(draft.estimateMinutes == 30)
    }
}

/// The source half of the same slice: the quick-create sheet is a host of the shared panel, keeps
/// what the panel deliberately does not do, and writes through the one create helper it shares
/// with the iPad timeline ([[T-3171]]).
@Suite("Quick-create sheet hosts the shared panel")
@MainActor
struct CadenceQuickCreatePanelAdoptionTests {

    private func code(_ relativePath: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(relativePath)
        #expect(raw.count > 1_000, "\(relativePath) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "\(relativePath): the comment stripper removed nothing")
        #expect(stripped.count == raw.count)
        return stripped
    }

    @Test("The sheet draws the panel and none of the old form")
    func theSheetDrawsThePanel() throws {
        let sheet = try code("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        #expect(CadenceSourceScan.matchCount(#"CadenceSchedulePanel\("#, in: sheet) == 1)
        #expect(sheet.contains("State(initialValue: .quickCreate("))
        #expect(sheet.contains("canCommit: canCreate"))
        // Creating: nothing to delete, so the control is absent rather than disabled.
        #expect(sheet.contains("delete: nil"))
        for retired in [
            "iOSSegmentedChoice(", "EstimatePickerControl(", "CadenceStartTimeFieldRow(", "iOSContainerChoicePopover(",
            "iOSChoicePopoverList(", "Toggle(", "actionErrorNotice", "cyclePriority", "enum iOSCalendarQuickCreateKind",
        ] {
            #expect(!sheet.contains(retired), "the quick-create sheet still carries \(retired)")
        }
    }

    /// Add greys out as the old arrow did: a title for either kind, and for an event a calendar
    /// that can be written to — a gate the draft cannot see, so the host hands it in.
    @Test("An event needs a writable calendar before Add is offered")
    func anEventNeedsAWritableCalendar() throws {
        let sheet = try code("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        let gate = try #require(CadenceSourceScan.declarationBody("private var canCreate: Bool", in: sheet))
        #expect(CadenceSourceScan.matchCount(#"case \.event:[^\n]*\n[^\n]*&& selectedWritableCalendar != nil"#, in: gate) == 1)
        let calendar = try #require(CadenceSourceScan.declarationBody("private var selectedWritableCalendar: EKCalendar?", in: sheet))
        #expect(calendar.contains("calendarManager.writableCalendars.first { $0.calendarIdentifier == draft.calendarID }"))
    }

    /// The panel names a missing calendar and never raises a system prompt; this sheet, a surface
    /// opened on purpose, still offers the request — in its own slot, directly under that row.
    @Test("Allow Calendar Access stays in the host, under the panel's calendar row")
    func calendarAccessStaysInTheHost() throws {
        let sheet = try code("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        let request = try #require(CadenceSourceScan.declarationBody("private var calendarAccessRequest: some View", in: sheet))
        #expect(request.contains("if draft.kind == .event && !calendarManager.isAuthorized {"))
        #expect(request.contains(#"title: "Allow Calendar Access""#))
        #expect(CadenceSourceScan.matchCount(#"calendarManager\.requestAccess\(\)"#, in: request) == 1)
        #expect(CadenceSourceScan.matchCount(#"calendarManager\.requestAccess\(\)"#, in: sheet) == 1)
        #expect(request.contains("normalizeCalendarSelection()"), "access granted, and no calendar chosen")
        // Drawn in the panel's host slot, first, ahead of the notes.
        #expect(CadenceSourceScan.matchCount(#"\) \{\s*calendarAccessRequest\s*notesSection\s*\}"#, in: sheet) == 1)
        #expect(sheet.contains("calendarUnavailableNotice: calendarUnavailableNotice"))
        let panel = try code("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        #expect(!panel.contains("requestAccess"), "the shared panel raises a permission prompt")
    }

    /// Each kind keeps its own time choice across a switch, as the two separate toggles did.
    @Test("A kind switch restores the time choice of the kind it lands on")
    func aKindSwitchRestoresTheLandingKindsTimeChoice() throws {
        let sheet = try code("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        #expect(CadenceSourceScan.matchCount(
            #"\.onChange\(of: draft\.kind\) \{ oldKind, newKind in\s*rememberTimeChoice\(of: oldKind\)\s*draft\.isAllDay = !isTimed\(newKind\)"#,
            in: sheet
        ) == 1)
        let timed = try #require(CadenceSourceScan.functionBody(named: "isTimed", in: sheet))
        #expect(timed.contains("case .task: return hasTime"))
        #expect(timed.contains("case .event: return !eventIsAllDay"))
        let remember = try #require(CadenceSourceScan.functionBody(named: "rememberTimeChoice", in: sheet))
        #expect(remember.contains("case .task: hasTime = !draft.isAllDay"))
        #expect(remember.contains("case .event: eventIsAllDay = draft.isAllDay"))
    }

    /// A list change re-resolves the section, and the Inbox offers none — its Section row greys
    /// out, as the sheet's always did.
    @Test("A list change re-resolves the section and the Inbox offers none")
    func aListChangeReResolvesTheSection() throws {
        let sheet = try code("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        #expect(sheet.contains(".onChange(of: draft.listToken) { _, _ in normalizeSection() }"))
        let creation = try code("Cadence/iOS/iOSTimelineDraftCreate.swift")
        let sections = try #require(CadenceSourceScan.functionBody(named: "sectionChoices", in: creation))
        #expect(sections.contains("guard area != nil || project != nil else { return [] }"))
    }

    /// One create implementation behind both create-mode hosts.
    @Test("Both create hosts write through the one shared helper")
    func bothCreateHostsWriteThroughOneHelper() throws {
        let creation = try code("Cadence/iOS/iOSTimelineDraftCreate.swift")
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskMutationSupport\.insertScheduledTask\("#, in: creation) == 1)
        #expect(CadenceSourceScan.matchCount(#"calendarManager\.createEvent\("#, in: creation) == 1)
        for path in ["Cadence/iOS/iOSCalendarQuickCreateSheet.swift", "Cadence/iOS/iOSTimelineDraftCreate.swift"] {
            let host = try code(path)
            #expect(CadenceSourceScan.matchCount(#"iOSScheduleDraftCreation\.createTask\("#, in: host) == 1, "\(path)")
            #expect(CadenceSourceScan.matchCount(#"iOSScheduleDraftCreation\.createEvent\("#, in: host) == 1, "\(path)")
        }
        let sheet = try code("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        #expect(!sheet.contains("insertScheduledTask("))
        #expect(!sheet.contains("HabitNotificationReconcileSupport"), "the sheet reconciles a second time")
    }
}
