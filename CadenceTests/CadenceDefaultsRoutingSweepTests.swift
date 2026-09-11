import Foundation
import Testing
@testable import Cadence

/// **T-745 (T-949 is the same ticket, re-counted).** Where a preference resolves, pinned as a rule
/// rather than as a list of correct call sites.
///
/// [[T-735]] redirected `@AppStorage` at the scene (`.defaultAppStorage(CadenceDefaults.store)`)
/// and pointed `CadenceCalendarDateMemory` at the same store. Those were the only two routed
/// readers in the app, and `CadenceDefaults`' own doc comment said so — which is a header, and a
/// header only helps whoever reads it before writing the next `UserDefaults.standard`.
///
/// ## What was measured, and where the filed audit was wrong
///
/// T-949's census reproduces exactly at `a92b659`: **19** non-comment `UserDefaults.standard`
/// references outside `CadenceDefaults.swift`. Its conclusion is also right — none of them diverges
/// in a shipping configuration, because `CadenceDefaults.store` **is** `UserDefaults.standard`
/// unless a `-CadenceSuiteName` launch argument is present, and only `scripts/simulator-claim.sh`
/// passes one. There is no product bug here and there never was one.
///
/// But 19 is not the exposure, because that census greps one spelling. Counted three ways over the
/// same tree, `Cadence/` held **33** unrouted sites:
///
/// - 19 literal `UserDefaults.standard` reads and writes — the filed number;
/// - **12** defaulted parameters spelled `defaults: UserDefaults = .standard`, in
///   `PersistenceController` (6), `PursuitToGoalMigration`, `AISettingsManager`,
///   `AppleAccountManager`, `CadenceCalendarLinkObservations`, `CadenceNotesEditorPreferences`;
/// - **2** `UserDefaults(suiteName: CadenceStoreSupport.appGroupIdentifier)` sites, which are a
///   *third* store and were invisible to both filings.
///
/// Six keys were reachable through two stores at once — `notificationsEnabled`,
/// `noteTemplateOverrides`, the hidden-calendar list, the observed-calendar list, the four
/// `CadencePreferenceKeys` the UI-test reset clears, and the retired key `purgeRetiredKeys` drops —
/// each written through `@AppStorage` (routed) and read through `.standard` (not). They agree today
/// only because no launch argument is present, which is the sense in which the app had no invariant
/// here at all.
///
/// ## The rule this file enforces
///
/// A file the **app target alone** compiles must not name `UserDefaults.standard`,
/// `UserDefaults(suiteName:)`, or a `.standard` default: it resolves through `CadenceDefaults.store`.
///
/// **It was red before it was green**, which is the only thing that separates a census from a
/// decoration: run against `a92b659` unchanged it named twelve files —
/// `AISettingsManager`, `CadenceUITestSupport`, `MarkdownNoteSupport`, `NotificationManager`,
/// `PersistenceController`, `PursuitToGoalMigration`, `CadenceCalendarLinkObservations`,
/// `CadenceCalendarVisibilityPreferences`, `CadenceNotesEditorPreferences`, `AppleAccountManager`,
/// `ListDetailView`, `TasksPanel` — and those twelve are exactly what the same commit routes.
///
/// The exemption is *derived*, not asserted. `CadenceDefaults.swift` is in neither the
/// `CadenceWidgets` nor the `CadenceMCPServer` Sources phase, so a file those targets also compile
/// physically cannot reference it — `theSharedTargetExemptionNamesFilesTheRouterCannotReach`
/// measures exactly that rather than taking it on trust. Four files are exempt for that reason, and
/// two of them are the app-group suite, which is a deliberate second store: the widget is another
/// process, and `Theme`'s accent and `CadenceWidgetRefreshCenter`'s reload state are the two things
/// both processes must agree about.
///
/// ## Known limit, stated rather than papered over
///
/// The detector reads spellings. It catches the three that exist plus the three named-argument
/// forms (`defaults:`, `userDefaults:`, `in:`); it cannot catch a bare `.standard` passed
/// *positionally* into a `UserDefaults` parameter, because `.standard` is also a
/// `CadenceAccentPalette` case and matching it alone would fire on colour code. One such site
/// existed — `TasksPanel`'s `storedSortMode(in: .standard, …)` — which is why `in:` is a needle.
struct CadenceDefaultsRoutingSweepTests {

    /// The router itself. It reads the argument domain off `UserDefaults.standard`, which is the
    /// one place in the app that has to.
    static let routerPath = "Cadence/Shared/CadenceDefaults.swift"

    /// Files that keep an unrouted store **because a target that cannot compile `CadenceDefaults`
    /// also compiles them**, with the store each one actually reaches.
    ///
    /// Read in both directions by the tests below: a file here that stops offending, or that stops
    /// being a member of a second target, is an exemption vouching for nothing.
    static let sharedTargetSites: [String: String] = [
        "Cadence/Shared/Theme.swift":
            "CadenceWidgets compiles it; the accent id is app-group state two processes must agree on",
        "Cadence/Services/CadenceWidgetRefreshCenter.swift":
            "CadenceWidgets compiles it; the reload throttle and completion overrides are app-group state",
        "Cadence/Services/DataIntegrityRepairService.swift":
            "CadenceMCPServer compiles it, and that target has no CadenceDefaults to route through",
        "Cadence/Services/NoteMigrationService.swift":
            "CadenceMCPServer compiles it, and that target has no CadenceDefaults to route through"
    ]

    /// Every spelling of "some store other than the one this app resolves preferences against".
    ///
    /// `UserDefaults = .standard` rather than `= .standard`: the latter is a legal default for any
    /// type with a `standard` member and would read a `CadenceAccentPalette` as a defaults store.
    static let unroutedNeedles = [
        "UserDefaults.standard",
        "UserDefaults(suiteName:",
        "UserDefaults = .standard",
        "defaults: .standard",
        "userDefaults: .standard",
        "in: .standard"
    ]

    // MARK: - The sweep

    /// No file the app target alone compiles reaches a store other than `CadenceDefaults.store`.
    @Test func everyPreferenceInTheAppTargetResolvesThroughTheDefaultsRouter() throws {
        let hits = try Self.unroutedFiles()

        // The two categories that are allowed, each for a reason a test below checks.
        let offenders = hits
            .filter { $0 != Self.routerPath }
            .filter { Self.sharedTargetSites[$0] == nil }
            .sorted()

        #expect(offenders.isEmpty, """
            a file only the app target compiles resolves a preference against a store the app does \
            not read. `@AppStorage` and `CadenceCalendarDateMemory` go through \
            `CadenceDefaults.store`; a site that says `UserDefaults.standard` instead is the same \
            key in a second store, which agrees with the first only while no `-CadenceSuiteName` \
            launch argument is present (T-745/T-949). Route it through `CadenceDefaults.store`, or \
            — only if a target that cannot see `CadenceDefaults` also compiles the file — add it to \
            `sharedTargetSites` with the reason. Offenders: \(offenders).
            """)
    }

    /// The exemption's premise, measured rather than asserted: `CadenceDefaults.swift` is in
    /// neither explicit Sources phase, so a file those targets compile genuinely cannot route.
    ///
    /// Both directions. A ledgered file that is no longer a second target's member, or no longer
    /// reaches an unrouted store, is an exemption that has outlived its reason.
    @Test func theSharedTargetExemptionNamesFilesTheRouterCannotReach() throws {
        let widgets = try TargetSourceGraph(
            name: "CadenceWidgets",
            // Widget-only file: no other target builds the intents.
            phaseAnchor: "Cadence/Services/CadenceWidgetIntents.swift",
            synchronizedRoots: ["CadenceWidgets"],
            ownFolder: "CadenceWidgets"
        ).memberFiles
        let mcp = try cadenceMCPServerMemberFiles()

        #expect(widgets.count >= 35, "the widget source list parsed as \(widgets.count) files")
        #expect(mcp.count >= 40, "the MCP source list parsed as \(mcp.count) files")

        // The premise. If either target ever compiles the router, the exemption below is no longer
        // "cannot" but "did not", and every file in it should be routed instead.
        #expect(!widgets.contains(Self.routerPath),
                "CadenceWidgets compiles the router now, so its files can and should route")
        #expect(!mcp.contains(Self.routerPath),
                "CadenceMCPServer compiles the router now, so its files can and should route")

        let hits = Set(try Self.unroutedFiles())
        for (path, reason) in Self.sharedTargetSites {
            #expect(widgets.contains(path) || mcp.contains(path),
                    "\(path) is app-only now, so it can route; the exemption (\(reason)) is stale")
            #expect(hits.contains(path),
                    "\(path) no longer reaches an unrouted store; drop its exemption")
        }

        // And the router itself still does the one unrouted read that resolves everything else.
        #expect(hits.contains(Self.routerPath), "the router stopped reading the argument domain")
    }

    /// The walk opened `Cadence/iOS/`, which the macOS test target compiles no symbol from and
    /// which holds 106 of the 587 files this rule covers.
    @Test func theRoutingSweepReachesTheIOSTreeAndTheMacOne() throws {
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(paths.contains("Cadence/iOS/iOSSettingsView.swift"),
                "the sweep never reached the iOS settings surface")
        #expect(paths.contains("Cadence/macOS/Views/SettingsView.swift"),
                "the sweep never reached the macOS settings surface")
        #expect(paths.filter { $0.hasPrefix("Cadence/iOS/") }.count >= 100,
                "the iOS tree read as fewer than the 106 files it holds")
    }

    // MARK: - The instrument is not vacuous

    /// The detector against literal fixtures: a fixture read out of the tree can be retuned by the
    /// same edit that breaks the rule. The negative witness is the *fixed* form of the positive
    /// one, which is the nearest pair there is.
    @Test func theRoutingDetectorSeparatesARoutedReadFromAnUnroutedOne() throws {
        let instrument = try Self.instrument()

        #expect(instrument.fires(on: "let raw = UserDefaults.standard.string(forKey: key) ?? \"\""))
        #expect(instrument.fires(on: "static func purge(in defaults: UserDefaults = .standard) {}"))
        #expect(instrument.fires(on: "UserDefaults(suiteName: CadenceStoreSupport.appGroupIdentifier)"))
        #expect(instrument.fires(on: "Self.storedSortMode(in: .standard, fallback: mode)"))

        #expect(!instrument.fires(on: "let raw = CadenceDefaults.store.string(forKey: key) ?? \"\""))
        #expect(!instrument.fires(on: "static func purge(in defaults: UserDefaults = CadenceDefaults.store) {}"))
        #expect(!instrument.fires(on: "palette = CadenceAccentPalette.standard"),
                "a bare `.standard` on the accent palette was read as a defaults store")
        #expect(!instrument.fires(on: "// UserDefaults.standard is not read here any more"),
                "the detector counted a comment as code")
        #expect(!instrument.fires(on: "let note = \"UserDefaults.standard\""),
                "the detector counted a string literal as code")
    }

    // MARK: - Scanning

    /// Paths under `Cadence/` whose **code** — comments and string literals blanked — names a store
    /// other than `CadenceDefaults.store`.
    static func unroutedFiles() throws -> [String] {
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence").sorted()
        return try Self.instrument().sweep(
            paths,
            atLeast: 500,
            including: Self.routerPath,
            read: CadenceSourceScan.sourceFile
        )
    }

    static func instrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "unroutedDefaultsStore",
            fires: "let enabled = UserDefaults.standard.bool(forKey: key)",
            andNotOn: "let enabled = CadenceDefaults.store.bool(forKey: key)",
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                return Self.unroutedNeedles.contains { code.contains($0) }
            }
        )
    }
}
