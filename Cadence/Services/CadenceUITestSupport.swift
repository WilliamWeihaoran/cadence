import Foundation
import SwiftData

enum CadenceUITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CADENCE_UI_TEST_MODE"] == "1"
    }

    @MainActor
    static func prepareAppState(modelContext: ModelContext) {
        guard isEnabled else { return }

        if ProcessInfo.processInfo.environment["CADENCE_RESET_USER_DEFAULTS"] == "1" {
            resetUserDefaults()
        }

        seedDataIfNeeded(modelContext: modelContext)
    }

    @MainActor
    private static func seedDataIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Context>()
        let existingContexts = (try? modelContext.fetch(descriptor)) ?? []
        guard existingContexts.isEmpty else { return }

        let context = Context(name: "UI Test Workspace", colorHex: "#5AA2FF", icon: "square.stack.3d.up.fill")
        context.order = 0

        let alphaArea = Area(name: "Alpha Area", context: context, colorHex: "#5AA2FF", icon: "folder.fill")
        alphaArea.order = 0

        let betaProject = Project(name: "Beta Project", context: context, colorHex: "#FFB84D")
        betaProject.icon = "checklist"
        betaProject.order = 1

        let gammaArea = Area(name: "Gamma Area", context: context, colorHex: "#4ECB71", icon: "tray.full.fill")
        gammaArea.order = 2

        modelContext.insert(context)
        modelContext.insert(alphaArea)
        modelContext.insert(betaProject)
        modelContext.insert(gammaArea)
        try? modelContext.save()
    }

    private static func resetUserDefaults() {
        let keys = [
            "selectedTheme",
            "listDetailDefaultPage",
            "sidebarHiddenTabs",
            "sidebarTabOrder",
            "sidebarTabColors",
        ]

        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
