import Foundation
import Testing
@testable import Cadence

/// **[[T-11196]]** -- two Search behaviours that differed between the platforms with no hardware
/// constraint to name ([[T-8201]]): (2) iOS Search took no Up/Down/Return from an iPad's hardware
/// keyboard while Cmd+K did, and (1) picking an event in Cmd+K only moved the calendar to its day
/// while iOS opens the event's editor.
///
/// The shared keyboard walk is pinned by value and runs on both destinations. The iOS view lives
/// inside `#if os(iOS)` and this target runs on macOS, so its wiring is pinned by source. The Mac
/// editor request is a macOS type, so that half is inside `#if os(macOS)` ([[T-12200]]).
struct CadenceSearchKeyboardHighlightTests {
    private let ids = ["task-a", "task-b", "continuation-Tasks", "note-c"]

    @Test func downAndUpStepOneRowAndClampAtBothEnds() {
        #expect(CadenceSearchKeyboardHighlight.moved(.down, currentID: "task-a", ids: ids) == "task-b")
        #expect(CadenceSearchKeyboardHighlight.moved(.down, currentID: "task-b", ids: ids) == "continuation-Tasks")
        #expect(CadenceSearchKeyboardHighlight.moved(.up, currentID: "task-b", ids: ids) == "task-a")
        #expect(CadenceSearchKeyboardHighlight.moved(.up, currentID: "task-a", ids: ids) == "task-a")
        #expect(CadenceSearchKeyboardHighlight.moved(.down, currentID: "note-c", ids: ids) == "note-c")
        #expect(CadenceSearchKeyboardHighlight.moved(.down, currentID: "task-a", ids: []) == nil)
    }

    @Test func aSyncKeepsALiveHighlightAndOtherwiseFallsToTheFirstRow() {
        #expect(CadenceSearchKeyboardHighlight.synced(current: "note-c", ids: ids) == "note-c")
        #expect(CadenceSearchKeyboardHighlight.synced(current: "gone", ids: ids) == "task-a")
        #expect(CadenceSearchKeyboardHighlight.synced(current: nil, ids: ids) == "task-a")
        #expect(CadenceSearchKeyboardHighlight.synced(current: "task-a", ids: []) == nil)
    }

    /// iOS starts with no highlight, so the first arrow lands ON the first row rather than walking
    /// past it, as the Mac's walk from an absent id would.
    @Test func theFirstArrowOnIOSLandsOnTheFirstRowAndLaterOnesStep() {
        #expect(CadenceSearchKeyboardHighlight.engagedMove(.down, currentID: nil, ids: ids) == "task-a")
        #expect(CadenceSearchKeyboardHighlight.engagedMove(.up, currentID: nil, ids: ids) == "task-a")
        #expect(CadenceSearchKeyboardHighlight.engagedMove(.down, currentID: "gone", ids: ids) == "task-a")
        #expect(CadenceSearchKeyboardHighlight.engagedMove(.down, currentID: "task-a", ids: ids) == "task-b")
        #expect(CadenceSearchKeyboardHighlight.engagedMove(.down, currentID: nil, ids: []) == nil)
    }

    @Test func returnWithNothingHighlightedActsOnTheFirstRow() {
        #expect(CadenceSearchKeyboardHighlight.submitTarget(highlightedID: nil, ids: ids) == "task-a")
        #expect(CadenceSearchKeyboardHighlight.submitTarget(highlightedID: "note-c", ids: ids) == "note-c")
        #expect(CadenceSearchKeyboardHighlight.submitTarget(highlightedID: nil, ids: []) == nil)
    }

    @Test func aContinuationIDIsNamespacedSoItCannotCollideWithAResult() {
        #expect(CadenceSearchKeyboardHighlight.continuationID(forSection: "Tasks") == "continuation-Tasks")
    }
}

/// The iOS wiring, by source: the rows draw the shared highlight, the keys go through the shared
/// walk, and the touch keyboard's Search key opens nothing unless the arrows highlighted a row.
struct CadenceIOSSearchKeyboardWiringTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    @Test func iOSSearchTakesUpDownAndReturnThroughTheSharedWalk() throws {
        let view = try Self.code("Cadence/iOS/iOSSearchView.swift")
        #expect(view.contains(".onKeyPress(keys: [.upArrow, .downArrow, .return])"))
        let handler = try #require(CadenceSourceScan.functionBody(named: "handleKeyboardPress", in: view))
        #expect(handler.contains("CadenceSearchKeyboardHighlight.engagedMove("))
        let submit = try #require(CadenceSourceScan.functionBody(named: "submitHighlightedResult", in: view))
        #expect(submit.contains("CadenceSearchKeyboardHighlight.submitTarget("))
        #expect(submit.contains("open(result.destination)"))
        #expect(view.contains("iOSSearchResultRow(result: result, isHighlighted: highlightedResultID == result.id)"))
    }

    @Test func theSearchFieldSubmitOpensARowOnlyOnceTheArrowsHighlightedOne() throws {
        let view = try Self.code("Cadence/iOS/iOSSearchView.swift")
        let submit = try #require(CadenceSourceScan.declarationBody(".onSubmit(of: .search)", in: view))
        #expect(submit.contains("guard highlightedResultID != nil else { return }"))
    }

    @Test func bothPlatformsDrawTheOneHighlightPlate() throws {
        let rows = try Self.code("Cadence/iOS/iOSSearchSupportViews.swift")
        #expect(rows.contains(".cadenceSearchHighlightPlate(isHighlighted: isHighlighted, tint: tint)"))
        let mac = try Self.code("Cadence/macOS/Views/GlobalSearchSupportViews.swift")
        #expect(mac.components(separatedBy: ".cadenceSearchHighlightPlate(").count - 1 == 2)
    }
}

#if os(macOS)
/// **(1)** Cmd+K picking an event jumps to its day AND asks the block to open its editor.
@MainActor
struct CadenceCmdKEventEditorRequestTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func pickingAnEventJumpsToItsDayAndAsksForItsEditor() {
        let manager = CalendarNavigationManager()
        var selected: [SidebarItem] = []
        RootCommandActionSupport.handleEventSelection(
            "event-1",
            startDate: now,
            calendarNavigationManager: manager,
            setSelection: { selected.append($0) }
        )

        #expect(selected == [.calendar])
        #expect(manager.request?.dateKey == DateFormatters.dateKey(from: now))
        #expect(manager.eventEditorRequest?.eventID == "event-1")
    }

    @Test func anEventWithNoStartSelectsTheCalendarAndAsksForNothing() {
        let manager = CalendarNavigationManager()
        var selected: [SidebarItem] = []
        RootCommandActionSupport.handleEventSelection(
            "event-1",
            startDate: nil,
            calendarNavigationManager: manager,
            setSelection: { selected.append($0) }
        )

        #expect(selected == [.calendar])
        #expect(manager.request == nil)
        #expect(manager.eventEditorRequest == nil)
    }

    @Test func onlyTheNamedEventTakesTheRequestAndOnlyOnce() {
        let manager = CalendarNavigationManager()
        manager.open(date: now, editingEventID: "event-1", now: now)

        #expect(!manager.takeEventEditorRequest(for: "event-2", now: now))
        #expect(manager.takeEventEditorRequest(for: "event-1", now: now))
        // A second segment of a multi-day event shares the id and must not open a second popover.
        #expect(!manager.takeEventEditorRequest(for: "event-1", now: now))
        #expect(manager.eventEditorRequest == nil)
    }

    @Test func aRequestNobodyTookLapsesRatherThanOpeningOnALaterVisit() {
        let manager = CalendarNavigationManager()
        manager.open(date: now, editingEventID: "event-1", now: now)
        let later = now.addingTimeInterval(CalendarNavigationManager.editorRequestLifetime + 1)

        #expect(!manager.takeEventEditorRequest(for: "event-1", now: later))
        #expect(manager.eventEditorRequest == nil)
    }

    @Test func aPlainJumpRetiresAPendingEditorRequest() {
        let manager = CalendarNavigationManager()
        manager.open(date: now, editingEventID: "event-1", now: now)
        manager.open(dateKey: "2026-08-28", now: now)

        #expect(manager.eventEditorRequest == nil)
        #expect(!manager.takeEventEditorRequest(for: "event-1", now: now))
    }

    /// The page clears `request` the moment it has scrolled, before the blocks are drawn, so the
    /// editor request has to outlive that.
    @Test func clearingTheJumpLeavesTheEditorRequestForTheBlock() {
        let manager = CalendarNavigationManager()
        manager.open(date: now, editingEventID: "event-1", now: now)
        manager.clear()

        #expect(manager.request == nil)
        #expect(manager.takeEventEditorRequest(for: "event-1", now: now))
    }

    /// Wiring, by source: Cmd+K's event arm routes through the request, only the Calendar page
    /// lets blocks answer it, and both the timed block and the all-day chip do.
    @Test func theCalendarPageAloneLetsItsBlocksAndChipsOpenTheRequestedEditor() throws {
        func code(_ path: String) throws -> String {
            CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        }
        let action = try code("Cadence/macOS/Views/macOSRootCommandActionSupport.swift")
        let handle = try #require(CadenceSourceScan.functionBody(named: "handleSearchSelection", in: action))
        #expect(handle.contains("handleEventSelection("))

        let page = try code("Cadence/macOS/Views/CalendarPageView.swift")
        #expect(page.contains(".environment(\\.honoursCalendarEventEditorRequests, true)"))

        let block = try code("Cadence/macOS/Views/TimelineEventBlock.swift")
        #expect(block.contains(".honoursCalendarEventEditorRequest(eventID: item.id)"))
        let chip = try code("Cadence/macOS/Views/CalendarEventChipPopoverSupport.swift")
        #expect(chip.contains(".honoursCalendarEventEditorRequest(eventID: item().id)"))
    }
}
#endif
