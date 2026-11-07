import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-12641]]: a new task can be given subtasks on every create surface, not only the Mac's.
///
/// The Mac capture card and drag-create popover had the checklist; on iOS the capture sheet built
/// its draft with a literal `subtaskTitles: []`, the two calendar create sheets wrote through an
/// insert that took no titles, and none of the three switched the panel's editor on. Modelled on
/// `CadenceCodexQuickCreateSubtasksTests`: the checklist has to reach a SECOND store context, so a
/// row that exists only in the writing context's memory does not count.
@MainActor
struct CadenceIOSCreateSubtasksTests {
    /// Raw editor lines, as `CadenceSchedulePanel`'s one-per-line field splits them.
    private let typed = ["  Review changes  ", "", "\t", "Run checks", "Review changes"]
    private let stored = ["Review changes", "Run checks", "Review changes"]

    private func storedChecklist(in container: ModelContainer) throws -> [String] {
        let reader = ModelContext(container)
        let task = try #require(try reader.fetch(FetchDescriptor<AppTask>()).first)
        #expect(try reader.fetch(FetchDescriptor<Subtask>()).count == stored.count)
        return (task.subtasks ?? []).sorted { $0.order < $1.order }.map(\.title)
    }

    /// The iOS capture sheet's write: `CadenceTaskComposerSupport.draft` into `TaskCreationService`.
    @Test func captureSheetDraftCarriesTheChecklistToASecondContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let fields = CadenceTaskComposerFields(
            container: .inbox, sectionName: "", doDateKey: "2026-10-23", dueDateKey: "", priority: .none
        )
        let draft = CadenceTaskComposerSupport.draft(
            title: "Prepare release", notes: "", fields: fields, tags: [], subtaskTitles: typed
        )
        #expect(draft.subtaskTitles == typed)
        let created = try TaskCreationService(areas: [], projects: [])
            .createTask(from: draft, into: ModelContext(container))
        #expect(created != nil)
        #expect(try storedChecklist(in: container) == stored)
    }

    @Test func captureSheetDraftDefaultsToNoChecklist() {
        let fields = CadenceTaskComposerFields(
            container: .inbox, sectionName: "", doDateKey: "", dueDateKey: "", priority: .none
        )
        #expect(CadenceTaskComposerSupport.draft(title: "x", notes: "", fields: fields, tags: []).subtaskTitles.isEmpty)
    }

    /// The two iOS calendar create sheets' write, `iOSScheduleDraftCreation.createTask`, lands on
    /// this insert; on the Mac it is the only half of that path compiled.
    @Test func scheduledInsertCarriesTheChecklistToASecondContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let task = try #require(try CadenceTaskMutationSupport.insertScheduledTask(
            title: "Prepare release", allTasks: [], modelContext: ModelContext(container),
            scheduledDate: "2026-10-23", scheduledStartMin: 600, estimatedMinutes: 30,
            subtaskTitles: typed, refusing: false
        ))
        #expect(task.scheduledStartMin == 600)
        #expect(try storedChecklist(in: container) == stored)
    }

    /// A refused commit takes the checklist back out with the task, not just the task.
    @Test func refusedScheduledInsertLeavesNoOrphanedChecklist() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        #expect(throws: CadenceUITestCommitRefusal.Refused.self) {
            _ = try CadenceTaskMutationSupport.insertScheduledTask(
                title: "Prepare release", allTasks: [], modelContext: context,
                scheduledDate: "2026-10-23", scheduledStartMin: 600, estimatedMinutes: 30,
                subtaskTitles: typed, refusing: true
            )
        }
        #expect(try context.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Subtask>()).isEmpty, "the refused insert left subtasks behind")
    }

    #if os(iOS)
    @Test func calendarCreateSheetsWriteCarriesTheChecklistToASecondContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        var draft = CadenceScheduleDraft(dateKey: "2026-10-23", startMin: 600)
        draft.title = "Prepare release"
        draft.subtaskTitles = typed
        let failure = iOSScheduleDraftCreation.createTask(
            from: draft, allTasks: [], areas: [], projects: [], modelContext: ModelContext(container)
        )
        #expect(failure == nil)
        #expect(try storedChecklist(in: container) == stored)
    }
    #endif

    /// The editor is switched on at all three iOS hosts and reaches the capture presentation two
    /// of them use; the behavioural tests above cannot see a SwiftUI argument.
    @Test func everyIOSCreateHostOffersTheChecklistEditor() throws {
        func code(_ path: String) throws -> String {
            let source = try cadenceTestSource(path)
            #expect(source.count > 500, "non-vacuity: \(path) read empty")
            return CadenceSourceScan.codeOnly(source)
        }
        for path in [
            "Cadence/iOS/iOSCreateTaskSheet.swift",
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            "Cadence/iOS/iOSTimelineDraftCreate.swift",
        ] {
            #expect(try code(path).contains("offersSubtasks: true"), "\(path) does not offer subtasks")
        }
        let sheet = try code("Cadence/iOS/iOSCreateTaskSheet.swift")
        let create = try #require(CadenceSourceScan.functionBody(named: "create", in: sheet))
        #expect(create.contains("subtaskTitles: draft.subtaskTitles"))
        let timeline = try code("Cadence/iOS/iOSTimelineDraftCreate.swift")
        let write = try #require(CadenceSourceScan.functionBody(named: "createTask", in: timeline))
        #expect(write.contains("subtaskTitles: draft.subtaskTitles"))
        let panel = try code("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        let capture = try #require(CadenceSourceScan.declarationBody("if let captureOptions", in: panel))
        #expect(capture.contains("CadenceScheduleCaptureCard("))
        #expect(capture.contains("offersSubtasks: offersSubtasks,"))
        let card = try code("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        #expect(card.contains("if offersSubtasks, draft.kind == .task"))
    }
}
