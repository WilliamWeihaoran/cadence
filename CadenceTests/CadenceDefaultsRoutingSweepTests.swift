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
/// The exemption is *derived*, not asserted. `CadenceDefaults.swift` is not in the `CadenceWidgets`
/// Sources phase, so a file that target also compiles physically cannot reference it —
/// `theSharedTargetExemptionNamesFilesTheRouterCannotReach` measures exactly that rather than
/// taking it on trust. **Two** files are exempt for that reason, and both are the app-group suite,
/// which is a deliberate second store: the widget is another process, and `Theme`'s accent and
/// `CadenceWidgetRefreshCenter`'s reload state are the two things both processes must agree about.
///
/// ## The other two exemptions are gone, and so is the write they were hiding ([[T-1170]])
///
/// `DataIntegrityRepairService` and `NoteMigrationService` were exempt on the same *derived*
/// footing — `CadenceMCPServer` compiles them and had no router to route through. That reason was
/// about a build graph and not about who owns the file being written, and the difference was
/// measured rather than argued: the signed-in person's own `com.haoranwei.Cadence.plist` came out
/// of an ordinary `xcodebuild test` run with the same 86 keys and two different **values**, both
/// `…lastReport.v1`, stamped inside the run. A debug test host carries bundle id
/// `com.haoranwei.Cadence`, so it gets their container, and `UserDefaults.standard` there is their
/// file.
///
/// Two changes, and it takes both. `Cadence/Shared/CadenceDefaults.swift` is in `CadenceMCPServer`'s
/// Sources phase now, so those two services route like everything else; and the shared scheme's
/// `TestAction` passes `-CadenceSuiteName xctest-host`, so the store they route *to* is a private
/// suite rather than the person's own domain. Routing alone would have changed nothing — with no
/// launch argument `CadenceDefaults.store` **is** `UserDefaults.standard`, which is exactly why
/// routing was safe to do to a hot file in T-745 and exactly why it is not a fix by itself.
///
/// ## And the test target is swept too, since the leak was in both halves
///
/// `noTestInThisTargetWritesTheSignedInPersonsOwnPreferences` applies the same rule to
/// `CadenceTests/`, where the old guard's own snapshot-and-restore read `UserDefaults.standard`
/// while the service it guarded had moved. Its ledger counts **occurrences, not files**: a
/// per-file allowance is a file that can grow a second site behind its first one.
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
            "CadenceWidgets compiles it; the reload throttle and completion overrides are app-group state"
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

        // **The MCP half went the other way ([[T-1170]]).** The router used to be out of that
        // target's reach, and the two launch-report services were exempt for that reason alone —
        // a statement about a build graph, not about who owns the file being written. The file is
        // in `CadenceMCPServer`'s Sources phase now, which is what makes their routing compile, so
        // this reads as a *requirement*: drop the router from that phase and both services are
        // offenders again rather than quietly re-exempt.
        #expect(mcp.contains(Self.routerPath),
                "CadenceMCPServer stopped compiling the router, so its files cannot route")

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

    // MARK: - The test target's own reach (T-1170)

    /// The spellings that are forbidden in `CadenceTests/`, derived from the app's list rather than
    /// re-typed beside it — minus the one that is legitimate here.
    ///
    /// `UserDefaults(suiteName:)` is how a test opens a store of its own; `withTemporaryDefaults`
    /// is built on it and `TemporaryDefaultsSuiteRule` already governs how the name is minted. What
    /// is never legitimate is the *device-wide domain*, which inside this container is the
    /// signed-in person's `com.haoranwei.Cadence.plist`.
    static let sharedDomainNeedles = unroutedNeedles.filter { $0 != "UserDefaults(suiteName:" }

    /// How many shared-domain spellings each test file is allowed, and why.
    ///
    /// **A count, not a membership.** Every allowlist this repository has been bitten by was a set
    /// of *files*: the entry earns its keep once and then vouches for whatever is typed into that
    /// file afterwards. Pinning the number means a new site in a ledgered file fails here as
    /// loudly as a new site anywhere else, and a ledgered file that stops offending fails too.
    static let sharedDomainTestSites: [String: (count: Int, reason: String)] = [
        "CadenceTests/CadenceAgentDefaultsIsolationTests.swift": (
            12,
            "the router's own suite: the fallback it measures IS the shared domain, so it must name it"
        ),
        "CadenceTests/CadenceAccentPaletteTests.swift": (
            1,
            "one identity check that the app-group store the widget reads is not the device-wide domain"
        )
    ]

    /// No test in this target resolves a preference against the signed-in person's own domain.
    @Test func noTestInThisTargetWritesTheSignedInPersonsOwnPreferences() throws {
        let instrument = try Self.sharedDomainInstrument()
        let hits = try instrument.sweep(
            try cadenceTestFiles(),
            atLeast: 300,
            including: "CadenceTests/CadenceAgentDefaultsIsolationTests.swift",
            read: cadenceTestSource
        )

        let unledgered = hits.filter { Self.sharedDomainTestSites[$0] == nil }.sorted()
        #expect(unledgered.isEmpty, """
            these test files name `UserDefaults.standard`, which in this target is the signed-in \
            person's own `com.haoranwei.Cadence.plist` — the test host carries the app's bundle id \
            and so gets their container (T-1170). Route the site through `CadenceDefaults.store`, \
            which a `CadenceTests` run resolves to the private `xctest-host` suite, or open a suite \
            of your own with `withTemporaryDefaults`. Offenders: \(unledgered).
            """)

        // The other direction, per occurrence. A ledgered file that stopped offending is an
        // exemption vouching for nothing; one that grew a second site would otherwise hide behind
        // the first.
        for (path, entry) in Self.sharedDomainTestSites {
            let counted = Self.sharedDomainCount(in: try cadenceTestSource(path))
            #expect(counted == entry.count, """
                \(path) holds \(counted) shared-domain sites, not the \(entry.count) ledgered \
                (\(entry.reason)). If the new one is deliberate, say so by moving the number.
                """)
        }
    }

    /// **The containment, in the host that is running this line.**
    ///
    /// Everything above reads text; this asks the process. The scheme argument is the only reason
    /// `CadenceDefaults.store` is not the person's own domain during a test run, and an argument is
    /// exactly the kind of thing that survives in a file while failing to arrive — `xcodebuild`
    /// could stop forwarding it, a test plan could shadow the scheme, or someone could tidy the
    /// `TestAction`. The probe round-trip names *which* suite rather than merely "not that one":
    /// `suiteName(forAgentID:)` falls back to the shared domain for a malformed id, silently and by
    /// design, so "is private" alone would pass for a typo that redirected nothing.
    @Test func theTestHostResolvesItsPreferencesToTheXCTestSuite() throws {
        #expect(CadenceDefaults.isPrivateSuite(CadenceDefaults.store), """
            this test host resolves preferences against `UserDefaults.standard`, so anything it \
            writes lands in the signed-in person's own com.haoranwei.Cadence.plist (T-1170). The \
            scheme's TestAction should be passing -\(CadenceDefaults.suiteNameArgumentKey) \
            \(Self.testHostSuiteID).
            """)

        // Read out of the `TestAction` specifically. The same text in the `LaunchAction` would
        // satisfy a whole-file `contains` while redirecting nothing here — and would be wrong for
        // its own reason: a human running Cadence from Xcode should see their own preferences, not
        // a suite the test target chose. `CadenceTimeZoneIndependenceTests` keeps `TZ` and
        // `AppleLocale` off the LaunchAction for the same reason.
        let scheme = try cadenceTestSource(Self.schemePath)
        let argument = "-\(CadenceDefaults.suiteNameArgumentKey) \(Self.testHostSuiteID)"
        let testAction = try #require(
            Self.schemeSection(of: scheme, from: "<TestAction", to: "</TestAction>"),
            "the scheme no longer has a TestAction"
        )
        let launchAction = try #require(
            Self.schemeSection(of: scheme, from: "<LaunchAction", to: "</LaunchAction>"),
            "the scheme no longer has a LaunchAction"
        )
        #expect(
            testAction.contains(argument),
            "the TestAction stopped passing \(argument), which is what this containment rests on"
        )
        #expect(
            !launchAction.contains("-\(CadenceDefaults.suiteNameArgumentKey)"),
            """
            the LaunchAction redirects preferences too, so a human running Cadence from Xcode is \
            now looking at a suite the test suite named rather than at their own settings
            """
        )

        let suiteName = try #require(CadenceDefaults.suiteName(forAgentID: Self.testHostSuiteID))
        let suite = try #require(UserDefaults(suiteName: suiteName))
        let probeKey = "cadence.tests.t1170.\(UUID().uuidString)"
        defer { CadenceDefaults.store.removeObject(forKey: probeKey) }

        CadenceDefaults.store.set("routed", forKey: probeKey)
        #expect(
            suite.string(forKey: probeKey) == "routed",
            "the host's store is some private suite, but not \(suiteName)"
        )
    }

    /// The id the shared scheme passes. Spelled once; the scheme is scanned for this exact text.
    static let testHostSuiteID = "xctest-host"

    static let schemePath = "Cadence.xcodeproj/xcshareddata/xcschemes/Cadence.xcscheme"

    /// One `<Action …>…</Action>` block of a scheme, or `nil` if it is not there.
    static func schemeSection(of scheme: String, from opening: String, to closing: String) -> String? {
        guard let start = scheme.range(of: opening),
              let end = scheme.range(of: closing, range: start.upperBound..<scheme.endIndex)
        else { return nil }
        return String(scheme[start.lowerBound..<end.upperBound])
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

    /// How many shared-domain spellings a source holds, with comments and string literals blanked.
    static func sharedDomainCount(in source: String) -> Int {
        let code = CadenceSourceScan.codeOnly(source)
        return sharedDomainNeedles.reduce(0) { total, needle in
            total + code.components(separatedBy: needle).count - 1
        }
    }

    /// The witnesses are the two halves of the T-1170 fix on one line: the write as it was, and the
    /// same write routed. A detector that stopped reading either one fails the constructor.
    static func sharedDomainInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "aTestReachesTheSharedDefaultsDomain",
            fires: "UserDefaults.standard.set(data, forKey: key)",
            andNotOn: "CadenceDefaults.store.set(data, forKey: key)",
            by: { sharedDomainCount(in: $0) > 0 }
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
