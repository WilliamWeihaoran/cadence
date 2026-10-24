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

    // MARK: - [[T-5002]]: the screens are gone, and the DATA is not

    /// **The fourteen files, by name, because a sweep cannot miss a list it is handed.**
    ///
    /// `codexRetiredTrackingViewsStayOutsideTheLiveViewGraph` built its inventory *by reading the
    /// retired files* and then asserted nothing else referenced those names. That shape cannot
    /// survive the files being deleted — with nothing to read, the inventory is empty and the
    /// sweep passes over everything — so the inventory is declared here instead. This is the
    /// inversion [[T-3078]] wrote down: a deletion with no inverted guard gets quietly undone.
    ///
    /// Both halves are asserted. **The files are not there**, which is the claim a re-added file
    /// breaks; and **no file under `Cadence/` declares or mentions any of the 55 names in code**,
    /// which is the claim a re-added *declaration somewhere else* breaks. The second is the one
    /// that matters: `GoalsView` reappearing inside `TasksPanel.swift` is the failure mode a
    /// path-only check cannot see.
    private static let retiredTrackingViewFiles = [
        "Cadence/macOS/Views/GoalsView.swift",
        "Cadence/macOS/Views/GoalsSupportViews.swift",
        "Cadence/macOS/Views/GoalInspectorView.swift",
        "Cadence/macOS/Views/GoalPickerViews.swift",
        "Cadence/macOS/Views/GoalTimelineView.swift",
        "Cadence/macOS/Views/GoalTimelineSupportViews.swift",
        "Cadence/macOS/Views/GoalTimelineBarView.swift",
        "Cadence/macOS/Views/GoalTimelineDateMath.swift",
        "Cadence/macOS/Views/HabitsView.swift",
        "Cadence/macOS/Views/HabitsSupportViews.swift",
        "Cadence/macOS/Views/HabitsFormSupportViews.swift",
        "Cadence/macOS/Views/HabitListSupport.swift",
        "Cadence/iOS/iOSFeatureViews.swift",
        "Cadence/iOS/iOSFeatureDetailViews.swift",
    ]

    /// Every type, and the one top-level constant, the fourteen files declared.
    private static let retiredTrackingViewNames = [
        "GoalDirectionHeaderCard",
        "GoalInspectorSheet",
        "GoalInspectorView",
        "GoalKindBadge",
        "GoalKindSection",
        "GoalLinkPickerButton",
        "GoalLinkPickerList",
        "GoalLinkPickerStyle",
        "GoalLinkedListRow",
        "GoalMissionCard",
        "GoalMissionGroup",
        "GoalMissionGroupView",
        "GoalMissionGrouping",
        "GoalSectionHeading",
        "GoalSignalTile",
        "GoalStatusBadge",
        "GoalStatusFilter",
        "GoalTaskContributorRow",
        "GoalTimelineBarFrame",
        "GoalTimelineBarView",
        "GoalTimelineDateMath",
        "GoalTimelineFilterPopover",
        "GoalTimelineGoalRailRow",
        "GoalTimelineGrid",
        "GoalTimelineGroupRow",
        "GoalTimelineMonthHeader",
        "GoalTimelineMonthMarker",
        "GoalTimelineResizeEdge",
        "GoalTimelineRow",
        "GoalTimelineRowBackground",
        "GoalTimelineRowKind",
        "GoalTimelineRowLayout",
        "GoalTimelineTodayLine",
        "GoalTimelineView",
        "GoalsEmptyDetail",
        "GoalsView",
        "GoalsViewMode",
        "GoalsViewModeToggle",
        "HabitDetailView",
        "HabitFormFields",
        "HabitGoalGroup",
        "HabitGoalSectionView",
        "HabitGoalSupportCard",
        "HabitListCard",
        "HabitListFilter",
        "HabitQuietMetrics",
        "HabitsEmptyDetail",
        "HabitsView",
        "iOSGoalDetail",
        "iOSGoalsView",
        "iOSHabitCheckInGlyph",
        "iOSHabitCheckInSize",
        "iOSHabitDetail",
        "iOSHabitSummaryRow",
        "iOSHabitsView",
    ]

    @Test func codexRetiredTrackingViewsAreGoneFromTheTree() throws {
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(paths.count > 300, "non-vacuity: the walk found \(paths.count) files")
        #expect(
            paths.contains("Cadence/macOS/Views/TasksPanel.swift"),
            "non-vacuity: the walk never reached the macOS view folder the retired files lived in"
        )
        #expect(Self.retiredTrackingViewNames.count == 55)
        #expect(Set(Self.retiredTrackingViewNames).count == Self.retiredTrackingViewNames.count,
                "the retired-name list holds a duplicate")

        // Half one: none of the fourteen files is back.
        let present = Self.retiredTrackingViewFiles.filter { paths.contains($0) }
        #expect(present.isEmpty, "\(present) came back; [[T-5002]] deleted the Goals and Habits screens")

        // Half two: and no surviving file declares or spells any of their names in CODE.
        // Comments are stripped, deliberately: this repository records retirements in tombstone
        // comments on purpose, and several of the comments left behind by T-5002 quote these names.
        let pattern = #"\b(?:"# + Self.retiredTrackingViewNames.sorted().joined(separator: "|") + #")\b"#
        let instrument = try CadenceScanInstrument(
            "a retired tracking view is declared or referenced again",
            fires: "GoalInspectorView(goal: archived)",
            andNotOn: "let goal = Goal(title: archived)"
        ) { CadenceSourceScan.matchCount(pattern, in: $0) > 0 }
        let hits = try instrument.sweep(
            paths, atLeast: 300,
            including: "Cadence/iOS/iOSRootView.swift",
            read: { CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0)) }
        )
        #expect(hits.isEmpty, "a retired tracking view is live again in \(hits)")
    }

    /// **The models stay, and that is the owner's decision rather than an oversight.**
    ///
    /// [[T-5002]]'s follow-up decision is explicit: deleting the screens leaves any pre-retirement
    /// habit or goal row invisible in the app and reachable only through export, the rows are NOT
    /// to be deleted, and no Settings note is wanted. So the three models and the link row have to
    /// stay in the schema, in the export and in the privacy reset — dropping a model from
    /// `CadenceSchema` destroys the rows a CloudKit store already holds.
    ///
    /// Asserted against the schema's own declared list rather than by constructing one of each,
    /// because "it compiles" is not "the container will migrate it".
    @Test func theRetiredTrackingModelsAreStillCarriedBySchemaExportAndReset() throws {
        let schema = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Services/CadenceSchema.swift")
        )
        #expect(schema.contains("enum CadenceSchema"), "non-vacuity: wrong file read")
        for model in ["Habit", "HabitCompletion", "Goal", "GoalListLink"] {
            #expect(
                CadenceSourceScan.matchCount(#"\b"# + model + #"\.self\b"#, in: schema) >= 1,
                "\(model) left CadenceSchema — every stored row of it is destroyed"
            )
        }

        let reset = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Services/CadencePrivacyDataResetService.swift")
        )
        for model in ["Habit", "HabitCompletion", "Goal", "GoalListLink"] {
            #expect(
                CadenceSourceScan.matchCount(#"\b"# + model + #"\b"#, in: reset) >= 1,
                "the privacy reset no longer clears \(model), so Delete Data leaves it behind"
            )
        }

        // Export is asserted behaviourally rather than by source, next door, in
        // `codexTrackingBackendGraphSurvivesAnArchiveRoundTrip`: it writes one of each, encodes,
        // decodes and imports into a second container. That is the test the owner's "reachable
        // only through export" rests on, so it is named here rather than left to be found.
        let archive = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Services/CadenceDataExportService.swift")
        )
        for key in ["goals", "habits", "habitCompletions", "goalListLinks"] {
            #expect(archive.contains(key), "the export archive no longer carries \(key)")
        }
    }

    /// **[[T-5150]] inverted by [[T-5002]].** T-5150 was that `iOSHabitDetail`'s hero still drew
    /// an "Edit habit" pencil wired to a defaulted `{}` after [[T-2079]] deleted the editor, and it
    /// pinned the pencil's absence against the declaration. T-5002 deleted the declaration, the
    /// file it lived in and the page that presented it, so the strongest form of "draws no Edit
    /// control" is that there is no control and no view to draw it.
    ///
    /// Kept as its own test rather than folded into the sweep above because the sweep argues about
    /// a list of 55 names and this argues about one defect that has a ticket: a reader who comes
    /// back to T-5150 should find something that still names it.
    @Test func theRetiredIOSHabitDetailIsGoneRatherThanMerelyEditless() throws {
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(paths.count > 300, "non-vacuity: the walk found \(paths.count) files")
        #expect(!paths.contains("Cadence/iOS/iOSFeatureDetailViews.swift"))
        #expect(!paths.contains("Cadence/iOS/iOSFeatureViews.swift"))

        var declaring: [String] = []
        for path in paths {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            if CadenceSourceScan.matchCount(#"\b(?:iOSHabitDetail|iOSHabitsView)\b"#, in: code) > 0 {
                declaring.append(path)
            }
        }
        #expect(declaring.isEmpty, "the retired iOS habit detail is live again in \(declaring)")

        // And the literal the pencil carried is gone from the tree, not merely from one file —
        // the half a declaration check cannot make.
        var saying: [String] = []
        for path in paths where CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile(path)
        ).contains("Edit habit") {
            saying.append(path)
        }
        #expect(saying.isEmpty, "\(saying) offers to edit a habit nothing can edit")
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
