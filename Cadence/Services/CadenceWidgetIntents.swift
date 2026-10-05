import AppIntents
import Foundation
import SwiftData

// Every `perform()` here can run in the widget extension, which never runs the app's startup
// sequence. Open the store through `CadenceStoreSupport.makeSharedWriteContainer()` and nothing
// else: a plain write-capable open *creates* a missing store, which is how a widget tap used to be
// able to skip the legacy migration for good (T-311). The refusal it throws is user-facing copy.

/// What every writing App Intent does *after* it has saved, in one place.
///
/// There were three of them, and until T-312 each spelled its own tail: an optimistic widget
/// override where it had one, then `reloadAllWidgets(force: true)`. That tail was incomplete in
/// the same way at all three sites — a task completed from a widget button kept its pending
/// "due today" reminder, and a task captured for today did not get one — because nothing told the
/// app that its store had changed underneath it.
///
/// **Two of them ship now.** [[T-2078]] retired `ToggleHabitCompletionIntent` with the Habit
/// Check-In widget that was its only button: an `AppIntent` compiled into this extension stays in
/// the AppIntents metadata and keeps showing up in Shortcuts whether or not a widget draws it, so
/// a habit *write* would have survived the widget's removal as a Shortcuts action. `habitCompletion:`
/// below is deliberately **kept**: the optimistic-override pair it drives
/// (`CadenceWidgetRefreshCenter.markHabitCompletion` / `recentHabitCompletionStates`) is still read
/// by `CadenceHabitWidgetSupport`, and the `Habit` schema is kept, so the tail stays whole rather
/// than being amputated halfway for a feature the owner asked to be recoverable.
///
/// **The reconcile is deliberately not here.** These intents run in the widget extension.
/// `NotificationManager.reconcile` reads `notificationsEnabled` through `CadenceDefaults.store` —
/// this process's own `UserDefaults.standard` unless a launch argument names a private suite
/// ([[T-1315]]) — which the extension does not share with the app, so reconciling here would decide
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
        guard let capture = Self.resolvedCapture(from: title) else {
            return .result(dialog: "Add a task title.")
        }

        let container = try CadenceStoreSupport.makeSharedWriteContainer()
        let modelContext = ModelContext(container)
        try Self.captureTask(
            title: title,
            planForToday: planForToday,
            in: modelContext
        )
        CadenceWidgetIntentWriteSupport.publish()
        // The cleaned title, not what was typed: the dialog is a receipt for the row that was
        // written, and quoting the raw text back would name a task that does not exist.
        return .result(dialog: "Captured \(capture.title).")
    }

    /// What a typed capture resolves to, or `nil` when there is nothing to create.
    ///
    /// **T-354.** This used to be a bare `trimmingCharacters(in:)`, so the widget stored
    /// `"review launch plan !!!"` at default priority while the same words typed into the app
    /// produced a *high*-priority task titled `"review launch plan"` — the same sentence making
    /// two different tasks depending only on where it was typed, with the `!!!` left visible in
    /// the title afterwards as the artefact. `TaskTitleShortcutParsing` is the rule
    /// `TaskCreationService` resolves the shortcut through, moved into `Models/` so this target
    /// can reach it; see its note.
    ///
    /// A title that is *only* marks resolves to an empty title and creates nothing, which is the
    /// same "nothing to create" answer `TaskCreationService.insertion(from:into:)` gives.
    static func resolvedCapture(from typed: String) -> (title: String, priority: TaskPriority)? {
        var priority = TaskPriority.none
        let title = TaskTitleShortcutParsing.titleApplyingPriorityShortcut(typed, priority: &priority)
        guard !title.isEmpty else { return nil }
        return (title, priority)
    }

    static func captureTask(title: String, planForToday: Bool, in modelContext: ModelContext) throws {
        guard let capture = resolvedCapture(from: title) else { return }

        let task = AppTask(title: capture.title)
        task.priority = capture.priority
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
