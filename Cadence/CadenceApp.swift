import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Context.self,
            Area.self,
            Project.self,
            AppTask.self,
            DailyNote.self,
            Document.self,
            SavedLink.self,
            Goal.self,
            Habit.self,
            HabitCompletion.self,
        ])

        func makeContainer() throws -> ModelContainer {
            let cloudConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")
            )
            if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
                return container
            }
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [localConfig])
        }

        if let container = try? makeContainer() { return container }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if let files = try? FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.contains(".store") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        for name in ["default.store-wal", "default.store-shm"] {
            try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(name))
        }

        do {
            return try makeContainer()
        } catch {
            fatalError("Could not create ModelContainer even after reset: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
#if os(macOS)
            macOSRootView()
                .environment(CalendarManager.shared)
                .environment(FocusManager.shared)
#else
            iOSRootView()
#endif
        }
        .modelContainer(sharedModelContainer)
    }
}
