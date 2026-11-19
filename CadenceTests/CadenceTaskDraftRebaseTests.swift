import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-18451]]: an open task editor follows a change made to its task elsewhere.
///
/// The three hosts (`CadenceTaskInlinePanel`, `iOSTaskDetailSheet`, the Mac
/// `TaskInspectorScheduleEditor`) re-read the task on change and hand it to
/// `CadenceScheduleDraft.rebase(draft:opened:onto:)`. What is pinned here is the rule: a unit the
/// user has not moved adopts the stored value into BOTH drafts, so the panel stops showing the
/// value it opened with and the dismiss guard does not read the adoption as unsaved; a unit the
/// user moved keeps the user's value and the opened value Save measures it against.
@Suite("Open task editor follows outside changes")
@MainActor
struct CadenceTaskDraftRebaseTests {

    private func store() throws -> (ModelContainer, ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (container, ModelContext(container))
    }

    private func filedTask(in context: ModelContext, area: Area) throws -> AppTask {
        let task = AppTask(title: "Report")
        task.notes = "Before"
        task.priority = .medium
        task.scheduledDate = "2026-10-16"
        task.scheduledStartMin = 10 * 60
        task.estimatedMinutes = 30
        task.dueDate = "2026-10-23"
        task.area = area
        task.context = area.context
        context.insert(task)
        try context.save()
        return task
    }

    @Test("A field the user left alone shows what another writer stored")
    func untouchedFieldsFollowTheStore() throws {
        let (_, context) = try store()
        let work = Area(name: "Work")
        let home = Area(name: "Home")
        context.insert(work)
        context.insert(home)
        let task = try filedTask(in: context, area: work)
        var opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.priority = .high

        task.title = "Renamed elsewhere"
        task.notes = "Synced notes"
        task.dueDate = "2026-10-26"
        task.scheduledDate = "2026-10-21"
        task.scheduledStartMin = 15 * 60
        task.estimatedMinutes = 50
        task.area = home
        task.recurrenceRule = .weekly
        try context.save()

        let stored = CadenceScheduleDraft(editing: task)
        CadenceScheduleDraft.rebase(draft: &draft, opened: &opened, onto: stored)

        #expect(draft.title == "Renamed elsewhere", "the panel still shows the title it opened with")
        #expect(draft.notes == "Synced notes")
        #expect(draft.dueDateKey == "2026-10-26", "the panel still shows the due date it opened with")
        #expect(draft.startDateKey == "2026-10-21" && draft.startMin == 15 * 60, "the do slot did not follow")
        #expect(draft.estimateMinutes == 50)
        #expect(draft.endMin == stored.endMin, "the drawn block is not the stored block")
        #expect(draft.listToken == stored.listToken, "the list did not follow the move")
        #expect(draft.repeatRule == .weekly)
        #expect(draft.priority == .high, "the user's own change was replaced")
        #expect(opened.priority == .medium, "the opened value Save measures the user's change against moved")

        // Everything but the user's priority now reads as the store: the adoption is not an edit.
        var expected = stored
        expected.priority = .high
        #expect(draft == expected)
        #expect(opened == stored)
    }

    @Test("Adopting an outside change is never unsaved work")
    func anAdoptedChangeIsNotUnsavedWork() throws {
        let (_, context) = try store()
        let work = Area(name: "Work")
        context.insert(work)
        let task = try filedTask(in: context, area: work)
        var opened = CadenceScheduleDraft(editing: task)
        var draft = opened

        task.dueDate = "2026-10-26"
        task.title = "Renamed elsewhere"
        try context.save()
        CadenceScheduleDraft.rebase(draft: &draft, opened: &opened, onto: CadenceScheduleDraft(editing: task))

        #expect(draft.dueDateKey == "2026-10-26")
        #expect(!CadenceTaskSheetUnsavedWork.draftDiffers(draft, from: opened), "a sync made the sheet refuse its swipe")
    }

    @Test("A field the user moved keeps the user's value, and Save still writes it")
    func aMovedFieldKeepsTheUsersValue() throws {
        let (container, context) = try store()
        let work = Area(name: "Work")
        context.insert(work)
        let task = try filedTask(in: context, area: work)
        var opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.title = "Mine"
        draft.dueDateKey = "2026-10-30"

        task.title = "Theirs"
        task.dueDate = "2026-10-26"
        task.scheduledDate = "2026-10-21"
        try context.save()
        CadenceScheduleDraft.rebase(draft: &draft, opened: &opened, onto: CadenceScheduleDraft(editing: task))

        #expect(draft.title == "Mine", "an outside rename replaced what the user typed")
        #expect(draft.dueDateKey == "2026-10-30")
        #expect(opened.title == "Report" && opened.dueDateKey == "2026-10-23", "the opened read of a moved field changed")
        #expect(draft.startDateKey == "2026-10-21", "the untouched do date did not follow")
        #expect(CadenceTaskSheetUnsavedWork.draftDiffers(draft, from: opened), "the user's edit no longer reads as unsaved")

        #expect(CadenceTaskEditDraftCommit.save(
            draft, opened: opened, to: task, area: work, project: nil,
            allTasks: [task], scope: .thisTask, in: context, reconciler: .inert
        ))
        let saved = try #require(try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first)
        #expect(saved.title == "Mine")
        #expect(saved.dueDate == "2026-10-30")
        #expect(saved.scheduledDate == "2026-10-21")
    }

    @Test("A moved estimate keeps its length on a do slot moved elsewhere")
    func aMovedEstimateFollowsAnOutsideSlot() throws {
        let (_, context) = try store()
        let work = Area(name: "Work")
        context.insert(work)
        let task = try filedTask(in: context, area: work)
        var opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.setEstimate(45)

        task.scheduledDate = "2026-10-21"
        task.scheduledStartMin = 14 * 60
        task.estimatedMinutes = 90
        try context.save()
        CadenceScheduleDraft.rebase(draft: &draft, opened: &opened, onto: CadenceScheduleDraft(editing: task))

        #expect(draft.startDateKey == "2026-10-21" && draft.startMin == 14 * 60, "the untouched slot did not follow")
        #expect(draft.estimateMinutes == 45, "the user's estimate was replaced")
        #expect(draft.endMin == 14 * 60 + 45, "the block was not redrawn at the new start")
        #expect(opened.estimateMinutes == 30, "the opened estimate moved")
    }

    @Test("A moved series is kept whole")
    func aMovedSeriesIsKeptWhole() throws {
        let (_, context) = try store()
        let work = Area(name: "Work")
        context.insert(work)
        let task = try filedTask(in: context, area: work)
        var opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.repeatRule = .daily

        task.recurrenceRule = .weekly
        task.title = "Renamed elsewhere"
        try context.save()
        CadenceScheduleDraft.rebase(draft: &draft, opened: &opened, onto: CadenceScheduleDraft(editing: task))

        #expect(draft.repeatRule == .daily, "an outside rule replaced the one the user picked")
        #expect(opened.repeatRule == .none, "the opened rule moved, so Save may not see the user's change")
        #expect(draft.changesRecurrence(from: opened))
        #expect(draft.title == "Renamed elsewhere")
    }

    @Test("A slot Save would not write follows the store")
    func aSlotSaveWouldNotWriteFollowsTheStore() throws {
        let (_, context) = try store()
        let work = Area(name: "Work")
        context.insert(work)
        let task = try filedTask(in: context, area: work)
        task.scheduledStartMin = -1
        try context.save()
        var opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        // Time switched on, moved, and switched off again: the clock the panel keeps differs,
        // but `changesSlot` reads no change, so Save would write no slot at all.
        draft.startMin = 13 * 60
        #expect(!draft.changesSlot(from: opened))

        task.scheduledDate = "2026-10-21"
        try context.save()
        CadenceScheduleDraft.rebase(draft: &draft, opened: &opened, onto: CadenceScheduleDraft(editing: task))

        #expect(draft.startDateKey == "2026-10-21", "the panel kept a do date Save would not write")
        #expect(!CadenceTaskSheetUnsavedWork.draftDiffers(draft, from: opened))
    }

    @Test("A series Save would not write follows the store")
    func aSeriesSaveWouldNotWriteFollowsTheStore() throws {
        let (_, context) = try store()
        let work = Area(name: "Work")
        context.insert(work)
        let task = try filedTask(in: context, area: work)
        var opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        // An end condition on a task that does not repeat: `changesRecurrence` reads no change.
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 3
        #expect(!draft.changesRecurrence(from: opened))

        task.recurrenceRule = .weekly
        try context.save()
        CadenceScheduleDraft.rebase(draft: &draft, opened: &opened, onto: CadenceScheduleDraft(editing: task))

        #expect(draft.repeatRule == .weekly, "the panel kept a series Save would not write")
        #expect(!draft.changesRecurrence(from: opened), "an adopted rule would ask the series question")
    }

    @Test("A read of another task changes nothing")
    func aReadOfAnotherTaskChangesNothing() throws {
        let (_, context) = try store()
        let work = Area(name: "Work")
        context.insert(work)
        let task = try filedTask(in: context, area: work)
        let other = AppTask(title: "Someone else")
        other.dueDate = "2026-12-01"
        context.insert(other)
        try context.save()
        var opened = CadenceScheduleDraft(editing: task)
        var draft = opened
        draft.priority = .high
        let (openedBefore, draftBefore) = (opened, draft)

        CadenceScheduleDraft.rebase(draft: &draft, opened: &opened, onto: CadenceScheduleDraft(editing: other))

        #expect(draft == draftBefore, "another task's fields were adopted into this one's draft")
        #expect(opened == openedBefore)
    }
}
