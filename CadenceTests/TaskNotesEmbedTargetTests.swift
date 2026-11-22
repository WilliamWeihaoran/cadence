import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-19075]]: a `( ) Title` typed in a task's notes files into the owner task's list and
/// section on both platforms.** The Mac's task-notes hosts did this through `TaskNotesEmbedTarget`;
/// iOS had its own builder, always in the default section, and neither iOS task-notes host passed
/// the owner, so the card landed in the Inbox. The target now lives in `Shared/` and both platforms
/// build the draft from it. Not macOS-gated: the value half runs on either test host.
@MainActor
struct TaskNotesEmbedTargetTests {

    /// The ticket's own steps as values: "Pick tiles" in Kitchen reno / Buy; "Order grout" typed in
    /// its notes lands in Kitchen reno / Buy, through the creation service the hosts call.
    @Test func aTasksNotesFileANewCardIntoTheOwnersListAndSection() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let project = Project(name: "Kitchen reno")
        project.sectionNames = [TaskSectionDefaults.defaultName, "Buy"]
        let owner = AppTask(title: "Pick tiles")
        owner.project = project
        owner.sectionName = "Buy"
        modelContext.insert(project)
        modelContext.insert(owner)
        try modelContext.save()

        let (draft, areas, projects) = TaskNotesEmbedTarget.ownerTask(owner).draft(title: "Order grout")
        #expect(draft.container == .project(project.id))
        #expect(draft.sectionName == "Buy", "the owner's section was dropped")
        #expect(areas.isEmpty)
        #expect(projects.map(\.id) == [project.id])

        let inserted = TaskCreationService(areas: areas, projects: projects).insertTask(from: draft, into: modelContext)
        let created = try #require(inserted)
        try modelContext.save()
        #expect(created.project?.id == project.id, "the card landed outside the owner's list")
        #expect(created.area == nil)
        #expect(created.resolvedSectionName == "Buy", "the card landed outside the owner's section")
    }

    /// The other two shapes the iOS surface still builds: an area wins over a project, and no list
    /// at all is the Inbox, default section.
    @Test func anAreaWinsOverAProjectAndNoListIsTheInbox() throws {
        let area = Area(name: "Home")
        let project = Project(name: "Launch")
        let both = TaskNotesEmbedTarget(area: area, project: project, sectionName: "Later").draft(title: "A")
        #expect(both.draft.container == .area(area.id))
        #expect(both.draft.sectionName == "Later")
        #expect(both.projects.isEmpty)

        let loose = TaskNotesEmbedTarget.coreNotes.draft(title: "B")
        #expect(loose.draft.container == .inbox)
        #expect(loose.draft.sectionName == TaskSectionDefaults.defaultName)
        #expect(loose.areas.isEmpty && loose.projects.isEmpty)
    }

    /// **Source shape — the iOS hosts are `#if os(iOS)` views a macOS test cannot render.** The
    /// surface builds its draft through the shared target, an owner task wins, and both iOS
    /// task-notes hosts pass the task they are the notes of.
    @Test func bothIOSTaskNotesHostsPassTheirOwnerTask() throws {
        let surface = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift"))
        let draftBody = try #require(
            CadenceSourceScan.declarationBody("private func embedDraft(title: String)", in: surface),
            "the iOS surface has no embed draft builder"
        )
        #expect(draftBody.contains("embedTarget.draft(title: title)"), "iOS builds its own draft again")
        let target = try #require(
            CadenceSourceScan.declarationBody("private var embedTarget: TaskNotesEmbedTarget", in: surface),
            "the iOS surface has no embed target"
        )
        #expect(target.contains("if let embeddedTaskOwner { return .ownerTask(embeddedTaskOwner) }"))
        #expect(CadenceSourceScan.matchCount(#"TaskCreationDraft\("#, in: surface) == 0, "a second draft builder")

        for (path, needle) in [
            ("Cadence/iOS/iOSTaskDetailSheetSections.swift", "embeddedTaskOwner: ownerTask,"),
            ("Cadence/iOS/iOSTaskDetailSheet.swift", "ownerTask: task,"),
            ("Cadence/iOS/iOSFocusView.swift", "embeddedTaskOwner: task")
        ] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("iOSMarkdownEditingSurface(") || code.contains("iOSTaskNotesSection("), "\(path) hosts no task notes")
            #expect(code.contains(needle), "\(path) does not pass the owner task, so its notes file into the Inbox")
        }
    }
}
