#if os(macOS)
import AppKit
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-7810 / T-7811.** The macOS markdown editors' typed-but-uncommitted buffers.
///
/// T-7810: the fallback commit was a pure debounce re-armed on every keystroke, so continuous
/// typing never reached the store until a pause, and an abrupt kill lost it all. The schedule now
/// has a ceiling measured from the FIRST uncommitted keystroke. Proved on the shared helper with an
/// injected clock; each editor is pinned to use it.
///
/// T-7811: `applicationWillTerminate` flushed none of the buffers. It now drains
/// `MarkdownEditorTerminationFlush`, which each editor registers with while a commit is pending.
/// Proved through the real quit hook; each editor is pinned to register and unregister.
///
/// Neither is verified on a live quit or kill of the app: the owner's Cadence may be running and
/// the launcher refuses ([[T-3259]]).
@MainActor
struct MarkdownEditorFallbackCommitTests {

    private static let second: UInt64 = 1_000_000_000

    /// Replays a keystroke stream through the schedule the way an editor does: a keystroke made
    /// before the armed commit fires re-arms it; one made after starts a new window. Returns the
    /// times the commits fire.
    private func commitTimes(
        keystrokesAt offsets: [TimeInterval],
        idleDelay: UInt64,
        maxWait: UInt64
    ) -> [TimeInterval] {
        var fires: [TimeInterval] = []
        var windowStart: Date?
        var armedFire: TimeInterval?
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        for offset in offsets {
            if let fire = armedFire, fire <= offset {
                fires.append(fire)
                armedFire = nil
                windowStart = nil
            }
            let schedule = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
                pendingWindowStart: armedFire == nil ? nil : windowStart,
                now: origin.addingTimeInterval(offset),
                idleDelay: idleDelay,
                maxWait: maxWait
            )
            windowStart = schedule.windowStart
            armedFire = offset + TimeInterval(schedule.delay) / TimeInterval(Self.second)
        }
        if let armedFire { fires.append(armedFire) }
        return fires
    }

    @Test func continuousTypingStillCommitsWithinTheCeilingOfTheFirstKeystroke() {
        // A keystroke every half second for a minute: never a 15 s pause.
        let keystrokes = stride(from: 0.0, through: 60.0, by: 0.5).map { $0 }
        let fires = commitTimes(
            keystrokesAt: keystrokes,
            idleDelay: MarkdownEditorSyncTiming.fallbackContentCommitDelay,
            maxWait: MarkdownEditorSyncTiming.fallbackContentCommitMaxWait
        )
        // A pure debounce commits once, after the last keystroke. The ceiling commits during.
        #expect(fires.count >= 4, "continuous typing was never committed: \(fires)")
        let ceiling = TimeInterval(MarkdownEditorSyncTiming.fallbackContentCommitMaxWait) / TimeInterval(Self.second)
        // Every keystroke reaches the store no later than the ceiling after it was typed.
        for keystroke in keystrokes {
            let committedBy = fires.first { $0 >= keystroke }
            #expect(committedBy != nil)
            if let committedBy { #expect(committedBy - keystroke <= ceiling) }
        }
    }

    @Test func theCeilingDoesNotRaiseTheCommitRateAboveOnePerIdleDelay() {
        let keystrokes = stride(from: 0.0, through: 60.0, by: 0.5).map { $0 }
        let fires = commitTimes(
            keystrokesAt: keystrokes,
            idleDelay: MarkdownEditorSyncTiming.fallbackContentCommitDelay,
            maxWait: MarkdownEditorSyncTiming.fallbackContentCommitMaxWait
        )
        let idle = TimeInterval(MarkdownEditorSyncTiming.fallbackContentCommitDelay) / TimeInterval(Self.second)
        for (earlier, later) in zip(fires, fires.dropFirst()) {
            #expect(later - earlier >= idle - 0.5, "commits closer together than the idle delay: \(fires)")
        }
    }

    @Test func aPauseStillCommitsAtTheIdleDelayAfterTheLastKeystroke() {
        // Idle shorter than the ceiling, so the idle rule is visible: three keystrokes, then quiet.
        let fires = commitTimes(keystrokesAt: [0, 1, 2], idleDelay: 5 * Self.second, maxWait: 20 * Self.second)
        #expect(fires == [7])
    }

    @Test func theFirstEditOfAWindowGetsTheFullIdleDelayAndOpensTheWindow() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let schedule = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(pendingWindowStart: nil, now: now)
        #expect(schedule.windowStart == now)
        #expect(schedule.delay == MarkdownEditorSyncTiming.fallbackContentCommitDelay)
    }

    @Test func anEditPastTheCeilingFiresAtOnceAndKeepsTheWindow() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let schedule = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
            pendingWindowStart: start,
            now: start.addingTimeInterval(40),
            idleDelay: 15 * Self.second,
            maxWait: 15 * Self.second
        )
        #expect(schedule.windowStart == start)
        #expect(schedule.delay == 0)
    }

    // MARK: - T-7891: a ceiling commit must not mint a half-typed #tag

    @Test func onlyACommitTheCeilingDidNotCutShortSyncsTags() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let idle = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(pendingWindowStart: nil, now: start)
        #expect(MarkdownEditorSyncTiming.fallbackCommitSyncsTags(delay: idle.delay))
        let capped = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
            pendingWindowStart: start,
            now: start.addingTimeInterval(14)
        )
        #expect(capped.delay < MarkdownEditorSyncTiming.fallbackContentCommitDelay, "precondition: capped")
        #expect(!MarkdownEditorSyncTiming.fallbackCommitSyncsTags(delay: capped.delay))
        let due = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
            pendingWindowStart: start,
            now: start.addingTimeInterval(40)
        )
        #expect(!MarkdownEditorSyncTiming.fallbackCommitSyncsTags(delay: due.delay))
    }

    /// `"x #pro"` typed with the caret at the end, fourteen seconds into a window, so the ceiling
    /// commits it one second later while `#project` is half typed. Through `NotePanel`'s write
    /// (`CadenceCoreNoteSupport.update`) into an in-memory store: no `pro` Tag. The next true idle
    /// commit, of the finished word, mints `project` only. Read from a second context.
    @Test func aCeilingCommitOfAHalfTypedTagMintsNoTagAndTheNextIdleCommitMintsTheFinishedOne() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let editing = ModelContext(container)
        let note = Note(kind: .list, title: "Note", content: "x")
        editing.insert(note)
        try editing.save()
        func tagNames() throws -> [String] {
            try ModelContext(container).fetch(FetchDescriptor<Cadence.Tag>()).map(\.name).sorted()
        }

        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let ceiling = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(
            pendingWindowStart: start,
            now: start.addingTimeInterval(14)
        )
        CadenceCoreNoteSupport.update(
            note,
            content: "x #pro",
            in: editing,
            syncTags: MarkdownEditorSyncTiming.fallbackCommitSyncsTags(delay: ceiling.delay)
        )
        let noteID = note.id
        let stored = try #require(
            try ModelContext(container).fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })).first
        )
        #expect(stored.content == "x #pro", "the ceiling commit must still write the body")
        #expect(try tagNames().isEmpty, "a ceiling commit minted the half-typed tag")

        let idle = MarkdownEditorSyncTiming.fallbackContentCommitSchedule(pendingWindowStart: nil, now: start.addingTimeInterval(20))
        CadenceCoreNoteSupport.update(
            note,
            content: "x #project",
            in: editing,
            syncTags: MarkdownEditorSyncTiming.fallbackCommitSyncsTags(delay: idle.delay)
        )
        #expect(try tagNames() == ["project"])
        #expect(note.tags?.map(\.name) == ["project"])
    }

    /// Both tag-syncing editors gate the sync on the helper, write the body anyway, owe the sync to
    /// the next flush point when the body is unchanged by then, and re-arm an idle commit for it.
    @Test func bothNoteEditorsDeferTheTagSyncOfACeilingCommit() throws {
        for editor in [
            ("Cadence/macOS/Views/NoteEditorPane.swift", "struct NoteEditorPane"),
            ("Cadence/macOS/Views/NotePanel.swift", "struct NotePanel: View"),
        ] {
            let source = CadenceSourceScan.codeOnly(try cadenceTestSource(editor.0))
            let body = try #require(CadenceSourceScan.declarationBody(editor.1, in: source), "\(editor.0)")
            let schedule = try #require(CadenceSourceScan.functionBody(named: "scheduleFallbackContentSync", in: body), "\(editor.0)")
            #expect(schedule.contains("let syncsTags = MarkdownEditorSyncTiming.fallbackCommitSyncsTags(delay: schedule.delay)"), "\(editor.0)")
            #expect(schedule.contains("syncTags: syncsTags)"), "\(editor.0)")
            #expect(schedule.contains("if tagSyncDeferredNoteID == noteID { scheduleFallbackContentSync(for: content"), "\(editor.0)")
            let persist = try #require(CadenceSourceScan.functionBody(named: "persistEditorContentIfNeeded", in: body), "\(editor.0)")
            #expect(persist.contains("tagSyncDeferredNoteID = syncTags ? nil : noteID"), "\(editor.0)")
            #expect(persist.contains("tagSyncDeferredNoteID == noteID"), "\(editor.0) never pays a deferred sync on an unchanged body")
        }
        let pane = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/macOS/Views/NoteEditorPane.swift"))
        let persist = try #require(CadenceSourceScan.functionBody(named: "persistEditorContentIfNeeded", in: pane))
        #expect(persist.filter { !$0.isWhitespace }.contains(
            "ifsyncTags{TagSupport.syncNoteTagsFromMarkdownCommittingInsertions(note,in:modelContext)}"
        ))
        let panel = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/macOS/Views/NotePanel.swift"))
        let panelPersist = try #require(CadenceSourceScan.functionBody(named: "persistEditorContentIfNeeded", in: panel))
        #expect(panelPersist.contains("CadenceCoreNoteSupport.update(note, content: content, in: currentNotesContext, syncTags: syncTags)"))
    }

    // MARK: - T-7811: the quit-time flush

    @Test func quittingRunsEveryRegisteredEditorFlushOnce() {
        let registry = MarkdownEditorTerminationFlush.shared
        let first = UUID()
        let second = UUID()
        let dropped = UUID()
        var flushed: [UUID] = []
        registry.register(first) { flushed.append(first) }
        registry.register(second) { flushed.append(second) }
        registry.register(dropped) { flushed.append(dropped) }
        registry.unregister(dropped)
        // Re-registering replaces rather than adds: an editor re-registers on every keystroke.
        registry.register(first) { flushed.append(first) }

        CadenceAppDelegate().applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        #expect(flushed.filter { $0 == first }.count == 1)
        #expect(flushed.filter { $0 == second }.count == 1)
        #expect(!flushed.contains(dropped), "an editor that disappeared was flushed on quit")

        // Drained: a second pass runs nothing.
        registry.flushAllBeforeTermination()
        #expect(flushed.count == 2)
    }

    // MARK: - T-7832: the note title on quit

    /// The note title is typed straight into the model and committed only at Return or blur
    /// ([[T-4971]]). A title typed and then quit is committed by the quit hook. Read from a second
    /// context, because only the store answers whether it survived. In-memory store, built here.
    @Test func quittingCommitsANoteTitleTypedButNotYetSubmitted() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let editing = ModelContext(container)
        let note = Note(kind: .list, title: "Old", content: "body")
        editing.insert(note)
        try editing.save()

        let titleFlushID = UUID()
        note.title = "Typed, never submitted"
        MarkdownEditorTerminationFlush.shared.registerCommit(titleFlushID, in: editing)
        #expect(editing.hasChanges, "precondition: the title is pending, not committed")

        CadenceAppDelegate().applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        let noteID = note.id
        let reader = ModelContext(container)
        let stored = try #require(
            try reader.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })).first
        )
        #expect(stored.title == "Typed, never submitted", "a title typed before Cmd-Q was not committed")
        #expect(!editing.hasChanges)
    }

    /// The title setter registers that commit under its own key — not the body's, which it would
    /// replace — and the pane drops it when it goes.
    @Test func theNoteTitleSetterRegistersItsOwnQuitCommit() throws {
        let path = "Cadence/macOS/Views/NoteEditorPane.swift"
        let source = CadenceSourceScan.codeOnly(try cadenceTestSource(path))
        let binding = try #require(CadenceSourceScan.declarationBody("private var titleBinding", in: source))
        #expect(binding.contains(
            "MarkdownEditorTerminationFlush.shared.registerCommit(titleTerminationFlushID, in: modelContext)"
        ))
        let body = try #require(CadenceSourceScan.declarationBody("struct NoteEditorPane", in: source))
        let disappear = try #require(body.range(of: ".onDisappear {"))
        #expect(
            String(body[disappear.upperBound...].prefix(400))
                .contains("MarkdownEditorTerminationFlush.shared.unregister(titleTerminationFlushID)"),
            "the title's quit commit is never unregistered"
        )
    }

    // MARK: - Every editor uses both

    private static let editors: [(path: String, declaration: String)] = [
        ("Cadence/macOS/Views/NoteEditorPane.swift", "struct NoteEditorPane"),
        ("Cadence/macOS/Views/ListNotesSupportViews.swift", "struct TaskNoteEditorPane: View"),
        ("Cadence/macOS/Views/FocusNotesPanel.swift", "struct FocusNotesPanel: View"),
        ("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift", "struct TaskDetailNotesSection: View"),
        ("Cadence/macOS/Views/NotePanel.swift", "struct NotePanel: View"),
    ]

    @Test func everyMarkdownEditorArmsItsFallbackThroughTheCeilingAndRegistersForQuit() throws {
        for editor in Self.editors {
            let source = CadenceSourceScan.codeOnly(try cadenceTestSource(editor.path))
            let body = try #require(
                CadenceSourceScan.declarationBody(editor.declaration, in: source),
                "\(editor.path): \(editor.declaration) not found"
            )
            let schedule = try #require(
                CadenceSourceScan.functionBody(named: "scheduleFallbackContentSync", in: body),
                "\(editor.path): no scheduleFallbackContentSync"
            )
            #expect(schedule.contains("MarkdownEditorSyncTiming.fallbackContentCommitSchedule("), "\(editor.path)")
            #expect(schedule.contains("Task.sleep(nanoseconds: schedule.delay)"), "\(editor.path)")
            #expect(!schedule.contains("fallbackContentCommitDelay"), "\(editor.path) still sleeps the bare debounce")
            // The window only carries over while a commit is armed.
            #expect(schedule.contains("pendingWindowStart: pendingFallbackContentSyncTask == nil ? nil : fallbackContentWindowStart"), "\(editor.path)")
            #expect(schedule.contains("fallbackContentWindowStart = schedule.windowStart"), "\(editor.path)")
            // Registered for quit, gated on something being pending.
            let register = try #require(
                schedule.range(of: "MarkdownEditorTerminationFlush.shared.register(terminationFlushID) {"),
                "\(editor.path) does not register for the quit-time flush"
            )
            let closure = String(schedule[register.upperBound...].prefix(200))
            #expect(closure.contains("guard pendingFallbackContentSyncTask != nil else { return }"), "\(editor.path)")
            #expect(closure.contains("flushPendingEditorContent()"), "\(editor.path)")
            // And dropped when the editor goes.
            let disappear = try #require(body.range(of: ".onDisappear {"), "\(editor.path)")
            #expect(
                String(body[disappear.upperBound...].prefix(300))
                    .contains("MarkdownEditorTerminationFlush.shared.unregister(terminationFlushID)"),
                "\(editor.path) never unregisters"
            )
        }
        // NotePanel's private copy of the timing is gone.
        let notePanel = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/macOS/Views/NotePanel.swift"))
        #expect(!notePanel.contains("CoreNoteSyncTiming"))
    }

    // MARK: - T-9123: an outside change to the observed text

    /// Replays the reported loss: the editor loaded "Draft", another writer stored "Synced", then the
    /// user types "!" and the buffer commits. Before T-9123 the buffer never left "Draft", so the
    /// commit wrote "Draft!" over the synced text.
    @Test func anIdleBufferAdoptsAnOutsideChangeSoTheNextCommitKeepsIt() {
        var buffer = "Draft"
        let store = "Synced"
        if let adopted = MarkdownEditorStoreAdoption.adoptedBuffer(
            storeText: store, buffer: buffer, bufferIsLoaded: true, commitIsPending: false
        ) {
            buffer = adopted
        }
        buffer += "!"
        #expect(buffer == "Synced!")
    }

    @Test func aBufferWithTypingPendingKeepsItsTextAndTheOutsideChangeLoses() {
        // Last writer wins while a commit is armed: the buffer holds keystrokes the store lacks.
        #expect(MarkdownEditorStoreAdoption.adoptedBuffer(
            storeText: "Synced", buffer: "Draft typed", bufferIsLoaded: true, commitIsPending: true
        ) == nil)
    }

    @Test func anUnloadedOrMatchingBufferAdoptsNothing() {
        #expect(MarkdownEditorStoreAdoption.adoptedBuffer(
            storeText: "Synced", buffer: "Other task", bufferIsLoaded: false, commitIsPending: false
        ) == nil)
        #expect(MarkdownEditorStoreAdoption.adoptedBuffer(
            storeText: "Same", buffer: "Same", bufferIsLoaded: true, commitIsPending: false
        ) == nil)
    }

    private static let taskNotesEditors: [(path: String, declaration: String)] = [
        ("Cadence/macOS/Views/ListNotesSupportViews.swift", "struct TaskNoteEditorPane: View"),
        ("Cadence/macOS/Views/FocusNotesPanel.swift", "struct FocusNotesPanel: View"),
        ("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift", "struct TaskDetailNotesSection: View"),
    ]

    @Test func everyTaskNotesEditorAdoptsAnOutsideNotesChangeThroughTheSharedRule() throws {
        for editor in Self.taskNotesEditors {
            let source = CadenceSourceScan.codeOnly(try cadenceTestSource(editor.path))
            let body = try #require(
                CadenceSourceScan.declarationBody(editor.declaration, in: source),
                "\(editor.path): \(editor.declaration) not found"
            )
            let observer = try #require(body.range(of: ".onChange(of: task.notes) {"), "\(editor.path) does not observe task.notes")
            #expect(String(body[observer.upperBound...].prefix(120)).contains("adoptStoreNotesIfIdle("), "\(editor.path)")
            let adopt = try #require(
                CadenceSourceScan.functionBody(named: "adoptStoreNotesIfIdle", in: body),
                "\(editor.path): no adoptStoreNotesIfIdle"
            )
            #expect(adopt.contains("MarkdownEditorStoreAdoption.adoptedBuffer("), "\(editor.path)")
            #expect(adopt.contains("buffer: editorContent"), "\(editor.path)")
            #expect(adopt.contains("bufferIsLoaded: loadedTaskID == task.id"), "\(editor.path)")
            #expect(adopt.contains("commitIsPending: pendingFallbackContentSyncTask != nil"), "\(editor.path)")
            #expect(adopt.contains("editorContent = adopted"), "\(editor.path)")
        }
    }
}
#endif
