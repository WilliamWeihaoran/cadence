import Foundation
import SwiftData
import Testing
@testable import Cadence

@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceCodexTrackingUIRetirementTests {
    @Test func codexTaskSurfacesHaveNoTrackingControlsOrQueries() throws {
        let instrument = try CadenceScanInstrument(
            "retired tracking controls on task surfaces",
            fires: "@Query private var goals: [Goal]; task.goal = selected",
            andNotOn: "var list: GoalLinkTarget?; task.project = selected"
        ) { source in
            let code = CadenceSourceScan.codeOnly(source)
            return CadenceSourceScan.matchCount(
                #"\b(?:Goal|Habit|HabitCompletion|GoalListLink)\b|\.\s*goal\b|\b(?:milestoneRow|showMilestonePicker|iOSTaskRowGoalChip)\b"#,
                in: code
            ) > 0 || CadenceSourceScan.matchCount(
                #"\b(?:goals?|habits?|milestones?)\b"#,
                in: CadenceSourceScan.strippingComments(source).lowercased()
            ) > 0
        }
        #expect(instrument.fires(on: "Text(\"Milestone\")"))
        #expect(!instrument.fires(on: "// The retired milestone chip."))
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence").filter {
            let name = URL(fileURLWithPath: $0).lastPathComponent
            return ($0.contains("/iOS/") && name.hasPrefix("iOSTask"))
                || ($0.contains("/macOS/Views/") && name.hasPrefix("TaskInspector"))
        }
        let hits = try instrument.sweep(
            paths, atLeast: 10, including: "Cadence/iOS/iOSTaskDetailSheetSections.swift",
            read: { try CadenceSourceScan.sourceFile($0) }
        )
        #expect(hits.isEmpty, "tracking UI remains in \(hits)")
        let sections = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailSheetSections.swift")
        #expect(sections.contains("struct iOSTaskFieldListSection: View"))
        #expect(sections.contains("repeatRow"))
        #expect(sections.contains("loggedRow"))
    }

    @Test func codexRetiredTrackingViewsStayOutsideTheLiveViewGraph() throws {
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let retired = paths.filter { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return (path.contains("/macOS/Views/") && (name.hasPrefix("Goal") || name.hasPrefix("Habit")))
                || path == "Cadence/iOS/iOSFeatureViews.swift"
                || path == "Cadence/iOS/iOSFeatureDetailViews.swift"
                || path == "Cadence/Shared/Components/HabitProgressViews.swift"
                || path == "Cadence/Shared/Components/GoalProgressBar.swift"
        }
        var names = Set<String>()
        for path in retired {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            names.formUnion(CadenceSourceScan.captures(
                #"\bstruct\s+(\w+)(?:<[^{}]*>)?\s*:\s*View\b"#, in: code
            ).map(\.text))
        }
        #expect(names.count >= 50, "the retired view inventory stopped reading its declarations")
        #expect(names.contains("GoalsView"))
        #expect(names.contains("HabitsView"))
        #expect(names.contains("iOSGoalDetail"))
        #expect(names.contains("HabitInfoCard"))
        let pattern = #"\b(?:"# + names.sorted().joined(separator: "|") + #")\b"#
        let instrument = try CadenceScanInstrument(
            "a live surface references a retired tracking view",
            fires: "GoalInspectorView(goal: archived)",
            andNotOn: "let goal = Goal(title: archived)"
        ) { CadenceSourceScan.matchCount(pattern, in: $0) > 0 }
        let retiredPaths = Set(retired)
        let hits = try instrument.sweep(
            paths.filter { !retiredPaths.contains($0) }, atLeast: 500,
            including: "Cadence/iOS/iOSRootView.swift",
            read: { CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0)) }
        )
        #expect(hits.isEmpty, "a retired view is reachable through \(hits)")
    }

    @Test func codexTrackingArchivePreviewGroupsRecordsWithoutLosingCounts() {
        for mode in [CadenceArchiveImportMode.mergeKeepingExistingRows, .restoreOverwritingExistingRows] {
            let plan = CadenceArchiveImportPlan(
                mode: mode,
                insertCountsByEntityName: ["Goal": 2, "Habit": 1, "HabitCompletion": 3, "AppTask": 1],
                matchedCountsByEntityName: ["GoalListLink": 2, "Pursuit": 1, "Habit": 4],
                entityNamesOnlyInTheArchive: [], linkedCalendarCount: 0
            )
            let lines = CadenceArchiveImportPresentation.planLines(plan)
            #expect(lines.count == 2)
            #expect(lines.first?.title == "Retained legacy records")
            #expect(lines.first?.addedCount == 6)
            #expect(lines.first?.matchedCount == 7)
            #expect(lines.first?.mode == mode)
            #expect(lines.reduce(0) { $0 + $1.addedCount } == plan.totalInsertCount)
            #expect(lines.reduce(0) { $0 + $1.matchedCount } == plan.totalMatchedCount)
            #expect(plan.insertCountsByEntityName["Goal"] == 2)
            #expect(plan.matchedCountsByEntityName["Habit"] == 4)
        }
    }

    @Test func codexTrackingRetirementCopyStillDisclosesRetainedData() throws {
        let sourcePaths = [
            "Cadence/iOS/iOSDataResetSettingsSection.swift",
            "Cadence/macOS/Views/SettingsDataSafetySection.swift"
        ]
        let instrument = try CadenceScanInstrument(
            "retired feature names in reset copy", fires: "Text(\"Deletes goals and habits\")",
            andNotOn: "Text(\"Deletes retained legacy records\")"
        ) { CadenceSourceScan.matchCount(#"\b(?:goals?|habits?|milestones?)\b"#, in: $0.lowercased()) > 0 }
        let hits = try instrument.sweep(
            sourcePaths, atLeast: 2, including: sourcePaths[0],
            read: { CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile($0)) }
        )
        #expect(hits.isEmpty)
        for path in sourcePaths {
            let source = try CadenceSourceScan.sourceFile(path)
            #expect(source.contains("retained legacy record"))
            #expect(source.contains("CadenceUnmanagedStoreCopy.resetGateLeavesThem"))
        }
        for copy in [
            CadenceNotificationSettingsCopy.remindersToggleDetail,
            CadenceNotificationSettingsCopy.accessRequiredDetail,
            CadenceDataExportPresentation.description,
            CadenceListDeletionKind.context.cascadeSentence
        ] {
            #expect(!instrument.fires(on: copy))
        }
        var summary = CadenceListDeletionSummary()
        summary.goals = 1
        #expect(!summary.isEmpty)
        #expect(summary.lostItemLines == ["1 retained legacy record"])
        summary.habits = 2
        #expect(summary.lostItemLines == ["3 retained legacy records"])
    }

    @Test func codexDefaultProjectBriefDoesNotAdvertiseRetiredFeatures() throws {
        let template = try #require(NoteTemplateLibrary.defaultTemplate(id: "project-brief"))
        #expect(template.subtitle == "Objective, scope, deliverables")
        #expect(template.body.contains("## Objective"))
        #expect(template.body.contains("## Deliverables"))
        #expect(!template.body.contains("## Goal"))
        #expect(!template.body.contains("Milestone"))
    }

    @Test func codexTrackingBackendGraphSurvivesAnArchiveRoundTrip() throws {
        let source = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let context = Context(name: "Archived tracking")
        let area = Area(name: "Work", context: context)
        let goal = Goal(title: "Retained direction", context: context)
        let milestone = Goal(title: "Retained milestone", context: context)
        milestone.parentGoal = goal
        let habit = Habit(title: "Retained routine", context: context, goal: milestone)
        let completion = HabitCompletion(date: "2026-10-05", habit: habit)
        let link = GoalListLink(goal: goal, area: area)
        let task = AppTask(title: "Still a task")
        task.goal = milestone
        task.context = context
        source.insert(context)
        source.insert(area)
        source.insert(goal)
        source.insert(milestone)
        source.insert(habit)
        source.insert(completion)
        source.insert(link)
        source.insert(task)
        try source.save()

        let archive = try CadenceDataExportService.decode(
            CadenceDataExportService.encode(CadenceDataExportService.makeArchive(in: source))
        )
        #expect(archive.goals.count == 2)
        #expect(archive.habits.count == 1)
        #expect(archive.habitCompletions.count == 1)
        #expect(archive.goalListLinks.count == 1)
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let destination = ModelContext(container)
        try CadenceArchiveImportService.apply(archive, in: destination)
        let reader = ModelContext(container)
        let goals = try reader.fetch(FetchDescriptor<Goal>())
        #expect(Set(goals.map(\.id)) == [goal.id, milestone.id])
        #expect(goals.first { $0.id == milestone.id }?.parentGoal?.id == goal.id)
        #expect(try reader.fetch(FetchDescriptor<Habit>()).first?.goal?.id == milestone.id)
        #expect(try reader.fetch(FetchDescriptor<HabitCompletion>()).first?.habit?.id == habit.id)
        #expect(try reader.fetch(FetchDescriptor<GoalListLink>()).first?.goal?.id == goal.id)
        #expect(try reader.fetch(FetchDescriptor<AppTask>()).first?.goal?.id == milestone.id)
    }
}
