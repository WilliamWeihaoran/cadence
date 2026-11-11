// Compiled for macOS only: the palette half (`GlobalSearchIndexSupport`) is a macOS type, and the
// iOS half is pinned by scanning `iOSSearchView.swift`, which this bundle cannot call.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-16325]]: a note search matches the text the user wrote, not the hidden tag block.**
///
/// Tagging a note through its tag control writes a `---` / `tags: ["Work"]` / `---` block above
/// the body, which the editor, the Notes list and the search excerpt all hide. Cmd+K, iOS Search
/// and a list's Notes-tab field matched the raw `content`, so `tags` (or a quote mark in the list
/// field) found every tagged note with nothing on its row saying why. The tag itself stays
/// findable by name through the tag field every one of those searches scores.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceSearchNoteFrontmatterTests {

    /// A note tagged through the real door, so the block is the one the app writes.
    private func taggedNote(
        kind: NoteKind,
        title: String,
        body: String,
        in context: ModelContext
    ) -> Note {
        let note = Note(kind: kind, title: title, content: body, eventDateKey: kind == .meeting ? "2026-11-10" : "")
        context.insert(note)
        TagSupport.setTags(named: ["Work"], on: note, in: context, writeFrontmatter: true)
        return note
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    @Test func theTagBlockIsWrittenAndHiddenFromTheMatchText() throws {
        let context = try makeContext()
        let note = taggedNote(kind: .permanent, title: "Groceries", body: "Milk and eggs", in: context)
        // The premise: the block is in the stored text.
        #expect(note.content.hasPrefix("---\ntags: [\"Work\"]\n---"))
        let text = CadenceSearchNoteText.body(of: note, taskTitles: [:])
        #expect(!text.contains("tags"))
        #expect(!text.contains("---"))
        #expect(text.contains("Milk and eggs"))
    }

    @Test func cmdKNotesDoNotMatchTheWordTagsFromTheHiddenBlock() throws {
        let context = try makeContext()
        let tagged = taggedNote(kind: .permanent, title: "Groceries", body: "Milk and eggs", in: context)
        let aboutTags = Note(kind: .permanent, title: "Labels", content: "How I use tags")
        context.insert(aboutTags)

        let hits = GlobalSearchIndexSupport.noteResults(notes: [tagged, aboutTags], query: "tags", taskTitles: [:])
        #expect(hits.map(\.id) == [CadenceSearchIdentity.note(aboutTags.id)])

        // The tag still finds the note, through the tag field.
        let byTag = GlobalSearchIndexSupport.noteResults(notes: [tagged, aboutTags], query: "work", taskTitles: [:])
        #expect(byTag.map(\.id) == [CadenceSearchIdentity.note(tagged.id)])
    }

    @Test func cmdKEventNotesDoNotMatchTheWordTagsFromTheHiddenBlock() throws {
        let context = try makeContext()
        let tagged = taggedNote(kind: .meeting, title: "Standup", body: "Blockers: none", in: context)

        let hits = GlobalSearchIndexSupport.eventNoteResults(notes: [tagged], query: "tags", taskTitles: [:])
        #expect(hits.isEmpty)
        let byTag = GlobalSearchIndexSupport.eventNoteResults(notes: [tagged], query: "work", taskTitles: [:])
        #expect(byTag.map(\.id) == [CadenceSearchIdentity.eventNote(tagged.id)])
    }

    @Test func theListNotesTabFieldDoesNotMatchTheHiddenBlock() throws {
        let context = try makeContext()
        let tagged = taggedNote(kind: .list, title: "Plan", body: "Ship it", in: context)

        for query in ["tags", "\"", "---"] {
            let kept = CadenceListRelatedNotes.filter([tagged], query: query, requiredTagSlugs: [], tasks: [])
            #expect(kept.isEmpty, "query \(query) matched the hidden tag block")
        }
        let byTag = CadenceListRelatedNotes.filter([tagged], query: "work", requiredTagSlugs: [], tasks: [])
        #expect(byTag.map(\.id) == [tagged.id])
        let byBody = CadenceListRelatedNotes.filter([tagged], query: "ship", requiredTagSlugs: [], tasks: [])
        #expect(byBody.map(\.id) == [tagged.id])
    }

    /// iOS Search's note builder is a private member of an iOS view, so its half is pinned by
    /// source shape: it matches on the shared body, and no raw-content spelling is left.
    @Test func iOSSearchMatchesNotesOnTheSharedBody() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code.contains("struct iOSSearchView"))
        let builder = try #require(CadenceSourceScan.functionBody(named: "noteSectionResults", in: code))
        #expect(CadenceSourceScan.matchCount(
            #"CadenceSearchNoteText\.body\(of: note, taskTitles: taskTitles\)"#, in: builder
        ) == 1)
        #expect(CadenceSourceScan.matchCount(#"resolving\(note\.content"#, in: code) == 0)
    }
}
#endif
