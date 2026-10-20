// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and
// this suite reaches macOS-only app types that do not exist there. The gate preserves exactly the
// coverage this file had before; narrowing it so any cross-platform half runs on iOS too is
// follow-up, not part of making the target iOS-capable.
#if os(macOS)
import EventKit
import Foundation
import Testing
@testable import Cadence

/// **The macOS event editor hosts the shared schedule panel** ([[T-3171]], the fourth adoption
/// slice): `CalendarEventEditPopover`, opened from a timeline block and from a Calendar Board card,
/// draws `CadenceSchedulePanel` in edit mode and its own form is gone.
///
/// Behavioural where the claim is a value — what a Save asks the host to write, which day a
/// segment's popover opens on, what the Calendar row is called, where a roller's minute lands —
/// because those are the halves that could be wrong without anything on screen saying so. The
/// rest is a source scan, as the iOS slices' adoption suites are: the popover is a SwiftUI body.
@Suite("macOS event editor hosts the shared panel")
@MainActor
struct CadenceMacEventEditorPanelAdoptionTests {

    // MARK: Fixtures

    private var calendar: Calendar { Calendar.current }

    private func instant(_ key: String, _ minute: Int) throws -> Date {
        let day = try #require(DateFormatters.date(from: key, in: calendar))
        return try #require(CadenceCalendarEventTiming.startDate(day: day, startMin: minute, calendar: calendar))
    }

    private func event(start: Date, end: Date, notes: String? = "Agenda", location: String? = "Room 4") -> EKEvent {
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Standup"
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.location = location
        return event
    }

    private func code(_ relativePath: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(relativePath)
        #expect(raw.count > 1_000, "\(relativePath) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "\(relativePath): the comment stripper removed nothing")
        #expect(stripped.count == raw.count)
        return stripped
    }

    private let popoverPath = "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift"
    private let hostPaths = [
        "Cadence/macOS/Views/TimelineEventBlock.swift",
        "Cadence/macOS/Views/CalendarBoardItemSupportViews.swift",
    ]

    // MARK: What a Save writes

    /// An untouched Save writes the event's **own** instants back — seconds and all, which no
    /// wall-clock minute can spell — and none of the fields the old popover never wrote.
    @Test("An untouched Save writes the event's own instants and nothing else new")
    func anUntouchedSaveWritesTheEventsOwnInstants() throws {
        // 30 seconds past the minute: a re-derivation from the draft's minutes cannot reach it.
        let start = try instant("2026-06-15", 10 * 60).addingTimeInterval(30)
        let end = try instant("2026-06-15", 11 * 60).addingTimeInterval(30)
        let item = CalendarEventItem(event: event(start: start, end: end))
        let opened = CalendarEventEditPopover.openingDraft(for: item)
        var draft = opened
        draft.title = "Renamed"

        let request = CalendarEventEditRequest(
            draft: draft, opened: opened, originalStart: start, originalEnd: end
        )
        let range = try #require(request.range)
        #expect(range.start == start)
        #expect(range.end == end)
        #expect(request.title == "Renamed")
        #expect(request.notes == nil, "an untouched Save re-wrote the notes it opened with")
        #expect(request.location == nil, "an untouched Save re-wrote the location it opened with")
        #expect(request.isAllDay == nil, "an untouched Save re-wrote the all-day flag")

        // The contrast: the draft's own reading of the same schedule is NOT those instants, so
        // the equality above is the untouched branch and not a coincidence.
        let derived = try #require(draft.eventDateRange(calendar: calendar))
        #expect(derived.start != start)
    }

    /// A moved schedule is read on the wall clock, and each field the user changed is written.
    @Test("A changed field is written, and a moved schedule is read on the wall clock")
    func aChangedFieldIsWritten() throws {
        let start = try instant("2026-06-15", 10 * 60)
        let end = try instant("2026-06-15", 11 * 60)
        let item = CalendarEventItem(event: event(start: start, end: end))
        let opened = CalendarEventEditPopover.openingDraft(for: item)

        var draft = opened
        draft.notes = "New agenda"
        draft.location = ""
        draft.moveStart(toMinute: 14 * 60)
        let moved = CalendarEventEditRequest(draft: draft, opened: opened, originalStart: start, originalEnd: end)
        #expect(moved.notes == "New agenda")
        #expect(moved.location == "", "clearing the location wrote nothing, so it could never be cleared")
        let range = try #require(moved.range)
        #expect(range.start == (try instant("2026-06-15", 14 * 60)))
        #expect(range.end == (try instant("2026-06-15", 15 * 60)))

        var allDay = opened
        allDay.isAllDay = true
        let whole = CalendarEventEditRequest(draft: allDay, opened: opened, originalStart: start, originalEnd: end)
        #expect(whole.isAllDay == true)
        let day = try #require(whole.range)
        #expect(day.start == calendar.startOfDay(for: start))
        #expect(calendar.dateComponents([.day], from: day.start, to: day.end).day == 1)
    }

    /// The popover opens on the **whole** event whichever day's segment was clicked — the old
    /// Start and End fields edited the clicked day alone, and a middle day's could edit nothing.
    @Test("A segment's popover opens on the whole multi-day event")
    func aSegmentOpensOnTheWholeEvent() throws {
        let start = try instant("2026-06-15", 22 * 60)
        let end = try instant("2026-06-16", 2 * 60)
        let ek = event(start: start, end: end)
        let secondDay = try #require(DateFormatters.date(from: "2026-06-16", in: calendar))
        let segment = try #require(CalendarEventItem(event: ek, clippedTo: secondDay, calendar: calendar))
        #expect(segment.dateKey == "2026-06-16")
        #expect(segment.startMin == 0, "the fixture is not the second day's segment")

        let draft = CalendarEventEditPopover.openingDraft(for: segment)
        #expect(draft.subject.isEditing)
        #expect(draft.kind == .event)
        #expect(draft.startDateKey == "2026-06-15")
        #expect(draft.startMin == 22 * 60)
        #expect(draft.endDateKey == "2026-06-16")
        #expect(draft.endMin == 2 * 60)
        #expect(draft.notes == "Agenda")
        #expect(draft.location == "Room 4")
    }

    // MARK: The Calendar row

    /// The row names the calendar the link names: the offer as the link words it, and — when the
    /// event's own calendar is not in the offer — one extra row with the link's word for it rather
    /// than the panel's "Choose Calendar".
    @Test("The Calendar row always names the event's calendar")
    func theCalendarRowNamesTheEventsCalendar() throws {
        let store = EKEventStore()
        let work = EKCalendar(for: .event, eventStore: store)
        work.title = "Work"
        let workLink = CadenceCalendarLink(
            linkedCalendarID: work.calendarIdentifier,
            allCalendars: [work],
            visibleCalendars: [work],
            exclusion: .readOnly
        )
        let offered = CalendarEventEditPopover.calendarChoices(
            calendars: [work], link: workLink, selectedID: work.calendarIdentifier
        )
        #expect(offered.map(\.id) == [work.calendarIdentifier])
        #expect(offered.map(\.name) == ["Work"])

        let orphanLink = CadenceCalendarLink(
            linkedCalendarID: "gone",
            allCalendars: [work],
            visibleCalendars: [work],
            exclusion: .readOnly
        )
        let orphaned = CalendarEventEditPopover.calendarChoices(calendars: [work], link: orphanLink, selectedID: "gone")
        #expect(orphaned.count == 2)
        #expect(orphaned.last?.id == "gone")
        #expect(orphaned.last?.name == orphanLink.rowState.valueText)
    }

    /// An event with no calendar is read-only here: EventKit has nowhere to write it.
    @Test("An event with no calendar opens read-only")
    func aCalendarlessEventIsReadOnly() throws {
        let ek = event(start: try instant("2026-06-15", 9 * 60), end: try instant("2026-06-15", 10 * 60))
        #expect(ek.calendar == nil)
        #expect(CalendarEventEditPopover.isEditable(ek) == false)
    }

    // MARK: The rollers' grid

    /// The panel's rollers step in five minutes; the draft used to snap what they picked to the
    /// 15-minute touch grid, so a picked 4:05 was written as 4:00. A dragged edge keeps its grid.
    @Test("A roller's off-grid minute survives, and a dragged edge keeps the touch grid")
    func aRollerMinuteSurvives() throws {
        let item = CalendarEventItem(event: event(
            start: try instant("2026-06-15", 9 * 60),
            end: try instant("2026-06-15", 10 * 60)
        ))
        var draft = CalendarEventEditPopover.openingDraft(for: item)
        draft.moveStart(toMinute: 16 * 60 + 5)
        #expect(draft.startMin == 16 * 60 + 5)
        draft.setEndMinute(17 * 60 + 35)
        #expect(draft.endMin == 17 * 60 + 35)
        #expect(CadenceScheduleDraft.rollerGridMinutes == CadenceTimeRollerModel.minuteStep)

        var dragged = draft
        dragged.moveEndEdge(toMinute: 17 * 60 + 35)
        #expect(dragged.endMin % CadenceScheduleSupport.touchTimeGridMinutes == 0)
    }

    // MARK: Source shape

    /// The popover draws the panel, and none of its old form.
    @Test("The popover draws the panel and none of the old form")
    func thePopoverDrawsThePanel() throws {
        let popover = try code(popoverPath)
        #expect(popover.contains("struct CalendarEventEditPopover: View"), "the editor moved")
        #expect(CadenceSourceScan.matchCount(#"CadenceSchedulePanel\("#, in: popover) == 1)
        for retired in [
            "timeFieldRow", "parseTime", "startText", "endText", "infoCard",
            "CadenceCalendarPickerButton(", "durationMinutes:", "TextField(\"Event title\"",
        ] {
            #expect(!popover.contains(retired), "the popover still draws \(retired)")
        }
        // An existing series is not re-ruled from here, so the panel offers no Repeat.
        #expect(popover.contains("offersEventRepeat: false"))
        #expect(popover.contains("readOnlyNotice: isEditable"))
        #expect(popover.contains("canCommit: canSave"))
        // The Apple Calendar notes field is the panel's own spelling, and inert on a read-only
        // event while the Cadence note card beside it is not.
        #expect(CadenceSourceScan.matchCount(#"CadenceSchedulePanelNotesRow\(notes: \$draft\.notes\)\s*\.disabled\(!isEditable\)"#, in: popover) == 1)
    }

    /// Delete only on an event that can be written, and both Save and Delete still stop at the
    /// scope question on a recurring one.
    @Test("Delete is offered only on a writable event, and a series asks its scope")
    func deleteOnlyOnAWritableEvent() throws {
        let popover = try code(popoverPath)
        let actions = try #require(CadenceSourceScan.declarationBody("private var panelActions: CadenceSchedulePanelActions", in: popover))
        #expect(actions.contains("if isEditable {"))
        #expect(actions.contains("actions.delete = {"))
        #expect(actions.contains("requestAction(.delete)"))
        let request = try #require(CadenceSourceScan.functionBody(named: "requestAction", in: popover))
        #expect(request.contains("if item.isRecurringSeriesMember {"))
        #expect(request.contains("pendingAction = action"))
        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: popover))
        #expect(save.contains("requestAction(.save)"), "Save skipped the scope question")
    }

    /// Both hosts write what the request carries — the whole event's range, and the three fields
    /// the panel added — and neither re-derives a segment's range any more.
    @Test("Both hosts write the panel's request")
    func bothHostsWriteTheRequest() throws {
        for path in hostPaths {
            let host = try code(path)
            #expect(host.contains("onSave: { request, scope in"), "\(path)")
            #expect(host.contains("guard let range = request.range else {"), "\(path)")
            for field in ["title: request.title", "calendarID: request.calendarID", "notes: request.notes",
                          "isAllDay: request.isAllDay", "location: request.location"] {
                #expect(host.contains(field), "\(path) drops \(field)")
            }
            #expect(!host.contains("eventDateRangeForEditedSegment(startMin: startMin, durationMinutes: duration)"),
                    "\(path) still edits a segment's range")
        }
    }

    /// The macOS manager writes the all-day flag before the dates (EventKit reads an all-day
    /// event's dates as whole days), and leaves both new fields alone when it is handed `nil`.
    @Test("The macOS manager writes all-day before the dates, and nil leaves a field alone")
    func theManagerWritesAllDayFirst() throws {
        let manager = try code("Cadence/macOS/Services/CalendarManager.swift")
        let start = try #require(manager.range(of: "startDate: Date,\n        endDate: Date,\n        calendarID: String? = nil,\n        notes: String? = nil,\n        scope: CalendarRecurrenceEditScope = .thisOccurrence,"))
        let body = String(manager[start.upperBound...].prefix(2_000))
        let allDay = try #require(body.range(of: "if let isAllDay {\n            event.isAllDay = isAllDay\n        }"))
        let location = try #require(body.range(of: "if let location {"))
        let dates = try #require(body.range(of: "event.startDate = startDate"))
        #expect(allDay.upperBound <= dates.lowerBound, "the all-day flag is set after the dates")
        #expect(location.upperBound <= dates.lowerBound)
        #expect(body.contains("isAllDay: Bool? = nil"))
        #expect(body.contains("location: String? = nil"))
    }
}

#endif
