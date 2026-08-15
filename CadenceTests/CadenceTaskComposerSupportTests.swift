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

    // MARK: - Chip visibility

    @Test
    func inboxNeverShowsASectionChip() {
        #expect(CadenceTaskComposerSupport.showsSectionChip(
            container: .inbox,
            availableSections: ["Default", "Doing"]
        ) == false)
    }

    @Test
    func aListWithOnlyTheDefaultSectionShowsNoSectionChip() {
        #expect(CadenceTaskComposerSupport.showsSectionChip(
            container: .area(UUID()),
            availableSections: [TaskSectionDefaults.defaultName]
        ) == false)
    }

    @Test
    func aListWithRealSectionsShowsTheSectionChip() {
        #expect(CadenceTaskComposerSupport.showsSectionChip(
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

    // MARK: - Chip labels

    @Test
    func anUnsetDateChipShowsItsOwnName() {
        #expect(CadenceTaskComposerSupport.dateChipLabel("", placeholder: "Do") == "Do")
        #expect(CadenceTaskComposerSupport.dateChipLabel("", placeholder: "Due") == "Due")
    }

    @Test
    func nearDatesReadAsWordsAndFarOnesAsDates() {
        let today = DateFormatters.todayKey()
        let tomorrow = DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let yesterday = DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let farOff = DateFormatters.dateKey(from: Calendar.current.date(byAdding: .day, value: 40, to: Date())!)

        #expect(CadenceTaskComposerSupport.dateChipLabel(today, placeholder: "Do") == "Today")
        #expect(CadenceTaskComposerSupport.dateChipLabel(tomorrow, placeholder: "Do") == "Tomorrow")
        #expect(CadenceTaskComposerSupport.dateChipLabel(yesterday, placeholder: "Do") == "Yesterday")
        #expect(CadenceTaskComposerSupport.dateChipLabel(farOff, placeholder: "Do") == DateFormatters.shortDateString(from: farOff))
    }

    @Test
    func thePriorityChipShowsTheMarkItWasTypedWith() {
        #expect(CadenceTaskComposerSupport.priorityChipLabel(.none) == "Priority")
        #expect(CadenceTaskComposerSupport.priorityChipLabel(.low) == "!")
        #expect(CadenceTaskComposerSupport.priorityChipLabel(.medium) == "!!")
        #expect(CadenceTaskComposerSupport.priorityChipLabel(.high) == "!!!")
    }

    @Test
    func theTagChipNamesOneTagAndCountsSeveral() {
        #expect(CadenceTaskComposerSupport.tagChipLabel(names: []) == "Tags")
        #expect(CadenceTaskComposerSupport.tagChipLabel(names: ["  "]) == "Tags")
        #expect(CadenceTaskComposerSupport.tagChipLabel(names: ["urgent"]) == "urgent")
        #expect(CadenceTaskComposerSupport.tagChipLabel(names: ["urgent", "home"]) == "2 tags")
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
