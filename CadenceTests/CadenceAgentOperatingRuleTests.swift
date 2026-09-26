import Foundation
import Testing
@testable import Cadence

/// The operating rules an agent works under, for the three of them that a test can actually hold.
///
/// **T-1386.** A coordinator brief listed this repository's subagent non-negotiables and four of
/// them turned out to live in no always-read document — only in the ledger, only in
/// `docs/CODEX_REQUESTS.md`, or nowhere. Giving a rule a home is half the fix; the other half is
/// that a rule with a citation nobody can run is the defect T-1153 was filed about. So each rule
/// below is stated in `docs/SUBAGENT_RUNBOOK.md` or `AGENTS.md` **and** names this suite, and the
/// rules that cannot be checked this way say so in their own text rather than borrowing a name
/// from here.
///
/// **The notification rule was stated wrong, and that is why it is first.** It circulated as
/// *"never schedule a real user notification — use the test seam"*, which implies an opt-in. There
/// is no such seam: `NotificationManager.isTestEnvironment` reads `XCTestConfigurationFilePath`,
/// `XCTestSessionIdentifier`, `XCODE_RUNNING_FOR_PREVIEWS` and `CadenceUITestSupport.isEnabled`,
/// and every entry point guards on it, so suppression inside a test host is automatic and there is
/// nothing to opt into. What an agent can actually do wrong is defeat that guard, or schedule from
/// a process the guard does not cover — which is exactly what `CadenceWriteService`'s own header
/// says about a command-line tool.
struct CadenceAgentOperatingRuleTests {

    private static let notificationManagerPath = "Cadence/Services/NotificationManager.swift"
    private static let providerPath = "Cadence/Services/AI/AIProvider.swift"

    // MARK: - Never schedule a notification out of a process the guard does not cover

    /// One door to the OS notification centre, and it is the guarded one.
    ///
    /// Stated as an equality rather than as "no offenders": the file that must be in the answer is
    /// the non-vacuity claim, and a detector gone blind reports the empty set.
    @Test func theOnlyFileInTheAppThatReachesTheNotificationCentreIsTheGuardedManager() throws {
        let instrument = try CadenceScanInstrument(
            "names the OS notification centre",
            fires: "private lazy var center: UNUserNotificationCenter = .current()",
            andNotOn: "let request = UNNotificationRequest(identifier: id, content: c, trigger: t)",
            by: { $0.contains("UNUserNotificationCenter") }
        )

        let reached = try instrument.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            // 600 files at the time of writing; the floor only rules out a walk that found one
            // folder and called it the app.
            atLeast: 400,
            including: Self.notificationManagerPath,
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(
            reached == [Self.notificationManagerPath],
            """
            \(reached) reaches UNUserNotificationCenter outside NotificationManager, which is the \
            one type that guards on isTestEnvironment. A second door schedules real notifications \
            to the user's Notification Center under the app's bundle id (T-1386).
            """
        )
    }

    /// Every declaration that touches the centre guards on `isTestEnvironment`, and `center` stays
    /// `lazy`.
    ///
    /// The `lazy` is not a style choice: a plain stored-property initializer runs before the
    /// `init()` body, so a non-`lazy` `center` would touch the OS on every construction with the
    /// guard never having run. The declarations are named rather than counted, per the repo's own
    /// rule against a floor over a population that moves.
    @Test func everyNotificationManagerDeclarationThatTouchesTheCentreGuardsOnTheTestEnvironment() throws {
        let stripped = try CadenceCommitSurfaceScan.scanned(Self.notificationManagerPath)

        #expect(
            stripped.contains("private lazy var center: UNUserNotificationCenter = .current()"),
            """
            NotificationManager.center is no longer lazy. A stored-property initializer runs before \
            init()'s isTestEnvironment guard, so the OS is touched on every construction (T-1386).
            """
        )

        let unguarded = try CadenceScanInstrument(
            "touches the centre without the test-environment guard",
            fires: "    func schedule() async {\n        center.add(request)\n    }",
            andNotOn: "    func schedule() async {\n        guard !Self.isTestEnvironment else { return }\n        center.add(request)\n    }",
            by: { $0.contains("center.") && !$0.contains("isTestEnvironment") }
        )

        let declarations = cadenceNotificationManagerDeclarations(stripped)
        #expect(declarations.count >= 9, "parsed only \(declarations.count) declarations")

        let touching = declarations.filter { $0.body.contains("center.") }.map(\.name).sorted()
        #expect(
            touching == [
                "cancel(habitIDs)",
                "cancel(taskIDs)",
                "cancelAll()",
                "init()",
                "reconcile()",
                "refreshAuthorizationState()",
                "requestAuthorization()",
            ],
            "the declarations touching `center.` are now \(touching)"
        )

        let offenders = declarations.filter { unguarded.fires(on: $0.body) }.map(\.name).sorted()
        #expect(
            offenders.isEmpty,
            """
            \(offenders) touches the notification centre without guarding on isTestEnvironment, so \
            a test run would schedule against the user's real Notification Center (T-1386).
            """
        )
    }

    /// Suppression under test is automatic, and it is on **here** for the documented reason.
    ///
    /// Asserting `isTestEnvironment` alone would also pass if it were true by some accident; the
    /// second expectation names the variable the running process actually carries, which is what
    /// makes "there is nothing to opt into" a measured claim rather than a restatement.
    @MainActor
    @Test func notificationSuppressionInsideATestHostIsAutomaticRatherThanOptIn() throws {
        #expect(NotificationManager.isTestEnvironment)

        let environment = ProcessInfo.processInfo.environment
        #expect(
            environment["XCTestConfigurationFilePath"] != nil
                || environment["XCTestSessionIdentifier"] != nil,
            """
            this process carries neither XCTest variable, so NotificationManager.isTestEnvironment \
            is true for some other reason than being a test host (T-1386).
            """
        )

        let stripped = try CadenceCommitSurfaceScan.scanned(Self.notificationManagerPath)
        let body = try #require(
            CadenceSourceScan.declarationBody("static var isTestEnvironment: Bool", in: stripped),
            "isTestEnvironment is no longer declared the way this assertion reads it"
        )
        for key in [
            "XCTestConfigurationFilePath",
            "XCTestSessionIdentifier",
            "XCODE_RUNNING_FOR_PREVIEWS",
            "CadenceUITestSupport.isEnabled",
        ] {
            #expect(body.contains(key), "isTestEnvironment no longer consults \(key)")
        }
    }

    // MARK: - Never make a live OpenAI call with the owner's key

    /// One file names the endpoint, and it is the provider.
    @Test func theOnlyFileInTheAppThatNamesTheOpenAIEndpointIsTheProvider() throws {
        let instrument = try CadenceScanInstrument(
            "names the OpenAI endpoint",
            fires: "endpoint: URL = URL(string: \"https://api.openai.com/v1/responses\")!",
            andNotOn: "endpoint: URL = URL(string: \"https://example.com/v1/responses\")!",
            by: { $0.contains("api.openai.com") }
        )

        let reached = try instrument.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            atLeast: 400,
            including: Self.providerPath,
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(
            reached == [Self.providerPath],
            "\(reached) names api.openai.com; the provider is the one door out (T-1386)."
        )
    }

    /// **What this holds, and what it cannot.** It holds the one path an agent runs by the dozen: a
    /// test run cannot reach OpenAI, because nothing in this target builds the provider from the
    /// stored key, opens the real Keychain, or names the endpoint. It does **not** hold an agent
    /// driving the built app by hand and pressing the AI action with the owner's key in the
    /// Keychain — nothing mechanical can, and `docs/SUBAGENT_RUNBOOK.md` says so instead of
    /// implying this test covers it.
    @Test func noTestInThisTargetCanReachOpenAIWithTheOwnersKey() throws {
        let instrument = try CadenceScanInstrument(
            "reaches OpenAI or the real Keychain from a test",
            fires: "let manager = AISettingsManager(secretStore: KeychainCredentialStore())",
            andNotOn: "let manager = AISettingsManager(secretStore: InMemorySecretStore(), defaults: defaults)",
            by: { source in
                source.contains("api.openai.com")
                    || source.contains("KeychainCredentialStore(")
                    || source.contains("AISettingsManager.shared")
            }
        )

        // This file is left out of its own walk, and that is a real cost stated rather than hidden.
        // Its instrument fixtures spell the needles as string literals, so the first run reported
        // this test as the offender it exists to look for. `codeOnly` would blank those literals —
        // and with them the endpoint inside a real `URL(string:)`, which is the shape an offender
        // would take. So the reader stays the comment stripper and the scanner steps out of the
        // walk; nothing here checks this file, and the two fixtures above are what keep the
        // detector honest instead.
        let walked = try CadenceSourceScan.swiftFiles(under: "CadenceTests")
            .filter { $0 != "CadenceTests/CadenceAgentOperatingRuleTests.swift" }
        #expect(
            walked.count == (try CadenceSourceScan.swiftFiles(under: "CadenceTests").count) - 1,
            "the scanner excluded something other than exactly itself"
        )

        let offenders = try instrument.sweep(
            walked,
            atLeast: 300,
            including: "CadenceTests/AITests.swift",
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(
            offenders.isEmpty,
            """
            \(offenders) would let a scoped test run reach the owner's OpenAI key or the live \
            endpoint. Stub the secret store and assert on makeURLRequest(for:) instead (T-1386).
            """
        )
    }

    // MARK: - v1 ships English-only

    /// The product decision, as the two things that would contradict it.
    ///
    /// `docs/CODEX_REQUESTS.md` records the decision and the ledger records it twice; neither is a
    /// document an agent is told to read, which is why `AGENTS.md` now carries it. The check is the
    /// absence of localisation *resources*, which is what adding a second language starts with.
    @Test func v1ShipsEnglishOnlyAndCarriesNoLocalisationResource() throws {
        let project = try CadenceSourceScan.sourceFile("Cadence.xcodeproj/project.pbxproj")
        #expect(project.count > 400, "the project file read as \(project.count) characters")
        #expect(project.contains("developmentRegion = en;"))
        #expect(
            project.contains("knownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);"),
            "the project declares regions other than en and Base, so v1 is no longer English-only"
        )

        var walked = 0
        var resources: [String] = []
        for tree in ["Cadence", "CadenceWidgets"] {
            let root = CadenceSourceScan.repositoryRoot().appendingPathComponent(tree)
            let enumerator = try #require(FileManager.default.enumerator(atPath: root.path))
            for element in enumerator {
                guard let name = element as? String else { continue }
                walked += 1
                if name.hasSuffix(".lproj") || name.hasSuffix(".strings") || name.hasSuffix(".xcstrings") {
                    resources.append("\(tree)/\(name)")
                }
            }
        }

        #expect(walked >= 600, "walked only \(walked) entries, which is not the product tree")
        #expect(
            resources.isEmpty,
            """
            \(resources) is a localisation resource. v1 ships English-only and T-18 is deferred \
            scope rather than an oversight (T-1386); user-facing copy stays English literals.
            """
        )
    }
}

// MARK: - Reading NotificationManager a declaration at a time

struct CadenceNotificationDeclaration: Equatable {
    /// `name(firstLabel)` — the first parameter label is in the name because `cancel` is
    /// overloaded twice and both overloads touch the centre.
    let name: String
    let body: String
}

/// Splits the manager's stripped source into one block per `func`/`init`, with everything above the
/// first declaration kept as its own block so a stored property that touched the centre could not
/// hide in the gap.
func cadenceNotificationManagerDeclarations(_ stripped: String) -> [CadenceNotificationDeclaration] {
    var declarations: [CadenceNotificationDeclaration] = []
    var name = "<stored properties>"
    var body: [String] = []

    for raw in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if let declared = cadenceDeclaredName(line) {
            declarations.append(CadenceNotificationDeclaration(name: name, body: body.joined(separator: "\n")))
            name = declared
            body = []
        }
        body.append(line)
    }
    declarations.append(CadenceNotificationDeclaration(name: name, body: body.joined(separator: "\n")))
    return declarations
}

private func cadenceDeclaredName(_ line: String) -> String? {
    guard line.hasPrefix("    ") else { return nil }
    var trimmed = Substring(line.trimmingCharacters(in: .whitespaces))
    // `private nonisolated static func` stacks three of these, so this loops rather than
    // unrolling a fixed number of passes and silently missing the fourth spelling.
    while let modifier = ["private ", "nonisolated ", "static ", "override ", "final "]
        .first(where: { trimmed.hasPrefix($0) }) {
        trimmed = trimmed.dropFirst(modifier.count)
    }
    guard trimmed.hasPrefix("func ") || trimmed.hasPrefix("init(") else { return nil }
    let rest = trimmed.hasPrefix("func ") ? trimmed.dropFirst("func ".count) : trimmed
    let base = rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
    let afterParen = rest.dropFirst(base.count).dropFirst()
    let label = afterParen.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
    return "\(base)(\(label))"
}
