import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Two visible defects in the iOS event editor, found by a read-from-source sweep of the iOS
/// calendar sheets (agent `ioscalsheet0108`).
///
/// - [[T-8571]]: the sheet minted the event's Cadence note under `draft.title` -- the title field as
///   the user was retyping it -- while its own lookup and macOS's popover use the event's saved
///   title. A note made after a rename-then-Cancel kept the cancelled name, and the title fallback
///   (the path that exists because EventKit re-issues identifiers) could miss the note the lookup
///   had found and mint a second one beside it.
/// - [[T-8572]]: typing notes made the sheet refuse every swipe-down. The note is committed as it is
///   typed, but its mirror into Apple Calendar is a store change, and [[T-5171]]'s reload then
///   copied the new `EKEvent.notes` into `draft.notes` -- which no field draws and Save never reads
///   -- so the guard's `draft != openedDraft` read an unsaved edit that did not exist.
///
/// `Cadence/iOS/` is `#if os(iOS)` and invisible to the macOS test target, so the sheet's call
/// sites are pinned by source; the rules they call are exercised directly.
@MainActor
struct CadenceiOSEventEditSheetSweepTests {
    private static let sheetPath = "Cadence/iOS/iOSCalendarEventEditSheet.swift"

    private func code(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 1_000, "\(path) read back too small to be the real file")
        return CadenceSourceScan.strippingComments(raw)
    }

    // MARK: - T-8571

    /// The consequence the fix removes, on the shared lookup both platforms call: an existing note
    /// whose identifier no longer matches is found by the event's saved title and missed by a
    /// retyped one, which then inserts a duplicate.
    @Test func aRetypedTitleMissesTheEventsExistingNoteAndMintsASecond() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let existing = Note(kind: .meeting, title: "Standup", content: "# Standup\n\nagenda")
        existing.calendarEventID = "stale-identifier"
        existing.calendarID = "cal-work"
        existing.eventDateKey = "2026-10-30"
        existing.eventStartMin = 9 * 60
        existing.eventEndMin = 9 * 60 + 15
        context.insert(existing)
        try context.save()

        func resolve(title: String) -> (note: Note?, inserted: Int) {
            var inserted = 0
            let note = CadenceEventNoteSupport.noteForEditing(
                calendarEventID: "fresh-identifier",
                eventTitle: title,
                calendarID: "cal-work",
                eventDateKey: "2026-10-30",
                eventStartMin: 9 * 60,
                eventEndMin: 9 * 60 + 15,
                notes: [existing],
                insert: { _ in inserted += 1 }
            )
            return (note, inserted)
        }

        let saved = resolve(title: "Standup")
        #expect(saved.note === existing)
        #expect(saved.inserted == 0)
        // Reset what the adoption above rewrote, so the second call sees the same stale row.
        existing.calendarEventID = "stale-identifier"
        let retyped = resolve(title: "Team standup")
        #expect(retyped.note !== existing)
        #expect(retyped.inserted == 1, "a retyped title should miss the existing note -- the hazard this pins against")
    }

    @Test func theEventSheetNamesItsNoteFromTheSavedEventTitle() throws {
        let sheet = try code(Self.sheetPath)
        let title = try #require(CadenceSourceScan.declarationBody("private var savedEventTitle: String", in: sheet))
        #expect(title.contains("iOSCalendarEventSupport.title(for: event)"))

        let lookup = try #require(CadenceSourceScan.declarationBody("private var linkedEventNote: Note?", in: sheet))
        #expect(lookup.contains("eventTitle: savedEventTitle"))
        let ensure = try #require(CadenceSourceScan.functionBody(named: "ensureEventNote", in: sheet))
        #expect(ensure.contains("eventTitle: savedEventTitle"), "the note a keystroke mints is not named from the saved title")
        #expect(sheet.contains("iOSEventNoteEditorSheet(note: note, eventTitle: savedEventTitle, event: event)"))
        // Nothing on the note path reads the title field as it is being typed.
        #expect(CadenceSourceScan.matchCount(#"eventTitle:\s*draft\.title"#, in: sheet) == 0)
        // The regex can see the old spelling at all.
        #expect(CadenceSourceScan.matchCount(#"eventTitle:\s*draft\.title"#, in: "eventTitle: draft.title,") == 1)
    }

    // MARK: - T-8572

    private func openedDraft() -> CadenceScheduleDraft {
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

    @Test func theEventEditorsSwipeGuardIgnoresNotesTheNoteAlreadyCommitted() {
        let opened = openedDraft()
        #expect(!CadenceEventEditDismissGuard.blocksSwipe(opened: opened, current: opened, notesHavePendingEdit: false))

        var mirrored = opened
        mirrored.notes = "the note's mirror, reloaded from EKEvent.notes"
        #expect(
            !CadenceEventEditDismissGuard.blocksSwipe(opened: opened, current: mirrored, notesHavePendingEdit: false),
            "a reloaded EKEvent.notes is not an unsaved edit"
        )

        var renamed = opened
        renamed.title = "Team standup"
        #expect(CadenceEventEditDismissGuard.blocksSwipe(opened: opened, current: renamed, notesHavePendingEdit: false))

        var moved = mirrored
        moved.location = "Room 4"
        #expect(CadenceEventEditDismissGuard.blocksSwipe(opened: opened, current: moved, notesHavePendingEdit: false))

        // Words still in the well's debounce are not committed, so they hold the sheet ([[T-5170]]).
        #expect(CadenceEventEditDismissGuard.blocksSwipe(opened: opened, current: opened, notesHavePendingEdit: true))
    }

    @Test func theEventSheetsSwipeGuardReadsTheSharedRule() throws {
        let sheet = try code(Self.sheetPath)
        let wired = #"\.interactiveDismissDisabled\(\s*CadenceEventEditDismissGuard\.blocksSwipe\(\s*opened:\s*openedDraft,\s*current:\s*draft,\s*notesHavePendingEdit:\s*notesFlush\.hasPendingEdit\s*\)\s*\)"#
        #expect(CadenceSourceScan.matchCount(wired, in: sheet) == 1, "the event sheet's swipe guard is not the shared rule")
        #expect(CadenceSourceScan.matchCount(#"\.interactiveDismissDisabled\("#, in: sheet) == 1)
        #expect(!sheet.contains("interactiveDismissDisabled(draft != openedDraft"))
    }
}
