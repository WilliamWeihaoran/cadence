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

    /// A Swift error whose cause is reachable **only by reflection** — no `userInfo`, an
    /// `Optional<Error>` stored property — which is the shape `SwiftDataError` presents.
    private struct ReflectedCauseError: LocalizedError {
        var cause: Error?
        /// Distinguishes one wrapper from another. The extractor skips a candidate whose words
        /// match the error it came out of — a cause that says nothing new is not a cause — so two
        /// wrappers with one description would test the skip rather than the recursion.
        var level: Int = 1
        var errorDescription: String? {
            "The operation couldn\u{2019}t be completed. (Cadence.ReflectedCauseError error \(level).)"
        }
    }

    /// A cause that says something the wrapper does not.
    private struct SpecificCauseError: LocalizedError {
        var errorDescription: String? {
            "The file \u{201C}default.store\u{201D} couldn\u{2019}t be opened because it isn\u{2019}t in the correct format."
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
    /// **Whether the framework nests at all is toolchain-specific, so this bounds it rather than
    /// pinning it (T-1296, and T-1318's list).** Measured 2026-09-21 on **Xcode 27**: a real store
    /// failure carries a nested Cocoa error and the reason is specific. Measured 2026-09-22 on
    /// **Xcode 26**, in CI, from this test going red: it does not, and `storeFailureReason` falls
    /// back to SwiftData's own description — correctly, which is the point. CI runs 26 and the
    /// owner's Mac runs 27, so asserting either answer turns the other environment red; the first
    /// version of this test asserted the 27 answer and did exactly that.
    ///
    /// What is invariant, and what this asserts: the reason is never empty, and it is either the
    /// nested error's words or SwiftData's own — never something else, and never a truncation of
    /// either. A third answer is a real change to the fact the fix is built on.
    @Test func theReasonIsTheNestedErrorWhereThereIsOneAndSwiftDatasOwnWordsWhereThereIsNot() throws {
        let failure = try #require(try realStoreOpenFailure(.corruptFile))
        let reason = PersistenceController.storeFailureReason(failure)

        #expect(!reason.isEmpty)

        let nested = (failure as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
        if reason == failure.localizedDescription {
            #expect(
                nested == nil || nested?.localizedDescription == reason,
                """
                a nested error was reachable and its words were discarded in favour of SwiftData's \
                generic description — that is the defect this fix exists to prevent, not a \
                toolchain difference.
                """
            )
        } else {
            #expect(
                !reason.isEmpty,
                "the reason diverged from the generic description but says nothing: \(reason)"
            )
        }
    }

    /// The ticket's actual complaint, stated as a test: different causes used to produce one
    /// identical sentence, and the user could not tell a corrupt store from a permissions problem.
    ///
    /// **The oracle here used to be the *cardinality* of the message set — three distinct or one
    /// shared, never two — and that was a framework pin wearing a disguise (T-1318, audit R61-C).**
    /// It read like the bounded form: [[T-1296]] moved the claim off the individual observation and
    /// up to the aggregate, and stopped there. But a runtime that exposes a specific nested cause
    /// for *one* of these three failures and not the other two makes a **correctly operating**
    /// extractor produce exactly two distinct messages, and the old predicate called that "a
    /// partially working extractor". Nothing in this app's contract requires three framework errors
    /// to carry equally informative internals. No runtime has been observed producing two — this
    /// was green, and latent — which is precisely the shape [[T-1279]] and [[T-1296]] sprang from
    /// the other direction.
    ///
    /// What is asserted instead is **per error, and all of it ours**: the reason is non-empty, the
    /// message keeps the recovery prefix, and it ends in *the reason the extractor actually
    /// returned* for that error. A message that dropped its reason, truncated it, or carried
    /// another error's is red whichever of the three the runtime decided to describe. The
    /// extractor's own correctness stays strict where it can be deterministic:
    /// `theReasonPrefersTheNestedErrorAndFallsBackToTheOuterOne` and
    /// `theReasonReachesACauseThatOnlyReflectionCanSee` pin both channels on synthetic errors and
    /// need no framework error at all.
    @Test func everyStoreFailureIsReportedWithTheReasonTheExtractorFound() throws {
        let failures: [(name: String, error: Error)] = [
            ("a corrupt store file", try #require(try realStoreOpenFailure(.corruptFile))),
            ("a directory in the way", try #require(try realStoreOpenFailure(.directoryInTheWay))),
            ("an unwritable parent", try #require(try realStoreOpenFailure(.unwritableParent))),
        ]

        for failure in failures {
            let reason = PersistenceController.storeFailureReason(failure.error)
            let message = PersistenceController.primaryStoreFailureMessage(failure.error)

            #expect(!reason.isEmpty, "\(failure.name) produced no reason at all")
            #expect(
                message.hasPrefix(
                    "Cadence opened a recovery store because the CloudKit store could not be created"
                ),
                "\(failure.name) lost the recovery prefix: \(message)"
            )
            #expect(
                message.hasSuffix(reason),
                "\(failure.name) reported something other than the reason the extractor found: \(message)"
            )
            #expect(
                message != "Cadence opened a recovery store because the CloudKit store could not be created.",
                "\(failure.name) is back to the bare sentence T-1319 exists to replace"
            )
        }
    }

    /// **The reflected channel, on an error this repository built (audit R61-B).**
    ///
    /// `storeFailureReason` reaches a cause two ways: the standard `NSUnderlyingErrorKey`, and
    /// **reflection** — `SwiftDataError` stores its `_underlyingCocoaError` in a property and
    /// leaves `userInfo` empty, so the standard key finds nothing and only the `Mirror` walk does.
    /// Until this test, that second mechanism was exercised only through live framework errors,
    /// which is exactly the dependency T-1318 exists to remove: whether a given runtime supplies a
    /// reflected cause at all is the runtime's business, so a mutation that deleted the `Mirror`
    /// branch could fall back to the outer description without any test here going red.
    ///
    /// The fixture is a Swift error with a deliberately generic description and an `Optional<Error>`
    /// child, which is the shape the reflection walks — and the first assertion is that the fixture
    /// really is that shape, so this cannot quietly become a second test of the standard channel.
    @Test func theReasonReachesACauseThatOnlyReflectionCanSee() {
        let cause = SpecificCauseError()
        let reflected = ReflectedCauseError(cause: cause)

        // The fixture is what it claims to be: the standard channel finds nothing here.
        #expect(
            (reflected as NSError).userInfo[NSUnderlyingErrorKey] == nil,
            "the fixture carries a standard underlying error, so it no longer tests the Mirror walk"
        )
        #expect(
            reflected.localizedDescription != cause.localizedDescription,
            "the fixture's own words already say the cause, so finding it would prove nothing"
        )

        #expect(
            PersistenceController.storeFailureReason(reflected) == cause.localizedDescription,
            """
            the reflected cause was discarded in favour of the outer generic description — that is \
            the T-1319 defect on the one channel SwiftData actually uses
            """
        )

        // The floor, on the same shape: no child, and no child at all, keep the outer words rather
        // than returning an empty string.
        let childless = ReflectedCauseError(cause: nil)
        #expect(PersistenceController.storeFailureReason(childless) == childless.localizedDescription)
        #expect(PersistenceController.storeFailureReason(cause) == cause.localizedDescription)

        // Two deep, because the walk recurses: the deepest cause that says something new wins.
        let nested = ReflectedCauseError(cause: ReflectedCauseError(cause: cause, level: 2))
        #expect(PersistenceController.storeFailureReason(nested) == cause.localizedDescription)
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
