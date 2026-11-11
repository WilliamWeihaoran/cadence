import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-14471]]: a task created from a calendar slot on iPhone or iPad keeps the series' END, not
/// only its rule.
///
/// `iOSScheduleDraftCreation.createTask` -- the write behind the Calendar page's slot sheet and the
/// iPad timeline's draft panel -- configured the new task through a private copy that applied the
/// Repeat rule and never the Ends answer, so "Weekly, after 5 times" was stored as an endless
/// series. That configuration is `CadenceScheduleDraftTaskWrite.configure` in `Shared/` now, so it
/// is run here: through the same `insertScheduledTask` the iOS write uses, read back from a SECOND
/// store context, so a value that lived only in the writing context does not count. The iOS half
/// is behind `#if os(iOS)`, so that it calls the shared write is pinned by reading its body.
@MainActor
@Suite("Schedule draft task series end")
struct CadenceScheduleDraftTaskSeriesEndTests {

    private func weeklyTaskDraft() -> CadenceScheduleDraft {
        var draft = CadenceScheduleDraft(dateKey: "2026-11-09", startMin: 9 * 60, kind: .task)
        draft.title = "Standup"
        draft.repeatRule = .weekly
        return draft
    }

    /// The draft-to-task write both iOS hosts make, stored and read back.
    private func storedTask(from draft: CadenceScheduleDraft) throws -> AppTask {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        _ = try #require(try CadenceTaskMutationSupport.insertScheduledTask(
            title: draft.title, allTasks: [], modelContext: ModelContext(container),
            scheduledDate: draft.startDateKey, scheduledStartMin: draft.scheduledStartMin,
            estimatedMinutes: draft.estimateMinutes,
            configure: { task in
                CadenceScheduleDraftTaskWrite.configure(task, from: draft, area: nil, project: nil, allTasks: [])
            },
            refusing: false
        ))
        let tasks = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(tasks.count == 1)
        return try #require(tasks.first)
    }

    @Test("Weekly, after 5 times, is stored as five occurrences")
    func anAfterCountEndIsStored() throws {
        var draft = weeklyTaskDraft()
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 5

        let task = try storedTask(from: draft)
        #expect(task.recurrenceRule == .weekly, "non-vacuity: the rule itself did not land")
        #expect(task.recurrenceEndMode == .afterCount, "the series' end was dropped")
        #expect(task.recurrenceEndCount == 5)
        #expect(task.recurrenceEndDate.isEmpty)
    }

    @Test("Weekly, ending on a day, is stored with that day")
    func anOnDateEndIsStored() throws {
        var draft = weeklyTaskDraft()
        draft.seriesEndMode = .onDate
        draft.seriesEndDateKey = "2026-12-24"

        let task = try storedTask(from: draft)
        #expect(task.recurrenceEndMode == .onDate, "the series' end was dropped")
        #expect(task.recurrenceEndDate == "2026-12-24")
        #expect(task.recurrenceEndCount == 0)
    }

    /// The RESOLVED mode is what is written, as the Mac and `+` paths write it: an After count of
    /// zero is "never", not a one-occurrence series invented by `applyRecurrenceEnd`'s floor.
    @Test("An unfinished Ends answer is stored as never")
    func anUnresolvedEndIsStoredAsNever() throws {
        var draft = weeklyTaskDraft()
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 0

        let task = try storedTask(from: draft)
        #expect(task.recurrenceRule == .weekly)
        #expect(task.recurrenceEndMode == .never)
        #expect(task.recurrenceEndCount == 0)
    }

    /// [[T-16371]]: a `!`/`!!`/`!!!` marker in the title outranks the Priority chip, as it does on
    /// the `+` sheet and every Mac composer (`TaskCreationDraft.resolvedPriority`), and as the
    /// capture card itself shows it (`CadenceCaptureFieldInventory.priority(for:)`). The slot sheet
    /// and the iPad timeline panel let the chip win, so `Ship it !!!` typed after picking Low read
    /// High on the card and was saved Low.
    @Test("A title marker outranks the Priority chip, as on the + sheet and the Mac")
    func aTitleMarkerOutranksThePriorityChip() throws {
        var draft = CadenceScheduleDraft(dateKey: "2026-11-09", startMin: 9 * 60, kind: .task)
        draft.title = "Ship it !!!"
        draft.priority = .low

        let task = try storedTask(from: draft)
        let plusSheet = CadenceTaskComposerSupport.creationDraft(
            from: draft, container: .inbox, tags: [], subtaskTitles: []
        )
        #expect(task.title == "Ship it", "non-vacuity: the marker was not read at all")
        #expect(task.priority == plusSheet.resolvedPriority, "the slot write and the + sheet disagree")
        #expect(task.priority == CadenceCaptureFieldInventory.priority(for: draft), "saved unlike the card showed")
        #expect(task.priority == .high)
    }

    /// The slot sheet and timeline panel store notes trimmed, as the `+` sheet does
    /// (`TaskCreationDraft.trimmedNotes`, [[T-16373]]); a trailing newline no longer survives as a
    /// blank last line from one entry point only.
    @Test("Slot and timeline notes are stored trimmed, as the + sheet stores them")
    func notesAreStoredTrimmedLikeThePlusSheet() throws {
        var draft = CadenceScheduleDraft(dateKey: "2026-11-09", startMin: 9 * 60, kind: .task)
        draft.title = "Ship it"
        draft.notes = "  Bring the charger\n\n"

        let task = try storedTask(from: draft)
        let plusSheet = CadenceTaskComposerSupport.creationDraft(
            from: draft, container: .inbox, tags: [], subtaskTitles: []
        )
        #expect(plusSheet.notes == draft.notes, "non-vacuity: the + sheet draft did not carry the notes")
        #expect(task.notes == plusSheet.trimmedNotes, "the slot write and the + sheet disagree")
        #expect(task.notes == "Bring the charger")
    }

    /// The chip still decides when the title carries no marker.
    @Test("With no title marker the Priority chip is what is stored")
    func theChipDecidesWithoutAMarker() throws {
        var draft = CadenceScheduleDraft(dateKey: "2026-11-09", startMin: 9 * 60, kind: .task)
        draft.title = "Ship it"
        draft.priority = .low

        let task = try storedTask(from: draft)
        #expect(task.priority == .low)
    }

    /// The iOS write configures through the shared function and keeps no private copy of it.
    @Test("The iOS slot and timeline task write configures through the shared write")
    func theIOSTaskWriteUsesTheSharedConfiguration() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTimelineDraftCreate.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        let body = try #require(
            CadenceSourceScan.functionBody(named: "createTask", in: code),
            "could not find iOSScheduleDraftCreation.createTask"
        )
        #expect(body.contains("CadenceTaskMutationSupport.insertScheduledTask("), "non-vacuity: not the task write")
        #expect(
            CadenceSourceScan.matchCount(#"CadenceScheduleDraftTaskWrite\.configure\("#, in: body) == 1,
            "the iOS task write no longer configures through the shared write"
        )
        #expect(CadenceSourceScan.functionBody(named: "configure", in: code) == nil, "a private configure copy is back")
        #expect(!code.contains("applyRecurrenceRule("), "the iOS file applies a repeat rule of its own")
    }
}
