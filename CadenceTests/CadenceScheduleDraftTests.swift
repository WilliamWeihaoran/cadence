import Foundation
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
        #expect(panel.contains("if let delete = actions.delete"))
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
