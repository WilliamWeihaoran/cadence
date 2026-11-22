import Foundation

/// Where a card created from a markdown editor is filed, and what else rides in that creation's
/// commit. The one real policy difference between the hosts ([[T-6721]]): a task's notes file into
/// the owner task's list and section; the core notes into the Inbox; a list note into its list's
/// area or project, and it bumps that note's `updatedAt` in the same commit.
///
/// **[[T-19075]]: shared, not macOS-only.** It lived in `TaskNotesEmbedHandlers.swift` behind
/// `#if os(macOS)`, so iOS's `iOSMarkdownEditingSurface` carried its own area/project-or-Inbox
/// builder, always in the default section, and neither iOS task-notes host passed the owner: a
/// `( ) Title` typed in a task's notes on iPhone or iPad landed in the Inbox while the Mac filed it
/// into the owner's list and section. Both platforms now build the draft through `draft(title:)`.
struct TaskNotesEmbedTarget {
    /// Checked first: a non-nil area wins over `project`, else the Inbox.
    let area: Area?
    let project: Project?
    let sectionName: String
    /// A note whose `updatedAt` is bumped inside the creation's commit and put back when the
    /// commit is refused, so a refused embed cannot leave the note marked as edited.
    var touchedNote: Note? = nil

    /// A task's notes: the owner's area or project, in the owner's section.
    static func ownerTask(_ task: AppTask) -> Self {
        Self(area: task.area, project: task.project, sectionName: task.resolvedSectionName)
    }

    /// The core notes (today, week, notepad) belong to no list: the Inbox, default section.
    static var coreNotes: Self {
        Self(area: nil, project: nil, sectionName: TaskSectionDefaults.defaultName)
    }

    /// A note editor: a list note files into its list — the area or project the host passes,
    /// else the note's own — and any other kind of note into the Inbox; default section either way.
    /// The note's `updatedAt` rides in the creation's commit.
    static func noteEditor(_ note: Note, area: Area?, project: Project?) -> Self {
        let isListNote = note.kind == .list
        return Self(
            area: isListNote ? (area ?? note.area) : nil,
            project: isListNote ? (project ?? note.project) : nil,
            sectionName: TaskSectionDefaults.defaultName,
            touchedNote: note
        )
    }

    /// The draft a new embed is created from, and the lists it may file into: the target's area or
    /// project (else the Inbox), in its section. One builder for every host on both platforms, for
    /// the creation and for the re-creation an undone embed's redo makes ([[T-18174]]).
    func draft(title: String) -> (draft: TaskCreationDraft, areas: [Area], projects: [Project]) {
        let container: TaskContainerSelection
        let areas: [Area]
        let projects: [Project]
        if let area {
            container = .area(area.id)
            areas = [area]
            projects = []
        } else if let project {
            container = .project(project.id)
            areas = []
            projects = [project]
        } else {
            container = .inbox
            areas = []
            projects = []
        }

        let draft = TaskCreationDraft(
            title: title,
            notes: "",
            priority: .none,
            container: container,
            sectionName: sectionName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )
        return (draft, areas, projects)
    }
}
