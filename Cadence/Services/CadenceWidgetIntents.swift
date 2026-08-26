import AppIntents
import Foundation
import SwiftData

// Every `perform()` here can run in the widget extension, which never runs the app's startup
// sequence. Open the store through `CadenceStoreSupport.makeSharedWriteContainer()` and nothing
// else: a plain write-capable open *creates* a missing store, which is how a widget tap used to be
// able to skip the legacy migration for good (T-311). The refusal it throws is user-facing copy.

/// What every writing App Intent does *after* it has saved, in one place.
///
/// There are three of them, and until T-312 each spelled its own tail: an optimistic widget
/// override where it had one, then `reloadAllWidgets(force: true)`. That tail was incomplete in
/// the same way at all three sites — a task completed from a widget button kept its pending
/// "due today" reminder, and a task captured for today did not get one — because nothing told the
/// app that its store had changed underneath it.
///
/// **The reconcile is deliberately not here.** These intents run in the widget extension.
/// `NotificationManager.reconcile` reads `notificationsEnabled` from `UserDefaults.standard`,
/// which the extension does not share with the app, so reconciling in this process would decide
/// with the wrong setting and cancel every reminder the app had scheduled. Posting the app-group
/// marker is the whole fix: the app is the only process that can see that setting, and it
/// reconciles when it adopts the write. That is the same seam MCP writes already used
/// (`CadenceModelContainerFactory.notifyExternalWrite`), which is why the two out-of-process write
/// surfaces get one answer rather than two.
nonisolated enum CadenceWidgetIntentWriteSupport {
    static func publish(
        completedTaskID: UUID? = nil,
        habitCompletion: (id: UUID, isDoneToday: Bool)? = nil,
        storeURL: URL? = nil,
        userDefaults: UserDefaults? = nil,
        now: Date = Date()
    ) {
        if let completedTaskID {
            CadenceWidgetRefreshCenter.markTaskCompleted(completedTaskID, now: now, userDefaults: userDefaults)
        }
        if let habitCompletion {
            CadenceWidgetRefreshCenter.markHabitCompletion(
                habitCompletion.id,
                isDoneToday: habitCompletion.isDoneToday,
                now: now,
                userDefaults: userDefaults
            )
        }
        CadenceWidgetRefreshCenter.reloadAllWidgets(force: true, now: now, userDefaults: userDefaults)
        if let storeURL = storeURL ?? (try? CadenceStoreSupport.primaryStoreURL()) {
            CadenceStoreSupport.postExternalWrite(besideStoreAt: storeURL, now: now)
        }
    }
}

struct CadenceTodayWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Today Tasks" }
    static var description: IntentDescription { IntentDescription("See and complete today's Cadence tasks.") }
}

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete Task" }
    static var description: IntentDescription { IntentDescription("Marks a Cadence task as done.") }
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
        let container = try CadenceStoreSupport.makeSharedWriteContainer()
        let modelContext = ModelContext(container)
        let changed = try Self.completeTask(taskID: taskID, in: modelContext)
        if changed {
            CadenceWidgetIntentWriteSupport.publish(completedTaskID: UUID(uuidString: taskID))
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
    static var title: LocalizedStringResource { "Capture Task" }
    static var description: IntentDescription { IntentDescription("Adds a quick task to Cadence.") }
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

        let container = try CadenceStoreSupport.makeSharedWriteContainer()
        let modelContext = ModelContext(container)
        try Self.captureTask(
            title: trimmed,
            planForToday: planForToday,
            in: modelContext
        )
        CadenceWidgetIntentWriteSupport.publish()
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
    static var title: LocalizedStringResource { "Toggle Habit Check-In" }
    static var description: IntentDescription { IntentDescription("Logs or removes today's check-in for a Cadence habit.") }
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
        let container = try CadenceStoreSupport.makeSharedWriteContainer()
        let modelContext = ModelContext(container)
        let result = try Self.toggleHabitCompletionResult(habitID: habitID, in: modelContext)
        if result.changed {
            CadenceWidgetIntentWriteSupport.publish(
                habitCompletion: result.habitID.map { (id: $0, isDoneToday: result.isDoneToday) }
            )
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
    static var title: LocalizedStringResource { "Open Today" }
    static var description: IntentDescription { IntentDescription("Opens Cadence to Today.") }
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
