import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-7882]].** A focused editor commits a note's body mid-word — iOS after a 2.5 s pause, macOS
/// after 15 s, either platform on a focus loss — and the tag sync on that commit mints `pro` from a
/// caret still inside `#pro` of `#project`. The finished word's commit used to re-point the note at
/// `project` and leave `pro` behind for ever. Now a tag minted by one sync of a note is removed by
/// the next sync that drops it, if nothing else holds it and nobody has edited it since.
///
/// Every editor reaches the same function: iOS's hosts and macOS's `NotePanel` through
/// `CadenceCoreNoteSupport.update`, macOS's `NoteEditorPane` by calling
/// `TagSupport.syncNoteTagsFromMarkdownCommittingInsertions` itself — so both doors are driven
/// here. In-memory stores built per test; read back through a second context, because only the
/// store answers whether a row survived.
///
/// **[[T-7901]]** is pinned at the bottom: every way either macOS note editor switches note runs
/// the editor's flush first, and that flush pays a sync a [[T-7891]] ceiling commit deferred.
@MainActor
struct CadenceHalfTypedTagMintTests {

    private struct Store {
        let container: ModelContainer
        let editing: ModelContext

        init() throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            editing = ModelContext(container)
        }

        func note(_ content: String = "x") throws -> Note {
            let note = Note(kind: .list, title: "Note", content: content)
            editing.insert(note)
            try editing.save()
            return note
        }

        /// What the store holds, from a context that has seen none of the editing.
        func storedTagNames() throws -> [String] {
            try ModelContext(container).fetch(FetchDescriptor<Cadence.Tag>()).map(\.name).sorted()
        }
    }

    /// `NoteEditorPane.persistEditorContentIfNeeded`'s order: write the body, sync, commit.
    private func paneCommit(_ note: Note, _ content: String, in context: ModelContext) {
        note.content = content
        note.updatedAt = Date()
        TagSupport.syncNoteTagsFromMarkdownCommittingInsertions(note, in: context)
        CadencePendingChangePersistence.commitTypedContent(in: context)
    }

    // MARK: - T-7882

    @Test func aHalfTypedTagIsRemovedByTheFinishedWordsCommitThroughTheSharedNoteCommit() throws {
        let store = try Store()
        let note = try store.note()

        CadenceCoreNoteSupport.update(note, content: "x #pro", in: store.editing)
        #expect(try store.storedTagNames() == ["pro"], "the idle commit is expected to mint what the body says")

        CadenceCoreNoteSupport.update(note, content: "x #project", in: store.editing)
        #expect(try store.storedTagNames() == ["project"], "the half-typed `pro` outlived the finished word")
        #expect(note.tags?.map(\.name) == ["project"])
    }

    @Test func aHalfTypedTagIsRemovedByTheFinishedWordsCommitThroughTheNoteEditorPanesOwnSync() throws {
        let store = try Store()
        let note = try store.note()

        paneCommit(note, "x #pro", in: store.editing)
        paneCommit(note, "x #proj", in: store.editing)
        paneCommit(note, "x #project", in: store.editing)

        #expect(try store.storedTagNames() == ["project"], "a half-word minted on the way to `#project` survived")
    }

    /// The finished token is minted and kept: a quit's, a disappear's or a later idle commit of the
    /// same word removes nothing.
    @Test func theFinishedTokenOfACommitIsMintedAndSurvivesTheNextCommit() throws {
        let store = try Store()
        let note = try store.note()

        CadenceCoreNoteSupport.update(note, content: "x #project", in: store.editing)
        CadenceCoreNoteSupport.update(note, content: "x #project #urgent", in: store.editing)
        CadenceCoreNoteSupport.update(note, content: "x #project #urgent and more", in: store.editing)

        #expect(try store.storedTagNames() == ["project", "urgent"])
    }

    @Test func aDroppedMintAnotherNoteOrATaskNowHoldsIsKept() throws {
        let store = try Store()
        let note = try store.note()
        let other = try store.note()

        CadenceCoreNoteSupport.update(note, content: "x #pro #ide", in: store.editing)
        CadenceCoreNoteSupport.update(other, content: "y #pro", in: store.editing)
        let task = AppTask(title: "Task")
        store.editing.insert(task)
        let ide = try #require(note.tags?.first { $0.name == "ide" })
        task.tags = [ide]
        try store.editing.save()

        CadenceCoreNoteSupport.update(note, content: "x #project #idea", in: store.editing)

        #expect(try store.storedTagNames() == ["ide", "idea", "pro", "project"])
    }

    @Test func aTagThatExistedBeforeTheCommitIsNeverRemoved() throws {
        let store = try Store()
        store.editing.insert(Cadence.Tag(name: "pro"))
        try store.editing.save()
        let note = try store.note()

        CadenceCoreNoteSupport.update(note, content: "x #pro", in: store.editing)
        CadenceCoreNoteSupport.update(note, content: "x #project", in: store.editing)

        #expect(try store.storedTagNames() == ["pro", "project"])
    }

    @Test func aMintSomeoneEditedBeforeTheNextCommitIsKept() throws {
        let store = try Store()
        let note = try store.note()

        CadenceCoreNoteSupport.update(note, content: "x #pro", in: store.editing)
        let pro = try #require(note.tags?.first)
        pro.colorHex = "#ff0000"
        try store.editing.save()

        CadenceCoreNoteSupport.update(note, content: "x #project", in: store.editing)

        #expect(try store.storedTagNames() == ["pro", "project"], "a recoloured tag is the user's, not a half-word")
    }

    /// Only the next sync that changes the note's tags looks. A tag that survived it is the user's,
    /// so taking it out of the body two commits later leaves the row, as it always has.
    @Test func onlyTheNextTagChangingCommitOfTheNoteMayRemoveAMint() throws {
        let store = try Store()
        let note = try store.note()

        CadenceCoreNoteSupport.update(note, content: "x #pro", in: store.editing)
        CadenceCoreNoteSupport.update(note, content: "x #pro #other", in: store.editing)
        CadenceCoreNoteSupport.update(note, content: "x #other", in: store.editing)

        #expect(try store.storedTagNames() == ["other", "pro"])
    }

    // MARK: - T-7931

    /// The launch sweep's run over a store, at `now`, as the iPhone/iPad app's launch and the MCP
    /// server's (`CadenceMCPStorePreparation.prepare`) both call it.
    private func launchSweep(_ store: Store, now: Date = Date()) throws -> CadenceMaintenancePassOutcome {
        let outcome = TagSupport.syncAllNoteTagsFromMarkdown(in: store.editing, saveChanges: false, now: now)
        try store.editing.save()
        return outcome
    }

    /// A note as the Mac's ceiling commit leaves it: the body saved, its tags not synced.
    private func ceilingSaved(_ store: Store, _ content: String, writtenAt: Date) throws -> Note {
        let note = Note(kind: .list, title: "Note", content: content, updatedAt: writtenAt)
        store.editing.insert(note)
        try store.editing.save()
        return note
    }

    /// **[[T-7931]].** The sweep runs in another process with no caret, so it must not mint the
    /// half-word a ceiling commit saved; the Mac's finished-word commit then leaves only `project`.
    @Test func aLaunchSweepDoesNotMintTheHalfTypedTagACeilingCommitJustSaved() throws {
        let store = try Store()
        let now = Date()
        let note = try ceilingSaved(store, "x #pro", writtenAt: now.addingTimeInterval(-10))

        #expect(try launchSweep(store, now: now) == .nothingToDo)
        #expect(try store.storedTagNames().isEmpty, "the sweep minted the half-typed `pro`")
        #expect((note.tags ?? []).isEmpty)

        paneCommit(note, "x #project", in: store.editing)
        #expect(try store.storedTagNames() == ["project"], "`pro` outlived the finished word's commit")
    }

    /// Another device's clock may run ahead: a body written "in the future" is as fresh as one
    /// written a moment ago.
    @Test func aBodyStampedByAClockAheadOfThisOneIsStillFresh() throws {
        let store = try Store()
        let now = Date()
        _ = try ceilingSaved(store, "x #pro", writtenAt: now.addingTimeInterval(20))

        _ = try launchSweep(store, now: now)
        #expect(try store.storedTagNames().isEmpty, "a future-stamped half-typed body was minted")
    }

    /// A body that still reads `#pro` after the quiet period is the user's word, and is minted.
    @Test func aBodyStillForTheQuietPeriodIsMintedByTheSweep() throws {
        let store = try Store()
        let now = Date()
        let note = try ceilingSaved(
            store,
            "x #pro",
            writtenAt: now.addingTimeInterval(-(TagSupport.sweepInlineMintQuietPeriod + 1))
        )

        #expect(try launchSweep(store, now: now) == .changed)
        #expect(try store.storedTagNames() == ["pro"])
        #expect(note.tags?.map(\.name) == ["pro"])
    }

    /// Only a NEW row is withheld: a fresh note whose inline tags all exist is swept as before.
    @Test func aFreshNoteWhoseInlineTagsAllExistIsStillSwept() throws {
        let store = try Store()
        let now = Date()
        store.editing.insert(Cadence.Tag(name: "work", slug: "work", order: 0))
        let note = try ceilingSaved(store, "x #work", writtenAt: now)

        #expect(try launchSweep(store, now: now) == .changed)
        #expect(note.tags?.map(\.name) == ["work"])
        #expect(try store.storedTagNames() == ["work"])
    }

    /// The frontmatter `tags:` line is Cadence's own writing, never a caret mid-word: a fresh note
    /// that names a new tag there is minted as before.
    @Test func aFreshFrontmatterTagIsStillMintedByTheSweep() throws {
        let store = try Store()
        let now = Date()
        let note = try ceilingSaved(store, "---\ntags: [alpha]\n---\nBody", writtenAt: now)

        #expect(try launchSweep(store, now: now) == .changed)
        #expect(note.tags?.map(\.name) == ["alpha"])
    }

    // MARK: - T-7901

    /// Every `NoteEditorPane` in the app is torn down on a note switch rather than re-pointed, so
    /// the switch runs its `.onDisappear` flush while `note` is still the note being left — and
    /// that flush's persist defaults to `syncTags: true`, which pays a deferred sync on an
    /// unchanged body. The pane's own `.onChange(of: note.id)` reload, which would drop the owed
    /// sync, is reachable only by a host that re-points the pane, and this census is what says there
    /// is none. The event-note sheet holds one note for its life; a link out dismisses it.
    @Test func everyNoteEditorPaneHostTearsThePaneDownOnANoteSwitch() throws {
        var hosts = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let source = CadenceSourceScan.codeOnly(try cadenceTestSource(path))
            var searchStart = source.startIndex
            while let found = source.range(of: "NoteEditorPane(", range: searchStart..<source.endIndex) {
                searchStart = found.upperBound
                if found.lowerBound > source.startIndex,
                   source[source.index(before: found.lowerBound)].isLetter { continue } // TaskNoteEditorPane
                let open = source.index(before: found.upperBound)
                let arguments = try #require(
                    CadenceSourceScan.matchedRange(after: open, in: source, open: "(", close: ")"),
                    "\(path)"
                )
                hosts += 1
                if path.hasSuffix("EventNoteSupportViews.swift") {
                    #expect(
                        source[arguments].contains("onOpenNote: { TaskNoteLinkRouting.openDismissing("),
                        "the event-note sheet's pane must dismiss rather than switch note"
                    )
                    continue
                }
                let after = source[source.index(after: arguments.upperBound)...]
                    .drop { $0.isWhitespace }
                #expect(after.hasPrefix(".id("), "\(path): a NoteEditorPane that is re-pointed across a note switch drops its owed tag sync")
            }
        }
        #expect(hosts >= 7, "the census found \(hosts) NoteEditorPane constructions; it must not read vacuously")

        let pane = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/macOS/Views/NoteEditorPane.swift"))
        let disappear = try #require(CadenceSourceScan.declarationBody(".onDisappear", in: pane))
        #expect(disappear.contains("flushPendingEditorContent()"))
        let flush = try #require(CadenceSourceScan.functionBody(named: "flushPendingEditorContent", in: pane))
        #expect(flush.contains("persistEditorContentIfNeeded(editorContent, noteID: loadedNoteID ?? note.id)"),
                "the switch's flush must take the default `syncTags: true`")
    }

    /// `NotePanel` keeps one editor across its three tabs. Every path that changes the note it
    /// shows flushes first, while the outgoing tab is still active, so the flush's persist —
    /// `syncTags: true` by default — finds the outgoing note and pays its deferred sync.
    @Test func everyNotePanelNoteSwitchFlushesTheOutgoingNoteFirst() throws {
        let panel = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/macOS/Views/NotePanel.swift"))
        let body = try #require(CadenceSourceScan.declarationBody("struct NotePanel: View", in: panel))

        let select = try #require(CadenceSourceScan.functionBody(named: "selectTab", in: body))
        let selectFlush = try #require(select.range(of: "flushPendingEditorContent()"))
        let selectSwitch = try #require(select.range(of: "activeTab = tab"))
        #expect(selectFlush.lowerBound < selectSwitch.lowerBound, "selectTab switches tab before flushing")

        let refresh = try #require(CadenceSourceScan.functionBody(named: "refreshFromStore", in: body))
        let refreshFlush = try #require(refresh.range(of: "flushPendingEditorContent()"))
        let refreshReload = try #require(refresh.range(of: "loadOrCreate()"))
        #expect(refreshFlush.lowerBound < refreshReload.lowerBound, "refreshFromStore reloads the notes before flushing")

        let flush = try #require(CadenceSourceScan.functionBody(named: "flushPendingEditorContent", in: body))
        #expect(flush.contains("persistEditorContentIfNeeded(editorContent, noteID: loadedNoteID)"))

        // `selectTab` is the one write of `activeTab`; the reload that drops a pending commit runs
        // only from the editor's `.onAppear`.
        #expect(CadenceSourceScan.matchCount(#"activeTab\s*=[^=]"#, in: body) == 1)
        #expect(CadenceSourceScan.matchCount(#"loadEditorStateIfNeeded\(for: note\)"#, in: body) == 1)
    }
}
