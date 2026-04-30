import Foundation
import Testing
@testable import Cadence

@MainActor
struct NoteReferenceSupportTests {
    @Test func noteLinksIgnoreTaskReferences() {
        let noteID = UUID()
        let content = """
        Link to [[Project Brief]] and [[ task:Write summary ]] plus [[note:\(noteID.uuidString)|Weekly Review]].
        """

        let links = NoteReferenceParser.noteLinks(in: content)

        #expect(links == ["Project Brief", "Weekly Review"])
    }

    @Test func noteReferencesParseLegacyTitleAndStableIDForms() throws {
        let noteID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let content = """
        - [[Project Brief]]
        - [[note:\(noteID.uuidString)|Renamed note]]
        """

        let references = NoteReferenceParser.noteReferences(in: content)

        #expect(references.count == 2)
        #expect(references[0].noteID == nil)
        #expect(references[0].fallbackTitle == "Project Brief")
        #expect(references[1].noteID == noteID)
        #expect(references[1].fallbackTitle == "Renamed note")
    }

    @Test func taskReferencesParseLegacyTitleAndStableIDForms() throws {
        let taskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let content = """
        - [[task:Draft changelog]]
        - [[task:\(taskID.uuidString)|Renamed task]]
        """

        let references = NoteReferenceParser.taskReferences(in: content)

        #expect(references.count == 2)
        #expect(references[0].taskID == nil)
        #expect(references[0].fallbackTitle == "Draft changelog")
        #expect(references[1].taskID == taskID)
        #expect(references[1].fallbackTitle == "Renamed task")
    }

    @Test func linkedTasksPreferStableIDOverTitleFallback() throws {
        let taskID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let currentTask = AppTask(title: "Current task title")
        currentTask.id = taskID
        let staleTitleTask = AppTask(title: "Old task title")
        let note = Note(
            kind: .list,
            title: "Planning",
            content: "[[task:\(taskID.uuidString)|Old task title]]"
        )

        let linkedTasks = NoteReferenceResolver.linkedTasks(for: note, in: [staleTitleTask, currentTask])

        #expect(linkedTasks.map(\.id) == [taskID])
    }

    @Test func linkedNotesPreferStableIDOverTitleFallback() throws {
        let noteID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let currentNote = Note(id: noteID, kind: .list, title: "Current title")
        let staleTitleNote = Note(kind: .list, title: "Old title")
        let source = Note(
            kind: .list,
            title: "Source",
            content: "[[note:\(noteID.uuidString)|Old title]]"
        )

        let linkedNotes = NoteReferenceResolver.linkedNotes(for: source, in: [staleTitleNote, currentNote, source])

        #expect(linkedNotes.map(\.id) == [noteID])
    }

    @Test func backlinksMatchNoteLinksByTitle() {
        let source = Note(kind: .list, title: "Source", content: "See [[Target Note]].")
        let target = Note(kind: .list, title: "target note", content: "")
        let unrelated = Note(kind: .list, title: "Other", content: "[[Someone Else]]")

        let backlinks = NoteReferenceResolver.backlinks(for: target, in: [source, target, unrelated])

        #expect(backlinks.map(\.id) == [source.id])
    }

    @Test func backlinksMatchStableNoteIDs() throws {
        let targetID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let target = Note(id: targetID, kind: .list, title: "New title")
        let source = Note(kind: .list, title: "Source", content: "See [[note:\(targetID.uuidString)|Old title]].")

        let backlinks = NoteReferenceResolver.backlinks(for: target, in: [source, target])

        #expect(backlinks.map(\.id) == [source.id])
    }

    @Test func generatedReferenceMarkdownSanitizesDelimiters() {
        let note = Note(kind: .list, title: "Plan | [Draft]")
        let task = AppTask(title: "Ship | [Beta]")

        #expect(NoteReferenceParser.noteReferenceMarkdown(for: note).hasSuffix("|Plan - (Draft)]]"))
        #expect(NoteReferenceParser.taskReferenceMarkdown(for: task).hasSuffix("|Ship - (Beta)]]"))
    }

    @Test func markdownOutlineExtractsHeadingLocations() {
        let content = """
        Intro
        # One
        Body
        ## Two
        """

        let outline = MarkdownOutlineParser.items(in: content)

        #expect(outline.map(\.title) == ["One", "Two"])
        #expect(outline.map(\.level) == [1, 2])
        #expect(outline[0].location == 6)
    }

    @Test func markdownMetadataParsesFrontmatterAndInlineTags() {
        let content = """
        ---
        tags: [work, notes]
        status: active
        ---

        Body #markdown
        # Heading
        """

        let metadata = MarkdownMetadataParser.metadata(in: content)

        #expect(metadata.frontmatter.properties["status"] == "active")
        #expect(metadata.tags == ["work", "notes", "markdown"])
    }

    @Test func markdownTableParserFindsHeaderDelimiterAndRows() {
        let content = """
        | Name | Status |
        | --- | --- |
        | Alpha | Open |
        """

        let styles = MarkdownTableParser.rowStyles(in: content)

        #expect(styles[0]?.isHeader == true)
        #expect(styles[1]?.isDelimiter == true)
        #expect(styles[2]?.columnCount == 2)
    }

    @Test func unlinkedMentionsExcludeAlreadyLinkedNotes() {
        let mentioned = Note(kind: .list, title: "Project Brief")
        let linked = Note(kind: .list, title: "Decision Log")
        let source = Note(kind: .list, title: "Source", content: "Project Brief and [[\(linked.displayTitle)]].")

        let mentions = NoteUnlinkedMentionResolver.unlinkedMentions(for: source, in: [source, mentioned, linked])

        #expect(mentions.map(\.id) == [mentioned.id])
    }
}
