#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Coverage for the two things the inline column composer has to get right and cannot show you in
/// a view: what context a surface contributes to a new card, and how the resulting draft resolves
/// to a real task.
@MainActor
struct InlineTaskComposerSupportTests {

    // MARK: - What a surface contributes

    @Test func columnSurfaceSeedsItsListAndSection() {
        let areaID = UUID()
        let fields = InlineTaskComposerSupport.initialFields(
            for: .column(container: .area(areaID), sectionName: "Review")
        )

        #expect(fields.container == .area(areaID))
        #expect(fields.sectionName == "Review")
        // A kanban column is not a date, and must not invent one.
        #expect(fields.doDateKey.isEmpty)
        #expect(fields.startMin == -1)
    }

    @Test func columnSurfaceFallsBackToTheDefaultSectionWhenItHasNoName() {
        let fields = InlineTaskComposerSupport.initialFields(
            for: .column(container: .inbox, sectionName: "   ")
        )

        #expect(fields.sectionName == TaskSectionDefaults.defaultName)
    }

    @Test func daySurfaceSeedsItsDayAndNoList() {
        let fields = InlineTaskComposerSupport.initialFields(
            for: .day(dateKey: "2026-08-14", startMin: -1)
        )

        #expect(fields.doDateKey == "2026-08-14")
        #expect(fields.container == .inbox)
        #expect(fields.sectionName == TaskSectionDefaults.defaultName)
        #expect(fields.startMin == -1)
    }

    @Test func daySurfaceCarriesTheColumnTimeRangeWhenTheBoardHasOne() {
        let fields = InlineTaskComposerSupport.initialFields(
            for: .day(dateKey: "2026-08-14", startMin: 540)
        )

        #expect(fields.startMin == 540)
    }

    /// A timeline slot on no day is not a slot. Guards the `.day` seed against a board that hands
    /// over a start minute with an empty date key.
    @Test func daySurfaceDropsTheTimeSlotWhenItHasNoDay() {
        let fields = InlineTaskComposerSupport.initialFields(
            for: .day(dateKey: "", startMin: 540)
        )

        #expect(fields.startMin == -1)
    }

    // MARK: - Which chips the surface offers

    @Test func columnShowsListAndSectionButNoDay() {
        let fields = InlineTaskComposerSupport.initialFields(
            for: .column(container: .project(UUID()), sectionName: "Doing")
        )
        let chips = InlineTaskComposerSupport.chips(
            for: .column(container: fields.container, sectionName: fields.sectionName),
            fields: fields
        )

        #expect(chips.showsList)
        #expect(chips.showsSection)
        #expect(!chips.showsDay)
        #expect(!chips.showsTimeRange)
    }

    /// Inbox is the absence of a list, and a list is what owns sections — so there is nothing for
    /// the section chip to choose between. Same rule the create sheet's toolbar uses.
    @Test func inboxColumnHidesTheSectionChip() {
        let surface = InlineTaskComposerSurface.column(container: .inbox, sectionName: TaskSectionDefaults.defaultName)
        let chips = InlineTaskComposerSupport.chips(
            for: surface,
            fields: InlineTaskComposerSupport.initialFields(for: surface)
        )

        #expect(chips.showsList)
        #expect(!chips.showsSection)
    }

    @Test func dayColumnShowsTheDayAndNoListUntilOneIsChosen() {
        let surface = InlineTaskComposerSurface.day(dateKey: "2026-08-14", startMin: -1)
        let chips = InlineTaskComposerSupport.chips(
            for: surface,
            fields: InlineTaskComposerSupport.initialFields(for: surface)
        )

        #expect(chips.showsDay)
        #expect(!chips.showsList)
        #expect(!chips.showsSection)
        #expect(!chips.showsTimeRange)
    }

    /// The title field's `~` shortcut can route a day-column draft into a list. Hiding the list
    /// chip then would leave that choice invisible and un-undoable.
    @Test func dayColumnRevealsTheListChipOnceTheDraftHasAList() {
        let surface = InlineTaskComposerSurface.day(dateKey: "2026-08-14", startMin: -1)
        var fields = InlineTaskComposerSupport.initialFields(for: surface)
        fields.container = .area(UUID())

        let chips = InlineTaskComposerSupport.chips(for: surface, fields: fields)

        #expect(chips.showsList)
        #expect(chips.showsSection)
        #expect(chips.showsDay)
    }

    @Test func timeRangeChipAppearsOnlyWithATimelineSlot() {
        let surface = InlineTaskComposerSurface.day(dateKey: "2026-08-14", startMin: 540)
        let fields = InlineTaskComposerSupport.initialFields(for: surface)

        #expect(InlineTaskComposerSupport.chips(for: surface, fields: fields).showsTimeRange)
        #expect(InlineTaskComposerSupport.timeRangeLabel(for: fields, estimatedMinutes: 60)
            == TimeFormatters.timeRange(startMin: 540, endMin: 600))

        var unslotted = fields
        unslotted.startMin = -1
        #expect(InlineTaskComposerSupport.timeRangeLabel(for: unslotted) == nil)
    }

    // MARK: - Submitting

    @Test func blankTitlesAreNotCreatable() {
        #expect(!InlineTaskComposerSupport.canCreate(title: ""))
        #expect(!InlineTaskComposerSupport.canCreate(title: "   \n "))
        #expect(InlineTaskComposerSupport.canCreate(title: "Ship it"))
    }

    // MARK: - How a draft resolves to a task

    @Test func columnDraftLandsInTheColumnsListAndSection() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let workContext = Context(name: "Work")
        let area = Area(name: "Operations", context: workContext)
        area.sectionNames = [TaskSectionDefaults.defaultName, "Review"]
        modelContext.insert(workContext)
        modelContext.insert(area)
        try modelContext.save()

        let fields = InlineTaskComposerSupport.initialFields(
            for: .column(container: .area(area.id), sectionName: "Review")
        )
        let draft = InlineTaskComposerSupport.draft(title: "Audit the rota", fields: fields, tags: [])
        let task = try #require(TaskCreationService(areas: [area], projects: [])
            .insertTask(from: draft, into: modelContext))

        #expect(task.title == "Audit the rota")
        #expect(task.area?.id == area.id)
        #expect(task.context?.id == workContext.id)
        #expect(task.sectionName == "Review")
        #expect(task.scheduledDate.isEmpty)
        #expect(task.scheduledStartMin == -1)
        #expect(task.estimatedMinutes == InlineTaskComposerSupport.defaultEstimatedMinutes)
    }

    @Test func dayDraftLandsOnTheColumnsDay() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fields = InlineTaskComposerSupport.initialFields(for: .day(dateKey: "2026-08-14", startMin: -1))
        let draft = InlineTaskComposerSupport.draft(title: "Call the vet", fields: fields, tags: [])
        let task = try #require(TaskCreationService(areas: [], projects: [])
            .insertTask(from: draft, into: modelContext))

        #expect(task.scheduledDate == "2026-08-14")
        #expect(task.scheduledStartMin == -1)
        #expect(task.area == nil)
        #expect(task.project == nil)
        // The board buckets on the do date alone, so a day column must not also set a due date.
        #expect(task.dueDate.isEmpty)
    }

    @Test func dayDraftKeepsTheColumnTimeSlot() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fields = InlineTaskComposerSupport.initialFields(for: .day(dateKey: "2026-08-14", startMin: 540))
        let draft = InlineTaskComposerSupport.draft(title: "Standup", fields: fields, tags: [])
        let task = try #require(TaskCreationService(areas: [], projects: [])
            .insertTask(from: draft, into: modelContext))

        #expect(task.scheduledDate == "2026-08-14")
        #expect(task.scheduledStartMin == 540)
    }

    /// Clearing the day chip has to clear the slot with it, or the draft carries a start minute on
    /// no day at all.
    @Test func clearingTheDayDropsTheTimeSlotFromTheDraft() {
        var fields = InlineTaskComposerSupport.initialFields(for: .day(dateKey: "2026-08-14", startMin: 540))
        fields.doDateKey = ""

        let draft = InlineTaskComposerSupport.draft(title: "Someday", fields: fields, tags: [])

        #expect(draft.scheduledDateKey.isEmpty)
        #expect(draft.scheduledStartMin == -1)
    }

    /// The composer has no priority chip because the shared title field already carries the
    /// `!`/`!!`/`!!!` shortcut — this is the path that has to keep working for that to be true.
    @Test func titlePriorityShortcutSurvivesTheDraft() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fields = InlineTaskComposerSupport.initialFields(for: .column(container: .inbox, sectionName: ""))
        let draft = InlineTaskComposerSupport.draft(title: "!!! Renew the licence", fields: fields, tags: [])
        let task = try #require(TaskCreationService(areas: [], projects: [])
            .insertTask(from: draft, into: modelContext))

        #expect(task.title == "Renew the licence")
        #expect(task.priority == .high)
    }

    @Test func draftKeepsTagsTheTitleFieldAdded() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let tag = Tag(name: "Deep Work")
        modelContext.insert(tag)
        try modelContext.save()

        let fields = InlineTaskComposerSupport.initialFields(for: .column(container: .inbox, sectionName: ""))
        let draft = InlineTaskComposerSupport.draft(title: "Write the brief", fields: fields, tags: [tag])
        let task = try #require(TaskCreationService(areas: [], projects: [])
            .insertTask(from: draft, into: modelContext))

        #expect(task.sortedTags.map(\.name) == ["Deep Work"])
    }

    /// Switching the list chip must not leave a section name the new list has never heard of.
    @Test func changingTheListNormalizesTheSectionName() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let area = Area(name: "Operations")
        area.sectionNames = [TaskSectionDefaults.defaultName, "Review"]
        let project = Project(name: "Launch")
        project.sectionNames = [TaskSectionDefaults.defaultName, "Shipping"]
        modelContext.insert(area)
        modelContext.insert(project)
        try modelContext.save()

        let normalized = InlineTaskComposerSupport.normalizedSectionName(
            "Review",
            for: .project(project.id),
            areas: [area],
            projects: [project]
        )

        #expect(normalized == TaskSectionDefaults.defaultName)
    }
}
#endif
