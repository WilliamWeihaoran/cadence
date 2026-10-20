import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexCaptureSectionBatchTests {
    @Test func captureEstimateLabelIsOptInAndDoesNotChangeOtherPickerCallers() throws {
        let ordinary = EstimatePickerPopoverContent(value: .constant(0))
        let capture = EstimatePickerPopoverContent(value: .constant(0), unsetValueLabel: "Clear estimate")
        let committing = EstimatePickerPopoverContent(value: 0, onCommit: { _ in true })
        #expect(ordinary.unsetValueLabel == "None")
        #expect(committing.unsetValueLabel == "None")
        #expect(capture.unsetValueLabel == "Clear estimate")
        let read = CadenceSourceScan.strippedSourceReader()
        let picker = try read("Cadence/Shared/Components/EstimatePickerControl.swift")
        #expect(picker.contains("struct EstimatePickerPopoverContent: View"))
        #expect(picker.contains("Text(total > 0 ? CadenceTaskPresentationSupport.estimateLabel(minutes: total) : unsetValueLabel)"))
        let card = try read("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        #expect(card.contains("private var estimateBinding: Binding<Int>"))
        #expect(card.contains("EstimatePickerPopoverContent(value: estimateBinding"))
        #expect(card.contains("unsetValueLabel: \"Clear estimate\""))
    }

    @Test func captureSectionEntryPointsShareOneCommittedControlAndLeaveBoardMappingIntact() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let mac = try read("Cadence/macOS/Views/ListDetailComponents.swift")
        let ios = try read("Cadence/iOS/iOSListDetailView.swift")
        let control = try read("Cadence/Shared/Components/CadenceSectionCreationRow.swift")
        #expect(mac.contains("struct ListTasksView: View"))
        #expect(ios.contains("struct iOSListDetailView: View"))
        #expect(control.contains("struct CadenceSectionCreationRow: View"))
        let spelling = "CadenceSectionCreationRow(area: area, project: project)"
        #expect(mac.components(separatedBy: spelling).count - 1 == 1)
        #expect(ios.components(separatedBy: spelling).count - 1 == 2, "empty and populated lists both need the control")
        let add = try #require(CadenceSourceScan.functionBody(named: "addSection", in: control))
        #expect(add.contains("CadenceSectionEditingSupport.createSection("))
        #expect(add.contains("guard failureNotice == nil else { return }"))
        let guardRange = try #require(add.range(of: "guard failureNotice == nil"))
        let cancel = try #require(add.range(of: "cancel()"))
        #expect(guardRange.upperBound < cancel.lowerBound)
        let board = try read("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        #expect(board.contains("ListSectionKanbanColumn("))
        #expect(board.contains("ForEach(columns, id: \\.id)"))
        #expect(board.contains("cardsBySectionName[section.name] ?? []"))
    }

    @Test func captureCardRenderingUsesTheTestedInventoryAndStablePopoverOwner() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let host = try read("Cadence/iOS/iOSCreateTaskSheet.swift")
        let panel = try read("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        let card = try read("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift")
        #expect(host.contains("struct iOSCreateTaskSheet: View"))
        #expect(host.contains("CadenceSchedulePanel("))
        #expect(host.contains(".capturePresentation("))
        #expect(panel.contains("if let captureOptions"))
        #expect(panel.contains("CadenceScheduleCaptureCard("))
        #expect(panel.contains("draft: $draft"))
        #expect(card.contains("struct CadenceScheduleCaptureCard"))
        let fields = try #require(CadenceSourceScan.declarationBody("private var fields: [CadenceCaptureField]", in: CadenceSourceScan.codeOnly(card)))
        #expect(fields.contains("CadenceCaptureFieldInventory.fields("))
        #expect(fields.contains("for: draft.kind"))
        #expect(fields.contains("offersTaskRepeat: offersTaskRepeat"))
        #expect(fields.contains("offersEventRepeat: offersEventRepeat"))
        #expect(card.contains("let dates = fields.filter { ($0 == .doDate || $0 == .dueDate) && isSet($0) }"))
        #expect(card.contains("let rest = fields.filter(restCarriesChip)"))
        #expect(card.contains("ForEach(fields.filter { !isSet($0)"))
        #expect(card.contains(".popover(item: $activeField)"))
        // The switch is `CadenceScheduleKindSwitch`, shared with the standard panel, and not a
        // `Picker(.segmented)`: `Cadence/iOS` and `Cadence/Shared` draw no native pickers, which
        // `SettingsSharedVocabularyTests.noMobileOrSharedSurfaceDrawsANativePicker` enforces.
        #expect(card.contains("CadenceScheduleKindSwitch(kind: kindBinding"))
        #expect(card.contains("Button(\"Repeat\", systemImage: \"repeat\")"))
        let create = try #require(CadenceSourceScan.functionBody(named: "create", in: host))
        #expect(create.contains("creation.repeatRule = draft.repeatRule"))
        #expect(create.contains("creation.seriesEndMode = draft.seriesEndMode"))
        #expect(create.contains("creation.seriesEndDateKey = draft.seriesEndDateKey"))
        #expect(create.contains("creation.seriesEndCount = draft.seriesEndCount"))
    }

    @Test func captureCardIconsKeepTheirRelativeOrderAndClearingRestoresEveryTaskField() {
        var draft = CadenceScheduleDraft(dateKey: "2026-10-17", startMin: 600)
        draft.clearDoDate()
        let icons = CadenceCaptureFieldInventory.taskIcons
        #expect(icons == [.doDate, .dueDate, .list, .tags])
        #expect(CadenceCaptureFieldInventory.overflow == [.repeatRule, .priority, .estimate])
        for mask in 0..<16 {
            var candidate = draft
            candidate.startDateKey = mask & 1 == 0 ? "" : "2026-10-20"
            candidate.dueDateKey = mask & 2 == 0 ? "" : "2026-10-22"
            candidate.listToken = CadenceTaskComposerSupport.token(for: mask & 4 == 0 ? .inbox : .area(UUID()))
            let tags: Set<String> = mask & 8 == 0 ? [] : ["tag"]
            let expected = icons.enumerated().filter { mask & (1 << $0.offset) == 0 }.map(\.element)
            #expect(icons.filter { !CadenceCaptureFieldInventory.isSet($0, draft: candidate, tagIDs: tags) } == expected)
        }
        #expect(icons.filter { !CadenceCaptureFieldInventory.isSet($0, draft: draft, tagIDs: []) } == icons)
        draft.startDateKey = "2026-10-20"
        draft.dueDateKey = "2026-10-22"
        draft.listToken = CadenceTaskComposerSupport.token(for: .area(UUID()))
        draft.repeatRule = .weekly
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 5
        draft.priority = .high
        draft.estimateIsExplicit = true
        for field in CadenceCaptureFieldInventory.fields(for: .task) where field != .tags {
            #expect(CadenceCaptureFieldInventory.isSet(field, draft: draft, tagIDs: []), "non-vacuity: \(field)")
            CadenceCaptureFieldInventory.clear(field, draft: &draft)
            #expect(!CadenceCaptureFieldInventory.isSet(field, draft: draft, tagIDs: []))
        }
        #expect(draft.seriesEndMode == .never)
        #expect(draft.seriesEndCount == 0)
        #expect(draft.estimateMinutes == CadenceTaskComposerSupport.defaultEstimatedMinutes)
        #expect(icons.filter { !CadenceCaptureFieldInventory.isSet($0, draft: draft, tagIDs: []) } == icons)
        #expect(CadenceCaptureFieldInventory.isSet(.tags, draft: draft, tagIDs: ["tag"]))
    }

    @Test func captureCardKindSwitchRestoresMetadataAndUntimedTaskWhileSharingOnlyTitleAndNotes() {
        var memory = CadenceCaptureKindMemory()
        var draft = CadenceScheduleDraft(dateKey: "2026-10-17", startMin: 600)
        draft.clearDoDate()
        draft.dueDateKey = "2026-10-25"
        draft.priority = .high
        draft.listToken = CadenceTaskComposerSupport.token(for: .project(UUID()))
        let original = draft
        memory.select(.event, draft: &draft)
        #expect(draft.kind == .event)
        #expect(!draft.startDateKey.isEmpty)
        #expect(!draft.isAllDay)
        draft.location = "Library"
        draft.calendarID = "writable-calendar"
        draft.startDateKey = "2026-10-23"
        draft.endDateKey = "2026-10-24"
        draft.title = "Shared title"
        draft.notes = "Shared notes"
        memory.select(.task, draft: &draft)
        #expect(draft.kind == .task)
        #expect(draft.startDateKey.isEmpty)
        #expect(draft.isAllDay)
        #expect(draft.dueDateKey == original.dueDateKey)
        #expect(draft.listToken == original.listToken)
        #expect(draft.priority == original.priority)
        #expect(draft.title == "Shared title")
        #expect(draft.notes == "Shared notes")
        memory.select(.event, draft: &draft)
        #expect(draft.location == "Library")
        #expect(draft.calendarID == "writable-calendar")
        #expect(draft.startDateKey == "2026-10-23")
        #expect(draft.endDateKey == "2026-10-24")
    }

    @Test func captureRecurrenceAndItsLimitExistBeforeTheSingleCreationCommit() throws {
        let store = try CadenceTestStore.container()
        let context = ModelContext(store)
        var draft = creationDraft()
        draft.repeatRule = .monthly
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 4
        var commits = 0
        let created = try TaskCreationService(areas: [], projects: []).createTask(from: draft, into: context, commit: { context in
            commits += 1
            let inserted = try #require(context.fetch(FetchDescriptor<AppTask>()).first)
            #expect(inserted.recurrenceRule == .monthly)
            #expect(inserted.recurrenceEndMode == .afterCount)
            #expect(inserted.recurrenceEndCount == 4)
            #expect(!inserted.recurrenceSeriesIDRaw.isEmpty)
            try context.save()
        })
        let task = try #require(created)
        #expect(commits == 1)
        let reader = ModelContext(store)
        let stored = try #require(reader.fetch(FetchDescriptor<AppTask>()).first)
        #expect(stored.id == task.id)
        #expect(stored.recurrenceRule == .monthly)
        #expect(stored.recurrenceEndCount == 4)
    }

    @Test func captureRecurrenceSaveRefusalRemovesTheWholeInsertionAndPreservesUnrelatedEdits() throws {
        struct Refused: Error {}
        let context = ModelContext(try CadenceTestStore.container())
        let existing = AppTask(title: "Original")
        context.insert(existing)
        try context.save()
        existing.title = "Unrelated pending edit"
        var draft = creationDraft()
        draft.repeatRule = .daily
        draft.seriesEndMode = .onDate
        draft.seriesEndDateKey = "2026-11-01"
        var commits = 0
        #expect(throws: Refused.self) {
            _ = try TaskCreationService(areas: [], projects: []).createTask(from: draft, into: context, commit: { _ in
                commits += 1
                throw Refused()
            })
        }
        #expect(commits == 1)
        #expect(existing.title == "Unrelated pending edit")
        let remaining = try context.fetch(FetchDescriptor<AppTask>())
        #expect(remaining.map(\.id) == [existing.id])
        #expect(context.hasChanges)
    }

    @Test func captureCreationKeepsLegacyNonRecurringDefaultsAndUsesExistingEndNormalization() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let service = TaskCreationService(areas: [], projects: [])
        let created = try service.createTask(from: creationDraft(), into: context)
        let ordinary = try #require(created)
        #expect(ordinary.recurrenceRule == .none)
        #expect(ordinary.recurrenceSeriesIDRaw.isEmpty)
        for mode in TaskRecurrenceEndMode.allCases {
            var draft = creationDraft()
            draft.repeatRule = .yearly
            draft.seriesEndMode = mode
            draft.seriesEndDateKey = "2027-10-17"
            draft.seriesEndCount = 3
            let created = try service.createTask(from: draft, into: context)
            let task = try #require(created)
            #expect(task.recurrenceRule == .yearly)
            #expect(task.recurrenceEndMode == mode)
            #expect(task.recurrenceEndDate == (mode == .onDate ? "2027-10-17" : ""))
            #expect(task.recurrenceEndCount == (mode == .afterCount ? 3 : 0))
        }
    }

    private func creationDraft() -> TaskCreationDraft {
        TaskCreationDraft(title: "Capture", notes: "", priority: .none, container: .inbox,
                          sectionName: TaskSectionDefaults.defaultName, dueDateKey: "", scheduledDateKey: "2026-10-17",
                          subtaskTitles: [], tags: [])
    }

    @Test func captureSectionsRefuseBlankAndCaseInsensitiveDuplicateNamesBeforeCommitting() throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Work")
        area.sectionConfigs = [TaskSectionConfig(name: "Doing")]
        modelContext.insert(area)
        try modelContext.save()
        let before = area.sectionConfigs
        var commits = 0
        for (name, expected) in [
            (" \n ", KanbanColumnRenameRefusal.emptyName.notice),
            (" dOiNg ", KanbanColumnRenameRefusal.nameAlreadyTaken.notice),
        ] {
            let notice = CadenceSectionEditingSupport.createSection(
                named: name,
                colorHex: area.colorHex,
                in: area,
                modelContext: modelContext,
                commit: { _ in commits += 1 }
            )
            #expect(notice == expected)
            #expect(area.sectionConfigs == before)
        }
        #expect(commits == 0)
        #expect(!modelContext.hasChanges)
    }

    @Test func captureSectionsCommitAnAreasNewEmptyColumnWithoutChangingItsExistingMetadata() throws {
        let container = try CadenceTestStore.container()
        let modelContext = ModelContext(container)
        let area = Area(name: "Work")
        let existing = TaskSectionConfig(name: "Doing", dueDate: "2026-10-30")
        area.sectionConfigs = [existing]
        let before = area.sectionConfigs
        modelContext.insert(area)
        try modelContext.save()
        #expect(CadenceSectionEditingSupport.createSection(
            named: "  Review  ", colorHex: area.colorHex, in: area, modelContext: modelContext
        ) == nil)
        let reader = ModelContext(container)
        let stored = try #require(reader.fetch(FetchDescriptor<Area>()).first)
        #expect(Array(stored.sectionConfigs.prefix(before.count)) == before)
        #expect(stored.sectionConfigs.first { $0.uuid == existing.uuid } == existing)
        let added = try #require(stored.sectionConfigs.first { $0.name == "Review" })
        #expect(added.colorHex == area.colorHex)
        #expect(added.uuid != existing.uuid)
        #expect(try reader.fetchCount(FetchDescriptor<AppTask>()) == 0)
        #expect(!modelContext.hasChanges)
    }

    @Test func captureSectionsCommitAProjectsSectionThroughTheSamePath() throws {
        let container = try CadenceTestStore.container()
        let modelContext = ModelContext(container)
        let project = Project(name: "Launch")
        modelContext.insert(project)
        try modelContext.save()
        #expect(CadenceSectionEditingSupport.createSection(
            named: "Review", colorHex: project.colorHex, in: project, modelContext: modelContext
        ) == nil)
        let reader = ModelContext(container)
        let stored = try #require(reader.fetch(FetchDescriptor<Project>()).first)
        #expect(stored.sectionConfigs.contains { $0.name == "Review" })
    }

    @Test func captureSectionsKeepUnrelatedPendingEditsAndOriginalColumnsOnSaveRefusal() throws {
        struct Refused: Error {}
        let modelContext = ModelContext(try CadenceTestStore.container())
        let project = Project(name: "Launch")
        let task = AppTask(title: "Original")
        project.sectionConfigs = [TaskSectionConfig(name: TaskSectionDefaults.defaultName)]
        modelContext.insert(project)
        modelContext.insert(task)
        try modelContext.save()
        let before = project.sectionConfigs
        task.title = "Unrelated pending edit"
        var commits = 0
        let notice = CadenceSectionEditingSupport.createSection(
            named: "Review", colorHex: project.colorHex, in: project, modelContext: modelContext,
            commit: { _ in
                commits += 1
                throw Refused()
            }
        )
        #expect(commits == 1, "non-vacuity: the injected refusal must be reached")
        #expect(notice == CadenceSectionConfigAddOutcome.refusalNotice)
        #expect(project.sectionConfigs == before)
        #expect(task.title == "Unrelated pending edit")
        #expect(modelContext.hasChanges)
    }
}
