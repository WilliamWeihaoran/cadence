// [[T-5280]]: `TimelineEventBlockEditGate` is a macOS view type, so the iOS test target cannot
// compile this file.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// [[T-5240]], [[T-5241]], [[T-5242]]: what a macOS calendar event offers to change, from where.
///
/// The rules are `TimelineEventBlockEditGate`'s, tested as values. The wiring — that the block and
/// the two chips actually consult them, and that the chips open the editor — is a view-construction
/// fact no unit test can drive, so it is pinned by source scan, read through `codeOnly` so prose
/// naming a call cannot stand in for it.
@Suite("macOS calendar event chips and block edit gates")
@MainActor
struct CadenceCalendarEventChipEditingTests {
    // MARK: - T-5242: a handle only on an edge the event has

    @Test("A single-day event draws both handles")
    func aSingleDayEventDrawsBothHandles() {
        #expect(TimelineEventBlockEditGate.drawsResizeHandle(edge: .start, isEditable: true, isFirstSegment: true, isLastSegment: true))
        #expect(TimelineEventBlockEditGate.drawsResizeHandle(edge: .end, isEditable: true, isFirstSegment: true, isLastSegment: true))
    }

    @Test("A multi-day segment draws no handle on a midnight clip")
    func aMidnightClipDrawsNoHandle() {
        // First day's piece: its own start, clipped at midnight below.
        #expect(TimelineEventBlockEditGate.drawsResizeHandle(edge: .start, isEditable: true, isFirstSegment: true, isLastSegment: false))
        #expect(!TimelineEventBlockEditGate.drawsResizeHandle(edge: .end, isEditable: true, isFirstSegment: true, isLastSegment: false))
        // Last day's piece: clipped at midnight above, its own end below.
        #expect(!TimelineEventBlockEditGate.drawsResizeHandle(edge: .start, isEditable: true, isFirstSegment: false, isLastSegment: true))
        #expect(TimelineEventBlockEditGate.drawsResizeHandle(edge: .end, isEditable: true, isFirstSegment: false, isLastSegment: true))
        // A middle day is clipped on both sides.
        #expect(!TimelineEventBlockEditGate.drawsResizeHandle(edge: .start, isEditable: true, isFirstSegment: false, isLastSegment: false))
        #expect(!TimelineEventBlockEditGate.drawsResizeHandle(edge: .end, isEditable: true, isFirstSegment: false, isLastSegment: false))
    }

    // MARK: - T-5241: a read-only event offers nothing

    @Test("A read-only event draws no handle and takes no move")
    func aReadOnlyEventOffersNoGesture() {
        #expect(!TimelineEventBlockEditGate.drawsResizeHandle(edge: .start, isEditable: false, isFirstSegment: true, isLastSegment: true))
        #expect(!TimelineEventBlockEditGate.drawsResizeHandle(edge: .end, isEditable: false, isFirstSegment: true, isLastSegment: true))
        #expect(!TimelineEventBlockEditGate.allowsMove(isEditable: false))
        #expect(TimelineEventBlockEditGate.allowsMove(isEditable: true))
    }

    // MARK: - T-5241 (b): a write that changes nothing puts the block back

    private let current = (start: Date(timeIntervalSinceReferenceDate: 800_000_000),
                           end: Date(timeIntervalSinceReferenceDate: 800_003_600))
    private var moved: (start: Date, end: Date) {
        (current.start.addingTimeInterval(3_600), current.end.addingTimeInterval(3_600))
    }

    @Test("A refused write clears the block's live drag state")
    func aRefusedWriteClearsLiveState() {
        for failure: CalendarWriteFailure in [.notAuthorized, .noWritableCalendar, .invalidRange] {
            #expect(
                TimelineEventBlockEditGate.clearsLiveState(after: failure, requested: moved, current: current),
                "a \(failure) refusal left the block at the dropped time"
            )
        }
    }

    @Test("A committed change keeps live state until the store refresh replaces it")
    func aCommittedChangeKeepsLiveState() {
        #expect(!TimelineEventBlockEditGate.clearsLiveState(after: nil, requested: moved, current: current))
        // Only the end moved: still a change.
        #expect(!TimelineEventBlockEditGate.clearsLiveState(
            after: nil,
            requested: (current.start, current.end.addingTimeInterval(900)),
            current: current
        ))
        // Only the start moved: still a change.
        #expect(!TimelineEventBlockEditGate.clearsLiveState(
            after: nil,
            requested: (current.start.addingTimeInterval(-900), current.end),
            current: current
        ))
    }

    @Test("A write of the range the event already has clears live state")
    func aNoOpWriteClearsLiveState() {
        #expect(TimelineEventBlockEditGate.clearsLiveState(after: nil, requested: current, current: current))
    }

    // MARK: - Wiring

    private static let block = "Cadence/macOS/Views/TimelineEventBlock.swift"
    private static let chips = "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"
    private static let host = "Cadence/macOS/Views/CalendarEventChipPopoverSupport.swift"

    private static func code(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw, "\(path): expected comments and literals to have been blanked")
        return code
    }

    @Test("The timeline block consults the gate for its gestures, handles and write answer")
    func theBlockConsultsTheGate() throws {
        let code = try Self.code(Self.block)
        #expect(code.contains("CalendarEventEditPopover.isEditable(item.ekEvent)"))
        #expect(
            CadenceSourceScan.matchCount(#"including: TimelineEventBlockEditGate\.allowsMove\(isEditable: isEditable\) \? \.all : \.subviews"#, in: code) == 1,
            "the move gesture is not gated on the event being editable"
        )
        #expect(
            CadenceSourceScan.matchCount(#"TimelineEventBlockEditGate\.drawsResizeHandle\(\s*edge: edge,\s*isEditable: isEditable,\s*isFirstSegment: item\.isFirstSegment,\s*isLastSegment: item\.isLastSegment"#, in: code) == 1,
            "the resize handles are drawn without asking which edges the segment has"
        )
        #expect(
            CadenceSourceScan.matchCount(#"let failure = calendarManager\.updateEvent\(\s*item\.ekEvent,\s*title: item\.title"#, in: code) == 1,
            "the drag/resize write discards its answer again"
        )
        #expect(
            CadenceSourceScan.matchCount(#"if TimelineEventBlockEditGate\.clearsLiveState\(\s*after: failure,[^}]*\{\s*cancelPendingEventMutation\(\)"#, in: code) == 1,
            "a refused or no-op write does not put the block back"
        )
    }

    @Test("Both event chips open the event editor and only an editable all-day chip drags")
    func bothChipsOpenTheEditor() throws {
        let code = try Self.code(Self.chips)
        let month = try #require(CadenceSourceScan.declarationBody("struct MonthEventChip: View", in: code))
        let allDay = try #require(CadenceSourceScan.declarationBody("struct AllDayEventChip: View", in: code))
        #expect(month.contains(".calendarEventChipEditor(isPresented: $showEditor) { event }"), "a Month event chip opens nothing")
        #expect(
            allDay.contains(".calendarEventChipEditor(isPresented: $showEditor) { CalendarEventItem(event: event) }"),
            "an all-day chip opens nothing"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\.calendarEventDraggable\(\s*CalendarEventDragPayload\.string\(for: event\),\s*isEditable: CalendarEventEditPopover\.isEditable\(event\)"#, in: allDay) == 1,
            "the all-day chip's drag is not gated on the event being editable"
        )
        #expect(!allDay.contains(".draggable("), "the all-day chip drags unconditionally again")
        // The drop that converts all-day to timed refuses a read-only event too: the column calls
        // the shared rule, whose refusal `MacTodayAllDayDropTests` pins by behaviour ([[T-8091]]).
        #expect(code.contains("CalendarAllDayEventDropSupport.convert("))
        // Non-vacuity: the task chips beside it still drag, so the ban above can see `.draggable(`.
        let task = try #require(CadenceSourceScan.functionBody(named: "calendarTaskChipInteractions", in: code))
        #expect(task.contains(".draggable("))
    }

    // MARK: - T-5351: the Month task chip does what the all-day lane's does

    @Test("Month and all-day task chips share one click, inspector and drag")
    func bothTaskChipsOpenTheInspectorAndDrag() throws {
        let code = try Self.code(Self.chips)
        for declaration in ["struct MonthTaskChip: View", "struct AllDayTaskChip: View"] {
            let chip = try #require(CadenceSourceScan.declarationBody(declaration, in: code))
            #expect(chip.contains("@State private var showInspector = false"), "\(declaration) holds no inspector state")
            #expect(
                CadenceSourceScan.matchCount(#"\.calendarTaskChipInteractions\(task: task, showInspector: \$showInspector\)"#, in: chip) == 1,
                "\(declaration) does not wear the shared task-chip interactions"
            )
            // One definition, not two copies drifting apart.
            #expect(!chip.contains(".onTapGesture"), "\(declaration) grew its own click again")
            #expect(!chip.contains(".draggable("), "\(declaration) grew its own drag again")
        }
        let shared = try #require(CadenceSourceScan.functionBody(named: "calendarTaskChipInteractions", in: code))
        #expect(shared.contains(".onTapGesture { showInspector.wrappedValue = true }"), "a click opens nothing")
        #expect(
            CadenceSourceScan.matchCount(#"RightClickActionTrigger \{\s*showInspector\.wrappedValue = true\s*\}"#, in: shared) == 1,
            "a right-click opens nothing"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\.popover\(isPresented: showInspector, arrowEdge: \.bottom\) \{\s*TaskDetailPopover\(task: task\)"#, in: shared) == 1,
            "the click does not open the task's inspector"
        )
        #expect(shared.contains(".draggable(task.id.uuidString)"), "the chip does not drag as its task")
    }

    @Test("The chip editor host carries the Board card's write wiring")
    func theChipHostReportsItsWrites() throws {
        let code = try Self.code(Self.host)
        #expect(CadenceSourceScan.matchCount(#"CalendarEventEditPopover\("#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"calendarManager\.report\("#, in: code) == 2, "a Save outcome is discarded")
        #expect(code.contains("CadenceCalendarEventEditingSupport.saveOutcome(for: failure)"))
        #expect(CadenceSourceScan.matchCount(#"\) \{ isPresented = false \}"#, in: code) == 1, "Save closes outside a committed outcome")
        #expect(CadenceSourceScan.matchCount(#"deleteConfirmationManager\.presentRefusable\("#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"deleteEvent\(item\.ekEvent, scope: scope\)"#, in: code) == 1)
        #expect(code.contains("if outcome == .deleted { isPresented = false }"))
        #expect(code.contains("actionFailureNotice: $actionFailureNotice"))
        #expect(
            CadenceSourceScan.matchCount(#"\.onTapGesture \{ isPresented\.wrappedValue = true \}\s*\.popover\(isPresented: isPresented"#, in: code) == 1,
            "the chip modifier does not open its popover on click"
        )
        #expect(
            CadenceSourceScan.matchCount(#"if isEditable \{\s*draggable\(payload\)\s*\} else \{\s*self\s*\}"#, in: code) == 1,
            "the gated draggable drags regardless"
        )
    }
}
#endif
