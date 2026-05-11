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
        let container = try CadenceStoreSupport.makeSharedContainer(
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let modelContext = ModelContext(container)
        let changed = try Self.completeTask(taskID: taskID, in: modelContext)
        if changed {
            if let uuid = UUID(uuidString: taskID) {
                CadenceWidgetRefreshCenter.markTaskCompleted(uuid)
            }
            CadenceWidgetRefreshCenter.reloadTodayWidgets(force: true)
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

        task.status = .done
        task.completedAt = Date()
        try modelContext.save()
        return true
    }
}
