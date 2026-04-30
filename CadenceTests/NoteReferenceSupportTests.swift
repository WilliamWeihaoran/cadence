import Foundation
import Testing
@testable import Cadence

@MainActor
struct NoteReferenceSupportTests {
    @Test func noteLinksIgnoreTaskReferences() {
        let content = """
        Link to [[Project Brief]] and [[ task:Write summary ]] plus [[ Weekly Review ]].
        """

        let links = NoteReferenceParser.noteLinks(in: content)

        #expect(links == ["Project Brief", "Weekly Review"])
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

    @Test func backlinksMatchNoteLinksByTitle() {
        let source = Note(kind: .list, title: "Source", content: "See [[Target Note]].")
        let target = Note(kind: .list, title: "target note", content: "")
        let unrelated = Note(kind: .list, title: "Other", content: "[[Someone Else]]")

        let backlinks = NoteReferenceResolver.backlinks(for: target, in: [source, target, unrelated])

        #expect(backlinks.map(\.id) == [source.id])
    }
}
