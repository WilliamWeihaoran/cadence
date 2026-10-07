import Foundation
import Testing
@testable import Cadence

/// [[T-3013]]. The gate that stops a development-signed build mirroring the owner's real store into
/// CloudKit's **Development** environment — and, much more importantly, the pins that stop that
/// gate ever refusing a build it should not refuse.
///
/// [[T-2053]] established the damage by forensics and then by direct observation: one SwiftData
/// store was mirrored into two CloudKit environments, `NSPersistentCloudKitContainer` keeps no
/// environment discriminator, so whichever build ran last marked records as already-exported and
/// the other believed it. The owner's Mac stopped reaching the owner's iPad for four weeks.
///
/// **The whole risk of the fix is that it has the same symptom as the bug.** A guard that refuses
/// when it should not stops the owner's real Mac syncing, silently, and looks exactly like
/// [[T-2053]] from the outside. So the table below is exhaustive on purpose, and more than half of
/// its rows exist to assert that something does **not** refuse.
struct CadenceSigningEnvironmentTests {

    // MARK: - The pure gate, exhaustively

    /// Every value the entitlement can present, and the verdict each one earns.
    ///
    /// One row refuses. Every other row — including all four ways the question could not be
    /// answered at all — keeps syncing. See `CadenceSigningEnvironment`'s doc comment for why the
    /// two errors are not symmetric and why this asymmetry must not be "fixed".
    @Test func theTruthTableRefusesOnlyTheLiteralDevelopmentMarker() {
        let table: [(String?, CadenceSigningEnvironment.Verdict)] = [
            // The one and only refusal.
            ("development", .developmentSigned),

            // A Release build — TestFlight, the App Store, and the installed copy in
            // /Applications. Never refused.
            ("production", .notPositivelyDevelopment),

            // No entitlement, an unreadable one, a failed Security call, a value that was not a
            // String: `pushEnvironmentEntitlementOfCurrentProcess` answers `nil` for all of them.
            (nil, .notPositivelyDevelopment),

            // Present and empty.
            ("", .notPositivelyDevelopment),

            // Capitalisation this build cannot emit. `com.apple.developer.icloud-container-environment`
            // is the capitalised spelling, and it is deliberately NOT what this gate reads.
            ("Development", .notPositivelyDevelopment),
            ("DEVELOPMENT", .notPositivelyDevelopment),
            ("PRODUCTION", .notPositivelyDevelopment),
            ("Production", .notPositivelyDevelopment),

            // Whitespace is not trimmed, for the same reason case is not folded: trimming widens
            // the set of values that refuse.
            (" development", .notPositivelyDevelopment),
            ("development ", .notPositivelyDevelopment),
            ("\tdevelopment\n", .notPositivelyDevelopment),

            // Not a prefix match, not a substring match.
            ("development-build", .notPositivelyDevelopment),
            ("not-development", .notPositivelyDevelopment),

            // An unexpanded build setting, which is what a misconfigured target would ship.
            ("$(APS_ENVIRONMENT)", .notPositivelyDevelopment),

            // Garbage.
            ("hunter2", .notPositivelyDevelopment),
            ("0", .notPositivelyDevelopment),
            ("<null>", .notPositivelyDevelopment),
        ]

        for (value, expected) in table {
            #expect(
                CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: value) == expected,
                "the gate's verdict for \(value.map { "\"\($0)\"" } ?? "nil") is not \(expected)"
            )
        }

        // The table is not vacuous: it really does contain both answers.
        let verdicts = Set(table.map { CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: $0.0) })
        #expect(verdicts == [.developmentSigned, .notPositivelyDevelopment])
    }

    /// The named pin on the fail direction, and the test the [[T-3013]] mutation run inverted the
    /// gate to kill.
    ///
    /// Separate from the table above even though the table covers `nil`, because this is the row
    /// whose failure is catastrophic and silent, and a reviewer deleting a row from a table is a
    /// much quieter act than deleting a test with this name.
    @Test func anUnreadableEntitlementKeepsSyncingRatherThanRefusing() {
        #expect(CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: nil) == .notPositivelyDevelopment)
        #expect(!CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: nil).mustOpenLocalStoreOnly)

        #expect(!CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: "production").mustOpenLocalStoreOnly)
        #expect(!CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: "").mustOpenLocalStoreOnly)
        #expect(!CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: "Development").mustOpenLocalStoreOnly)

        // And the one that does.
        #expect(CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: "development").mustOpenLocalStoreOnly)
    }

    /// The impure wrapper holds no decision of its own.
    ///
    /// This is what makes "a pure, testable gate" true rather than merely claimed: if the wrapper
    /// ever grew a branch, the table above would stop describing what the app does.
    @Test func theImpureWrapperOnlyDelegates() {
        for value in ["development", "production", "", "Development", nil] as [String?] {
            #expect(
                CadenceSigningEnvironment.currentProcessVerdict(entitlement: value)
                    == CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: value)
            )
        }
    }

    /// The Security call runs, does not trap, and reads back something from this process's own
    /// vocabulary — not an assertion about which environment the test host happens to be signed
    /// for, which is a property of whoever built it.
    @Test func readingThisProcessEntitlementAnswersFromTheKnownVocabulary() {
        let value = CadenceSigningEnvironment.pushEnvironmentEntitlementOfCurrentProcess()
        #expect(
            value == nil || value == "development" || value == "production",
            "this process's push entitlement read back as \(value ?? "nil"), which is outside Apple's two values"
        )
    }

    /// Both spellings are read, platform-native first, and neither is dropped.
    @Test func bothPlatformSpellingsOfThePushKeyAreRead() {
        let keys = CadenceSigningEnvironment.pushEnvironmentEntitlementKeys
        #expect(Set(keys) == ["com.apple.developer.aps-environment", "aps-environment"])
        #expect(keys.count == 2)
        #if os(macOS)
        #expect(keys.first == "com.apple.developer.aps-environment")
        #else
        #expect(keys.first == "aps-environment")
        #endif
    }

    // MARK: - The iOS reader, which cannot use SecTask at all

    /// `SecTask` is macOS-only — `SecTask.h` is in `MacOSX.sdk` and not in `iPhoneOS.sdk` — so the
    /// iOS half reads the push environment out of the bundle's embedded provisioning profile
    /// instead. The parser compiles on both platforms precisely so this macOS-built suite can
    /// drive it, over bytes this test writes itself.
    ///
    /// The fixture is shaped like a real `.mobileprovision`: a CMS envelope with binary noise on
    /// both sides of one XML property list. It carries the **bare** `aps-environment` spelling,
    /// which is iOS's, so a reader that only ever looked for the macOS spelling fails this.
    @Test func theProvisioningProfileReaderFindsBothSpellingsInsideACMSEnvelope() throws {
        for (key, value) in [("aps-environment", "production"), ("com.apple.developer.aps-environment", "development")] {
            let profile = try provisioningProfileFixture(entitlements: [key: value])
            #expect(CadenceSigningEnvironment.pushEnvironmentEntitlement(inProvisioningProfile: profile) == value)
        }

        // And the verdicts those two produce, which is the point of reading it at all.
        let release = try provisioningProfileFixture(entitlements: ["aps-environment": "production"])
        let debug = try provisioningProfileFixture(entitlements: ["aps-environment": "development"])
        #expect(
            CadenceSigningEnvironment.verdict(
                forPushEnvironmentEntitlement: CadenceSigningEnvironment.pushEnvironmentEntitlement(inProvisioningProfile: release)
            ) == .notPositivelyDevelopment
        )
        #expect(
            CadenceSigningEnvironment.verdict(
                forPushEnvironmentEntitlement: CadenceSigningEnvironment.pushEnvironmentEntitlement(inProvisioningProfile: debug)
            ) == .developmentSigned
        )
    }

    /// Every malformed profile answers `nil`, and `nil` keeps syncing.
    ///
    /// This is the iOS half of the fail direction: the reader is a *witness* rather than the signed
    /// entitlement itself, and that is only safe because nothing it fails to understand can refuse.
    @Test func aProfileThisReaderCannotUnderstandKeepsSyncing() throws {
        let malformed: [Data] = [
            Data(),
            Data("not a provisioning profile at all".utf8),
            // An envelope with no property list in it.
            Data([0x30, 0x82, 0x0A, 0x0B] + Array(repeating: UInt8(0xAB), count: 64)),
            // A property list that is not a dictionary.
            Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><array/></plist>".utf8),
            // Truncated: an opening delimiter and no closing one.
            Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>".utf8),
            // A well-formed profile with no entitlements at all.
            try provisioningProfileFixture(entitlements: [:]),
            // Entitlements present, push key absent.
            try provisioningProfileFixture(entitlements: ["get-task-allow": "true"]),
        ]

        for data in malformed {
            let value = CadenceSigningEnvironment.pushEnvironmentEntitlement(inProvisioningProfile: data)
            #expect(value == nil, "a malformed profile produced \(value ?? "nil") instead of nil")
            #expect(
                CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: value) == .notPositivelyDevelopment
            )
        }
    }

    /// The bundle lookup is a lookup, not an assumption: a bundle with no `embedded.mobileprovision`
    /// answers `nil` rather than guessing.
    ///
    /// Driven over a bundle this test builds under its **own** temporary directory. Nothing here
    /// reads the running app's container.
    @Test func aBundleWithNoEmbeddedProfileAnswersNil() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceSigningEnvironmentTests-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = root.appendingPathComponent("Empty.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle = try #require(Bundle(url: bundleURL))
        #expect(bundle.url(forResource: "embedded", withExtension: "mobileprovision") == nil)
        #if !os(macOS)
        #expect(CadenceSigningEnvironment.pushEnvironmentEntitlementOfCurrentProcess(bundle: bundle) == nil)
        #endif
    }

    // MARK: - What the user is told

    /// Refusing silently is the failure mode, so the refusal has a banner and the banner says why.
    @Test func theRefusalRaisesAStartupIssueThatExplainsItself() {
        let issue = CadenceStartupIssue(
            kind: .developmentBuild,
            message: CadenceSigningEnvironment.localStoreOnlyMessage
        )

        // It is a sync-level issue, so `CadenceSyncHealth.resolve` reports "not syncing" even on a
        // perfectly healthy iCloud account, and macOS Settings > iCloud Sync shows it too.
        #expect(CadenceStartupIssueKind.developmentBuild.disablesCloudSync)
        #expect(!CadenceStartupIssueKind.developmentBuild.losesDataOnQuit)
        let health = CadenceSyncHealth.resolve(
            startupIssue: issue,
            account: .available,
            pushRegistration: .registered
        )
        #expect(health.level == .notSyncing)

        // Plain language, and it names both the cause and the consequence.
        let detail = issue.bannerDetail.lowercased()
        #expect(detail.contains("development build"))
        #expect(detail.contains("sync"))
        #expect(issue.bannerTitle.lowercased().contains("development build"))
        #expect(!issue.bannerDetail.contains("cloudKitDatabase"))

        // And it is not the recovery-store story, which is the wrong one to tell here: nothing
        // failed, nothing was moved, no recovery store was opened. The copy says so in as many
        // words, and it is not `.recoveryStore`'s copy wearing a different kind.
        #expect(detail.contains("no recovery store was opened"))
        let recoveryStore = CadenceStartupIssue(kind: .recoveryStore, message: issue.message)
        #expect(issue.bannerTitle != recoveryStore.bannerTitle)
        #expect(issue.bannerDetail != recoveryStore.bannerDetail)
        #expect(issue.bannerIcon != recoveryStore.bannerIcon)
    }

    // MARK: - The build settings the gate depends on

    /// The discriminator itself, read off `project.pbxproj`: Debug is `development`, Release is
    /// `production`, on the `Cadence` app target.
    ///
    /// Without this, nothing in the repository fails if a future edit flips the two, and flipping
    /// them turns the gate into exactly the silent-no-sync bug it was built to end — a Release
    /// build, TestFlight included, would start refusing.
    @Test func theProjectStillSpellsTheTwoConfigurationsThisGateDependsOn() throws {
        let project = try projectFile()

        let configurationIDs = try appTargetConfigurationIDs(in: project)
        #expect(configurationIDs.count == 2, "the Cadence app target no longer has exactly two build configurations")

        var byName: [String: String] = [:]
        for id in configurationIDs {
            let block = try #require(
                buildConfigurationBlock(id: id, in: project),
                "no XCBuildConfiguration block for \(id)"
            )
            let name = try #require(setting("name", in: block), "configuration \(id) has no name")
            let aps = try #require(
                setting("APS_ENVIRONMENT", in: block),
                "configuration \(name) no longer sets APS_ENVIRONMENT, which is the gate's only discriminator"
            )
            byName[name] = aps
        }

        #expect(byName["Debug"] == "development")
        #expect(byName["Release"] == "production")

        // A Release build is what TestFlight and the App Store ship, so this is the line that says
        // the gate never refuses one.
        #expect(
            CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: byName["Release"])
                == .notPositivelyDevelopment
        )
        #expect(
            CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: byName["Debug"])
                == .developmentSigned
        )

        // No third configuration anywhere in the project sets it to something else behind these
        // two — a target or project-level override would silently win over what was just read.
        let allValues = Set(
            project.components(separatedBy: "APS_ENVIRONMENT = ")
                .dropFirst()
                .compactMap { $0.components(separatedBy: ";").first }
        )
        #expect(allValues == ["development", "production"], "APS_ENVIRONMENT is set somewhere else too: \(allValues)")
    }

    /// The other half: the build setting has to reach the signed product, which it does only
    /// because both entitlements files interpolate it.
    ///
    /// Each file carries its own platform's spelling of the key — macOS
    /// `com.apple.developer.aps-environment`, iOS the bare `aps-environment` ([[T-1309]]) — and
    /// `CadenceSigningEnvironment.pushEnvironmentEntitlementKeys` reads both.
    @Test func bothEntitlementsFilesStillInterpolateTheBuildSetting() throws {
        let macOS = try textFile(at: "Cadence/Cadence.entitlements")
        let iOS = try textFile(at: "Cadence/Cadence-iOS.entitlements")

        #expect(macOS.contains("<key>com.apple.developer.aps-environment</key>"))
        #expect(iOS.contains("<key>aps-environment</key>"))
        for file in [macOS, iOS] {
            #expect(file.contains("<string>$(APS_ENVIRONMENT)</string>"))
        }

        // Option (a) was explicitly NOT taken: pinning the iCloud environment would have made
        // every locally built debug run read and write the owner's live Production data.
        for file in [macOS, iOS] {
            #expect(
                !file.contains("com.apple.developer.icloud-container-environment"),
                "the iCloud environment key is pinned in an entitlements file; T-3013 chose the runtime refusal instead"
            )
        }
    }

    // MARK: - Helpers

    /// Bytes shaped like a `.mobileprovision`: binary CMS noise, one XML property list, more noise.
    private func provisioningProfileFixture(entitlements: [String: String]) throws -> Data {
        var profile: [String: Any] = [
            "AppIDName": "Cadence",
            "TeamIdentifier": ["SM6Y3D2D55"],
        ]
        if !entitlements.isEmpty {
            profile["Entitlements"] = entitlements
        }
        let plist = try PropertyListSerialization.data(
            fromPropertyList: profile,
            format: .xml,
            options: 0
        )

        var data = Data([0x30, 0x82, 0x0B, 0xC1, 0x06, 0x09, 0x2A, 0x86])
        data.append(plist)
        data.append(Data(repeating: 0xCD, count: 48))
        return data
    }

    private func projectFile() throws -> String {
        try textFile(at: "Cadence.xcodeproj/project.pbxproj")
    }

    private func textFile(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The object ids in the `Cadence` **native target**'s configuration list — not the project's,
    /// which is a different list with the same two names.
    private func appTargetConfigurationIDs(in project: String) throws -> [String] {
        let marker = "/* Build configuration list for PBXNativeTarget \"Cadence\" */ = {"
        let start = try #require(project.range(of: marker), "the Cadence app target's configuration list is gone")
        let rest = project[start.upperBound...]
        let end = try #require(rest.range(of: "};"), "unterminated configuration list")
        return String(rest[..<end.lowerBound])
            .components(separatedBy: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains("/*"), trimmed.hasSuffix(",") else { return nil }
                return trimmed.components(separatedBy: " ").first
            }
    }

    /// One `XCBuildConfiguration` object's body, located by its id rather than by its name.
    private func buildConfigurationBlock(id: String, in project: String) -> String? {
        guard let start = project.range(of: "\t\t\(id) /*") else { return nil }
        let rest = project[start.lowerBound...]
        guard rest.contains("isa = XCBuildConfiguration;") else { return nil }
        guard let end = rest.range(of: "\n\t\t};") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    /// `key = value;` out of a pbxproj block, with any quoting stripped.
    private func setting(_ key: String, in block: String) -> String? {
        for line in block.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key) = "), trimmed.hasSuffix(";") else { continue }
            let value = trimmed
                .dropFirst("\(key) = ".count)
                .dropLast()
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return value
        }
        return nil
    }
}
