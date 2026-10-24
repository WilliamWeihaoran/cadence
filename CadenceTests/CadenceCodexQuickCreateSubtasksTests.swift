#if os(macOS)
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexQuickCreateSubtasksTests {
    private func draft() -> CadenceScheduleDraft {
        var draft = QuickCreateChoicePopover.openingDraft(
            dateKey: "2026-10-23", startMin: 600, endMin: 660,
            defaultsToCalendarEvent: false
        )
        draft.title = "Prepare release"
        draft.notes = "Keep the checklist"
        draft.subtaskTitles = ["  Review changes  ", "", "\t", "Run checks", "Review changes"]
        return draft
    }

    @Test func codexQuickCreateChecklistReachesASecondStoreContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let payload = QuickCreateTaskDraft(scheduleDraft: draft())
        let created = try #require(try SchedulePanelDataSupport.insertDragCreatedTask(
            payload, areas: [], projects: [], in: context
        ))
        let reader = ModelContext(container)
        let stored = try #require(try reader.fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.id == created.id)
        #expect(stored.notes == "Keep the checklist")
        let subtasks = (stored.subtasks ?? []).sorted { $0.order < $1.order }
        #expect(subtasks.map(\.title) == ["Review changes", "Run checks", "Review changes"])
        #expect(Set(subtasks.map(\.id)).count == 3)
        #expect(try reader.fetch(FetchDescriptor<Subtask>()).count == 3)
    }

    @Test func codexQuickCreateChecklistSurvivesKindSwitchAndKeepsOrder() {
        var draft = draft()
        let titles = draft.subtaskTitles
        draft.kind = .event
        draft.normalizeForKind()
        draft.kind = .task
        draft.normalizeForKind()
        #expect(draft.subtaskTitles == titles)
        #expect(QuickCreateTaskDraft(scheduleDraft: draft).subtaskTitles
                == ["Review changes", "Run checks", "Review changes"])
    }

    @Test func codexQuickCreateChecklistDefaultsOffForOtherPanelHosts() {
        let actions = CadenceSchedulePanelActions(commit: { nil }, cancel: {})
        let panel = CadenceSchedulePanel(draft: .constant(draft()), actions: actions)
        #expect(!panel.offersSubtasks)
        let enabled = CadenceSchedulePanel(
            draft: .constant(draft()), offersSubtasks: true, actions: actions
        )
        #expect(enabled.offersSubtasks)
        #expect(CadenceScheduleDraft(dateKey: "2026-10-23", startMin: 600).subtaskTitles.isEmpty)
    }

    @Test func codexQuickCreateChecklistIsWiredFromEditorThroughBothHosts() throws {
        func code(_ path: String) throws -> String {
            let source = try cadenceTestSource(path)
            #expect(source.count > 500)
            return CadenceSourceScan.codeOnly(source)
        }
        let panel = try code("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        #expect(panel.contains("if offersSubtasks { subtasksEditor }"))
        #expect(panel.contains("draft.subtaskTitles = $0.components(separatedBy:"))
        let popover = try code("Cadence/macOS/Views/QuickCreateChoicePopover.swift")
        #expect(popover.contains("offersSubtasks: true"))
        #expect(popover.contains("onCreateTask(QuickCreateTaskDraft(scheduleDraft: draft))"))
        let calendar = try code("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        #expect(calendar.contains("subtaskTitles: draft.subtaskTitles"))
        let createTask = try #require(CadenceSourceScan.functionBody(named: "createTask", in: calendar))
        #expect(createTask.contains("subtaskTitles: subtaskTitles"))
    }
}
#endif
