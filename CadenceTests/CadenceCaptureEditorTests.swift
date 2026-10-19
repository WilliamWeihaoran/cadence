import SwiftUI
import Testing
@testable import Cadence

@Suite("Capture card preserves record editing")
@MainActor
struct CadenceCaptureEditorTests {
    @Test func anExistingCaptureRecordCannotChangeKind() {
        for subject in [CadenceScheduleDraft.Subject.editingTask(UUID()), .editingEvent("fixture")] {
            var draft = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 600, kind: .task)
            draft.subject = subject
            let opened = draft
            var memory = CadenceCaptureKindMemory()
            memory.select(.event, draft: &draft)
            #expect(draft == opened)
        }
        var creating = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 600, kind: .task)
        var memory = CadenceCaptureKindMemory()
        memory.select(.event, draft: &creating)
        #expect(creating.kind == .event)
    }

    @Test func captureEditorsOfferOnlyFieldsTheirHostsCanWrite() {
        let task = CadenceCaptureFieldInventory.fields(for: .task, offersTaskRepeat: false)
        #expect(!task.contains(.repeatRule))
        #expect(task.contains(.dueDate))
        #expect(task.contains(.estimate))
        let event = CadenceCaptureFieldInventory.fields(for: .event, offersEventRepeat: false)
        #expect(!event.contains(.repeatRule))
        #expect(event.contains(.location))
        #expect(event.contains(.calendar))
        #expect(CadenceCaptureFieldInventory.fields(for: .event).contains(.repeatRule))
    }

    @Test func clearingAnEditedEstimateMeansNoneWithoutRewritingTheTitle() {
        var draft = CadenceScheduleDraft(dateKey: "2026-10-19", startMin: 600, kind: .task)
        draft.subject = .editingTask(UUID())
        draft.title = "!! Keep this literal title"
        #expect(TaskTitleSupport.priorityShortcut(in: draft.title) != nil)
        draft.setEstimate(20)
        draft.estimateIsExplicit = true
        #expect(CadenceCaptureFieldInventory.isSet(.estimate, draft: draft, tagIDs: []))
        CadenceCaptureFieldInventory.clear(.estimate, draft: &draft)
        #expect(draft.estimateMinutes == 0)
        #expect(!draft.estimateIsExplicit)
        CadenceCaptureFieldInventory.clear(.priority, draft: &draft)
        #expect(draft.title == "!! Keep this literal title")
        #expect(CadenceCaptureFieldInventory.priority(for: draft) == .none)
        #expect(!CadenceCaptureFieldInventory.isSet(.priority, draft: draft, tagIDs: []))
        draft.subject = .creating
        CadenceCaptureFieldInventory.clear(.estimate, draft: &draft)
        #expect(draft.estimateMinutes == CadenceTaskComposerSupport.defaultEstimatedMinutes)
    }

    private func source(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 1_000)
        return CadenceSourceScan.strippingComments(raw)
    }

    @Test func bothRecordEditorsPresentTheCaptureCard() throws {
        for name in ["iOSTaskDetailSheet", "iOSCalendarEventEditSheet"] {
            let host = try source("Cadence/iOS/\(name).swift")
            #expect(host.contains(".capturePresentation(CadenceScheduleCaptureOptions())"))
            #expect(host.contains(".presentationBackground(.clear)"))
            #expect(host.contains(".interactiveDismissDisabled(draft != openedDraft)"))
            #expect(!host.contains("NavigationStack {"))
        }
        let task = try source("Cadence/iOS/iOSTaskDetailSheet.swift")
        let sections = try #require(CadenceSourceScan.declarationBody("private var recordSections: some View", in: task))
        #expect(sections.contains("statusActionsSection"))
        let status = try #require(CadenceSourceScan.declarationBody("private var statusActionsSection: some View", in: task))
        #expect(status.contains("onToggleCompletion: toggleCompletion"))
        #expect(task.contains("showDeleteConfirmation = true"))
        #expect(task.contains("notesText: $draft.notes"))
    }

    @Test func captureForwardsAndEnforcesReadOnlyAndStatus() throws {
        let panel = try source("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        let card = try source("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        let route = try #require(CadenceSourceScan.declarationBody("var body: some View", in: panel))
        for parameter in ["readOnlyNotice", "titleStatus", "offersTaskRepeat", "offersEventRepeat"] {
            #expect(route.contains("\(parameter): \(parameter)"))
        }
        #expect(card.contains("isEditing: draft.subject.isEditing"))
        #expect(card.contains("if !isReadOnly, let delete = actions.delete"))
        #expect(card.contains("Text(\"Save\")"))
        #expect(card.contains(".strikethrough(titleStatus?.isSettled == true)"))
        #expect(card.contains("if notesField == nil || !draft.subject.isEditing"))
        #expect(card.contains("if fields.contains(.repeatRule)"))
        #expect(card.contains(".cadenceFont(.editorTitle)"))
        let commit = try #require(CadenceSourceScan.functionBody(named: "commit", in: card))
        #expect(commit.contains("guard !isReadOnly, canCommit"))
        #expect(CadenceSourceScan.matchCount(#"\.disabled\(isReadOnly\)"#, in: card) >= 5)
    }
}
