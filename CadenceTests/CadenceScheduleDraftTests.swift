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

    /// Lines of the column that are **code**, with its prose dropped.
    ///
    /// The two pins below are negative — they say a shape is *gone* — and the commentary that
    /// explains why it went quotes the retired line verbatim. A bare substring sweep would read
    /// that explanation as the thing it is warning about, so the comments come out first.
    private func timelineColumnCode() -> String {
        source("Cadence/iOS/iOSCalendarTimelineViews.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// **[[T-3240]].** The draft editor is a popover hanging off the block it edits, and that block
    /// carries a 32pt touch band at each end for adjusting it. A popover is modal by default, so
    /// its outside-tap dismissal took every touch on the pane: reaching for a handle produced no
    /// gesture at all and tore the block down instead — *"the entire event just disappears"*.
    ///
    /// Two things had to change together and both are pinned here, because a reader who undoes
    /// either one alone puts the bug back. The presentation stops swallowing the touch, and the
    /// teardown stops being reactive: `.onChange(of: isDraftEditorPresented)` cleared the draft
    /// from *anything* that toggled the presentation, the swallowed touch included. The clearing
    /// was right and the trigger was wrong, so it moved into an explicit `finishDraftCreation()`,
    /// which is `TimelineDayCanvas`'s rule on the Mac and the reason the Mac never had this.
    ///
    /// **Source text, and it pins the shape rather than the behaviour.** Neither a presentation's
    /// modality nor "a gesture reached its view" is a value any runtime check in this target can
    /// read, and the column is `#if os(iOS)`, so no macOS test run can even name its symbols. The
    /// behaviour was measured on `Cadence-iPadPro11` instead (T-3240's own line says how).
    @Test("The draft editor lets a touch reach the block it hangs off")
    func draftEditorLetsATouchReachTheBlockItHangsOff() {
        let timeline = timelineColumnCode()
        #expect(!timeline.isEmpty)
        #expect(timeline.contains(".presentationBackgroundInteraction(.enabled)"))
        #expect(timeline.contains("private func finishDraftCreation()"))
        #expect(
            !timeline.contains("onChange(of: isDraftEditorPresented)"),
            "the draft is cleared by a decision, not by whatever toggled the presentation"
        )
    }

    /// **The other half of [[T-3240]], and the one that is easiest to undo by tidying.**
    ///
    /// Both readers of the draft want a `CadenceScheduleDraft` rather than an optional one, so the
    /// binding's getter falls back to the value the layer was drawn from. That makes a write
    /// arriving from a view on its way down a *resurrection*: it puts the fallback back into the
    /// state the column just cleared. Measured on `Cadence-iPadPro11` with the guard removed —
    /// Cancel dismissed the editor and left the block on the canvas at its adjusted range, which
    /// is the leak the retired reactive teardown used to mop up by clearing a second time.
    @Test("A dismissing editor cannot resurrect a cleared draft")
    func aDismissingEditorCannotResurrectAClearedDraft() {
        let timeline = timelineColumnCode()
        #expect(timeline.contains("private func draftBinding(fallingBackTo current: CadenceScheduleDraft)"))
        // The guard, in the setter it belongs to. `guard draft != nil` on its own is not a pin:
        // the press gesture higher up the file carries the same line for its own reason, so the
        // sweep would pass on a `draftBinding` that had been tidied back to `set: { draft = $0 }`.
        // Matched on whitespace-collapsed text, so a reflow of the closure is not a failure.
        let collapsed = timeline.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(collapsed.contains("set: { updated in guard draft != nil else { return } draft = updated }"))
        #expect(
            !timeline.contains("set: { draft = $0 }"),
            "an unguarded setter over the draft is the resurrection path"
        )
    }

    /// **[[T-3246]], the measured residual [[T-3240]] left.** The handle receives its gesture now,
    /// but the same touch is still reported to the popover as an outside tap, so the editor went
    /// down while the drag ran and the owner had to tap the block again to get it back.
    ///
    /// **Two ways of holding it open are measured dead ends, and the second is the new one.**
    /// `interactiveDismissDisabled()` pushes the presentation out of its popover representation —
    /// the panel renders clipped off the pane with Cancel and Add unreachable. *Refusing the
    /// write* does nothing at all: with a `Binding` whose setter dropped **every** `false`, an
    /// outside tap on the canvas still took the popover down (`Cadence-iPadPro11`, 2026-10-19).
    /// SwiftUI dismisses first and tells the binding after. So the dismissal is left alone and the
    /// editor is put back when the adjustment ends.
    ///
    /// **The range comparison is the load-bearing half, not the re-presentation.** "A drag on the
    /// block ended" also describes a vertical scroll that started on the block, and raising a
    /// popover on that is a worse defect than the one being fixed. Only a touch that moved an edge
    /// gets the editor back. Both halves are pinned: a reader who keeps the gesture and drops the
    /// comparison has swapped one bug for another.
    ///
    /// Source text for the same reason the two pins above are: the column is `#if os(iOS)`, and no
    /// macOS test run can name its symbols. Measured on `Cadence-iPadPro11` — the editor returned
    /// by itself reading `Estimate 1h 30m`, the adjusted range.
    @Test("An adjusted draft gets its editor back without a second tap")
    func anAdjustedDraftGetsItsEditorBackWithoutASecondTap() {
        let timeline = timelineColumnCode()
        #expect(timeline.contains(".simultaneousGesture(draftAdjustmentObserver)"))
        #expect(timeline.contains("private var draftAdjustmentObserver: some Gesture"))
        #expect(timeline.contains("@State private var draftRangeUnderTouch: (start: Int, end: Int)?"))

        // The comparison, collapsed on whitespace so a reflow of the closure is not a failure.
        // Without it the observer re-raises the editor for any drag that ends on the block, a
        // vertical scroll of the timeline included.
        let collapsed = timeline.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(
            collapsed.contains(
                "guard adjusted.startMin != before.start || adjusted.endMin != before.end else { return }"
            ),
            "only a touch that moved an edge may put the editor back"
        )

        #expect(
            !timeline.contains("interactiveDismissDisabled"),
            "measured worse than the bug: the panel loses its popover representation"
        )
        #expect(
            timeline.contains(".popover(isPresented: $isDraftEditorPresented"),
            "the dismissal is left alone — a refusing binding was measured to do nothing"
        )
    }

    /// **[[T-3252]], the keyboard half.** The editor that `draftAdjustmentObserver` puts back after
    /// an edge drag is a fresh presentation, so the panel's `onAppear` ran again and focused the
    /// title — the keyboard came back on a gesture that was about the block's range, not its name.
    ///
    /// Behavioural on the decision: a new draft focuses its title, an existing record does not,
    /// and a draft whose editor is RETURNING does not either. Then the wiring, as source text for
    /// the reason the pins above are: the column is `#if os(iOS)`.
    @Test("A draft editor returning after an adjustment leaves the keyboard down")
    func aReturningDraftEditorLeavesTheKeyboardDown() {
        #expect(CadenceSchedulePanelTitleFocus.takesFocusOnAppear(.opened, isEditing: false))
        #expect(
            !CadenceSchedulePanelTitleFocus.takesFocusOnAppear(.returnedAfterAdjustment, isEditing: false),
            "the returning editor re-raises the keyboard"
        )
        #expect(!CadenceSchedulePanelTitleFocus.takesFocusOnAppear(.opened, isEditing: true))
        #expect(!CadenceSchedulePanelTitleFocus.takesFocusOnAppear(.returnedAfterAdjustment, isEditing: true))

        let panel = source("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        #expect(
            panel.contains("isTitleFocused = CadenceSchedulePanelTitleFocus.takesFocusOnAppear("),
            "the panel's onAppear no longer asks the policy"
        )
        let host = source("Cadence/iOS/iOSTimelineDraftCreate.swift")
        #expect(host.contains(".appearing(titleFocusAppearance)"), "the draft host drops the appearance")

        // Exactly one site says the editor is returning, and it is the adjustment observer, after
        // its range comparison — so a tap, a press and a fresh draft all still focus the title.
        let timeline = timelineColumnCode()
        #expect(
            CadenceSourceScan.matchCount(#"draftEditorAppearance = \.returnedAfterAdjustment"#, in: timeline) == 1,
            "the returning appearance is written from somewhere other than the adjustment observer"
        )
        let collapsed = timeline.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(
            collapsed.contains(
                "guard adjusted.startMin != before.start || adjusted.endMin != before.end else { return } "
                    + "draftEditorAppearance = .returnedAfterAdjustment isDraftEditorPresented = true"
            ),
            "the returning appearance is not the adjustment observer's"
        )
        #expect(timeline.contains("titleFocusAppearance: draftEditorAppearance"))
        // Every other presentation resets it, so a stale `.returnedAfterAdjustment` cannot leak
        // into the next draft's first presentation: the tap, the press, `beginDraft` and the
        // teardown.
        #expect(CadenceSourceScan.matchCount(#"draftEditorAppearance = \.opened"#, in: timeline) == 4)
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

    /// **The owner's report, as a test.** The calendar's drag-create and the `+` palette draw the
    /// same form and used to put two different surfaces round it — a floating card on one path, a
    /// navigation sheet with its own day header and markdown well on the other — which is what the
    /// owner read as "still the old creation sheet". One presentation now, applied in both hosts.
    @Test("Drag-create opens the same capture card the palette does")
    func dragCreateOpensTheCaptureCard() throws {
        let sheet = try code("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        let palette = try code("Cadence/iOS/iOSCreateTaskSheet.swift")
        for (name, host) in [("quick-create", sheet), ("palette", palette)] {
            #expect(CadenceSourceScan.matchCount(#"\.capturePresentation\("#, in: host) == 1, "\(name)")
            #expect(host.contains(".presentationBackground(.clear)"), "\(name)")
            #expect(host.contains(".presentationDetents([.height(cardHeight)])"), "\(name)")
        }
        for retired in ["NavigationStack {", "iOSEditorSection(", "iOSMarkdownEditingSurface(", "private var header"] {
            #expect(!sheet.contains(retired), "drag-create still carries \(retired)")
        }
        // The seed is what the two entry points differ by, and it survived the move.
        #expect(sheet.contains("startMin: Self.defaultStartMinute(dateKey: dateKey, startMinute: initialStartMinute)"))
        #expect(sheet.contains("opensTimed: opensTimed"))
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
        // Drawn in the panel's host slot. The markdown well that used to follow it there went with
        // the full-sheet chrome ([[T-3171]]'s seventh slice): the capture card draws the notes.
        #expect(CadenceSourceScan.matchCount(#"\) \{\s*calendarAccessRequest\s*\}"#, in: sheet) == 1)
        #expect(sheet.contains("calendarUnavailableNotice: calendarUnavailableNotice"))
        let panel = try code("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        #expect(!panel.contains("requestAccess"), "the shared panel raises a permission prompt")
    }

    /// Each kind keeps its own time choice across a switch, as the two separate toggles did —
    /// **and that is no longer this sheet's own pair of flags.** The seventh adoption slice moved
    /// the sheet onto the capture presentation, whose `CadenceCaptureKindMemory` remembers each
    /// kind's whole draft; the sheet's `hasTime` / `eventIsAllDay` pair would have fought it,
    /// reading the landing kind's `isAllDay` as the leaving kind's answer. Behavioural now, over
    /// the shared memory, which is the thing every capture host actually gets.
    @Test("A kind switch restores the time choice of the kind it lands on")
    func aKindSwitchRestoresTheLandingKindsTimeChoice() throws {
        var memory = CadenceCaptureKindMemory()
        // A task tapped from no slot: on the day, at no particular time.
        var draft = CadenceScheduleDraft.quickCreate(dateKey: "2026-10-16", startMin: 9 * 60, opensTimed: false, kind: .task)
        #expect(draft.isAllDay)

        memory.select(.event, draft: &draft)
        #expect(draft.kind == .event)
        #expect(!draft.isAllDay, "an event opens timed however the task was left")
        #expect(draft.startDateKey == "2026-10-16", "the slot's day survives the switch")

        memory.select(.task, draft: &draft)
        #expect(draft.kind == .task)
        #expect(draft.isAllDay, "the task's own untimed choice came back, not the event's")

        // And the other direction: a timed task stays timed across a round trip.
        var timed = CadenceScheduleDraft.quickCreate(dateKey: "2026-10-16", startMin: 10 * 60, opensTimed: true, kind: .task)
        var timedMemory = CadenceCaptureKindMemory()
        timedMemory.select(.event, draft: &timed)
        timedMemory.select(.task, draft: &timed)
        #expect(!timed.isAllDay)
        #expect(timed.startMin == 10 * 60)

        // The sheet no longer carries a second answer to the same question.
        let sheet = try code("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        for retired in ["func isTimed(", "func rememberTimeChoice(", "eventIsAllDay", "hasTime"] {
            #expect(!sheet.contains(retired), "the quick-create sheet still carries \(retired)")
        }
    }

    /// The capture card's own inventory, behavioural: the one row a host can genuinely not serve
    /// is left out rather than drawn dead. Drag-create offers no tag and no way to make one,
    /// because the create helper it shares with the iPad timeline writes none.
    @Test("A host with no tags and no way to add one is offered no tag field")
    func aHostWithNoTagsIsOfferedNoTagField() {
        let bare = CadenceScheduleCaptureOptions()
        let withChoices = CadenceScheduleCaptureOptions(
            tagChoices: [CadenceSchedulePanelChoice(id: "t1", name: "Deep work")]
        )
        let withCreate = CadenceScheduleCaptureOptions(createTag: { _ in nil })

        #expect(!CadenceCaptureFieldInventory.isOffered(.tags, by: bare))
        #expect(CadenceCaptureFieldInventory.isOffered(.tags, by: withChoices), "a tag to pick is enough")
        #expect(CadenceCaptureFieldInventory.isOffered(.tags, by: withCreate), "a way to make one is enough")

        // Tags are the ONLY row this answers for: an empty List picker is still a picker, and the
        // Calendar row says what is missing in words.
        for field in CadenceCaptureField.allCases where field != .tags {
            #expect(CadenceCaptureFieldInventory.isOffered(field, by: bare), "\(field.rawValue)")
        }

        // The inventory itself is untouched — the host's answer filters it, it does not rewrite it.
        let task = CadenceCaptureFieldInventory.fields(for: .task)
        #expect(task.contains(.tags))
        #expect(task.filter { CadenceCaptureFieldInventory.isOffered($0, by: bare) } == task.filter { $0 != .tags })
        // An event never had a tag row to lose.
        #expect(!CadenceCaptureFieldInventory.fields(for: .event).contains(.tags))
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
