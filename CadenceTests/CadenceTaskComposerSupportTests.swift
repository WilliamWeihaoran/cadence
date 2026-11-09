import Foundation
import Testing
@testable import Cadence

/// The iOS create-task sheet's arithmetic: what a seed resolves to, which chips a draft earns,
/// what each chip says, and what the sheet hands `TaskCreationService`.
///
/// The sheet itself is under `Cadence/iOS/` and so invisible to this target; everything worth
/// pinning was kept out of it deliberately. The marker cases matter most — the `~`/`#`/`!` title
/// shortcuts are parsed by `TaskTitleSupport`, and these tests are what keep the composer *using*
/// that parser rather than growing a second one.
@MainActor
struct CadenceTaskComposerSupportTests {

    // MARK: - Seed resolution

    @Test
    func emptySeedResolvesToAnInboxDraftWithNothingSet() {
        let fields = CadenceTaskComposerSupport.initialFields(for: CadenceTaskComposerSeed())

        #expect(fields.container == .inbox)
        #expect(fields.sectionName == TaskSectionDefaults.defaultName)
        #expect(fields.doDateKey.isEmpty)
        #expect(fields.dueDateKey.isEmpty)
        #expect(fields.priority == .none)
    }

    @Test
    func seededListAndDatesSurviveIntoTheFields() {
        let areaID = UUID()
        let seed = CadenceTaskComposerSeed(
            doDateKey: "2026-08-15",
            dueDateKey: "2026-08-20",
            priority: .high,
            container: .area(areaID),
            sectionName: "Backlog"
        )

        let fields = CadenceTaskComposerSupport.initialFields(for: seed)

        #expect(fields.container == .area(areaID))
        #expect(fields.sectionName == "Backlog")
        #expect(fields.doDateKey == "2026-08-15")
        #expect(fields.dueDateKey == "2026-08-20")
        #expect(fields.priority == .high)
    }

    @Test
    func blankSeededSectionFallsBackToDefaultRatherThanAnEmptyChip() {
        let seed = CadenceTaskComposerSeed(container: .project(UUID()), sectionName: "   ")

        #expect(CadenceTaskComposerSupport.initialFields(for: seed).sectionName == TaskSectionDefaults.defaultName)
    }

    // MARK: - Row visibility

    @Test
    func inboxNeverShowsASectionRow() {
        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .inbox,
            availableSections: ["Default", "Doing"]
        ) == false)
    }

    @Test
    func aListWithOnlyTheDefaultSectionShowsNoSectionRow() {
        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .area(UUID()),
            availableSections: [TaskSectionDefaults.defaultName]
        ) == false)
    }

    @Test
    func aListWithRealSectionsShowsTheSectionRow() {
        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .project(UUID()),
            availableSections: [TaskSectionDefaults.defaultName, "Doing"]
        ))
    }

    // MARK: - Create gating

    @Test
    func aTitleOfWhitespaceCannotCreate() {
        #expect(CadenceTaskComposerSupport.canCreate(title: "   \n ") == false)
        #expect(CadenceTaskComposerSupport.canCreate(title: "") == false)
        #expect(CadenceTaskComposerSupport.canCreate(title: "Buy milk"))
    }

    // MARK: - The iOS capture sheet's draft

    /// [[T-14794]]: `iOSCreateTaskSheet.create()` built its `TaskCreationDraft` by hand and copied
    /// the raw `seriesEndMode`, so an `.afterCount` end with a count of 0 reached the service as a
    /// series that stops after one occurrence. It calls the builder the Mac's Cmd+N card calls now,
    /// which resolves the end first. The sheet cannot be presented here, so its call is read from
    /// source and the builder's answer is checked on the very draft that diverged.
    @Test
    func theIOSCaptureSheetBuildsItsDraftThroughTheSharedBuilder() throws {
        let host = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCreateTaskSheet.swift")
        )
        let create = try #require(CadenceSourceScan.functionBody(named: "create", in: host))
        #expect(create.contains("TaskCreationService(areas: areas, projects: projects)"),
                "read the wrong create()")
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskComposerSupport\.creationDraft\("#, in: create) == 1,
                "the iOS sheet no longer builds through the shared builder")
        #expect(CadenceSourceScan.matchCount(#"creation\.\w+\s*="#, in: create) == 0,
                "the iOS sheet writes a draft field by hand again")
        #expect(!create.contains("CadenceTaskComposerSupport.draft("))

        var draft = CadenceScheduleDraft.quickCreate(dateKey: "2026-11-10", startMin: 9 * 60, opensTimed: false, kind: .task)
        draft.repeatRule = .weekly
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 0
        let creation = CadenceTaskComposerSupport.creationDraft(
            from: draft, container: .inbox, tags: [], subtaskTitles: []
        )
        #expect(creation.repeatRule == .weekly)
        #expect(creation.seriesEndMode == .never, "a count of 0 is no end, not an end after one")
    }

    // MARK: - Draft

    @Test
    func theDraftCarriesEveryChipValue() {
        let projectID = UUID()
        let fields = CadenceTaskComposerFields(
            container: .project(projectID),
            sectionName: "Doing",
            doDateKey: "2026-08-15",
            dueDateKey: "2026-08-18",
            priority: .medium
        )

        let draft = CadenceTaskComposerSupport.draft(
            title: "  Ship the thing  ",
            notes: " with a note ",
            fields: fields,
            tags: []
        )

        #expect(draft.trimmedTitle == "Ship the thing")
        #expect(draft.trimmedNotes == "with a note")
        #expect(draft.container == .project(projectID))
        #expect(draft.sectionName == "Doing")
        #expect(draft.scheduledDateKey == "2026-08-15")
        #expect(draft.dueDateKey == "2026-08-18")
        #expect(draft.resolvedPriority == .medium)
        #expect(draft.estimatedMinutes == CadenceTaskComposerSupport.defaultEstimatedMinutes)
    }

    /// The `!!!` marker is stripped from the title and read as a priority by `TaskCreationDraft`.
    /// The composer passes the raw title precisely so that keeps happening in one place.
    @Test
    func aBangMarkerInTheTitleReachesTheDraftAsAPriority() {
        let draft = CadenceTaskComposerSupport.draft(
            title: "Call the plumber!!!",
            notes: "",
            fields: CadenceTaskComposerFields(
                container: .inbox,
                sectionName: TaskSectionDefaults.defaultName,
                doDateKey: "",
                dueDateKey: "",
                priority: .none
            ),
            tags: []
        )

        #expect(draft.trimmedTitle == "Call the plumber")
        #expect(draft.resolvedPriority == .high)
    }

    @Test
    func aTimeSlotWithoutADayIsNotASlot() {
        let fields = CadenceTaskComposerFields(
            container: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            doDateKey: "",
            dueDateKey: "",
            priority: .none
        )

        let draft = CadenceTaskComposerSupport.draft(
            title: "Standup",
            notes: "",
            fields: fields,
            tags: [],
            scheduledStartMin: 540
        )

        #expect(draft.scheduledStartMin == -1)
    }

    @Test
    func aTimeSlotOnADaySurvives() {
        let fields = CadenceTaskComposerFields(
            container: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            doDateKey: "2026-08-15",
            dueDateKey: "",
            priority: .none
        )

        let draft = CadenceTaskComposerSupport.draft(
            title: "Standup",
            notes: "",
            fields: fields,
            tags: [],
            scheduledStartMin: 540
        )

        #expect(draft.scheduledStartMin == 540)
    }

    // MARK: - Inline markers

    @Test
    func theChipPreviewsThePriorityTheTitleIsAskingFor() {
        #expect(CadenceTaskComposerSupport.resolvedPriority(title: "Email Sam!!", selected: .none) == .medium)
        #expect(CadenceTaskComposerSupport.resolvedPriority(title: "Email Sam", selected: .low) == .low)
        // The marker wins, exactly as it will at creation.
        #expect(CadenceTaskComposerSupport.resolvedPriority(title: "Email Sam!", selected: .high) == .low)
    }

    @Test
    func pickingAPriorityFromTheChipTakesTheMarkerOutOfTheTitle() {
        #expect(CadenceTaskComposerSupport.titleClearingPriorityMarker("Email Sam!!!") == "Email Sam")
        #expect(CadenceTaskComposerSupport.titleClearingPriorityMarker("!!Email Sam") == "Email Sam")
        #expect(CadenceTaskComposerSupport.titleClearingPriorityMarker("  Email Sam  ") == "Email Sam")
    }

    @Test
    func acceptingAListSuggestionConsumesTheMarkerAndItsQuery() {
        let shortcut = TaskTitleSupport.containerShortcut(in: "Draft the brief ~des")
        #expect(shortcut != nil)
        #expect(CadenceTaskComposerSupport.title(removingShortcut: shortcut!) == "Draft the brief")
    }

    @Test
    func acceptingATagSuggestionConsumesTheMarkerAndItsQuery() {
        let shortcut = TaskTitleSupport.tagShortcut(in: "Draft the brief #ur")
        #expect(shortcut != nil)
        #expect(CadenceTaskComposerSupport.title(removingShortcut: shortcut!) == "Draft the brief")
    }

    @Test
    func aMarkerTypedAsTheWholeTitleLeavesAnEmptyTitleBehind() {
        let shortcut = TaskTitleSupport.containerShortcut(in: "~work")
        #expect(shortcut != nil)
        #expect(CadenceTaskComposerSupport.title(removingShortcut: shortcut!).isEmpty)
    }

    @Test
    func suggestionsMatchOnPrefixNotSubstring() {
        #expect(CadenceTaskComposerSupport.matchesQuery("Design", query: "des"))
        #expect(CadenceTaskComposerSupport.matchesQuery("Design", query: "DES"))
        #expect(CadenceTaskComposerSupport.matchesQuery("Design", query: ""))
        #expect(CadenceTaskComposerSupport.matchesQuery("Design", query: "sign") == false)
    }

    // MARK: - Do date buttons

    @Test
    func theTwoFixedButtonsProduceTheirOwnDays() {
        let calendar = CadenceTestTimeZones.pinnedCalendar()
        let reference = Date()
        let today = DateFormatters.dateKey(from: reference)
        let tomorrow = DateFormatters.dateKey(from: calendar.date(byAdding: .day, value: 1, to: reference)!)

        #expect(CadenceTaskComposerSupport.dateKey(for: .today, from: reference) == today)
        #expect(CadenceTaskComposerSupport.dateKey(for: .tomorrow, from: reference) == tomorrow)
    }

    @Test
    func aButtonIsSelectedOnlyForItsOwnDay() {
        let calendar = CadenceTestTimeZones.pinnedCalendar()
        let today = DateFormatters.todayKey()
        let tomorrow = DateFormatters.dateKey(from: calendar.date(byAdding: .day, value: 1, to: Date())!)

        #expect(CadenceTaskComposerSupport.isSelected(.today, doDateKey: today))
        #expect(CadenceTaskComposerSupport.isSelected(.tomorrow, doDateKey: today) == false)
        #expect(CadenceTaskComposerSupport.isSelected(.tomorrow, doDateKey: tomorrow))
        #expect(CadenceTaskComposerSupport.isSelected(.today, doDateKey: "") == false)
        #expect(CadenceTaskComposerSupport.isSelected(.tomorrow, doDateKey: "") == false)
    }

    // `toggledDoDateKey`, `doDatePickLabel` and `isCustomDoDate` were tested here until the do-date
    // block became a tile. Each was unreachable from any surface by the time it went — the tile's
    // picker carries its own Clear, the tile states a value rather than a `Pick…` prompt, and
    // nothing asked whether a date was "custom" once the tile stopped needing a third label. They
    // went with their assertions rather than the tests keeping dead code alive.
    //
    // What survives of that block is the pair `dateValueLabel` reads, covered above.

    // MARK: - Row values



    /// A row is labelled "Priority", so its trailing control answers it in words — the `!!` mark the
    /// chip used to show named the field rather than the value.
    @Test
    func thePriorityRowSpellsTheValueOut() {
        #expect(CadenceTaskComposerSupport.priorityValueLabel(.none) == "None")
        #expect(CadenceTaskComposerSupport.priorityValueLabel(.low) == "Low")
        #expect(CadenceTaskComposerSupport.priorityValueLabel(.medium) == "Medium")
        #expect(CadenceTaskComposerSupport.priorityValueLabel(.high) == "High")
    }

    @Test
    func theTagsRowNamesOneTagAndCountsSeveral() {
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: []) == "None")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["  "]) == "None")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent"]) == "urgent")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent", "home"]) == "2 tags")
    }

    // MARK: - Container tokens

    @Test
    func containerTokensRoundTrip() {
        let areaID = UUID()
        let projectID = UUID()

        for selection: TaskContainerSelection in [.inbox, .area(areaID), .project(projectID)] {
            let token = CadenceTaskComposerSupport.token(for: selection)
            #expect(CadenceTaskComposerSupport.selection(fromToken: token) == selection)
        }
    }

    @Test
    func aTokenTheAppNoLongerRecognisesReadsAsInbox() {
        #expect(CadenceTaskComposerSupport.selection(fromToken: "area:not-a-uuid") == .inbox)
        #expect(CadenceTaskComposerSupport.selection(fromToken: "project:") == .inbox)
        #expect(CadenceTaskComposerSupport.selection(fromToken: "") == .inbox)
    }
}
