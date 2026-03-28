import SwiftUI
import SwiftData

@main
struct CadenceApp: App {
    var sharedModelContainer: ModelContainer = PersistenceController.shared.container

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
