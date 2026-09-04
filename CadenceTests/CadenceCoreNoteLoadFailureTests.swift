import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-849: a note panel that fails to load one note must still show the rest, and must say
/// so.** `CadenceCoreNoteSupport.loadOrCreateCoreNotes(in:dayKey:)` used to build its
/// `CadenceCoreNoteState` from three `try?`s straight into the struct's stored properties, so a
/// thrown fetch and "this note does not exist yet" produced the identical `nil` — except the
/// second case cannot happen: `NoteMigrationService.dailyNote`/`weeklyNote`/`permanentNote` all
/// create the note on a miss. `NotePanel` read that `nil` as "still loading" and drew a
/// `ProgressView()` that a failure would never resolve, with nothing on screen ever saying a
/// fetch had gone wrong.
///
/// These tests exercise the hoisted overload, `loadOrCreateCoreNotes(today:week:notepad:)`,
/// the same seam `HabitNotificationReconcileSupport.reconcileInput` uses for the same reason: an
/// in-memory `ModelContext` will not reliably fail a fetch or a save on demand, so the failure
/// path is only reachable by injecting the `nil` a throw would have produced.
struct CadenceCoreNoteLoadFailureTests {
    @Test func allThreeNotesLoadingSucceedsWithNoFailedTabs() {
        let today = Note(kind: .daily, title: "Today")
        let week = Note(kind: .weekly, title: "Week")
        let notepad = Note(kind: .permanent, title: "Notepad")

        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: today, week: week, notepad: notepad)

        #expect(state.today?.id == today.id)
        #expect(state.week?.id == week.id)
        #expect(state.notepad?.id == notepad.id)
        #expect(state.failedTabs.isEmpty)
    }

    /// **One failed fetch does not stop the other two from loading.** The week and notepad
    /// fetches are independent of the daily one, so a `nil` daily note must not erase them.
    @Test func aFailedFetchIsNamedAndDoesNotStopTheOtherTwoFromLoading() {
        let week = Note(kind: .weekly, title: "Week")
        let notepad = Note(kind: .permanent, title: "Notepad")

        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: nil, week: week, notepad: notepad)

        #expect(state.today == nil)
        #expect(state.failedTabs == [.today])
        #expect(state.week?.id == week.id)
        #expect(state.notepad?.id == notepad.id)
    }

    @Test func eachOfTheThreeTabsCanFailIndependently() {
        let today = Note(kind: .daily, title: "Today")

        let weekFailed = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: today, week: nil, notepad: today)
        #expect(weekFailed.failedTabs == [.week])

        let notepadFailed = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: today, week: today, notepad: nil)
        #expect(notepadFailed.failedTabs == [.notepad])
    }

    @Test func allThreeFailingNamesAllThree() {
        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: nil, week: nil, notepad: nil)
        #expect(state.failedTabs == Set(CadenceCoreNoteTab.allCases))
        #expect(state.today == nil)
        #expect(state.week == nil)
        #expect(state.notepad == nil)
    }

    /// **A genuinely fresh state is not "everything failed."** `CadenceCoreNoteState()`'s default
    /// `failedTabs` is empty, not every tab — the difference between "nobody has asked yet" and
    /// "every fetch threw" matters the same way it does in `CadenceNoteDeletionSummary`.
    @Test func aFreshStateHasNoFailedTabsByDefault() {
        #expect(CadenceCoreNoteState().failedTabs.isEmpty)
    }

    // MARK: - NotePanel actually reads and shows failedTabs (source scan; macOS-only view)

    /// `Cadence/macOS/` is invisible to this test target the way `Cadence/iOS/` is, so this reads
    /// the source rather than compiling against the view — the same arrangement
    /// `NoteEditorPerformanceRegressionTests.coreNotePanelDoesNotPersistEveryEditorChange` uses on
    /// this exact file.
    @Test func notePanelDistinguishesAFailedTabFromAStillLoadingOne() throws {
        let raw = try sourceFile("Cadence/macOS/Views/NotePanel.swift")
        let source = try strippingComments(raw)
        #expect(source != raw)

        // The flag exists, is populated from the snapshot, and is read per-tab rather than
        // gating the whole panel on one shared success bit.
        #expect(source.contains("failedNoteTabs"))
        #expect(source.contains("failedNoteTabs = snapshot.failedTabs"))
        #expect(source.contains("failedNoteTabs.contains(tab)"))

        // Every one of the three tabs routes through the same per-tab helper — a bare
        // `ProgressView()` for one of them, with no failure check, is exactly the T-849 shape.
        // 4, not 3: the helper's own declaration matches the needle too.
        #expect(CadenceSourceScan.matchCount("noteOrPlaceholder\\(", in: source) == 4)
        #expect(source.contains("noteOrPlaceholder(todayNote, tab: .today)"))
        #expect(source.contains("noteOrPlaceholder(weekNote, tab: .week)"))
        #expect(source.contains("noteOrPlaceholder(permNote, tab: .notepad)"))

        // The failure state draws something other than a spinner, and offers a way to retry
        // rather than stranding the tab.
        #expect(source.contains("func noteLoadFailureView"))
        #expect(source.contains("CadenceInlineFailureNotice"))
        #expect(source.contains("Button(\"Try Again\") { loadOrCreate() }"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Same crude, deliberately conservative implementation
/// `CadenceNoteDeletionSurfaceTests` uses on this exact file.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
