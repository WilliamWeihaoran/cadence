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

    @Test func appleReleaseReadinessDocsCoverBothDistributionTracks() throws {
        let readiness = try textFile(at: "docs/apple-release-readiness.md")
        let appStorePacket = try textFile(at: "docs/app-store-submission-packet.md")
        let directRunbook = try textFile(at: "docs/direct-distribution-runbook.md")
        let docsIndex = try textFile(at: "docs/index.html")

        #expect(readiness.contains("Primary channel: Mac App Store."))
        #expect(readiness.contains("Secondary channel: direct Developer ID distribution with notarization."))
        #expect(readiness.contains("Minimum macOS version: 26.1."))
        #expect(readiness.contains("Privacy Label Source Of Truth"))
        #expect(readiness.contains("Entitlement Justifications"))
        #expect(readiness.contains("Third-Party SDK And Package Audit"))
        #expect(readiness.contains("App Store Reviewer Script"))
        #expect(readiness.contains("CadenceMCPServer"))
        #expect(appStorePacket.contains("Do not answer \"Data Not Collected\""))
        #expect(appStorePacket.contains("Minimum OS: macOS 26.1"))
        #expect(appStorePacket.contains("Confirm `CadenceMCPServer`"))
        #expect(directRunbook.contains("Developer ID"))
        #expect(directRunbook.contains("xcrun notarytool submit"))
        #expect(directRunbook.contains("xcrun stapler staple"))
        #expect(directRunbook.contains("spctl -a -vv --type execute"))
        #expect(docsIndex.contains("apple-release-readiness.md"))
        #expect(docsIndex.contains("app-store-submission-packet.md"))
        #expect(docsIndex.contains("direct-distribution-runbook.md"))
    }

    @Test func appReviewNotesDocumentCurrentSubmissionPosture() throws {
        let reviewNotes = try textFile(at: "docs/app-review-notes.md")

        #expect(reviewNotes.contains("macOS 26.1 or later"))
        #expect(reviewNotes.contains("no in-app purchases or subscriptions"))
        #expect(reviewNotes.contains("does not contain ads, third-party analytics, or tracking"))
        #expect(reviewNotes.contains("widgets that read Cadence snapshots from the app group container"))
        #expect(reviewNotes.contains("AI features are optional"))
        #expect(reviewNotes.contains("Calendar access is optional"))
        #expect(reviewNotes.contains("private iCloud database"))
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
        let deletionBody = try #require(
            dataSafetySettings.range(of: "    private func deleteCadenceData() {").flatMap { start in
                dataSafetySettings
                    .range(
                        of: "\n}\n\nprivate struct SettingsReviewLinksSection",
                        range: start.upperBound..<dataSafetySettings.endIndex
                    )
                    .map { end in String(dataSafetySettings[start.lowerBound..<end.lowerBound]) }
            }
        )

        // The steps that outlive the store — the local backups and the widget snapshot — used to
        // be written out in this view. They are `PrivacyDataResetService`'s now, because iOS runs
        // the same reset and a second hand-written copy is how the two platforms drift; so this
        // asserts the pane reaches the shared sequence, and that the sequence still does the work.
        let resetService = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence/Services/CadencePrivacyDataResetService.swift"),
            encoding: .utf8
        )

        #expect(accountSettings.contains("Delete Account..."))
        #expect(dataSafetySettings.contains("Delete Account & Data"))
        #expect(deletionBody.contains("PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts"))
        #expect(resetService.contains("StoreBackupManager.deleteAllBackups"))
        #expect(resetService.contains("CadenceWidgetRefreshCenter.clearStoredState"))
        #expect(!deletionBody.contains("createBackupIfStoreExists"))
        #expect(reviewNotes.contains("Settings > Account"))
        // The iOS route the shipped documents promise, and did not have. See
        // `CadencePrivacyDataResetSurfaceTests` for the code behind it.
        #expect(reviewNotes.contains("Settings > Data Safety"))
        #expect(privacyPolicy.contains("Account and Data Deletion"))
        #expect(privacyPolicy.contains("removes local Cadence backups"))
    }

    /// The entitlement assertion below pinned `aps-environment` while
    /// `docs/app-review-notes.md` said "Cadence does not use push notifications" — a
    /// submission-facing falsehood that survived precisely because the code fact and the prose
    /// were pinned in different places, or in the prose's case not at all. This closes that gap
    /// from the prose side.
    ///
    /// It deliberately does **not** pin a sentence. What it pins is the shape of the claim: while
    /// the entitlement ships, the document may not deny push, and its push section must say what
    /// the push actually is (CloudKit, silent) so a reviewer is not left to guess. Rewording is
    /// free; reverting to a denial is not.
    @Test func appReviewNotesDescribePushAsCloudKitSilentSyncRatherThanDenyingIt() throws {
        let entitlements = try plistDictionary(at: "Cadence/Cadence.entitlements")
        let reviewNotes = try textFile(at: "docs/app-review-notes.md").lowercased()

        // The premise. If this entitlement is ever dropped, the prose rule below stops applying
        // and this test should be revisited rather than worked around.
        #expect(entitlements["com.apple.developer.aps-environment"] as? String == "$(APS_ENVIRONMENT)")

        for denial in [
            "does not use push notification",
            "doesn't use push notification",
            "no push notification",
            "does not send push notification",
            "uses no push notification",
        ] {
            #expect(!reviewNotes.contains(denial), "review notes deny push while the APS entitlement ships")
        }

        let pushSection = try #require(
            section(titled: "push notifications", in: reviewNotes),
            "review notes have no Push notifications section"
        )
        #expect(pushSection.contains("cloudkit"))
        #expect(pushSection.contains("silent"))
        // A reviewer needs to know the pushes are not user-facing; any of these phrasings says so.
        #expect(
            ["no alert", "no user-visible", "not user-facing", "no user-facing"]
                .contains { pushSection.contains($0) }
        )

        // And the local mechanism must not be folded into the push claim: they are different
        // APIs with different authorization, and conflating them is what the old sentence did.
        #expect(reviewNotes.contains("local notification"))
        #expect(reviewNotes.contains("unusernotificationcenter"))
    }

    /// `NSRemindersFullAccessUsageDescription` ships, so the user sees a Reminders permission
    /// prompt — and for a while neither shipped document mentioned reminders at all, so the
    /// privacy policy described a prompt the app does not make and omitted one it does.
    ///
    /// Pins the presence of the disclosure and the three facts a reviewer or user needs, not the
    /// wording: reminders exist in the app, access is separate from Calendar, and Cadence does not
    /// create or delete them.
    @Test func remindersAccessIsDisclosedWhereverTheAppAsksForIt() throws {
        let project = try textFile(at: "Cadence.xcodeproj/project.pbxproj")
        #expect(project.contains("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription"))

        let reviewNotes = try textFile(at: "docs/app-review-notes.md").lowercased()
        let privacyPolicy = try textFile(at: "docs/privacy.html").lowercased()

        for (document, text) in [("review notes", reviewNotes), ("privacy policy", privacyPolicy)] {
            #expect(text.contains("reminders"), "\(document) never mentions Reminders")
            #expect(text.contains("eventkit"), "\(document) does not say how reminders are read")
            #expect(
                text.contains("separately from calendar") || text.contains("separately from calendar access"),
                "\(document) does not say Reminders access is separate from Calendar access"
            )
            #expect(
                text.contains("never creates a reminder"),
                "\(document) does not state that Cadence never creates a reminder"
            )
            #expect(
                text.contains("never deletes one") || text.contains("never deletes a reminder"),
                "\(document) does not state that Cadence never deletes a reminder"
            )
        }

        // Both platforms surface reminders — an earlier verification called this macOS-only.
        #expect(privacyPolicy.contains("inbox"))
        #expect(reviewNotes.contains("ios/ipados") || reviewNotes.contains("iphone and ipad"))
    }

    /// `docs/privacy.html`'s stored-data list says "including", so an omission was imprecise
    /// rather than false — but tags and pasted note images are whole `@Model` types, and a
    /// privacy policy is the wrong document to be approximate in.
    @Test func privacyPolicyStoredDataListNamesTagsAndNoteImages() throws {
        let privacyPolicy = try textFile(at: "docs/privacy.html").lowercased()

        #expect(privacyPolicy.contains("tags"))
        #expect(privacyPolicy.contains("images you paste or drop into a note"))
    }

    @Test func appEntitlementsIncludeCloudKitPushSandboxNetworkCalendarAndAppGroupAccess() throws {
        let entitlements = try plistDictionary(at: "Cadence/Cadence.entitlements")

        #expect(entitlements["aps-environment"] == nil)
        #expect(entitlements["com.apple.developer.aps-environment"] as? String == "$(APS_ENVIRONMENT)")
        #expect(entitlements["com.apple.security.application-groups"] as? [String] == ["group.com.haoranwei.Cadence"])
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

    @Test func deploymentTargetIsExplicitlyMacOS261ForCurrentRelease() throws {
        let project = try textFile(at: "Cadence.xcodeproj/project.pbxproj")
        let readiness = try textFile(at: "docs/apple-release-readiness.md")
        let appStorePacket = try textFile(at: "docs/app-store-submission-packet.md")

        #expect(project.contains("MACOSX_DEPLOYMENT_TARGET = 26.1;"))
        #expect(readiness.contains("Minimum macOS version: 26.1. This is intentional"))
        #expect(appStorePacket.contains("Minimum OS: macOS 26.1"))
    }

    @Test func appTargetDoesNotEmbedMCPServerOrMCPPackage() throws {
        let project = try textFile(at: "Cadence.xcodeproj/project.pbxproj")
        let targetBlock = try #require(
            project.range(of: "8850FF1E2F75C94900A80F43 /* Cadence */ = {").flatMap { start in
                project.range(
                    of: "\n\t\t};",
                    range: start.upperBound..<project.endIndex
                ).map { end in String(project[start.lowerBound..<end.upperBound]) }
            }
        )

        #expect(targetBlock.contains("B10000002FCE00000000010F /* PBXTargetDependency */"))
        #expect(targetBlock.contains("packageProductDependencies = (\n\t\t\t);"))
        #expect(!targetBlock.contains("CadenceMCPServer"))
        #expect(!targetBlock.contains("MCP"))
    }

    @Test func appStartupMigratesLegacyStoreIntoAppGroupWhenNeeded() throws {
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

        #expect(initializerBody.contains("migrateLegacyStoreIfNeeded"))
        #expect(initializerBody.contains("legacyStoreCandidateDirectories"))
        #expect(initializerBody.contains("appGroupDirectoryURL"))
    }

    @Test func appTargetsRegisterAppGroups() throws {
        let project = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        #expect(project.contains("REGISTER_APP_GROUPS = YES;"))
    }

    @Test func appSourceUsesAppGroupContainerForSharedStore() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence/Services/CadenceStoreSupport.swift"),
            encoding: .utf8
        )

        #expect(source.contains("containerURL(forSecurityApplicationGroupIdentifier:"))
        #expect(source.contains("group.com.haoranwei.Cadence"))
        #expect(source.contains("sharedStoreDirectoryURL"))
    }

    @Test func widgetEntitlementsIncludeSandbox() throws {
        let entitlements = try plistDictionary(at: "CadenceWidgets/CadenceWidgets.entitlements")

        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.application-groups"] as? [String] == ["group.com.haoranwei.Cadence"])
    }

    @Test func appEntitlementsIncludeSharedAppGroup() throws {
        let entitlements = try plistDictionary(at: "Cadence/Cadence.entitlements")

        #expect(entitlements["com.apple.security.application-groups"] as? [String] == ["group.com.haoranwei.Cadence"])
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

    /// The block of a `Title:`-then-bullets section in `docs/app-review-notes.md`, from the
    /// heading to the next blank line. Lets a test assert about one section's contents without
    /// pinning its sentences, and without a match leaking in from a neighbouring section.
    private func section(titled title: String, in document: String) -> String? {
        guard let start = document.range(of: "\n\(title):\n") ?? document.range(of: "\(title):\n") else {
            return nil
        }
        let rest = document[start.upperBound...]
        guard let end = rest.range(of: "\n\n") else { return String(rest) }
        return String(rest[..<end.lowerBound])
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
