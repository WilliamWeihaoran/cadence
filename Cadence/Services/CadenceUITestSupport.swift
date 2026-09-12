import Foundation
import OSLog
import SwiftData

enum CadenceUITestSupport {

    private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "UITestSupport")

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CADENCE_UI_TEST_MODE"] == "1"
    }

    @MainActor
    static func prepareAppState(modelContext: ModelContext) {
        guard isEnabled else { return }

        if ProcessInfo.processInfo.environment["CADENCE_RESET_USER_DEFAULTS"] == "1" {
            if mayResetUserDefaults() {
                resetUserDefaults()
            } else {
                logger.error(
                    """
                    CADENCE_RESET_USER_DEFAULTS on the SHARED defaults domain: refusing. \
                    This launch carries no -CadenceSuiteName, so the four keys the reset \
                    removes would be the signed-in person's own (T-1157).
                    """
                )
            }
        }

        seedDataIfNeeded(modelContext: modelContext)
        // After the stock seed, never instead of it: a scenario adds Today's state on top of the
        // three sidebar lists every UI test already expects. See `CadenceUITestScenarioSeed`.
        CadenceUITestScenarioSeed.seedIfRequested(modelContext: modelContext)
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

    /// Whether a requested reset is allowed to delete anything — **T-1157**.
    ///
    /// `resetUserDefaults` below removes four keys, and it removes them from
    /// `CadenceDefaults.store`. That store is a private per-launch suite **only** when the launch
    /// passed `-CadenceSuiteName`; with no such argument it *is* `UserDefaults.standard`, which
    /// inside this app's container is the signed-in person's own `com.haoranwei.Cadence.plist`.
    /// Measured 2026-09-12 at `4efd003`: that file held **86 keys** and had been written the same
    /// morning, and neither `scripts/run-macos-app.sh` nor any of the four `XCUIApplication`
    /// launches in `CadenceUITests` passed the argument — so every UI run `AGENTS.md` tells an
    /// agent to make deleted `listDetailDefaultPage`, `sidebarHiddenTabs`, `sidebarTabOrder` and
    /// `sidebarTabColors` out of it.
    ///
    /// Both launchers pass the argument now. This is the half that does not depend on their
    /// getting it right: the argument is a *string*, `CadenceDefaults.suiteName(forAgentID:)`
    /// refuses a malformed one by **falling back to the shared domain**, and that fallback is
    /// silent by design — it is the product's own behaviour, so it cannot be made loud there. A
    /// mistyped id would therefore put the deletion straight back over the shared domain with
    /// nothing to show for it. Asking the resolved store *which domain it actually is* cannot be
    /// mistyped, and it is the only question whose answer is the hazard itself.
    ///
    /// Pure, and parameterised, so it is driven rather than launched. The "is this the shared
    /// domain" half is `CadenceDefaults.isPrivateSuite` rather than a comparison written here:
    /// naming the shared domain in this file is itself the T-745 defect, and
    /// `CadenceDefaultsRoutingSweepTests` failed on the first version of this function for saying
    /// `UserDefaults = .standard` in a parameter default.
    static func mayResetUserDefaults(store: UserDefaults = CadenceDefaults.store) -> Bool {
        CadenceDefaults.isPrivateSuite(store)
    }

    private static func resetUserDefaults() {
        // Read from `CadencePreferenceKeys` rather than re-typed: a key renamed there used to
        // leave this list quietly resetting a defaults entry nothing writes any more, which is a
        // UI-test reset that stops resetting without failing.
        let keys = [
            CadencePreferenceKeys.listDetailDefaultPage,
            CadencePreferenceKeys.sidebarHiddenTabs,
            CadencePreferenceKeys.sidebarTabOrder,
            CadencePreferenceKeys.sidebarTabColors,
        ]

        for key in keys {
            CadenceDefaults.store.removeObject(forKey: key)
        }
    }
}
