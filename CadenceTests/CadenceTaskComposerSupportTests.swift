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
        let reference = Date()
        let today = DateFormatters.dateKey(from: reference)
        let tomorrow = DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: 1, to: reference)!)

        #expect(CadenceTaskComposerSupport.dateKey(for: .today, from: reference) == today)
        #expect(CadenceTaskComposerSupport.dateKey(for: .tomorrow, from: reference) == tomorrow)
    }

    @Test
    func aButtonIsSelectedOnlyForItsOwnDay() {
        let today = DateFormatters.todayKey()
        let tomorrow = DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)

        #expect(CadenceTaskComposerSupport.isSelected(.today, doDateKey: today))
        #expect(CadenceTaskComposerSupport.isSelected(.tomorrow, doDateKey: today) == false)
        #expect(CadenceTaskComposerSupport.isSelected(.tomorrow, doDateKey: tomorrow))
        #expect(CadenceTaskComposerSupport.isSelected(.today, doDateKey: "") == false)
        #expect(CadenceTaskComposerSupport.isSelected(.tomorrow, doDateKey: "") == false)
    }

    /// The three buttons are the whole do-date control — nothing beside them holds a Clear — so a
    /// mis-tapped "Today" has to be undoable with the button that caused it.
    @Test
    func tappingTheDayTheDraftAlreadyHasClearsIt() {
        let reference = Date()
        let today = CadenceTaskComposerSupport.dateKey(for: .today, from: reference)
        let tomorrow = CadenceTaskComposerSupport.dateKey(for: .tomorrow, from: reference)

        #expect(CadenceTaskComposerSupport.toggledDoDateKey(current: "", tapping: .today, from: reference) == today)
        #expect(CadenceTaskComposerSupport.toggledDoDateKey(current: today, tapping: .today, from: reference).isEmpty)
        #expect(CadenceTaskComposerSupport.toggledDoDateKey(current: tomorrow, tapping: .tomorrow, from: reference).isEmpty)
        // Tapping the *other* button moves the date rather than clearing it.
        #expect(CadenceTaskComposerSupport.toggledDoDateKey(current: today, tapping: .tomorrow, from: reference) == tomorrow)
        #expect(CadenceTaskComposerSupport.toggledDoDateKey(current: tomorrow, tapping: .today, from: reference) == today)
    }

    /// A seeded day the two fixed buttons cannot say has to be legible without opening the picker —
    /// this sheet's whole reason for existing in this shape is that a seeded value is visible.
    @Test
    func theThirdButtonCarriesADayTheOtherTwoCannotSay() {
        let today = DateFormatters.todayKey()
        let tomorrow = DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let farOff = DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: 40, to: Date())!)
        let yesterday = DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

        #expect(CadenceTaskComposerSupport.doDatePickLabel("") == "Pick…")
        #expect(CadenceTaskComposerSupport.doDatePickLabel(today) == "Pick…")
        #expect(CadenceTaskComposerSupport.doDatePickLabel(tomorrow) == "Pick…")
        #expect(CadenceTaskComposerSupport.doDatePickLabel(farOff) == DateFormatters.shortDateString(from: farOff))
        #expect(CadenceTaskComposerSupport.doDatePickLabel(yesterday) == DateFormatters.shortDateString(from: yesterday))

        #expect(CadenceTaskComposerSupport.isCustomDoDate("") == false)
        #expect(CadenceTaskComposerSupport.isCustomDoDate(today) == false)
        #expect(CadenceTaskComposerSupport.isCustomDoDate(farOff))
    }

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
