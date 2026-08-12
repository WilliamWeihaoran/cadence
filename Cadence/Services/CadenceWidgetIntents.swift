import AppIntents
import SwiftData

struct CadenceTodayWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Today Tasks"
    static var description = IntentDescription("See and complete today's Cadence tasks.")
}

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks a Cadence task as done.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Task ID")
    var taskID: String

    init() {
        self.taskID = ""
    }

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let modelContext = ModelContext(container)
        let changed = try Self.completeTask(taskID: taskID, in: modelContext)
        if changed {
            if let uuid = UUID(uuidString: taskID) {
                CadenceWidgetRefreshCenter.markTaskCompleted(uuid)
            }
            CadenceWidgetRefreshCenter.reloadAllWidgets(force: true)
        }
        return .result()
    }

    @discardableResult
    static func completeTask(taskID: String, in modelContext: ModelContext) throws -> Bool {
        guard let uuid = UUID(uuidString: taskID) else { return false }

        let predicate = #Predicate<AppTask> { task in
            task.id == uuid
        }
        let descriptor = FetchDescriptor<AppTask>(predicate: predicate)
        guard let task = try modelContext.fetch(descriptor).first else { return false }
        guard !task.isCancelled else { return false }
        guard !task.isDone else { return false }

        // Same shared workflow every in-app completion path uses, so completing a recurring task
        // from a widget button or the "Complete Task" App Intent still spawns the next occurrence.
        CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        try modelContext.save()
        return true
    }
}

struct CaptureTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Task"
    static var description = IntentDescription("Adds a quick task to Cadence.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Plan for Today")
    var planForToday: Bool

    init() {
        self.title = ""
        self.planForToday = false
    }

    init(title: String, planForToday: Bool = false) {
        self.title = title
        self.planForToday = planForToday
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Add a task title.")
        }

        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let modelContext = ModelContext(container)
        try Self.captureTask(
            title: trimmed,
            planForToday: planForToday,
            in: modelContext
        )
        CadenceWidgetRefreshCenter.reloadAllWidgets(force: true)
        return .result(dialog: "Captured \(trimmed).")
    }

    static func captureTask(title: String, planForToday: Bool, in modelContext: ModelContext) throws {
        let task = AppTask(title: title)
        task.estimatedMinutes = 30
        task.order = try nextTaskOrder(in: modelContext)
        if planForToday {
            task.scheduledDate = CadenceWidgetDateSupport.dateKey(from: Date())
        }

        modelContext.insert(task)
        try modelContext.save()
    }

    private static func nextTaskOrder(in modelContext: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<AppTask>()
        let tasks = try modelContext.fetch(descriptor)
        return (tasks.map(\.order).max() ?? -1) + 1
    }
}

struct ToggleHabitCompletionIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Habit Check-In"
    static var description = IntentDescription("Logs or removes today's check-in for a Cadence habit.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Habit ID")
    var habitID: String

    init() {
        self.habitID = ""
    }

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let modelContext = ModelContext(container)
        let result = try Self.toggleHabitCompletionResult(habitID: habitID, in: modelContext)
        if result.changed {
            if let habitID = result.habitID {
                CadenceWidgetRefreshCenter.markHabitCompletion(
                    habitID,
                    isDoneToday: result.isDoneToday
                )
            }
            CadenceWidgetRefreshCenter.reloadAllWidgets(force: true)
        }
        return .result()
    }

    /// The toggle `perform()` runs. It returns the habit and its resulting state as well as
    /// whether anything changed, because `perform()` needs both to write the optimistic widget
    /// override — a `-> Bool` shim over this used to exist for the tests alone, which meant the
    /// two things `perform()` does with the result were never asserted together.
    static func toggleHabitCompletionResult(
        habitID: String,
        on dateKey: String = CadenceWidgetDateSupport.dateKey(from: Date()),
        in modelContext: ModelContext
    ) throws -> HabitToggleResult {
        guard let uuid = UUID(uuidString: habitID) else {
            return HabitToggleResult(changed: false, habitID: nil, isDoneToday: false)
        }

        let predicate = #Predicate<Habit> { habit in
            habit.id == uuid
        }
        let descriptor = FetchDescriptor<Habit>(predicate: predicate)
        guard let habit = try modelContext.fetch(descriptor).first else {
            return HabitToggleResult(changed: false, habitID: nil, isDoneToday: false)
        }

        let existing = (habit.completions ?? []).filter { $0.date == dateKey }
        let isDoneToday: Bool
        if existing.isEmpty {
            let completion = HabitCompletion(date: dateKey, habit: habit)
            modelContext.insert(completion)
            habit.completions = (habit.completions ?? []) + [completion]
            isDoneToday = true
        } else {
            for completion in existing {
                habit.completions = (habit.completions ?? []).filter { $0.id != completion.id }
                modelContext.delete(completion)
            }
            isDoneToday = false
        }
        try modelContext.save()
        return HabitToggleResult(
            changed: true,
            habitID: habit.id,
            isDoneToday: isDoneToday
        )
    }

    struct HabitToggleResult {
        let changed: Bool
        let habitID: UUID?
        let isDoneToday: Bool
    }
}

struct OpenCadenceTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"
    static var description = IntentDescription("Opens Cadence to Today.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct CadenceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureTaskIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Add a task in \(.applicationName)"
            ],
            shortTitle: "Capture Task",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: OpenCadenceTodayIntent(),
            phrases: [
                "Open Today in \(.applicationName)",
                "Show Today in \(.applicationName)"
            ],
            shortTitle: "Open Today",
            systemImageName: "sun.max.fill"
        )
    }
}
