import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1319.** A launch that could not open the real store says *why* it could not.
///
/// `PersistenceController.init` opened the primary, CloudKit-backed store with
/// `if let c = try? PersistenceController.makeContainer()`, and the `else` built an explicitly
/// labelled recovery store. Everything about that fallback is right — losing access to your own
/// data because CloudKit is unavailable is worse than not syncing — and the recovery *state* was
/// never silent: the banner and the iCloud Sync card both read `startupIssue`. What the `try?`
/// threw away was the only thing that launch knew about the cause. "Cadence opened a recovery
/// store because the CloudKit store could not be created." is the same sentence for a rejected
/// schema, a store file that will not open, and a container the app cannot reach — and it is the
/// one report the owner can send, about a launch that is showing them an app that is not their
/// data.
///
/// The tests below use **real** `ModelContainer` failures rather than a stub `Error`, because the
/// claim is about what the system's own `localizedDescription` contributes, and they run against
/// temporary directories only: nothing here goes near the app-group container.
@MainActor
struct CadenceStartupRecoveryReasonTests {

    /// A real `ModelContainer` open failure, of a named shape, against a temporary directory.
    ///
    /// **Not every bad URL throws.** Measured against the real framework on 2026-09-21: a store
    /// under `/dev/null/…` and one in a directory that does not exist both open *successfully*, so
    /// the obvious fixtures are no fixtures at all. These three do fail, and they fail for three
    /// genuinely different reasons, which is the property these tests need.
    private enum StoreFailureShape {
        /// A file that exists and is not a database.
        case corruptFile
        /// The store path is a directory.
        case directoryInTheWay
        /// The parent directory cannot be written to.
        case unwritableParent
    }

    private func realStoreOpenFailure(_ shape: StoreFailureShape) throws -> Error? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cadence-startup-reason-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL: URL
        switch shape {
        case .corruptFile:
            storeURL = directory.appendingPathComponent("corrupt.store")
            try Data("this is not a database".utf8).write(to: storeURL)
        case .directoryInTheWay:
            storeURL = directory.appendingPathComponent("folder.store")
            try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        case .unwritableParent:
            storeURL = directory.appendingPathComponent("locked.store")
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        }

        do {
            _ = try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(
                    "Fixture",
                    schema: CadenceSchema.schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            )
            return nil
        } catch {
            return error
        }
    }

    // MARK: - The sentence

    @Test func theRecoveryMessageCarriesTheFailureItUsedToDiscard() throws {
        let failure = try #require(try realStoreOpenFailure(.corruptFile), "the fixture stopped failing")
        let message = PersistenceController.primaryStoreFailureMessage(failure)

        #expect(message.hasPrefix("Cadence opened a recovery store because the CloudKit store could not be created"))
        #expect(message.hasSuffix(PersistenceController.storeFailureReason(failure)))
        // The regression this exists for: the message being the bare sentence again.
        #expect(message != "Cadence opened a recovery store because the CloudKit store could not be created.")
    }

    /// **The half that had to be measured.** Catching the error is not enough on its own:
    /// `SwiftDataError.localizedDescription` is one fixed string for every cause, so interpolating
    /// it would have produced a longer version of the same non-answer. The reason has to come from
    /// the nested Cocoa error, and this is what says so.
    ///
    /// If a future SDK makes `localizedDescription` itself specific and stops nesting, this goes
    /// red — deliberately. That is a change to the one fact the fix is built on.
    @Test func theSwiftDataDescriptionAloneIsNotTheReason() throws {
        let failure = try #require(try realStoreOpenFailure(.corruptFile))
        let reason = PersistenceController.storeFailureReason(failure)

        #expect(!reason.isEmpty)
        #expect(
            reason != failure.localizedDescription,
            "no nested error was found, so the reason is SwiftData's own generic description: \(reason)"
        )
    }

    /// The ticket's actual complaint, stated as a test: different causes used to produce one
    /// identical sentence, and the user could not tell a corrupt store from a permissions problem.
    @Test func differentStoreFailuresNoLongerReadIdentically() throws {
        let corrupt = try #require(try realStoreOpenFailure(.corruptFile))
        let directory = try #require(try realStoreOpenFailure(.directoryInTheWay))
        let unwritable = try #require(try realStoreOpenFailure(.unwritableParent))

        let messages = [corrupt, directory, unwritable].map(PersistenceController.primaryStoreFailureMessage)
        #expect(Set(messages).count == messages.count, "two causes still read alike: \(messages)")
    }

    /// The extractor itself, without the framework: the standard `NSUnderlyingErrorKey` channel is
    /// tried too, and an error that is already specific keeps its own words.
    @Test func theReasonPrefersTheNestedErrorAndFallsBackToTheOuterOne() {
        let plain = NSError(
            domain: "CadenceTest",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "The backup folder is missing."]
        )
        #expect(PersistenceController.storeFailureReason(plain) == "The backup folder is missing.")

        let wrapped = NSError(
            domain: "CadenceTest",
            code: 8,
            userInfo: [
                NSLocalizedDescriptionKey: "The operation could not be completed.",
                NSUnderlyingErrorKey: plain,
            ]
        )
        #expect(PersistenceController.storeFailureReason(wrapped) == "The backup folder is missing.")
    }

    // MARK: - What the user sees

    @Test func theBannerAndTheICloudCardBothShowTheReason() throws {
        let failure = try #require(try realStoreOpenFailure(.corruptFile))
        let reason = PersistenceController.storeFailureReason(failure)
        let issue = CadenceStartupIssue(
            kind: .recoveryStore,
            message: PersistenceController.primaryStoreFailureMessage(failure)
        )

        // The launch banner.
        #expect(issue.bannerTitle == "iCloud Sync Is Off")
        #expect(issue.bannerDetail.contains(reason))
        #expect(issue.bannerDetail.contains("will not sync to your other devices"))

        // Settings > iCloud Sync, on both platforms, through the one resolver they share.
        let health = CadenceSyncHealth.resolve(
            startupIssue: issue,
            account: .available,
            pushRegistration: .registered
        )
        #expect(health.level == .notSyncing)
        #expect(health.detail.contains(reason))
    }

    // MARK: - The `try?` does not come back

    /// Read from `init`'s own body rather than the file, so an unrelated `try?` elsewhere in
    /// `PersistenceController` neither satisfies nor breaks this.
    @Test func theLaunchDoesNotDiscardThePrimaryStoreError() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("init()", in: source),
            "PersistenceController.init is gone or its braces do not balance"
        )

        #expect(!body.contains("try? PersistenceController.makeContainer()"))
        #expect(!body.contains("try? Self.makeContainer()"))
        #expect(body.contains("try PersistenceController.makeContainer()"))
        #expect(body.contains("primaryStoreFailureMessage("))
        // Non-vacuity: this really is the boot sequence's body.
        #expect(body.contains("makeRecoveryContainer("))
    }
}
