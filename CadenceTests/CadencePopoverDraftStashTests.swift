// macOS only: the two popovers and `CadencePopoverDrafts` are macOS code.
#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import Cadence

/// [[T-19029]]: a click outside the Mac task inspector or event editor keeps the draft for the
/// next open of the same item; Save, Cancel and Escape keep nothing; an untouched popover keeps
/// nothing. The rules are `CadencePopoverDrafts`' three stashes, tested here as values on the very
/// stashes the popovers use (each test on its own fresh id), and the wiring by source shape.
@MainActor
struct CadencePopoverDraftStashTests {

    private static func taskOpened() -> CadenceScheduleDraft {
        CadenceScheduleDraft(dateKey: "2026-11-21", startMin: 9 * 60, kind: .task)
    }

    private static func eventOpened() -> CadenceScheduleDraft {
        let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
        return CadenceScheduleDraft(
            editingEventID: "event-1",
            title: "Standup",
            notes: "as opened",
            location: "",
            calendarID: "cal-work",
            start: start,
            end: start.addingTimeInterval(30 * 60),
            isAllDay: false
        )
    }

    // MARK: - Task schedule

    @Test func aRetitledTaskDraftIsKeptByAClickAwayAndRestoredOnTheSameTask() {
        let stash = CadencePopoverDrafts.taskSchedule
        let id = UUID().uuidString
        let opened = Self.taskOpened()
        var renamed = opened
        renamed.title = "Renamed"

        stash.close(id: id, draft: renamed, opened: opened)

        #expect(stash.restored(for: id, opened: opened)?.title == "Renamed", "a click-away dropped the typed title")
        #expect(stash.restored(for: UUID().uuidString, opened: opened) == nil, "another task opened with this one's draft")
        // A peek: the host's init runs on every render, so reading twice still finds it.
        #expect(stash.restored(for: id, opened: opened)?.title == "Renamed")
        stash.markCancel(id: id)
        stash.close(id: id, draft: opened, opened: opened)
    }

    @Test func anUntouchedTaskInspectorKeepsNothing() {
        let stash = CadencePopoverDrafts.taskSchedule
        let id = UUID().uuidString
        let opened = Self.taskOpened()
        let before = stash.keptCount

        stash.close(id: id, draft: opened, opened: opened)

        #expect(stash.restored(for: id, opened: opened) == nil)
        #expect(stash.keptCount == before)

        // Completion is a mirror, not an edit ([[T-5359]]): completing from the inspector keeps nothing.
        var completed = opened
        completed.isSettled = true
        stash.close(id: id, draft: completed, opened: opened)
        #expect(stash.restored(for: id, opened: opened) == nil, "a completed task kept a draft over nothing")
    }

    @Test func saveCancelAndEscapeOnATaskInspectorKeepNeitherDraftNorSubtaskEntry() {
        let task = UUID()
        let key = CadencePopoverDrafts.taskKey(task)
        let opened = Self.taskOpened()
        var renamed = opened
        renamed.title = "Renamed"

        CadencePopoverDrafts.markTaskCancel(task)
        CadencePopoverDrafts.taskSchedule.close(id: key, draft: renamed, opened: opened)
        CadencePopoverDrafts.taskSubtaskEntry.close(id: key, draft: "Call Sam", opened: "")

        #expect(CadencePopoverDrafts.taskSchedule.restored(for: key, opened: opened) == nil, "a cancelled inspector kept its draft")
        #expect(CadencePopoverDrafts.taskSubtaskEntry.restored(for: key, opened: "") == nil, "a cancelled inspector kept its subtask entry")

        // The mark is spent by that close: the next click-away keeps again.
        CadencePopoverDrafts.taskSchedule.close(id: key, draft: renamed, opened: opened)
        #expect(CadencePopoverDrafts.taskSchedule.restored(for: key, opened: opened)?.title == "Renamed")

        // A cancel over an already-kept draft clears it.
        CadencePopoverDrafts.markTaskCancel(task)
        CadencePopoverDrafts.taskSchedule.close(id: key, draft: renamed, opened: opened)
        #expect(CadencePopoverDrafts.taskSchedule.restored(for: key, opened: opened) == nil)
    }

    @Test func anUnmarkedCancelKeepsAgain() {
        let task = UUID()
        let key = CadencePopoverDrafts.taskKey(task)
        let opened = Self.taskOpened()
        var renamed = opened
        renamed.title = "Renamed"

        // An Escape a child panel consumed, then a click outside.
        CadencePopoverDrafts.markTaskCancel(task)
        CadencePopoverDrafts.markTaskCancel(task, false)
        CadencePopoverDrafts.taskSchedule.close(id: key, draft: renamed, opened: opened)

        #expect(CadencePopoverDrafts.taskSchedule.restored(for: key, opened: opened)?.title == "Renamed")
        CadencePopoverDrafts.markTaskCancel(task)
        CadencePopoverDrafts.taskSchedule.close(id: key, draft: renamed, opened: opened)
    }

    @Test func aReopenedDraftTypedBackToTheTaskClearsWhatWasKept() {
        let stash = CadencePopoverDrafts.taskSchedule
        let id = UUID().uuidString
        let opened = Self.taskOpened()
        var renamed = opened
        renamed.title = "Renamed"

        stash.close(id: id, draft: renamed, opened: opened)
        stash.close(id: id, draft: opened, opened: opened)

        #expect(stash.restored(for: id, opened: opened) == nil, "a reverted draft still came back")
    }

    @Test func aKeptTaskDraftIsDroppedOnceTheTaskMovedUnderIt() {
        let stash = CadencePopoverDrafts.taskSchedule
        let id = UUID().uuidString
        let opened = Self.taskOpened()
        var renamed = opened
        renamed.title = "Renamed"
        stash.close(id: id, draft: renamed, opened: opened)

        var moved = opened
        moved.title = "Retitled in another window"
        #expect(stash.restored(for: id, opened: moved) == nil, "a stale draft was painted over a newer stored title")

        // Completed meanwhile: the mirror is no move, and the restored draft carries the live one.
        var completed = opened
        completed.isSettled = true
        let restored = stash.restored(for: id, opened: completed)
        #expect(restored?.title == "Renamed")
        #expect(restored?.isSettled == true, "the restored draft kept a stale completion mirror")
        stash.markCancel(id: id)
        stash.close(id: id, draft: opened, opened: opened)
    }

    // MARK: - Subtask entry

    @Test func anUnsentSubtaskEntryIsKeptAndWhitespaceIsNot() {
        let stash = CadencePopoverDrafts.taskSubtaskEntry
        let id = UUID().uuidString

        stash.close(id: id, draft: " \n", opened: "")
        #expect(stash.restored(for: id, opened: "") == nil, "whitespace was kept as work")

        stash.close(id: id, draft: "Call Sam", opened: "")
        #expect(stash.restored(for: id, opened: "") == "Call Sam", "a click-away dropped the unsent subtask")

        // Sent (Save submits it, `prepareToSave`): the emptied field clears it.
        stash.close(id: id, draft: "", opened: "")
        #expect(stash.restored(for: id, opened: "") == nil)
    }

    // MARK: - Event schedule

    @Test func aRetitledEventIsKeptAndNotesAloneAreNot() {
        let stash = CadencePopoverDrafts.eventSchedule
        let id = UUID().uuidString
        let opened = Self.eventOpened()

        var mirrored = opened
        mirrored.notes = "the note's mirror, reloaded from EKEvent.notes"
        stash.close(id: id, draft: mirrored, opened: opened)
        #expect(stash.restored(for: id, opened: opened) == nil, "a committed note was kept as an unsaved edit")

        var renamed = mirrored
        renamed.title = "Team standup"
        stash.close(id: id, draft: renamed, opened: opened)

        // The event's notes moved since (the Notes field mirrors as it is typed): still the same
        // event, and the restored draft takes the notes it has now.
        var reopened = opened
        reopened.notes = "typed after the title"
        let restored = stash.restored(for: id, opened: reopened)
        #expect(restored?.title == "Team standup", "a click-away dropped the event's typed title")
        #expect(restored?.notes == "typed after the title")
    }

    @Test func aKeptEventDraftIsDroppedOnceTheEventMoved() {
        let id = UUID().uuidString
        let opened = Self.eventOpened()
        var renamed = opened
        renamed.title = "Team standup"
        CadencePopoverDrafts.eventSchedule.close(id: id, draft: renamed, opened: opened)
        var moved = opened
        moved.startMin += 60

        // A Save that landed, or Apple Calendar moving it: the event no longer opens as it did.
        #expect(CadencePopoverDrafts.eventSchedule.restored(for: id, opened: moved) == nil)
        #expect(CadencePopoverDrafts.eventSchedule.restored(for: id, opened: opened)?.title == "Team standup")

        CadencePopoverDrafts.eventSchedule.markCancel(id: id)
        CadencePopoverDrafts.eventSchedule.close(id: id, draft: renamed, opened: opened)
        #expect(CadencePopoverDrafts.eventSchedule.restored(for: id, opened: opened) == nil, "Cancel kept the event's draft")
    }

    // MARK: - Escape

    @Test func onlyAnEscapeKeyDownMarksTheCloseACancel() {
        #expect(CadencePopoverEscapeIntent.marksCancel(type: .keyDown, keyCode: 53))
        #expect(!CadencePopoverEscapeIntent.marksCancel(type: .keyDown, keyCode: 36), "Return read as Escape")
        #expect(!CadencePopoverEscapeIntent.marksCancel(type: .leftMouseDown, keyCode: nil), "a click outside read as Escape")
        #expect(!CadencePopoverEscapeIntent.marksCancel(type: .rightMouseDown, keyCode: nil))
        #expect(CadencePopoverEscapeIntent.watchedEvents.contains(.leftMouseDown))
        #expect(CadencePopoverEscapeIntent.watchedEvents.contains(.keyDown))
    }

    // MARK: - Wiring

    private func code(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 1_000, "\(path) read back too small to be the real file")
        return CadenceSourceScan.strippingComments(raw)
    }

    @Test func theTwoMacPopoversRestoreKeepAndClearThroughTheStash() throws {
        let editor = try code("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        #expect(editor.contains("CadencePopoverDrafts.taskSchedule.restored("))
        #expect(editor.contains("CadencePopoverDrafts.taskSchedule.close("))
        #expect(CadenceSourceScan.matchCount(#"CadencePopoverDrafts\.markTaskCancel\(task\.id\)"#, in: editor) == 2, "Save and Cancel")

        let inspector = try code("Cadence/macOS/Views/SchedulePanelComponents.swift")
        #expect(inspector.contains("CadencePopoverDrafts.taskSubtaskEntry.restored("))
        #expect(inspector.contains("CadencePopoverDrafts.taskSubtaskEntry.close("))
        #expect(inspector.contains(".cadencePopoverEscapeWatch { CadencePopoverDrafts.markTaskCancel(task.id, $0) }"))

        let event = try code("Cadence/macOS/Views/TimelineEventBlockSupportViews.swift")
        #expect(event.contains("CadencePopoverDrafts.eventSchedule.restored(for: item.id"))
        #expect(event.contains("CadencePopoverDrafts.eventSchedule.close(id: item.id"))
        #expect(event.contains(".cadencePopoverEscapeWatch { CadencePopoverDrafts.eventSchedule.markCancel(id: item.id, $0) }"))
        #expect(event.contains("if saveRequested && actionFailureNotice == nil"))
    }
}
#endif
