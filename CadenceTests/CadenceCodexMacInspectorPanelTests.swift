#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexMacInspectorPanelTests {
    private struct Refused: Error {}

    @Test func codexInspectorDraftCommitStoresScheduleAndPreservesLiveRecordEdits() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let work = Area(name: "Work")
        context.insert(work)
        let task = AppTask(title: "Before")
        context.insert(task)
        try context.save()
        var draft = CadenceScheduleDraft(editing: task)
        draft.title = "After"
        draft.priority = .high
        draft.listToken = CadenceTaskComposerSupport.token(for: .area(work.id))
        draft.startDateKey = "2026-10-25"
        draft.isAllDay = false
        draft.startMin = 605
        draft.estimateMinutes = 20
        draft.dueDateKey = "2026-10-27"
        task.notes = "Flushed while the panel was open"
        task.recurrenceRule = .weekly
        task.recurrenceEndMode = .afterCount
        task.recurrenceEndCount = 7
        task.status = .inProgress
        try context.save()
        var commits = 0
        #expect(TaskInspectorScheduleCommit.save(
            draft, to: task, areas: [work], projects: [], allTasks: [task], in: context,
            commit: { commits += 1; try $0.save() }
        ))
        #expect(commits == 1)
        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.title == "After")
        #expect(stored.priority == .high)
        #expect(stored.area?.id == work.id)
        #expect(stored.scheduledDate == "2026-10-25")
        #expect(stored.scheduledStartMin == 605)
        #expect(stored.estimatedMinutes == 20)
        #expect(stored.dueDate == "2026-10-27")
        #expect(stored.notes == "Flushed while the panel was open")
        #expect(stored.recurrenceRule == .weekly)
        #expect(stored.recurrenceEndMode == .afterCount)
        #expect(stored.recurrenceEndCount == 7)
        #expect(stored.status == .inProgress)
    }

    @Test func codexInspectorRefusedDraftRestoresFieldsAndLeavesTheRetryDraft() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Before")
        let other = AppTask(title: "Other")
        context.insert(task)
        context.insert(other)
        try context.save()
        var draft = CadenceScheduleDraft(editing: task)
        draft.title = "Retry this"
        draft.priority = .high
        draft.dueDateKey = "2026-10-27"
        other.notes = "Unrelated pending work"
        var commits = 0
        #expect(!TaskInspectorScheduleCommit.save(
            draft, to: task, areas: [], projects: [], allTasks: [task, other], in: context,
            commit: { _ in commits += 1; throw Refused() }
        ))
        #expect(commits == 1)
        #expect(task.title == "Before")
        #expect(task.priority == TaskPriority.none)
        #expect(task.dueDate.isEmpty)
        #expect(draft.title == "Retry this")
        #expect(draft.dueDateKey == "2026-10-27")
        #expect(other.notes == "Unrelated pending work")
        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.id == task.id })
        #expect(stored.title == "Before")
    }

    @Test func codexInspectorCannotSaveIntoADeletedList() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Keep this")
        context.insert(task)
        try context.save()
        var draft = CadenceScheduleDraft(editing: task)
        draft.title = "Do not write"
        draft.listToken = CadenceTaskComposerSupport.token(for: .area(UUID()))
        var commits = 0
        #expect(!TaskInspectorScheduleCommit.save(
            draft, to: task, areas: [], projects: [], allTasks: [task], in: context,
            commit: { _ in commits += 1 }
        ))
        #expect(commits == 0)
        #expect(task.title == "Keep this")
        #expect(task.area == nil)
    }

    @Test func codexInspectorClearingDoDateKeepsLegacyLinkAndRefusalInStep() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Timed")
        task.scheduledDate = "2026-10-25"
        task.scheduledStartMin = 600
        task.calendarEventID = "legacy-link"
        context.insert(task)
        try context.save()
        var draft = CadenceScheduleDraft(editing: task)
        draft.clearDoDate()
        #expect(!TaskInspectorScheduleCommit.save(
            draft, to: task, areas: [], projects: [], allTasks: [task], in: context,
            commit: { _ in throw Refused() }
        ))
        #expect(task.scheduledDate == "2026-10-25")
        #expect(task.scheduledStartMin == 600)
        #expect(task.calendarEventID == "legacy-link")
        #expect(TaskInspectorScheduleCommit.save(
            draft, to: task, areas: [], projects: [], allTasks: [task], in: context,
            commit: { try $0.save() }
        ))
        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.scheduledDate.isEmpty)
        #expect(stored.scheduledStartMin == -1)
        #expect(stored.calendarEventID.isEmpty)
    }

    @Test func codexInspectorTagWritesCommitAndUndoRefusals() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Tagged")
        let first = Tag(name: "First")
        let second = Tag(name: "Second")
        context.insert(task)
        context.insert(first)
        context.insert(second)
        try context.save()
        #expect(TaskInspectorScheduleCommit.setTags([first], on: task, in: context, commit: { try $0.save() }))
        #expect(!TaskInspectorScheduleCommit.setTags([second], on: task, in: context, commit: { _ in throw Refused() }))
        #expect(task.tags?.map(\.id) == [first.id])
        let stored = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.tags?.map(\.id) == [first.id])
    }

    @Test func codexInspectorNotesFlushRunsSynchronously() {
        let flush = TaskInspectorNotesFlush()
        var content = "buffered"
        flush.action = { content = "flushed" }
        flush.flush()
        #expect(content == "flushed")
        flush.action = nil
        flush.flush()
        #expect(content == "flushed")
    }

    @Test func codexInspectorActuallyHostsThePanelAndGuardsDismissal() throws {
        func source(_ path: String) throws -> String {
            let raw = try cadenceTestSource(path)
            #expect(raw.count > 500)
            return CadenceSourceScan.codeOnly(raw)
        }
        let root = try source("Cadence/macOS/Views/SchedulePanelComponents.swift")
        #expect(root.contains("TaskInspectorScheduleEditor(task: task, beforeSave: prepareToSave)"))
        #expect(!root.contains("TaskDetailHeaderSection("))
        #expect(!root.contains("TaskDetailScheduleGroupSection("))
        #expect(root.contains("notesFlush.flush()"))
        #expect(root.contains("return subtaskFailureNotice == nil"))
        #expect(root.contains("TaskInspectorRecurrenceControl(task: task, childPlacement: .besideInspector)"))
        #expect(root.contains("offersStatusActions: true"))
        let support = try source("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        let editor = try #require(CadenceSourceScan.declarationBody("struct TaskInspectorScheduleEditor<Content: View>: View", in: support))
        #expect(editor.contains("CadenceSchedulePanel("))
        #expect(editor.contains("offersTaskRepeat: false"))
        #expect(editor.contains("guard beforeSave() else"))
        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: editor))
        #expect(save.contains("guard TaskInspectorScheduleCommit.save("))
        #expect(save.contains("else { return CadenceTaskFieldEditCommit.saveFailureNotice }"))
        #expect(try #require(save.range(of: "TaskInspectorScheduleCommit.save(")).lowerBound
                < #require(save.range(of: "dismiss()")).lowerBound)
        #expect(support.contains("flush?.action = flushPendingEditorContent"))
    }
}
#endif
