import Foundation
import Testing
@testable import Cadence

struct AppStoreReviewReadinessTests {
    @Test func appPrivacyManifestDeclaresExpectedDataAndAPIs() throws {
        let manifest = try plistDictionary(at: "Cadence/PrivacyInfo.xcprivacy")

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect(collectedDataTypes(in: manifest).isSuperset(of: [
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeOtherUserContent",
        ]))
        #expect(apiReasons(for: "NSPrivacyAccessedAPICategoryUserDefaults", in: manifest) == ["CA92.1"])
        #expect(apiReasons(for: "NSPrivacyAccessedAPICategoryFileTimestamp", in: manifest) == ["C617.1"])
    }

    @Test func widgetPrivacyManifestAvoidsSharedContainerAPIsWithoutCollectedData() throws {
        let manifest = try plistDictionary(at: "CadenceWidgets/PrivacyInfo.xcprivacy")

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect(collectedDataTypes(in: manifest).isEmpty)
        #expect(apiReasons(for: "NSPrivacyAccessedAPICategoryUserDefaults", in: manifest).isEmpty)
        #expect(apiReasons(for: "NSPrivacyAccessedAPICategoryFileTimestamp", in: manifest) == ["C617.1"])
    }

    @Test func appInfoPlistContainsReviewReadyPrivacyKeys() throws {
        let info = try plistDictionary(at: "Cadence/Info.plist")

        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        #expect(info["UIBackgroundModes"] == nil)
        #expect((info["NSCalendarsFullAccessUsageDescription"] as? String)?.contains("create, update, or delete") == true)
    }

    @Test func appReviewLinksPointAtBundledGitHubPagesDocs() throws {
        let privacyURL = try #require(AppStoreReviewReadiness.privacyPolicyURL)
        let supportURL = try #require(AppStoreReviewReadiness.supportURL)

        #expect(privacyURL.absoluteString == "https://williamweihaoran.github.io/cadence/privacy.html")
        #expect(supportURL.absoluteString == "https://williamweihaoran.github.io/cadence/support.html")
        #expect(FileManager.default.fileExists(atPath: repositoryRoot().appendingPathComponent("docs/privacy.html").path))
        #expect(FileManager.default.fileExists(atPath: repositoryRoot().appendingPathComponent("docs/support.html").path))
    }

    @Test func accountDeletionIsExplicitInSettingsAndReviewDocs() throws {
        let accountSettings = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence/macOS/Views/SettingsSectionViews.swift"),
            encoding: .utf8
        )
        let dataSafetySettings = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence/macOS/Views/SettingsDataSafetySection.swift"),
            encoding: .utf8
        )
        let reviewNotes = try String(
            contentsOf: repositoryRoot().appendingPathComponent("docs/app-review-notes.md"),
            encoding: .utf8
        )
        let privacyPolicy = try String(
            contentsOf: repositoryRoot().appendingPathComponent("docs/privacy.html"),
            encoding: .utf8
        )

        #expect(accountSettings.contains("Delete Account..."))
        #expect(dataSafetySettings.contains("Delete Account & Data"))
        #expect(reviewNotes.contains("Settings > Account"))
        #expect(privacyPolicy.contains("Account and Data Deletion"))
    }

    @Test func appEntitlementsAvoidUnusedPushAndIncludeSandboxNetworkAndCalendarAccess() throws {
        let entitlements = try plistDictionary(at: "Cadence/Cadence.entitlements")

        #expect(entitlements["aps-environment"] == nil)
        #expect(entitlements["com.apple.developer.aps-environment"] == nil)
        #expect(entitlements["com.apple.security.application-groups"] == nil)
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
        #expect(entitlements["com.apple.security.personal-information.calendars"] as? Bool == true)
    }

    @Test func appSandboxUsesUserSelectedFileAccessForExports() throws {
        let project = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        #expect(project.contains("ENABLE_USER_SELECTED_FILES = readwrite;"))
        #expect(!project.contains("ENABLE_USER_SELECTED_FILES = readonly;"))
    }

    @Test func appStartupDoesNotProbeLegacyContainersAutomatically() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence/Services/PersistenceController.swift"),
            encoding: .utf8
        )
        let initializerBody = try #require(
            source.range(of: "    init() {").flatMap { start in
                source.range(of: "    private static func makeContainer()", range: start.upperBound..<source.endIndex).map { end in
                    String(source[start.upperBound..<end.lowerBound])
                }
            }
        )

        #expect(!initializerBody.contains("migrateLegacyStoreIfNeeded"))
        #expect(!initializerBody.contains("legacyStoreCandidateDirectories"))
        #expect(!initializerBody.contains("appGroupStore"))
    }

    @Test func appTargetsDoNotRegisterAppGroupsByDefault() throws {
        let project = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        #expect(!project.contains("REGISTER_APP_GROUPS = YES;"))
    }

    @Test func appSourceDoesNotAccessAppGroupContainersByDefault() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence/Services/CadenceStoreSupport.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("containerURL(forSecurityApplicationGroupIdentifier:"))
        #expect(!source.contains("group.com.haoranwei.Cadence"))
        #expect(!source.contains("makeSharedContainer"))
    }

    @Test func widgetEntitlementsIncludeSandbox() throws {
        let entitlements = try plistDictionary(at: "CadenceWidgets/CadenceWidgets.entitlements")

        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.application-groups"] == nil)
    }

    @Test func recoveryStoreCandidatesStartWithPrimaryStoreContainer() {
        let primaryStore = URL(fileURLWithPath: "/container/Library/Application Support/Cadence", isDirectory: true)
        let appSupport = URL(fileURLWithPath: "/container/Library/Application Support", isDirectory: true)
        let temporary = URL(fileURLWithPath: "/tmp", isDirectory: true)

        let candidates = PersistenceController.recoveryStoreDirectoryCandidates(
            primaryStoreDirectoryURL: primaryStore,
            applicationSupportDirectoryURL: appSupport,
            temporaryDirectoryURL: temporary
        )

        #expect(candidates.map(\.path) == [
            "/container/Library/Application Support/Cadence/Recovery",
            "/tmp/Cadence/Recovery",
        ])
    }

    @Test func recoveryStoreCandidatesStillExistWhenPrimaryStoreIsUnavailable() {
        let appSupport = URL(fileURLWithPath: "/container/Library/Application Support", isDirectory: true)
        let temporary = URL(fileURLWithPath: "/tmp", isDirectory: true)

        let candidates = PersistenceController.recoveryStoreDirectoryCandidates(
            primaryStoreDirectoryURL: nil,
            applicationSupportDirectoryURL: appSupport,
            temporaryDirectoryURL: temporary
        )

        #expect(candidates.map(\.path) == [
            "/container/Library/Application Support/Cadence/Recovery",
            "/tmp/Cadence/Recovery",
        ])
    }

    private func plistDictionary(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent(relativePath))
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(value as? [String: Any])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func collectedDataTypes(in manifest: [String: Any]) -> Set<String> {
        let entries = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        return Set(entries.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
    }

    private func apiReasons(for category: String, in manifest: [String: Any]) -> Set<String> {
        let entries = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let reasons = entries.first { $0["NSPrivacyAccessedAPIType"] as? String == category }?["NSPrivacyAccessedAPITypeReasons"]
        return Set(reasons as? [String] ?? [])
    }
}
