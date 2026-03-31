import SwiftData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    static let schema = Schema([
        Context.self,
        Area.self,
        Project.self,
        AppTask.self,
        Subtask.self,
        DailyNote.self,
        WeeklyNote.self,
        PermNote.self,
        Document.self,
        SavedLink.self,
        Goal.self,
        Habit.self,
        HabitCompletion.self,
    ])

    init() {
        if let c = try? PersistenceController.makeContainer() {
            container = c
            return
        }
        PersistenceController.deleteStoreFiles()
        do {
            container = try PersistenceController.makeContainer()
        } catch {
            fatalError("Could not create ModelContainer even after reset: \(error)")
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")
        )
        if let c = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return c
        }
        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [localConfig])
    }

    private static func deleteStoreFiles() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if let files = try? FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.contains(".store") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        for name in ["default.store-wal", "default.store-shm"] {
            try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(name))
        }
    }
}
