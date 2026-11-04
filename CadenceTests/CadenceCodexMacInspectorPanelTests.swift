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
        let opened = CadenceScheduleDraft(editing: task)
        var draft = opened
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
            draft, opened: opened, to: task, areas: [work], projects: [], allTasks: [task], in: context,
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
        let opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.title = "Retry this"
        draft.priority = .high
        draft.dueDateKey = "2026-10-27"
        other.notes = "Unrelated pending work"
        var commits = 0
        #expect(!TaskInspectorScheduleCommit.save(
            draft, opened: opened, to: task, areas: [], projects: [], allTasks: [task, other], in: context,
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
        let opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.title = "Do not write"
        draft.listToken = CadenceTaskComposerSupport.token(for: .area(UUID()))
        var commits = 0
        #expect(!TaskInspectorScheduleCommit.save(
            draft, opened: opened, to: task, areas: [], projects: [], allTasks: [task], in: context,
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
        let opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.clearDoDate()
        #expect(!TaskInspectorScheduleCommit.save(
            draft, opened: opened, to: task, areas: [], projects: [], allTasks: [task], in: context,
            commit: { _ in throw Refused() }
        ))
        #expect(task.scheduledDate == "2026-10-25")
        #expect(task.scheduledStartMin == 600)
        #expect(task.calendarEventID == "legacy-link")
        #expect(TaskInspectorScheduleCommit.save(
            draft, opened: opened, to: task, areas: [], projects: [], allTasks: [task], in: context,
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

    @Test func codexInspectorRecurrenceDraftScopesCommitsAndRetriesAtomically() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let seriesID = UUID().uuidString
        let tasks = (0..<3).map { index in
            let task = AppTask(title: "Occurrence \(index)")
            task.recurrenceRule = .daily
            task.recurrenceSeriesIDRaw = seriesID
            task.recurrenceOccurrenceIndex = index
            task.scheduledDate = "2026-11-0\(index + 2)"
            context.insert(task)
            return task
        }
        try context.save()
        let task = tasks[1]
        let opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.title = "Edited"
        #expect(!TaskInspectorScheduleCommit.needsRecurrenceScope(draft, opened: opened, task: task))
        var endOnly = opened
        endOnly.selectSeriesEnd(.afterCount)
        #expect(TaskInspectorScheduleCommit.needsRecurrenceScope(endOnly, opened: opened, task: task))
        draft.repeatRule = .weekly
        draft.selectSeriesEnd(.afterCount)
        draft.setSeriesEndCount(1)
        #expect(draft.seriesEndCount == task.recurrenceOccurrenceNumber)
        #expect(TaskInspectorScheduleCommit.needsRecurrenceScope(draft, opened: opened, task: task))
        // Editing, cancelling the draft, or cancelling scope has no record write to undo.
        #expect(tasks.allSatisfy { $0.recurrenceRule == .daily })
        #expect(task.title == "Occurrence 1")
        let storedBefore = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(storedBefore.allSatisfy { $0.recurrenceRule == .daily })
        #expect(!TaskInspectorScheduleCommit.save(
            draft, opened: opened, to: task, areas: [], projects: [], allTasks: tasks,
            scope: .thisAndFuture, in: context, commit: { _ in throw Refused() }
        ))
        #expect(tasks.allSatisfy { $0.recurrenceRule == .daily && $0.recurrenceEndMode == .never })
        #expect(task.title == "Occurrence 1")
        #expect(draft.repeatRule == .weekly)
        #expect(TaskInspectorScheduleCommit.save(
            draft, opened: opened, to: task, areas: [], projects: [], allTasks: tasks,
            scope: .thisTask, in: context, commit: { try $0.save() }
        ))
        #expect(task.title == "Edited")
        #expect(task.recurrenceRule == .weekly)
        #expect(task.recurrenceEndCount == 2)
        #expect(tasks[0].recurrenceRule == .daily)
        #expect(tasks[2].recurrenceRule == .daily)

        let reopened = CadenceScheduleDraft(editing: task)
        draft = reopened
        draft.repeatRule = .monthly
        draft.selectSeriesEnd(.onDate)
        draft.setSeriesEndDate(try #require(DateFormatters.date(from: "2027-01-02")))
        #expect(TaskInspectorScheduleCommit.save(
            draft, opened: reopened, to: task, areas: [], projects: [], allTasks: tasks,
            scope: .thisAndFuture, in: context, commit: { try $0.save() }
        ))
        #expect(tasks[0].recurrenceRule == .daily)
        for changed in tasks.suffix(2) {
            #expect(changed.recurrenceRule == .monthly)
            #expect(changed.recurrenceEndMode == .onDate)
            #expect(changed.recurrenceEndDate == "2027-01-02")
        }
        let beforeClear = CadenceScheduleDraft(editing: task)
        draft = beforeClear
        draft.repeatRule = .none
        #expect(TaskInspectorScheduleCommit.save(
            draft, opened: beforeClear, to: task, areas: [], projects: [], allTasks: tasks,
            scope: .thisAndFuture, in: context, commit: { try $0.save() }
        ))
        for changed in tasks.suffix(2) {
            #expect(changed.recurrenceRule == .none)
            #expect(changed.recurrenceEndMode == .never)
            #expect(changed.recurrenceEndDate.isEmpty)
            #expect(changed.recurrenceEndCount == 0)
        }
        let single = AppTask(title: "Single")
        var singleDraft = CadenceScheduleDraft(editing: single)
        singleDraft.repeatRule = .daily
        #expect(!TaskInspectorScheduleCommit.needsRecurrenceScope(
            singleDraft, opened: CadenceScheduleDraft(editing: single), task: single
        ))
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
        #expect(!root.contains("TaskInspectorRecurrenceControl("))
        #expect(root.contains("offersStatusActions: true"))
        let support = try source("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        let editor = try #require(CadenceSourceScan.declarationBody("struct TaskInspectorScheduleEditor<Content: View>: View", in: support))
        #expect(editor.contains("CadenceSchedulePanel("))
        #expect(editor.contains("offersTaskRepeat: true"))
        #expect(editor.contains("guard beforeSave() else"))
        let save = try #require(CadenceSourceScan.functionBody(named: "save", in: editor))
        #expect(save.contains("TaskInspectorScheduleCommit.needsRecurrenceScope(draft, opened: openedDraft, task: task)"))
        #expect(save.contains("isAskingRecurrenceScope = true"))
        #expect(editor.contains(".confirmationDialog("))
        #expect(editor.contains("saveFailureNotice = applySave(scope: .thisTask)"))
        #expect(editor.contains("saveFailureNotice = applySave(scope: .thisAndFuture)"))
        #expect(editor.contains("failureNotice: saveFailureNotice"))
        #expect(editor.contains("@State private var openedDraft"))
        let applySave = try #require(CadenceSourceScan.functionBody(named: "applySave", in: editor))
        #expect(applySave.contains("guard TaskInspectorScheduleCommit.save("))
        #expect(applySave.contains("else { return CadenceTaskFieldEditCommit.saveFailureNotice }"))
        #expect(try #require(applySave.range(of: "TaskInspectorScheduleCommit.save(")).lowerBound
                < #require(applySave.range(of: "dismiss()")).lowerBound)
        #expect(support.contains("flush?.action = flushPendingEditorContent"))
    }
}
#endif
