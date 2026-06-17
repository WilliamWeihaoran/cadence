#if os(iOS) && DEBUG
import Foundation
import SwiftData

@MainActor
enum iOSSampleDataSupport {
    @discardableResult
    static func seedReviewTasks(allTasks: [AppTask], modelContext: ModelContext) throws -> Int {
        let todayKey = DateFormatters.todayKey()
        let tomorrowKey = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            .map(DateFormatters.dateKey(from:)) ?? todayKey
        let yesterdayKey = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            .map(DateFormatters.dateKey(from:)) ?? todayKey
        var taskSnapshot = allTasks
        var existingTitles = Set(allTasks.map { $0.title })
        var inserted = 0
        let workspace = try reviewWorkspace(modelContext: modelContext)

        inserted += try insertIfMissing(
            title: "[Sample] Review iPad Today layout",
            existingTitles: &existingTitles,
            allTasks: &taskSnapshot,
            modelContext: modelContext,
            scheduledDate: todayKey
        ) { task, currentTasks in
            task.priority = .high
            task.estimatedMinutes = 45
            task.dueDate = todayKey
            assign(task, to: workspace.mobileArea, allTasks: currentTasks, sectionName: "Design QA")
            task.notes = """
            # UI Review
            - [ ] Check landscape spacing
            - [ ] Verify timeline card tap targets
            - [ ] Confirm notes pane is readable
            """
            addSubtasks(
                ["Landscape spacing", "Timeline tap targets", "Notes pane readability"],
                to: task,
                modelContext: modelContext
            )
            TagSupport.setTags(named: ["polish", "feature"], on: task, in: modelContext)
        }

        inserted += try insertIfMissing(
            title: "[Sample] Polish notes markdown editor",
            existingTitles: &existingTitles,
            allTasks: &taskSnapshot,
            modelContext: modelContext,
            scheduledDate: todayKey
        ) { task, currentTasks in
            task.priority = .medium
            task.estimatedMinutes = 30
            task.scheduledStartMin = (9 * 60) + 30
            assign(task, to: workspace.mobileArea, allTasks: currentTasks, sectionName: "Editor")
            task.notes = "Try **bold**, `code`, checklists, links, and preview mode."
            TagSupport.setTags(named: ["docs", "polish"], on: task, in: modelContext)
        }

        inserted += try insertIfMissing(
            title: "[Sample] Test Inbox capture on iPhone",
            existingTitles: &existingTitles,
            allTasks: &taskSnapshot,
            modelContext: modelContext
        ) { task, currentTasks in
            task.priority = .low
            task.estimatedMinutes = 20
            task.dueDate = tomorrowKey
            assign(task, to: workspace.launchProject, allTasks: currentTasks, sectionName: "Regression")
            task.notes = "Open Inbox, capture a task, then schedule it for Today."
            addSubtasks(
                ["Open Inbox", "Capture a task", "Move it to Today"],
                to: task,
                modelContext: modelContext
            )
            TagSupport.setTags(named: ["question"], on: task, in: modelContext)
        }

        inserted += try insertIfMissing(
            title: "[Sample] Check calendar quick create",
            existingTitles: &existingTitles,
            allTasks: &taskSnapshot,
            modelContext: modelContext,
            scheduledDate: todayKey
        ) { task, currentTasks in
            task.priority = .none
            task.estimatedMinutes = 25
            task.scheduledStartMin = 13 * 60
            assign(task, to: workspace.launchProject, allTasks: currentTasks, sectionName: "Regression")
            task.notes = "Use the Calendar page to create a timed task and verify it appears on Today."
            TagSupport.setTags(named: ["enhancement"], on: task, in: modelContext)
        }

        inserted += try insertIfMissing(
            title: "[Sample] Overdue launch checklist item with a longer title",
            existingTitles: &existingTitles,
            allTasks: &taskSnapshot,
            modelContext: modelContext
        ) { task, currentTasks in
            task.priority = .high
            task.dueDate = yesterdayKey
            task.estimatedMinutes = 60
            task.recurrenceRule = .weekly
            assign(task, to: workspace.launchProject, allTasks: currentTasks, sectionName: "Ship")
            task.notes = "This intentionally tests overdue badges, wrapping, and high-priority row tint."
            TagSupport.setTags(named: ["blocked", "polish"], on: task, in: modelContext)
        }

        inserted += try insertIfMissing(
            title: "[Sample] Write TestFlight review notes",
            existingTitles: &existingTitles,
            allTasks: &taskSnapshot,
            modelContext: modelContext,
            scheduledDate: todayKey
        ) { task, currentTasks in
            task.priority = .medium
            task.status = .inProgress
            task.estimatedMinutes = 75
            task.scheduledStartMin = 15 * 60
            assign(task, to: workspace.launchProject, allTasks: currentTasks, sectionName: "Ship")
            task.notes = """
            ## TestFlight Notes
            Capture:
            - navigation rough edges
            - awkward keyboard behavior
            - missing macOS parity
            """
            TagSupport.setTags(named: ["docs"], on: task, in: modelContext)
        }

        inserted += try insertIfMissing(
            title: "[Sample] Completed sync smoke test",
            existingTitles: &existingTitles,
            allTasks: &taskSnapshot,
            modelContext: modelContext,
            scheduledDate: todayKey
        ) { task, currentTasks in
            task.priority = .low
            task.status = .done
            task.completedAt = Date()
            task.estimatedMinutes = 15
            assign(task, to: workspace.mobileArea, allTasks: currentTasks, sectionName: "Design QA")
            task.notes = "Used to verify completed rows, counters, and uncomplete behavior."
        }

        inserted += seedReviewNotes(tasks: taskSnapshot, modelContext: modelContext)

        return inserted
    }

    private static func seedReviewNotes(tasks: [AppTask], modelContext: ModelContext) -> Int {
        let notes = CadenceCoreNoteSupport.loadOrCreateCoreNotes(in: modelContext)
        var inserted = 0
        let layoutTaskReference = taskReference(
            titled: "[Sample] Review iPad Today layout",
            in: tasks
        )
        let editorTaskReference = taskReference(
            titled: "[Sample] Polish notes markdown editor",
            in: tasks
        )
        let testFlightTaskReference = taskReference(
            titled: "[Sample] Write TestFlight review notes",
            in: tasks
        )

        if let today = notes.today, shouldReplaceSampleNoteContent(today.content) {
            CadenceCoreNoteSupport.update(
                today,
                content: """
                # [Sample Note] Today review

                > iPad should feel like Cadence in landscape: calm, dense, and usable without becoming cramped.

                - [ ] Check iPad landscape spacing with the task list populated.
                - [ ] Tap a scheduled task and confirm the detail sheet still feels native.
                - [ ] Try switching this note between Live, Edit, and Preview mode.
                - [ ] Open a markdown link: [Cadence repo](https://github.com/WilliamWeihaoran/cadence)

                ## Linked review tasks
                \(layoutTaskReference)
                \(editorTaskReference)

                | Surface | What to check | Status |
                | --- | --- | --- |
                | Today | tasks, notes, timeline | reviewing |
                | Notes | live markdown, preview, keyboard | active |
                | iPhone | vertical layout and tab bar | pending |

                ## Friction
                Capture anything that still feels unlike the Mac app:

                ```
                Paste exact UI notes here while testing.
                ```
                """,
                in: modelContext
            )
            inserted += 1
        }

        if let week = notes.week, shouldReplaceSampleNoteContent(week.content) {
            CadenceCoreNoteSupport.update(
                week,
                content: """
                # [Sample Note] This week

                ## Mobile parity
                1. Today: task capture, notes, and timeline
                2. Inbox: capture and schedule
                3. Lists: sample area and project
                4. Calendar: month selection and day schedule

                ## Markdown QA
                - **Bold** and *italic* should render live.
                - Inline code like `scheduledDate == today` should stand out.
                - ==Highlights== and ~~completed ideas~~ should be readable.
                - Nested quotes should preserve visual depth:

                > Level one note
                >> Level two follow-up

                ## Decision
                Keep iPad horizontal first; keep iPhone vertical and focused.
                """,
                in: modelContext
            )
            inserted += 1
        }

        if let notepad = notes.notepad, shouldReplaceSampleNoteContent(notepad.content) {
            CadenceCoreNoteSupport.update(
                notepad,
                content: """
                # [Sample Note] TestFlight notes

                Use this notepad for broad feedback while testing:

                - Layout feels crowded when...
                - Keyboard gets in the way when...
                - Missing Mac behavior I expected...
                - Interaction that feels better on iPad...

                ## Ship checklist
                \(testFlightTaskReference)

                | Build area | Pass? | Notes |
                | --- | --- | --- |
                | Today |  |  |
                | Inbox |  |  |
                | Lists |  |  |
                | Calendar |  |  |
                | Notes |  |  |

                ---

                > Leave this note in Live mode while testing so markdown rendering problems are obvious immediately.
                """,
                in: modelContext
            )
            inserted += 1
        }

        return inserted
    }

    private static func shouldReplaceSampleNoteContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "N" || trimmed.contains("[Sample Note]")
    }

    private static func taskReference(titled title: String, in tasks: [AppTask]) -> String {
        guard let task = tasks.first(where: { $0.title == title }) else {
            return "- \(title)"
        }
        return NoteReferenceParser.taskReferenceMarkdown(for: task)
    }

    private struct ReviewWorkspace {
        let context: Context
        let mobileArea: Area
        let launchProject: Project
    }

    private static func reviewWorkspace(modelContext: ModelContext) throws -> ReviewWorkspace {
        let context = try sampleContext(modelContext: modelContext)
        let area = try sampleArea(context: context, modelContext: modelContext)
        let project = try sampleProject(context: context, area: area, modelContext: modelContext)

        if !(context.areas ?? []).contains(where: { $0.id == area.id }) {
            context.areas = (context.areas ?? []) + [area]
        }
        if !(context.projects ?? []).contains(where: { $0.id == project.id }) {
            context.projects = (context.projects ?? []) + [project]
        }
        if !(area.projects ?? []).contains(where: { $0.id == project.id }) {
            area.projects = (area.projects ?? []) + [project]
        }

        try modelContext.save()
        return ReviewWorkspace(context: context, mobileArea: area, launchProject: project)
    }

    private static func sampleContext(modelContext: ModelContext) throws -> Context {
        let contexts = try modelContext.fetch(FetchDescriptor<Context>())
        if let existing = contexts.first(where: { $0.name == "[Sample] Mobile Review" }) {
            existing.isArchived = false
            return existing
        }

        let context = Context(name: "[Sample] Mobile Review", colorHex: "#4a9eff", icon: "iphone")
        context.order = contexts.count
        modelContext.insert(context)
        return context
    }

    private static func sampleArea(context: Context, modelContext: ModelContext) throws -> Area {
        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        if let existing = areas.first(where: { $0.name == "[Sample] iOS Polish" }) {
            existing.status = .active
            existing.context = context
            configureSampleArea(existing)
            return existing
        }

        let area = Area(name: "[Sample] iOS Polish", context: context, colorHex: "#4a9eff", icon: "ipad")
        area.order = areas.count
        configureSampleArea(area)
        modelContext.insert(area)
        return area
    }

    private static func sampleProject(context: Context, area: Area, modelContext: ModelContext) throws -> Project {
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        if let existing = projects.first(where: { $0.name == "[Sample] TestFlight Readiness" }) {
            existing.status = .active
            existing.context = context
            existing.area = area
            configureSampleProject(existing)
            return existing
        }

        let project = Project(name: "[Sample] TestFlight Readiness", context: context, area: area, colorHex: "#4ecb71")
        project.order = projects.count
        configureSampleProject(project)
        modelContext.insert(project)
        return project
    }

    private static func configureSampleArea(_ area: Area) {
        area.desc = "Temporary debug workspace for reviewing iPad and iPhone task UI."
        area.icon = "ipad"
        area.colorHex = "#4a9eff"
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Design QA", colorHex: "#f5b84b"),
            TaskSectionConfig(name: "Editor", colorHex: "#a78bfa")
        ]
    }

    private static func configureSampleProject(_ project: Project) {
        project.desc = "Sample launch checklist that exercises list, Today, Inbox, schedule, and detail editing states."
        project.icon = "checklist"
        project.colorHex = "#4ecb71"
        project.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Regression", colorHex: "#4a9eff"),
            TaskSectionConfig(name: "Ship", colorHex: "#ef6a6a")
        ]
    }

    private static func assign(
        _ task: AppTask,
        to area: Area,
        allTasks: [AppTask],
        sectionName: String
    ) {
        CadenceTaskMutationSupport.assignContainer(
            task,
            area: area,
            project: nil,
            sectionName: sectionName,
            allTasks: allTasks
        )
    }

    private static func assign(
        _ task: AppTask,
        to project: Project,
        allTasks: [AppTask],
        sectionName: String
    ) {
        CadenceTaskMutationSupport.assignContainer(
            task,
            area: nil,
            project: project,
            sectionName: sectionName,
            allTasks: allTasks
        )
    }

    private static func insertIfMissing(
        title: String,
        existingTitles: inout Set<String>,
        allTasks: inout [AppTask],
        modelContext: ModelContext,
        scheduledDate: String? = nil,
        configure: (AppTask, [AppTask]) -> Void
    ) throws -> Int {
        guard !existingTitles.contains(title) else { return 0 }
        let currentTasks = allTasks
        guard let task = try CadenceTaskMutationSupport.insertTask(
            title: title,
            allTasks: allTasks,
            modelContext: modelContext,
            scheduledDate: scheduledDate,
            configure: { configure($0, currentTasks) }
        ) else { return 0 }
        existingTitles.insert(title)
        allTasks.append(task)
        return 1
    }

    private static func addSubtasks(_ titles: [String], to task: AppTask, modelContext: ModelContext) {
        let subtasks = titles.enumerated().map { index, title in
            let subtask = Subtask(title: title)
            subtask.order = index
            subtask.parentTask = task
            modelContext.insert(subtask)
            return subtask
        }
        task.subtasks = (task.subtasks ?? []) + subtasks
    }
}
#endif
