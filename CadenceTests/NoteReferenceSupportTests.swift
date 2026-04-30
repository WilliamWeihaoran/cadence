import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
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

    @Test func embeddedTaskDraftTitlesParseChecklistInputs() {
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "() Draft note task") == "Draft note task")
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "( ) Draft note task") == "Draft note task")
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "    () Draft indented task") == "Draft indented task")
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "[ ] Draft markdown task") == nil)
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "[] Draft markdown task") == nil)
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "○ Draft legacy task") == nil)
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "[ ]   ") == nil)
        #expect(MarkdownTaskEmbedParser.draftTitle(in: "[x] Already done") == nil)
    }

    @Test func standaloneTaskReferencesParseAsEmbeds() throws {
        let taskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let reference = MarkdownTaskEmbedParser.standaloneTaskReference(
            in: "[[task:\(taskID.uuidString)|Draft task]]",
            lineStart: 12
        )

        #expect(reference?.id == taskID)
        #expect(reference?.title == "Draft task")
        #expect(reference?.range.location == 12)
    }

    @Test func inlineTaskReferencesStayInlineLinks() throws {
        let taskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let inline = "See [[task:\(taskID.uuidString)|Draft task]] after standup."

        #expect(MarkdownTaskEmbedParser.standaloneTaskReference(in: inline) == nil)
    }

    @Test func missingTaskEmbedRenderInfoKeepsReferenceTitle() throws {
        let taskID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let reference = try #require(MarkdownTaskEmbedParser.standaloneTaskReference(
            in: "[[task:\(taskID.uuidString)|Deleted task]]"
        ))

        let missing = MarkdownTaskEmbedRenderInfo.missing(reference: reference)

        #expect(missing.id == taskID)
        #expect(missing.title == "Deleted task")
        #expect(missing.isMissing)
    }

    @Test func taskEmbedRenderInfoSortsAndCountsSubtasks() throws {
        let task = AppTask(title: "Parent")
        let first = Subtask(title: "First")
        first.id = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        first.order = 1
        first.isDone = true
        let second = Subtask(title: "Second")
        second.id = try #require(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        second.order = 2
        let third = Subtask(title: "Third")
        third.id = try #require(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"))
        third.order = 3
        third.isDone = true
        let fourth = Subtask(title: "Fourth")
        fourth.id = try #require(UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd"))
        fourth.order = 4
        task.subtasks = [third, first, fourth, second]

        let info = MarkdownTaskEmbedRenderInfo.task(task)

        #expect(info.subtasks.map(\.title) == ["First", "Second", "Third", "Fourth"])
        #expect(info.completedSubtaskCount == 2)
        #expect(info.subtaskTotalCount == 4)
        #expect(info.visibleSubtasks.map(\.title) == ["First", "Second", "Third"])
        #expect(info.hiddenSubtaskCount == 1)
        #expect(info.cardHeight > MarkdownTaskEmbedRenderInfo.compactCardHeight)
    }

    @Test func taskEmbedSubtaskHitHelperSeparatesCheckboxTextAndWhitespace() throws {
        let subtaskID = try #require(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let rect = MarkdownTaskEmbedSubtaskHitRect.subtask(
            id: subtaskID,
            checkbox: NSRect(x: 10, y: 10, width: 10, height: 10),
            text: NSRect(x: 28, y: 8, width: 80, height: 16),
            full: NSRect(x: 8, y: 8, width: 104, height: 18)
        )

        #expect(MarkdownTaskEmbedSubtaskHitTesting.hit(at: NSPoint(x: 12, y: 12), in: [rect]) == .checkbox(subtaskID))
        #expect(MarkdownTaskEmbedSubtaskHitTesting.hit(at: NSPoint(x: 36, y: 12), in: [rect]) == .openInspector)
        #expect(MarkdownTaskEmbedSubtaskHitTesting.hit(at: NSPoint(x: 112, y: 12), in: [rect]) == nil)
    }

    @Test func checklistMarkerHelperAcceptsOnlyMarkerCharacter() {
        let line = "    ○ Draft task"
        let markerRange = MarkdownTaskEmbedParser.legacyChecklistMarkerRange(in: line, lineStart: 20)

        #expect(markerRange == NSRange(location: 24, length: 1))
        #expect(MarkdownTaskEmbedParser.isLegacyChecklistMarkerCharacter(24, in: line, lineStart: 20))
        #expect(!MarkdownTaskEmbedParser.isLegacyChecklistMarkerCharacter(25, in: line, lineStart: 20))
        #expect(!MarkdownTaskEmbedParser.isLegacyChecklistMarkerCharacter(31, in: line, lineStart: 20))
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
