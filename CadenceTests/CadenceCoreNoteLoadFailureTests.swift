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
/// These tests exercise the hoisted overload, `loadOrCreateCoreNotes(today:week:notepad:notepadReadFailed:)`,
/// the same seam `HabitNotificationReconcileSupport.scheduleReconcile` uses for the same reason: an
/// in-memory `ModelContext` will not reliably fail a fetch or a save on demand, so the failure
/// path is only reachable by injecting the `nil` a throw would have produced.
struct CadenceCoreNoteLoadFailureTests {
    @Test func allThreeNotesLoadingSucceedsWithNoFailedTabs() {
        let today = Note(kind: .daily, title: "Today")
        let week = Note(kind: .weekly, title: "Week")
        let notepad = Note(kind: .permanent, title: "Notepad")

        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: today, week: week, notepad: notepad, notepadReadFailed: false)

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

        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: nil, week: week, notepad: notepad, notepadReadFailed: false)

        #expect(state.today == nil)
        #expect(state.failedTabs == [.today])
        #expect(state.week?.id == week.id)
        #expect(state.notepad?.id == notepad.id)
    }

    @Test func eachOfTheThreeTabsCanFailIndependently() {
        let today = Note(kind: .daily, title: "Today")

        let weekFailed = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: today, week: nil, notepad: today, notepadReadFailed: false)
        #expect(weekFailed.failedTabs == [.week])

        let notepadFailed = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: today, week: today, notepad: nil, notepadReadFailed: true)
        #expect(notepadFailed.failedTabs == [.notepad])
    }

    @Test func allThreeFailingNamesAllThree() {
        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: nil, week: nil, notepad: nil, notepadReadFailed: true)
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

    // MARK: - T-17970: the notepad is read on load, never created

    /// A notepad with no note is "none", not "failed": it lands in `emptyTabs`, and nothing else.
    @Test func aNotepadThatReadsAsNoneIsEmptyNotFailed() {
        let today = Note(kind: .daily, title: "Today")
        let week = Note(kind: .weekly, title: "Week")

        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: today, week: week, notepad: nil, notepadReadFailed: false)

        #expect(state.notepad == nil)
        #expect(state.failedTabs.isEmpty)
        #expect(state.emptyTabs == [.notepad])
    }

    /// **The defect.** Deleting the last notepad note, then loading the page (an appear, a tab
    /// switch, a foregrounding), used to insert a blank "Notepad" through `permanentNote(in:)`.
    @MainActor @Test func loadingAfterTheLastNotepadNoteIsDeletedCreatesNone() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let only = try NoteMigrationService.createPermanentNote(in: context)
        context.delete(only)
        try context.save()

        let first = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: context, dayKey: "2026-11-15")
        let second = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: ModelContext(container), dayKey: "2026-11-15")

        let permanent = try ModelContext(container).fetch(FetchDescriptor<Note>()).filter { $0.kind == .permanent }
        #expect(permanent.isEmpty)
        #expect(first.notepad == nil && second.notepad == nil)
        #expect(first.emptyTabs == [.notepad])
        #expect(first.failedTabs.isEmpty)
        // The day and week notes keep their create-on-browse.
        #expect(first.today != nil && first.week != nil)
    }

    /// With notepad notes present the load returns the oldest — the note `permanentNote(in:)`
    /// hands every single-editor surface — and still creates nothing.
    @MainActor @Test func loadingWithNotepadNotesReturnsTheOldestAndAddsNone() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let oldest = try NoteMigrationService.permanentNote(in: context)
        _ = try NoteMigrationService.createPermanentNote(in: context, title: "Later")

        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: context, dayKey: "2026-11-15")

        #expect(state.notepad?.id == oldest.id)
        #expect(state.emptyTabs.isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).filter { $0.kind == .permanent }.count == 2)
    }

    /// The Mac pages read without creating too: the Notepad page's appear only selects, and the
    /// Today panel draws an empty state whose button is its one create.
    @Test func theMacNotepadSurfacesReadWithoutCreating() throws {
        let page = CadenceSourceScan.codeOnly(try sourceFile("Cadence/macOS/Views/NotesView.swift"))
        #expect(page.contains("if !applyRequestedSelection(), selectedNote == nil { selectNewestNotepadNote() }"))
        #expect(!page.contains("CadenceCoreNoteSupport.note(for: .notepad"))
        #expect(!page.contains("loadOrCreateNotepad"))

        let panel = CadenceSourceScan.codeOnly(try sourceFile("Cadence/macOS/Views/NotePanel.swift"))
        #expect(panel.contains("emptyNoteTabs = snapshot.emptyTabs"))
        #expect(panel.contains("} else if emptyNoteTabs.contains(tab) {"))
        #expect(CadenceSourceScan.matchCount("NoteMigrationService\\.permanentNote\\(", in: panel) == 1)
        #expect(panel.contains("{ createNotepadNote() }"))
    }

    // MARK: - [[T-18085]]: iOS's Notes date pick names a refused create

    /// The sentence a refused tab gets, and `nil` — which clears an earlier notice — for every tab
    /// that loaded.
    @Test func aFailedTabsNoticeIsTheMacSentenceAndOnlyForTheFailedTab() {
        let today = Note(kind: .daily, title: "Today")
        let state = CadenceCoreNoteSupport.loadOrCreateCoreNotes(today: today, week: nil, notepad: today, notepadReadFailed: false)

        #expect(state.createFailureNotice(for: .week) == CadencePendingChangePersistence.editFailureNotice)
        #expect(state.createFailureNotice(for: .today) == nil)
        #expect(state.createFailureNotice(for: .notepad) == nil)
        #expect(CadenceCoreNoteState().createFailureNotice(for: .today) == nil)
    }

    /// The date pick used to `guard … let note = loadCoreNotes().note(for: coreTab) else { return }`,
    /// dropping the refusal. It now sets the page's drawn notice from the loaded state before the
    /// guard, so a refusal is said and a success clears it. `Cadence/iOS/` is not compiled into
    /// this target, so this reads the source.
    @Test func theIOSDatePickSetsTheNoticeFromTheLoadedState() throws {
        let source = CadenceSourceScan.codeOnly(try sourceFile("Cadence/iOS/iOSNotesView.swift"))
        let open = try #require(CadenceSourceScan.declarationBody("private func openNoteForSelectedDay()", in: source))
        let notice = try #require(open.range(of: "createFailureNotice = state.createFailureNotice(for: coreTab)"))
        let guarded = try #require(open.range(of: "guard let note = state.note(for: coreTab) else { return }"))
        #expect(notice.upperBound < guarded.lowerBound, "the notice must be set before the guard returns")
        #expect(!open.contains("loadCoreNotes().note(for:"))
        #expect(source.contains("CadenceInlineFailureNotice(text: createFailureNotice)"))
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
        // [[T-9453]]: the shared action button, so the retry's hit area and hover wash are a
        // padded plate rather than the bare word under `.cadencePlain`.
        #expect(source.contains("CadenceActionButton(title: \"Try Again\", role: .secondary, size: .compact) { loadOrCreate() }"))
        #expect(!source.contains("Button(\"Try Again\")"))
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
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
