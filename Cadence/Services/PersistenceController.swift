import Dispatch
import Foundation
import SwiftData

struct PersistenceController {
    static let shared = PersistenceController()
    /// The one startup problem this launch hit, if any.
    ///
    /// Structured rather than a bare `String` since T-153: two of the things that can be recorded
    /// here leave the store with `cloudKitDatabase: .none`, and the rest do not touch sync at all.
    /// Every surface that showed this used to have to guess which from the prose.
    private(set) static var startupIssue: CadenceStartupIssue?

    /// Set only when `container` is `nil` — the CloudKit store, the on-disk recovery store, and a
    /// fully in-memory container all failed to open. See `makeRecoveryContainer`'s final catch.
    ///
    /// This used to be a `fatalError`, unconditionally, on a launch already three failures deep.
    /// It is not reachable by anything a user or a synced record can drive — recreating it needs
    /// SwiftData to be unable to construct even an in-memory container, which is not a storage or
    /// network condition, since in-memory needs neither — but "not reachable" is not the same
    /// promise as "cannot happen", and the trap's cost when it does is the worst first impression
    /// the app has: a crash on launch with no explanation and no way to recover anything. This is
    /// the honest alternative: say plainly that nothing could be opened, and try, once, to read
    /// whatever *is* still on disk well enough to export it — see
    /// `attemptRecoveryExport()`.
    private(set) static var terminalFailure: CadenceStartupTerminalFailure?

    /// `nil` exactly when `terminalFailure` is set. `CadenceApp` reads this to decide whether it
    /// can build the normal app shell at all, or has to fall back to
    /// `CadenceTerminalRecoveryView` instead — a `ModelContainer` this app never got is not a
    /// container any view can safely assume, including the two floating panels
    /// (`QuickTaskPanelController`, `TaskNotesPanelController`) that build their own `.modelContainer`
    /// off `PersistenceController.shared.container` outside the app's main window group.
    let container: ModelContainer?

    static let schema = CadenceSchema.schema

    init() {
        if Self.shouldResetStoreOnLaunch {
            Self.deleteResolvedStoreDirectory()
        }

        // After the reset, never before it: the reset removes the whole directory, lock file
        // included, and a claim taken on a file that is then deleted owns nothing (T-1090).
        Self.claimUITestStoreDirectoryIfNeeded()

        if Self.isRunningTests {
            do {
                container = try Self.makeContainer()
                return
            } catch {
                fatalError("Could not create test ModelContainer: \(error.localizedDescription)")
            }
        }

        // T-1366. `nil` unless someone set `CadenceStartupCostLedger.enabledDefaultsKey`, and every
        // `measure`/`finished` below is written on the optional so an uninstrumented launch runs
        // exactly the statements it always did.
        let recorder = CadenceStartupCostLedger.begin()

        var failedRestore: StoreBackupManager.FailedRestoreRecord?
        do {
            // **T-1448: every step below acts on the store directory THIS launch opens.** It used
            // to be `CadenceStoreSupport.primaryStoreDirectoryURL()` unconditionally, which is the
            // signed-in person's app-group store no matter what `CADENCE_UI_TEST_STORE_ID` said —
            // so an agent launch through `scripts/run-macos-app.sh` opened a private store and then
            // ran this whole preflight against *theirs*. It is not a read: `createBackupIfStoreExists`
            // below copied ~16 MB of their store into their backups folder on every agent launch
            // (four `…-startup` folders on 2026-09-28, one at 14:39:41 matching that run's log),
            // `purgeAutomaticBackups` then applied their retention policy to the rest, and a
            // restore they had staged would have been *applied* by the agent's process.
            let privateStoreDirectoryURL = CadenceUITestStoreDirectory.privateStoreDirectory()
            let storeDirectoryURL: URL
            if let privateStoreDirectoryURL {
                try FileManager.default.createDirectory(
                    at: privateStoreDirectoryURL,
                    withIntermediateDirectories: true
                )
                storeDirectoryURL = privateStoreDirectoryURL
            } else {
                storeDirectoryURL = try CadenceStoreSupport.primaryStoreDirectoryURL()
                // The legacy migration is the one step that must NOT follow the redirect, and the
                // reason is the shape of `migrateLegacyStoreIfNeeded`: it copies a pre-app-group
                // store into a target that has no store items yet. A private store directory is
                // always empty on its first launch, so pointing it there would *import* the
                // person's real data into the throwaway store and write a pre-restore backup
                // beside their legacy copy on the way. A private store has no predecessor.
                _ = try CadenceStoreSupport.migrateLegacyStoreIfNeeded(
                    appGroupDirectoryURL: storeDirectoryURL,
                    candidateLegacyDirectories: CadenceStoreSupport.legacyStoreCandidateDirectories(),
                    backupHandler: { legacyDirectory in
                        _ = try StoreBackupManager.createBackupIfStoreExists(
                            reason: .preRestore,
                            storeDirectoryURL: legacyDirectory
                        )
                    }
                )
            }
            // T-326: a restore that fails no longer takes the launch down with it. The staged
            // restore leaves the existing store untouched when it throws, so the right move is to
            // open that store normally and say what happened — not to fall through to a recovery
            // store, which used to hide an intact database behind an empty one.
            do {
                try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: storeDirectoryURL)
            } catch {
                failedRestore = StoreBackupManager.lastFailedRestore()
            }
            _ = try StoreBackupManager.createBackupIfStoreExists(
                reason: .startup,
                storeDirectoryURL: storeDirectoryURL
            )
            // A *refused* pending restore is not a preflight that did nothing: the original store
            // is intact and the launch is about to open it, which is the right outcome and still
            // the one the ledger has to keep apart from a clean pass.
            recorder.finished(.preflight, failedRestore == nil ? .completed : .refused("pendingRestoreRefused"))
        } catch {
            recorder.finished(.preflight, .refused(Self.instrumentReason(for: error)))
            recorder.commit()
            container = Self.makeRecoveryContainer(
                issue: "Cadence opened a recovery store because backup/restore preflight failed: \(Self.storeFailureReason(error))"
            )
            return
        }

        let primaryStoreFailure: Error
        do {
            let c = try PersistenceController.makeContainer()
            recorder.finished(.containerOpen, .completed)
            container = c
            if let failedRestore {
                Self.startupIssue = CadenceStartupIssue(
                    kind: failedRestore.startupIssueKind,
                    message: failedRestore.startupMessage
                )
            }
            let startupContext = ModelContext(c)
            Self.performStartupMaintenance(in: startupContext, recorder: recorder)
            recorder.commit()
            return
        } catch {
            // T-1319. This was `if let c = try? makeContainer()`, and the discarded error was the
            // single most informative thing this launch knew. Everything below the `try?` is
            // already correct — the fallback is deliberate, the recovery state is recorded, the
            // banner says sync is off — but "the CloudKit store could not be created" is where the
            // report stopped, and a rejected schema migration, a corrupt store file and a missing
            // app-group container all produce that one sentence. The two recovery paths on either
            // side of this one (the preflight failure above, the maintenance save below) already
            // interpolate theirs; this is the one that did not.
            primaryStoreFailure = error
        }
        recorder.finished(.containerOpen, .refused(Self.instrumentReason(for: primaryStoreFailure)))
        recorder.commit()
        container = Self.makeRecoveryContainer(
            issue: Self.primaryStoreFailureMessage(primaryStoreFailure)
        )
    }

    /// A failure reason for the **instrument**, which is not the sentence the user reads.
    ///
    /// `storeFailureReason(_:)` is built to be informative and therefore quotes the framework:
    /// nested Cocoa errors name file paths, and the whole point of the durable ledger is that it
    /// can be left behind by a widget or a launch and read later. This is the same error reduced to
    /// three things that cannot carry content — the Swift type, the `NSError` domain, and the code.
    static func instrumentReason(for error: Error) -> String {
        let bridged = error as NSError
        return "\(type(of: error))/\(bridged.domain)/\(bridged.code)"
    }

    /// What a launch that fell back to the recovery store says about why.
    ///
    /// Separate and pure so the sentence can be tested without a failing `ModelContainer`: making
    /// `makeContainer()` throw on demand means reaching the real app-group store, and the test
    /// target must never touch that. The shape — the old sentence, then a colon, then the reason —
    /// is deliberately the one `makeRecoveryContainer`'s in-memory fallback and the
    /// maintenance-save failure already use, because all three can appear in the same banner.
    static func primaryStoreFailureMessage(_ error: Error) -> String {
        "Cadence opened a recovery store because the CloudKit store could not be created: \(storeFailureReason(error))"
    }

    /// The most specific sentence available about why a store operation failed.
    ///
    /// **Catching the error is only half of T-1319, and this is the half that was measured.** A
    /// `ModelContainer` that fails to open throws `SwiftData.SwiftDataError`, whose
    /// `localizedDescription` is *"The operation couldn’t be completed. (SwiftData.SwiftDataError
    /// error 1.)"* — the same twelve words for every cause. Measured on this Mac against the real
    /// framework on 2026-09-21: a store file holding non-database bytes, a store path that is a
    /// directory, a read-only parent directory and an unwritable location all produce that one
    /// string. Interpolating it would have replaced one uninformative sentence with a longer
    /// uninformative sentence, which is the shape of fix this repository keeps finding in its own
    /// history.
    ///
    /// The real cause is in the error's `_underlyingCocoaError` — *"The file “default.store”
    /// couldn’t be opened because it isn’t in the correct format."*, *"The file couldn’t be saved
    /// because you don’t have permission."* — and it is reachable **only** by reflection:
    /// `SwiftDataError`'s `userInfo` is empty, so `NSUnderlyingErrorKey` finds nothing. Both
    /// channels are tried here, standard one first, and the plain description is the floor rather
    /// than a failure: an error that is already specific (a `FileManager` error from the
    /// backup/restore preflight, say) has no nested error to find and needs none.
    static func storeFailureReason(_ error: Error) -> String {
        nestedFailureDescription(of: error) ?? error.localizedDescription
    }

    /// The deepest nested error description that says something the outer one does not.
    ///
    /// Depth-limited and total: this runs on the launch path of a launch that has already failed
    /// once, so it answers `nil` rather than ever trapping or looping.
    private static func nestedFailureDescription(of error: Error, depth: Int = 0) -> String? {
        guard depth < 4 else { return nil }
        let outer = error.localizedDescription

        var candidates: [Error] = []
        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
            candidates.append(underlying)
        }
        candidates.append(contentsOf: Mirror(reflecting: error).children.compactMap { unwrappedError($0.value) })

        for candidate in candidates {
            let description = candidate.localizedDescription
            guard !description.isEmpty, description != outer else { continue }
            return nestedFailureDescription(of: candidate, depth: depth + 1) ?? description
        }
        return nil
    }

    /// An `Error` out of a reflected child, looking through the `Optional` that
    /// `SwiftDataError._underlyingCocoaError` is stored in.
    private static func unwrappedError(_ value: Any) -> Error? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else { return nil }
            return unwrappedError(wrapped)
        }
        return value as? Error
    }

    /// Every pass a launch runs against the store it just opened.
    ///
    /// **Not `private`, and `defaults` is not a convenience (T-1108).** The empty-store suite used
    /// to *replay* this sequence — four of its calls and a save, copied into a test helper — with a
    /// source-reading test beside it pinning that the real body still ran its passes in this order.
    /// That pin checks production against a list; it cannot check the replay against production,
    /// and the replay had silently drifted three ways: no
    /// `CadenceFocusLedger.reconcile`, no `removingForkedOccurrences:`, and an unconditional
    /// `try? save()` where this guards on `changedStore`. A test that imitates a sequence can drift
    /// from it and stay green, which is the failure this repository keeps re-finding, so the suite
    /// calls this instead. `defaults` is the one thing a test cannot share with a launch — writing
    /// the migration's completion flag into the real suite would leak between runs — and
    /// `PursuitToGoalMigration.runIfNeeded` already took it for the same reason.
    ///
    /// **`recorder` is [[T-1366]]'s instrument and is `nil` for every caller but a launch.** It is
    /// reached through `Optional.measure(_:_:classifying:)` rather than `recorder?.measure`, so an
    /// uninstrumented run executes each pass exactly as it always did; and it is reached on a
    /// lowercase receiver rather than a type, so the pass-set derivation in
    /// `CadenceFirstLaunchEmptyStoreTests` does not read the instrument as a sixth startup pass.
    ///
    /// **All five verdicts below are now real answers** ([[T-1402]]). Three of them used to be
    /// `indeterminate`, and that was a measurement rather than a gap in the instrument:
    /// `PursuitToGoalMigration.runIfNeeded` returned `Void` while the `migrate` beneath it returned
    /// a clean/failed `Bool`; `TagSupport.syncAllNoteTagsFromMarkdown` returned `false` for an
    /// unreadable `Note` table, an unreadable `Tag` table, an empty store and a clean pass alike;
    /// `CadenceFocusLedger.reconcile` returned `false` for a fetch it could not run and for a store
    /// with nothing to raise. The fix was to the **passes**, not to the meter: all three answer
    /// `CadenceMaintenancePassOutcome` now, and `CadenceStartupStageVerdict.forMaintenancePass`
    /// turns a `couldNotRead` into a `refused` rather than into a no-op. A launch that silently
    /// failed to repair no longer reads like a launch with nothing to repair.
    static func performStartupMaintenance(
        in context: ModelContext,
        defaults: UserDefaults = CadenceDefaults.store,
        recorder: CadenceStartupCostRecorder? = nil
    ) {
        // Folds any surviving `Pursuit` rows into `Goal`. Self-guarding and idempotent, and
        // manages its own saves because it deletes rows rather than just inserting them.
        // `_ =` and not a term in `changedStore` below: this pass manages its own saves — it
        // deletes rows rather than only inserting them — so by the time it returns, a store it
        // changed has already been committed and `context.hasChanges` is false. Its answer is the
        // instrument's to keep, which since [[T-1402]] it has one worth keeping.
        _ = recorder.measure(.pursuitMigration) {
            PursuitToGoalMigration.runIfNeeded(modelContext: context, defaults: defaults)
        } classifying: { outcome in
            .forMaintenancePass(outcome)
        }

        // **No pass here seeds the default tags, and that is the point (T-528).**
        //
        // The seed's only signal was "no tag carries this slug", and at launch that sentence has
        // two readings the store cannot tell apart: a user who has never had tags, and a user
        // whose tags have not arrived yet — a reinstall, a second device, a restore, the first
        // seconds of any CloudKit launch. Seeding on the second reading inserts an *active* `bug`
        // beside the archived, recoloured `bug` still in flight; `deduplicateTags` then merges the
        // pair and the tag the user archived is back, active, in the seed's colour, on every
        // synced device. On one device with no CloudKit at all it was simpler and just as wrong:
        // rename `bug` to `Defect` in Settings > Tags and the next launch re-seeded `bug` beside
        // it. Measured against the built app on 2026-08-30 — seven tags in, eight tags out.
        //
        // There is no local signal that separates the two readings, so the fix is not a better
        // guard on the insert; it is that a launch does not insert. `TagSupport.seedDefaultTags`
        // is now reached only from the "Add Defaults" controls that already ship on both
        // platforms, where "no tag carries this slug" has one reading because a person just said
        // so. `CadenceFirstLaunchEmptyStoreTests` holds the launch path to it.
        //
        // This also restores the symmetry `DataIntegrityRepairService`'s own doc comment argues
        // for twelve lines from here: every startup pass is now inert against a store that is
        // empty only because sync has not landed.
        let migrationReport = recorder.measure(.noteMigration) {
            NoteMigrationService.migrateAndRecordFailure(in: context, source: "app-startup", saveChanges: false)
        } classifying: { report in
            guard let report else { return .refused("noReport") }
            guard report.success else { return .refused("passReportedFailure") }
            return report.changedNoteCount > 0 ? .changed(report.changedNoteCount) : .noChange
        }
        let syncedNoteTags = recorder.measure(.tagSync) {
            TagSupport.syncAllNoteTagsFromMarkdown(in: context, saveChanges: false)
        } classifying: { outcome in
            .forMaintenancePass(outcome)
        }
        // `removingForkedOccurrences:` is the app supplying the half of T-622's collapse that
        // `DataIntegrityRepairService` cannot spell: it is in `CadenceMCPServer`'s explicit source
        // list and the task-deletion core is not. Omitting it here would leave forked recurring
        // occurrences uncollapsed on the one launch that matters, silently, so
        // `DataIntegrityRepairServiceTests.theAppStartupRepairSuppliesTheForkedOccurrenceRemover`
        // pins that this argument is present.
        let repairReport = recorder.measure(.integrityRepair) {
            DataIntegrityRepairService.repairAndRecordFailure(
                in: context,
                source: "app-startup",
                saveChanges: false,
                removingForkedOccurrences: CadenceForkedOccurrenceRemover.removeAndCancelReminders
            )
        } classifying: { report in
            guard let report else { return .refused("noReport") }
            guard report.success else { return .refused("passReportedFailure") }
            return report.changed ? .changed(nil) : .noChange
        }
        // T-621's store-wide pass, safe here by the same argument the repair above uses: it only
        // ever raises a counter and is a pure function of the counter and the ledger's rows, so a
        // launch that races the first CloudKit import computes a total that is too low and leaves
        // the counter alone. `bank` already heals the subject it writes to; this is for the task
        // nobody opens again, whose stale total an hours-mode `Goal` is still reading.
        let reconciledFocusMinutes = recorder.measure(.focusReconciliation) {
            CadenceFocusLedger.reconcile(in: context)
        } classifying: { outcome in
            .forMaintenancePass(outcome)
        }
        let changedStore = (migrationReport?.changedNoteCount ?? 0) > 0 ||
            syncedNoteTags.changedStore ||
            reconciledFocusMinutes.changedStore ||
            repairReport?.changed == true

        guard changedStore, context.hasChanges else { return }
        let saveFailure = recorder.measure(.maintenanceSave) { () -> Error? in
            do {
                try context.save()
                return nil
            } catch {
                return error
            }
        } classifying: { failure in
            guard let failure else { return .completed }
            return .refused(instrumentReason(for: failure))
        }
        if let saveFailure {
            startupIssue = CadenceStartupIssue(
                kind: .maintenanceSaveFailed,
                message: "Cadence could not save startup maintenance changes: \(storeFailureReason(saveFailure))"
            )
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let storeURL = try resolvedStoreURL()
        if shouldUseLocalStoreOnly {
            let localConfig = ModelConfiguration(
                "Cadence",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [localConfig])
        }

        let cloudConfig = ModelConfiguration(
            "Cadence",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")
        )
        return try ModelContainer(for: schema, configurations: [cloudConfig])
    }

    private static func makeRecoveryContainer(issue: String) -> ModelContainer? {
        startupIssue = CadenceStartupIssue(kind: .recoveryStore, message: issue)
        do {
            let recoveryDirectoryURL = try recoveryStoreDirectoryURL()
            try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
            let recoveryConfig = ModelConfiguration(
                "Cadence Recovery",
                schema: schema,
                url: recoveryDirectoryURL.appendingPathComponent("recovery.store"),
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [recoveryConfig])
        } catch {
            startupIssue = CadenceStartupIssue(
                kind: .inMemoryStore,
                message: "\(issue) Recovery store creation also failed, so Cadence opened a temporary in-memory store: \(storeFailureReason(error))"
            )
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                // Every store this launch could have opened — CloudKit, an on-disk recovery
                // store, a fully in-memory one — has now failed. There is nothing left to fall
                // back to that is still "the app": `container` stays `nil` and `CadenceApp` shows
                // `CadenceTerminalRecoveryView` instead of building a window group around a store
                // that does not exist.
                terminalFailure = CadenceStartupTerminalFailure(
                    message: "\(issue) In-memory store creation also failed: \(storeFailureReason(error))"
                )
                return nil
            }
        }
    }

    /// A best-effort, read-only, export-only open of the store **this launch tried to open** —
    /// tried only from `CadenceTerminalRecoveryView`, after `terminalFailure` is already set.
    ///
    /// **[[T-1842]] decided which of the two readings this is, and it is not the one the comment
    /// here used to argue for.** The old sentence said "whatever store this device actually has",
    /// and the code matched it: the candidates were built from `CadenceStoreSupport.primaryStoreURL()`
    /// and `primaryStoreDirectoryURL()` with no redirect at all. That is right for the shipping app,
    /// where the two readings coincide, and wrong everywhere else — a `CadenceTests` host, or an
    /// agent launch through `scripts/run-macos-app.sh`, opens a private store, and the whole point
    /// of a redirected launch is that the signed-in person's store is **not** the one it has. The
    /// screen is read-only and unreachable without a terminal failure, so nothing was ever copied;
    /// what it offered was worse in kind than a stray file, because the one button on it would have
    /// put the owner's tasks into an archive at a path chosen by whoever was driving that launch.
    /// It now resolves through `CadenceUITestStoreDirectory.redirectedStoreDirectory`, the same
    /// single resolver the store itself, its backups and its recovery directory take, and an
    /// environment naming neither redirect still answers the app-group store exactly.
    ///
    /// The recovery directories were already redirect-aware ([[T-1680]]) while the primary store
    /// beside them was not, which is the inconsistency that made this a defect rather than a choice.
    ///
    /// This is not a fourth attempt at the sequence above. `init` already tried the primary store
    /// **with CloudKit**, a separate on-disk recovery store **without** it, and a fully in-memory
    /// store, and all three failed before this is ever reachable. What none of those three tried
    /// is the thing this does first: the primary store's own file, local-only, read-only. If the
    /// boot failure was CloudKit's — an unreachable network, a bad container entitlement, a
    /// rejected schema push, all common and all outside this app's control — the user's actual
    /// data is sitting on disk untouched, and this is what gets it into an export instead of
    /// behind a launch-time crash. If the primary store's file cannot be read at all, this falls
    /// back to whatever on-disk recovery stores exist from a previous launch.
    ///
    /// Resolving the real URLs, opening a container and building the archive are three different
    /// functions — `recoveryExportCandidateStoreURLs`, `openReadOnlyStore(at:)` and
    /// `recoverFirstExportableStore` below — for the same reason `recoveryStoreDirectoryURL` is
    /// built on the already-pure `recoveryStoreDirectoryCandidates`: a test can hand the search
    /// real, isolated temporary files, or an injected open and export, without ever touching this
    /// device's actual app-group container.
    static func attemptRecoveryExport(
        in environment: [String: String] = ProcessInfo.processInfo.environment,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) -> RecoveryExportResult {
        recoverFirstExportableStore(from: recoveryExportCandidateStoreURLs(
            in: environment,
            temporaryDirectory: temporaryDirectory,
            fileManager: fileManager
        ))
    }

    /// The candidate list resolved for **this** launch, and the seam the redirect is asserted at
    /// ([[T-1842]]).
    ///
    /// Split out from `attemptRecoveryExport` for the reason the pure overload below is split out
    /// from this one: the ordering is one question, the resolution is another, and only the
    /// resolution can be wrong about *whose* store it names. A test can therefore read the two
    /// candidate lists a redirected and an unredirected launch produce and compare them, without
    /// opening anything at all.
    ///
    /// Nothing here creates a directory. The unredirected base is `CadenceStoreSupport.storeDirectoryLocation`,
    /// not `primaryStoreDirectoryURL` ([[T-1852]]) — a terminal-failure screen asking where the
    /// store would be must not be the thing that makes one.
    static func recoveryExportCandidateStoreURLs(
        in environment: [String: String],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) -> [URL] {
        let activeStoreDirectoryURL = CadenceUITestStoreDirectory.redirectedStoreDirectory(
            in: environment,
            temporaryDirectory: temporaryDirectory
        ) ?? (try? CadenceStoreSupport.storeDirectoryLocation(fileManager: fileManager))

        return recoveryExportCandidateStoreURLs(
            primaryStoreURL: activeStoreDirectoryURL?
                .appendingPathComponent(CadenceStoreSupport.storeFilename),
            recoveryDirectoryCandidates: recoveryStoreDirectoryCandidates(
                in: environment,
                temporaryDirectory: temporaryDirectory,
                fileManager: fileManager
            )
        )
    }

    /// The ordered list of store files `attemptRecoveryExport` will try: the
    /// primary store first (if one was resolved at all — a `nil` is dropped, not passed through as
    /// a URL that cannot exist), then each recovery directory's `recovery.store`, in the order
    /// `recoveryStoreDirectoryCandidates` already ranks them.
    ///
    /// Pure and independently testable: given the same two inputs, this always returns the same
    /// list, with no filesystem access at all.
    static func recoveryExportCandidateStoreURLs(
        primaryStoreURL: URL?,
        recoveryDirectoryCandidates: [URL]
    ) -> [URL] {
        var candidateStoreURLs: [URL] = []
        if let primaryStoreURL {
            candidateStoreURLs.append(primaryStoreURL)
        }
        candidateStoreURLs.append(contentsOf: recoveryDirectoryCandidates.map {
            $0.appendingPathComponent("recovery.store")
        })
        return candidateStoreURLs
    }

    /// One candidate that opened and then could not be turned into an archive.
    ///
    /// A candidate that did not open at all is **not** one of these: most launches have no recovery
    /// directory, so an absent store is the ordinary case and reporting it as a failure would bury
    /// the one that matters under noise. What this records is the case T-1099 is about — a store
    /// that is really there, really opened, and still gave nothing back.
    nonisolated struct RecoveryExportFailure: Equatable {
        let storeURL: URL
        let reason: String
    }

    /// An archive, the store it came from, and what was tried before it.
    nonisolated struct RecoveryExport: Equatable {
        let storeURL: URL
        let data: Data
        let recordCount: Int
        /// Stores that opened ahead of this one and failed to export. Non-empty means the screen
        /// has to say so: something on this device was reachable and did not make it into the file.
        let precedingFailures: [RecoveryExportFailure]
    }

    /// What one press of the recovery screen's export button found.
    nonisolated enum RecoveryExportResult: Equatable {
        /// No candidate opened at all.
        case noStoreOpened
        /// Every store that opened refused to export, in the order they were tried.
        case everyOpenedStoreFailed([RecoveryExportFailure])
        case exported(RecoveryExport)
    }

    /// Open each candidate in turn and try to build an archive from it, answering the first one
    /// that produces bytes.
    ///
    /// **T-1099 — this used to stop at the first store that *opened*.** Opening and exporting are
    /// two different failures: `CadenceDataExportService.makeArchive` runs twenty-one throwing
    /// fetches after the open, so a store that is intact enough for SwiftData to attach to and
    /// damaged enough to refuse a fetch ended the search — the second candidate was never reached,
    /// and pressing the button again repeated the same candidate order to the same dead end. The
    /// user was on the one screen in the app that exists because everything else already failed,
    /// and got less of their data out than the device was holding.
    ///
    /// `open` and `export` are parameters so the pair can be driven independently in a test:
    /// producing a store that genuinely opens and genuinely fails to export is not something a
    /// fixture can arrange with a file. Their defaults are the real thing, so the shipped path has
    /// no seam in it.
    ///
    /// What it deliberately does not do: merge stores, or prefer the largest archive. The candidate
    /// order is a ranking — the primary store first — and the first one that can answer wins, the
    /// same contract as before for every case that used to work.
    static func recoverFirstExportableStore(
        from candidateStoreURLs: [URL],
        open: (URL) -> ModelContainer? = { PersistenceController.openReadOnlyStore(at: $0) },
        export: (ModelContainer) throws -> CadenceDataExportOutcome = {
            try CadenceDataExportService.exportArchive(in: ModelContext($0))
        }
    ) -> RecoveryExportResult {
        var failures: [RecoveryExportFailure] = []
        for storeURL in candidateStoreURLs {
            guard let container = open(storeURL) else { continue }
            do {
                let outcome = try export(container)
                return .exported(RecoveryExport(
                    storeURL: storeURL,
                    data: outcome.data,
                    recordCount: outcome.recordCount,
                    precedingFailures: failures
                ))
            } catch {
                failures.append(RecoveryExportFailure(storeURL: storeURL, reason: error.localizedDescription))
            }
        }
        return failures.isEmpty ? .noStoreOpened : .everyOpenedStoreFailed(failures)
    }

    /// Opens one store file read-only, with CloudKit switched off. `nil` if it does not open.
    ///
    /// No explicit existence check runs before the open, and that absence is measured rather than
    /// assumed: a `FileManager.fileExists` guard sat here first, a mutation dropped it, and every
    /// test in this file still passed. `allowsSave: false` against a URL with no store there
    /// already refuses instead of creating one — the exact asymmetry
    /// `CadenceSharedStoreWriteGateTests.aWriteCapableOpenCreatesAMissingStoreAndAReadOnlyOpenDoesNot`
    /// measures for T-311 — so a second, redundant check here could only ever restate a guarantee
    /// `allowsSave: false` already gives for free. `allowsSave: false` is spelled explicitly below
    /// rather than left to a shared default, because it is the one line actually standing between
    /// this recovery path and writing into a store it did not create — and a "successful" open of
    /// an empty store it *did* just create would tell someone their data was recovered when
    /// nothing was, the opposite of what this screen exists to be honest about.
    static func openReadOnlyStore(at storeURL: URL) -> ModelContainer? {
        let configuration = ModelConfiguration(
            "Cadence Recovery Export",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [configuration])
    }

    static func recoveryStoreDirectoryCandidates(
        primaryStoreDirectoryURL: URL?,
        applicationSupportDirectoryURL: URL?,
        temporaryDirectoryURL: URL
    ) -> [URL] {
        var seenPaths: Set<String> = []
        return [
            primaryStoreDirectoryURL?.appendingPathComponent("Recovery", isDirectory: true),
            applicationSupportDirectoryURL?
                .appendingPathComponent("Cadence", isDirectory: true)
                .appendingPathComponent("Recovery", isDirectory: true),
            temporaryDirectoryURL
                .appendingPathComponent("Cadence", isDirectory: true)
                .appendingPathComponent("Recovery", isDirectory: true),
        ]
        .compactMap(\.self)
        .filter { candidate in
            seenPaths.insert(candidate.standardizedFileURL.path).inserted
        }
    }

    /// The same list, resolved for **this** launch and without creating anything.
    ///
    /// **[[T-1680]] — the recovery store was the last store path that had not learned about the
    /// redirect.** `recoveryStoreDirectoryURL()` below built its first candidate from
    /// `CadenceStoreSupport.primaryStoreDirectoryURL()` unconditionally, and it *creates* the
    /// directory it hands back. So a `CadenceTests` host, or an agent launch through
    /// `scripts/run-macos-app.sh`, that failed its preflight would have created a `Recovery/`
    /// folder — and opened a store in it — inside the signed-in person's app-group container. That
    /// is the shape [[T-1448]] found for the backups and [[T-1530]] for the test host, one
    /// directory over. The base is now `CadenceUITestStoreDirectory.redirectedStoreDirectory`, the
    /// single resolver both of those settled on, and an environment naming neither a store id nor
    /// a test host still answers the app-group path exactly.
    ///
    /// **Nothing here writes, and since [[T-1852]] that is true of the resolution too.** It used to
    /// end in `CadenceStoreSupport.primaryStoreDirectoryURL`, which *creates* the directory it
    /// answers — defensible while that was the only way to ask the question, and still a listing
    /// that made a folder in the signed-in person's group container merely by wondering where it
    /// was. `storeDirectoryLocation` composes the same path and creates nothing, which is what
    /// makes this question safe for `StoreBackupManager.unmanagedStoreDirectories()` to ask
    /// read-only, from a healthy launch, in order to *list* a recovery folder it must not touch.
    static func recoveryStoreDirectoryCandidates(
        in environment: [String: String],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) -> [URL] {
        let activeStoreDirectoryURL = CadenceUITestStoreDirectory.redirectedStoreDirectory(
            in: environment,
            temporaryDirectory: temporaryDirectory
        ) ?? (try? CadenceStoreSupport.storeDirectoryLocation(fileManager: fileManager))

        return recoveryStoreDirectoryCandidates(
            primaryStoreDirectoryURL: activeStoreDirectoryURL,
            applicationSupportDirectoryURL: fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first,
            temporaryDirectoryURL: temporaryDirectory
        )
    }

    private static func recoveryStoreDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        var lastError: Error?

        for candidate in recoveryStoreDirectoryCandidates(
            in: ProcessInfo.processInfo.environment,
            temporaryDirectory: fileManager.temporaryDirectory,
            fileManager: fileManager
        ) {
            do {
                try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
                return candidate
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private static var shouldUseLocalStoreOnly: Bool {
        isRunningTests ||
            ProcessInfo.processInfo.environment["CADENCE_LOCAL_STORE_ONLY"] == "1" ||
            ProcessInfo.processInfo.environment["CADENCE_UI_TEST_MODE"] == "1"
    }

    /// [[T-1530]]: the answer now comes from `CadenceUITestStoreDirectory`, which is where
    /// `StoreBackupManager` reads it too. A second hand-rolled copy here is how the store and its
    /// backups came to disagree about which process they were running in.
    private static var isRunningTests: Bool {
        CadenceUITestStoreDirectory.isRunningTests(in: ProcessInfo.processInfo.environment)
    }

    private static var shouldResetStoreOnLaunch: Bool {
        ProcessInfo.processInfo.environment["CADENCE_RESET_STORE"] == "1"
    }

    /// Lock this launch's store directory and remove the ones no live process owns.
    ///
    /// The whole answer to [[T-1090]] is here rather than in `CadenceUITests`, and the reason is
    /// on `CadenceUITestStoreDirectory`: the UI-test runner is sandboxed with a read-only
    /// exception over `/` and cannot delete anything inside the app's container. Which launches
    /// sweep, and why that is narrower than which launches get a private store, is argued there
    /// too.
    private static func claimUITestStoreDirectoryIfNeeded() {
        guard let id = CadenceUITestStoreDirectory.sweepingLaunchID(
            in: ProcessInfo.processInfo.environment
        ) else { return }
        CadenceUITestStoreDirectory.claimAndSweep(id: id, in: CadenceUITestStoreDirectory.rootDirectory())
    }

    /// **[[T-1530]]: one resolver, asked by the store and by its backups.** The two redirects —
    /// `CADENCE_UI_TEST_STORE_ID` and the test host's `<tmp>/CadenceTestsHostStore` — used to be
    /// spelled out here, and `StoreBackupManager.storeDirectoryURL(in:)` honoured only the first of
    /// them. `CadenceUITestStoreDirectory.redirectedStoreDirectory` is now the only place either
    /// question is answered, so the backups cannot go to a store this launch does not have open.
    private static func resolvedStoreURL() throws -> URL {
        guard let storeDirectoryURL = CadenceUITestStoreDirectory.redirectedStoreDirectory() else {
            return try CadenceStoreSupport.primaryStoreURL()
        }
        try FileManager.default.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
        return storeDirectoryURL.appendingPathComponent("default.store")
    }

    private static func deleteResolvedStoreDirectory() {
        guard let storeURL = try? resolvedStoreURL() else { return }
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }
}

enum StoreBackupReason: String, Codable {
    case startup
    case manual
    case preRestore = "pre-restore"

    var displayName: String {
        switch self {
        case .startup: return "Startup"
        case .manual: return "Manual"
        case .preRestore: return "Before Restore"
        }
    }
}

struct StoreBackupSnapshot: Identifiable, Hashable {
    let id: String
    let url: URL
    let createdAt: Date
    let reason: String
    let sizeBytes: Int64

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// A `Cadence Store Backups` folder that exists on disk beside a store directory Cadence **used
/// to** keep its store in, and therefore one nothing in the app reads, writes, thins or deletes.
///
/// **[[T-1532]].** Four of these were on the owner's Mac on 2026-09-29 and Settings → Data Safety
/// showed one: `listBackups()` resolves `defaultStoreDirectoryURL()`, which is the live store, and
/// `CadenceStoreSupport.legacyStoreCandidateDirectories()` names the old *store* directories, not a
/// backups folder beside them — so the migration never touched these and never will. The screen
/// exists to answer "what copies of my data does Cadence keep and where", and answering it for one
/// of four directories is worse than saying nothing, because the user reads the silence as zero.
///
/// **It carries no delete.** These sit under paths the app no longer owns — one of them holds the
/// only copies of pre-app-group state on that machine — and a "Clear backups" button that reached
/// one would be this screen destroying data on the strength of a path it inferred. `url` is shown
/// in full and revealed in Finder; what happens next is the user's.
struct UnmanagedBackupDirectory: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    /// How many backup folders are in it. Counted, not estimated — an empty leftover folder is not
    /// worth a row and is filtered out before it becomes one.
    let backupCount: Int
    let sizeBytes: Int64

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var displayCount: String {
        "\(backupCount) backup\(backupCount == 1 ? "" : "s")"
    }
}

/// A folder of Cadence **store** files that this launch is not opening, and that nothing in the
/// app adds to, thins, migrates or deletes.
///
/// **[[T-1680]].** [[T-1532]] made the stray *backup* folders visible and left the stray *stores*
/// invisible, which is the larger of the two: a backup folder announces itself by its name, and a
/// `Recovery/` folder sitting inside the live store directory does not. Two kinds exist on a real
/// machine and both are derived from lists the app already keeps, never guessed:
///
/// - `.recovery` — `PersistenceController.recoveryStoreDirectoryCandidates`, the directories
///   `makeRecoveryContainer` writes a `recovery.store` into when the primary store will not open.
///   The live store directory's own `Recovery/` child is one of these, which is why this list is
///   **not** filtered the way `unmanagedBackupDirectories` is: there the live directory is the one
///   already on screen, here it is the one nothing has ever named.
/// - `.previousLocation` — `CadenceStoreSupport.legacyStoreCandidateDirectories()`, the store
///   locations `migrateLegacyStoreIfNeeded` still reads from.
///
/// **It carries no delete, for the reason `UnmanagedBackupDirectory` carries none and one more.**
/// A recovery store is the only copy of anything typed during a degraded session — it is opened
/// with `cloudKitDatabase: .none`, so nothing in it ever synced — and whether **Delete Account &
/// Data** should take it is a product decision the owner has not made ([[T-1840]]). Until it is
/// made, the honest thing is to say where the folder is and say that the reset leaves it, which is
/// what this type and its row do.
struct UnmanagedStoreDirectory: Identifiable, Hashable {
    enum Kind: String, Hashable {
        /// Written by `PersistenceController.makeRecoveryContainer` after a failed store open.
        case recovery
        /// Where an earlier version of Cadence kept the store.
        case previousLocation

        var label: String {
            switch self {
            case .recovery: return "recovery store"
            case .previousLocation: return "earlier store location"
            }
        }
    }

    var id: String { url.path }
    let url: URL
    let kind: Kind
    /// How many store items are in it — counted, not estimated, and an empty leftover directory is
    /// filtered out before it can become a row.
    let itemCount: Int
    /// The store items only. A `Cadence Store Backups` folder beside them is
    /// `UnmanagedBackupDirectory`'s row, and counting it here would put the same bytes on two rows
    /// of the same screen.
    let sizeBytes: Int64
    /// When a store item in it was last written — the one fact that says whether this is debris
    /// from a launch years ago or something from this week.
    let lastModified: Date?

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var displayDetail: String {
        var parts = [kind.label, displaySize]
        if let lastModified {
            parts.append("last written \(lastModified.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " • ")
    }
}

/// One candidate before the filesystem has been asked about it: a path and what it would be.
struct UnmanagedStoreDirectoryCandidate: Hashable {
    let url: URL
    let kind: UnmanagedStoreDirectory.Kind
}

private struct StoreBackupManifest: Codable {
    let createdAt: Date
    let reason: StoreBackupReason
    let sourceStoreURL: String
    let items: [String]
}

enum StoreBackupManager {
    private static let backupDirectoryName = "Cadence Store Backups"
    private static let manifestName = "manifest.json"
    private static let pendingRestoreDefaultsKey = "cadence.pendingStoreRestoreURL"
    private static let failedRestoreDefaultsKey = "cadence.failedStoreRestore"
    /// Where a restore is assembled before it is allowed to replace anything, and where the store
    /// it replaces waits until the swap has finished. Both are hidden siblings of the store items
    /// inside the store directory, so a rename between them never crosses a volume, and neither
    /// name is in `CadenceStoreSupport.managedStoreItemNames`, so neither is ever mistaken for
    /// part of the store.
    private static let restoreStagingDirectoryName = ".cadence-restore-staging.tmp"
    private static let restoreDisplacedDirectoryName = ".cadence-restore-previous.tmp"
    /// Where originals a rollback could **not** put back are kept (T-1100), and the one directory
    /// in this file nothing ever deletes.
    ///
    /// Deliberately not a `.tmp` sibling of the two above: those two are scratch, and every path
    /// here is entitled to remove scratch. This is the user's own store files, held because the
    /// only other option is destroying them, and the name is what makes "scratch" and "the last
    /// copy of your data" two different things a later restore can tell apart. Visible rather than
    /// dotted, because `FailedRestoreRecord` names the path in a banner and a hidden folder is a
    /// worse answer to "where is my data" than a visible one.
    private static let unrestoredOriginalsDirectoryPrefix = "Cadence Unrestored Store Files"
    private static let denseStartupBackupCount = 5
    private static let dailyStartupRetentionDays = 7
    private static let weeklyStartupRetentionWeeks = 4
    private static let maxPreRestoreBackups = 5

    /// A restore that failed **and** could not be completely undone (T-1100).
    ///
    /// Its own type rather than a `CocoaError`, because the two facts a caller has to act on —
    /// that the store directory is no longer what it was, and where the originals went — cannot be
    /// recovered from a string. `performPendingRestoreIfNeeded` reads `retainedOriginalsPath` off
    /// it to build the record the banner shows; `errorDescription` is what a caller that only
    /// prints `localizedDescription` gets, so it has to carry the same three facts in prose.
    nonisolated struct RestoreRollbackFailure: LocalizedError, Equatable {
        /// The failure that started the rollback.
        let underlyingReason: String
        /// The store items the rollback could not put back, sorted.
        let unrestoredItemNames: [String]
        /// Where those items are now. Never empty, and never deleted by this app.
        let retainedOriginalsPath: String

        var errorDescription: String? {
            let items = unrestoredItemNames.joined(separator: ", ")
            return "\(underlyingReason) Undoing the restore then failed as well: \(items) could not be put back, so \(unrestoredItemNames.count == 1 ? "it was" : "they were") kept in \(retainedOriginalsPath) rather than deleted."
        }
    }

    /// A restore that was scheduled, attempted, and failed — kept instead of the pending key so
    /// the next launch reads it as history rather than as an instruction.
    nonisolated struct FailedRestoreRecord: Codable, Equatable {
        let backupPath: String
        let backupName: String
        let failedAt: Date
        let reason: String
        /// Set **only** when the rollback could not put every displaced original back (T-1100):
        /// the folder those originals were kept in instead. `nil` — the ordinary failed restore —
        /// means the store directory holds exactly what it held before the attempt.
        ///
        /// Optional so a record written before this field existed still decodes: a synthesized
        /// `init(from:)` reads a missing key for an `Optional` as `nil` rather than throwing, and
        /// a launch that threw away its own failure record would be a second defect on top of the
        /// first.
        let retainedOriginalsPath: String?

        init(
            backupPath: String,
            backupName: String,
            failedAt: Date,
            reason: String,
            retainedOriginalsPath: String? = nil
        ) {
            self.backupPath = backupPath
            self.backupName = backupName
            self.failedAt = failedAt
            self.reason = reason
            self.retainedOriginalsPath = retainedOriginalsPath
        }

        var backupURL: URL { URL(fileURLWithPath: backupPath, isDirectory: true) }

        /// What the startup banner says. It has to state the outcome the user cannot see for
        /// themselves — that their existing data is still there — because the visible evidence of
        /// a failed restore is that nothing changed, which is indistinguishable from nothing
        /// having been asked for.
        ///
        /// **T-1100: exactly one of these two sentences is true, and the record is what knows
        /// which.** "It kept the data already on this device" is a claim about the store directory,
        /// and a rollback that could not replace every original it moved aside has not earned it —
        /// the store there is part backup, part original, and the rest is in the retained folder.
        /// The second sentence says that, and says where, because the path is the only thing that
        /// makes those files findable.
        var startupMessage: String {
            guard let retainedOriginalsPath else {
                return "Cadence could not restore the backup \(backupName), so it kept the data already on this device: \(reason) The restore was not applied and will not be retried on its own."
            }
            return "Cadence could not restore the backup \(backupName), and could not put every file it had moved aside back where it found it: \(reason) Nothing was deleted — those files were kept in \(retainedOriginalsPath). The restore will not be retried on its own."
        }

        /// Which banner this record earns. The two differ in what they promise about the store, so
        /// the choice belongs with the fact that decides it rather than at the call site.
        var startupIssueKind: CadenceStartupIssueKind {
            retainedOriginalsPath == nil ? .restoreFailed : .restoreIncomplete
        }
    }

    static var backupRootURL: URL {
        (try? defaultStoreDirectoryURL().appendingPathComponent(backupDirectoryName, isDirectory: true))
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    @discardableResult
    static func createBackupIfStoreExists(reason: StoreBackupReason) throws -> URL? {
        try createBackupIfStoreExists(reason: reason, storeDirectoryURL: defaultStoreDirectoryURL())
    }

    @discardableResult
    static func createBackupIfStoreExists(
        reason: StoreBackupReason,
        storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL? {
        let sourceItems = existingStoreItems(in: storeDirectoryURL, fileManager: fileManager)
        guard !sourceItems.isEmpty else { return nil }

        let backupRootURL = backupRootURL(for: storeDirectoryURL)
        try fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)

        let now = Date()
        let finalURL = uniqueBackupDirectory(
            for: now,
            reason: reason,
            storeDirectoryURL: storeDirectoryURL,
            fileManager: fileManager
        )
        let temporaryURL = backupRootURL.appendingPathComponent(".\(finalURL.lastPathComponent).tmp", isDirectory: true)

        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        var copiedNames: [String] = []
        do {
            for source in sourceItems {
                let destination = temporaryURL.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(at: source, to: destination)
                copiedNames.append(source.lastPathComponent)
            }

            let manifest = StoreBackupManifest(
                createdAt: now,
                reason: reason,
                sourceStoreURL: storeDirectoryURL.appendingPathComponent("default.store").path,
                items: copiedNames
            )
            let manifestData = try JSONEncoder.cadenceBackupEncoder.encode(manifest)
            try manifestData.write(to: temporaryURL.appendingPathComponent(manifestName), options: .atomic)

            try fileManager.moveItem(at: temporaryURL, to: finalURL)
            if reason == .startup || reason == .preRestore {
                try purgeAutomaticBackups(storeDirectoryURL: storeDirectoryURL, fileManager: fileManager)
            }
            return finalURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func listBackups() -> [StoreBackupSnapshot] {
        listBackups(storeDirectoryURL: try? defaultStoreDirectoryURL())
    }

    static func listBackups(storeDirectoryURL: URL?, fileManager: FileManager = .default) -> [StoreBackupSnapshot] {
        guard let storeDirectoryURL else { return [] }
        let backupRootURL = backupRootURL(for: storeDirectoryURL)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: backupRootURL,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let manifest = manifest(at: url, fileManager: fileManager)
            let createdAt = manifest?.createdAt
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date.distantPast
            return StoreBackupSnapshot(
                id: url.lastPathComponent,
                url: url,
                createdAt: createdAt,
                reason: manifest?.reason.displayName ?? "Backup",
                sizeBytes: directorySize(url, fileManager: fileManager)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - The backups this app does not manage ([[T-1532]])

    /// Every directory a `Cadence Store Backups` folder could be sitting beside, live one first.
    ///
    /// Derived rather than listed, because a list is what missed one. Backups are always a child
    /// of the store directory (`backupRootURL(for:)`), so the candidates are exactly the store
    /// directories this app has used — and **their parents**, because two of the four folders
    /// found on 2026-09-29 sit directly under `Application Support`, from before the store moved
    /// into its own `Cadence/` subdirectory. The ticket itself counted three and the parent rule is
    /// what turned up the fourth: `…/Containers/com.haoranwei.Cadence/Data/Library/Application
    /// Support/Cadence/Cadence Store Backups`, 16 MB, six entries, newest 2026-05-28.
    ///
    /// Order is stable and de-duplicated by standardized path; a candidate that does not exist is
    /// not an error, it is the ordinary case on a machine that never had that layout.
    static func backupDirectoryCandidates(
        liveStoreDirectoryURL: URL?,
        legacyStoreDirectories: [URL] = CadenceStoreSupport.legacyStoreCandidateDirectories()
    ) -> [URL] {
        var storeDirectories: [URL] = []
        if let liveStoreDirectoryURL { storeDirectories.append(liveStoreDirectoryURL) }
        storeDirectories.append(contentsOf: legacyStoreDirectories)
        storeDirectories.append(contentsOf: storeDirectories.map { $0.deletingLastPathComponent() })

        var seenPaths: Set<String> = []
        return storeDirectories
            // A closure and not `.map(backupRootURL(for:))`: under this target's
            // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, an unapplied method reference does not
            // inherit the enclosing isolation the way a non-`Sendable` closure does, and the
            // shorter spelling is an `#ActorIsolatedCall` warning against a zero baseline.
            .map { backupRootURL(for: $0) }
            .filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
    }

    /// The candidates that exist, hold at least one backup, and are **not** the live directory.
    ///
    /// Read-only from end to end: `contentsOfDirectory`, `resourceValues` and the size walk, and
    /// nothing that creates, moves or removes. That is a property of this function rather than of
    /// its callers — it is the one thing that reaches paths the app has no business writing to.
    /// - Note: a `CadenceTests` process asks this with the **test host's** live directory, so the
    ///   owner's real app-group folder comes back as one of the unmanaged ones. That is the honest
    ///   answer for that process and it is why this whole path is read-only: after [[T-1530]] the
    ///   test host's store is `<tmp>/CadenceTestsHostStore`, and their app-group backups really are
    ///   a directory it does not manage. Tests inject rather than relying on it.
    static func unmanagedBackupDirectories() -> [UnmanagedBackupDirectory] {
        unmanagedBackupDirectories(liveStoreDirectoryURL: defaultStoreDirectoryLocation())
    }

    static func unmanagedBackupDirectories(
        liveStoreDirectoryURL: URL?,
        legacyStoreDirectories: [URL] = CadenceStoreSupport.legacyStoreCandidateDirectories(),
        fileManager: FileManager = .default
    ) -> [UnmanagedBackupDirectory] {
        let liveRootPath = liveStoreDirectoryURL
            .map { backupRootURL(for: $0).standardizedFileURL.path }

        return backupDirectoryCandidates(
            liveStoreDirectoryURL: liveStoreDirectoryURL,
            legacyStoreDirectories: legacyStoreDirectories
        )
        .filter { $0.standardizedFileURL.path != liveRootPath }
        .compactMap { rootURL in
            // `deletingLastPathComponent()` is the exact inverse of the `backupRootURL(for:)` the
            // candidate was built with, so this reads the candidate itself rather than guessing at
            // a second path from it.
            let backups = listBackups(
                storeDirectoryURL: rootURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
            guard !backups.isEmpty else { return nil }
            return UnmanagedBackupDirectory(
                url: rootURL,
                backupCount: backups.count,
                sizeBytes: backups.reduce(into: Int64(0)) { $0 += $1.sizeBytes }
            )
        }
    }

    // MARK: - The store folders this app is not using ([[T-1680]])

    /// Every directory that could hold Cadence store files this launch is not opening, recovery
    /// folders first, de-duplicated by standardized path.
    ///
    /// Derived rather than listed, exactly as `backupDirectoryCandidates` is, and from the two
    /// lists the app already acts on: the recovery half is where `makeRecoveryContainer` *writes*,
    /// the legacy half is where `migrateLegacyStoreIfNeeded` *reads*. Neither is inferred from a
    /// path seen on one Mac, which is the mistake [[T-1532]] had to correct with its parent rule.
    static func unmanagedStoreDirectoryCandidates(
        recoveryStoreDirectories: [URL],
        legacyStoreDirectories: [URL] = CadenceStoreSupport.legacyStoreCandidateDirectories()
    ) -> [UnmanagedStoreDirectoryCandidate] {
        var seenPaths: Set<String> = []
        let candidates =
            recoveryStoreDirectories.map { UnmanagedStoreDirectoryCandidate(url: $0, kind: .recovery) }
            + legacyStoreDirectories.map { UnmanagedStoreDirectoryCandidate(url: $0, kind: .previousLocation) }
        return candidates.filter { seenPaths.insert($0.url.standardizedFileURL.path).inserted }
    }

    /// The candidates that exist, hold at least one store item, and are **not** the store this
    /// launch has open.
    ///
    /// Read-only from end to end — `contentsOfDirectory`, `resourceValues` and the size walk, and
    /// nothing that creates, moves or removes. That is a property of this function and not of its
    /// callers, for the reason it is one on `unmanagedBackupDirectories`: this is the second place
    /// in the file that reaches paths the app has no business writing to, and one of them is the
    /// only copy of whatever a degraded launch recorded.
    ///
    /// - Note: a `CadenceTests` process asks the no-argument form with the **test host's** live
    ///   directory, so the owner's real app-group store comes back as one of these. That is the
    ///   honest answer for that process and it is why the whole path is read-only. Tests inject.
    static func unmanagedStoreDirectories() -> [UnmanagedStoreDirectory] {
        unmanagedStoreDirectories(
            liveStoreDirectoryURL: defaultStoreDirectoryLocation(),
            recoveryStoreDirectories: PersistenceController.recoveryStoreDirectoryCandidates(
                in: ProcessInfo.processInfo.environment
            )
        )
    }

    static func unmanagedStoreDirectories(
        liveStoreDirectoryURL: URL?,
        recoveryStoreDirectories: [URL],
        legacyStoreDirectories: [URL] = CadenceStoreSupport.legacyStoreCandidateDirectories(),
        fileManager: FileManager = .default
    ) -> [UnmanagedStoreDirectory] {
        let livePath = liveStoreDirectoryURL?.standardizedFileURL.path

        return unmanagedStoreDirectoryCandidates(
            recoveryStoreDirectories: recoveryStoreDirectories,
            legacyStoreDirectories: legacyStoreDirectories
        )
        .filter { $0.url.standardizedFileURL.path != livePath }
        .compactMap { candidate in
            let items = storeItems(in: candidate.url, fileManager: fileManager)
            guard !items.isEmpty else { return nil }
            return UnmanagedStoreDirectory(
                url: candidate.url,
                kind: candidate.kind,
                itemCount: items.count,
                sizeBytes: items.reduce(into: Int64(0)) { $0 += storeItemSize($1, fileManager: fileManager) },
                lastModified: items.compactMap {
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                }.max()
            )
        }
    }

    /// The names a store directory's own files go by, primary and recovery.
    ///
    /// Spelled from `CadenceStoreSupport.managedStoreItemNames` rather than beside it, so a sixth
    /// item added to the store cannot be a file this screen stops reporting.
    static let unmanagedStoreItemNames: [String] =
        CadenceStoreSupport.managedStoreItemNames + [
            "recovery.store",
            "recovery.store-wal",
            "recovery.store-shm",
            ".recovery_SUPPORT",
        ]

    /// The store files in a directory, and only those — matched by exact name, so a
    /// `Cadence Store Backups` folder, a `Cadence Unrestored Store Files …` folder or anything
    /// else a person left beside the store is neither counted nor sized here.
    private static func storeItems(in directoryURL: URL, fileManager: FileManager = .default) -> [URL] {
        ((try? fileManager.contentsOfDirectory(atPath: directoryURL.path)) ?? [])
            .filter { unmanagedStoreItemNames.contains($0) }
            .sorted()
            .map { directoryURL.appendingPathComponent($0) }
    }

    /// A size for one store item, file or directory. `directorySize` enumerates, and an enumerator
    /// over a plain file yields nothing — so `default.store` itself would have been sized at zero
    /// and `.default_SUPPORT` would have carried the whole row.
    private static func storeItemSize(_ url: URL, fileManager: FileManager = .default) -> Int64 {
        let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        )
        if values?.isDirectory == true {
            return directorySize(url, fileManager: fileManager)
        }
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    @discardableResult
    static func cleanUpAutomaticBackups() throws -> Int {
        try cleanUpAutomaticBackups(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    @discardableResult
    static func cleanUpAutomaticBackups(storeDirectoryURL: URL, fileManager: FileManager = .default) throws -> Int {
        let removableBackups = automaticBackupSnapshotsToRemove(
            listBackups(storeDirectoryURL: storeDirectoryURL, fileManager: fileManager)
        )
        for snapshot in removableBackups {
            try fileManager.removeItem(at: snapshot.url)
        }
        return removableBackups.count
    }

    @discardableResult
    static func deleteAllBackups() throws -> Int {
        try deleteAllBackups(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    /// Every folder of originals a failed rollback retained, oldest name first (T-1100).
    static func retainedUnrestoredOriginalDirectories(
        in storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        ((try? fileManager.contentsOfDirectory(atPath: storeDirectoryURL.path)) ?? [])
            .filter { $0.hasPrefix(unrestoredOriginalsDirectoryPrefix) }
            .sorted()
            .map { storeDirectoryURL.appendingPathComponent($0, isDirectory: true) }
    }

    /// Delete them.
    ///
    /// Reached from the privacy reset, and deliberately **not** from `deleteAllBackups`: a user
    /// clearing backups in Settings is managing disk space, and this folder is the last copy of
    /// store files a restore could not put back. A user who asks Cadence to delete *their data* is
    /// asking for it, though — leaving a copy of the store inside the app's own container would be
    /// the reset claiming more than it did, which is the same promise `docs/privacy.html` makes and
    /// T-1101 had to repair for the Keychain.
    @discardableResult
    static func deleteRetainedUnrestoredOriginals() throws -> Int {
        try deleteRetainedUnrestoredOriginals(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    @discardableResult
    static func deleteRetainedUnrestoredOriginals(
        storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        let retained = retainedUnrestoredOriginalDirectories(in: storeDirectoryURL, fileManager: fileManager)
        for directoryURL in retained {
            try fileManager.removeItem(at: directoryURL)
        }
        return retained.count
    }

    @discardableResult
    static func deleteAllBackups(storeDirectoryURL: URL) throws -> Int {
        let snapshots = listBackups(storeDirectoryURL: storeDirectoryURL)
        let backupRootURL = backupRootURL(for: storeDirectoryURL)

        if FileManager.default.fileExists(atPath: backupRootURL.path) {
            try FileManager.default.removeItem(at: backupRootURL)
        }

        return snapshots.count
    }

    /// - Parameter storeDirectoryURL: the store this restore is aimed at, `nil` for the real one.
    ///   It is needed because the pending restore is also recorded *beside the store* — see
    ///   `CadenceStoreSupport.restorePendingMarkerName` — so that the widget extension, which does
    ///   not share `UserDefaults.standard`, can see that a restore is about to replace whatever it
    ///   would write (T-311).
    static func scheduleRestore(
        from backupURL: URL,
        defaults: UserDefaults = CadenceDefaults.store,
        storeDirectoryURL: URL? = nil
    ) throws {
        guard isBackupDirectory(backupURL) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        // A freshly chosen backup supersedes whatever failed last time; otherwise the record of
        // the old failure would outlive the reason anyone would still care about it.
        defaults.removeObject(forKey: failedRestoreDefaultsKey)
        defaults.set(backupURL.path, forKey: pendingRestoreDefaultsKey)
        setSharedRestorePendingMarker(true, storeDirectoryURL: storeDirectoryURL)
    }

    static func clearPendingRestore(defaults: UserDefaults = CadenceDefaults.store, storeDirectoryURL: URL? = nil) {
        defaults.removeObject(forKey: pendingRestoreDefaultsKey)
        setSharedRestorePendingMarker(false, storeDirectoryURL: storeDirectoryURL)
    }

    /// Keep the app-group marker in step with the pending-restore key. Resolving the store
    /// directory here rather than at each call site keeps the two writes in one place, which is
    /// the only way the marker cannot outlive the thing it stands for.
    private static func setSharedRestorePendingMarker(_ pending: Bool, storeDirectoryURL: URL?) {
        guard let directoryURL = storeDirectoryURL ?? (try? defaultStoreDirectoryURL()) else { return }
        CadenceStoreSupport.setRestorePending(pending, inStoreDirectory: directoryURL)
    }

    static func pendingRestoreURL(defaults: UserDefaults = CadenceDefaults.store) -> URL? {
        guard let storedPath = defaults.string(forKey: pendingRestoreDefaultsKey), !storedPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: storedPath, isDirectory: true)
    }

    /// The restore Cadence tried, failed at, and refused to try again on its own.
    static func lastFailedRestore(defaults: UserDefaults = CadenceDefaults.store) -> FailedRestoreRecord? {
        guard let data = defaults.data(forKey: failedRestoreDefaultsKey) else { return nil }
        return try? JSONDecoder.cadenceBackupDecoder.decode(FailedRestoreRecord.self, from: data)
    }

    static func clearFailedRestore(defaults: UserDefaults = CadenceDefaults.store) {
        defaults.removeObject(forKey: failedRestoreDefaultsKey)
    }

    static func performPendingRestoreIfNeeded() throws {
        try performPendingRestoreIfNeeded(storeDirectoryURL: defaultStoreDirectoryURL())
    }

    /// Apply the restore the user scheduled on a previous launch, or do nothing.
    ///
    /// **T-326.** This used to remove the live store items *first* and copy the backup over them
    /// second, clearing the pending flag only after the last copy landed. Anything that threw in
    /// between — a full disk, a damaged sidecar inside the backup, a permission failure, an
    /// interrupted copy — left the user with no store **and** the pending restore still set: the
    /// app fell back to a recovery store, and the next launch ran the same failing restore again.
    /// Their data was sitting in the pre-restore backup and nothing told them so.
    ///
    /// The ordering now matches the one backup *creation* has used all along, about 130 lines
    /// above: assemble the whole replacement in a `.tmp` sibling, verify it, and only then swap.
    /// Nothing live is removed until a complete, verified replacement exists, and the swap itself
    /// moves the old items aside rather than deleting them so a failure mid-swap puts them back.
    ///
    /// A restore that fails is **quarantined** rather than left pending, so a launch cannot wedge.
    static func performPendingRestoreIfNeeded(
        storeDirectoryURL: URL,
        fileManager: FileManager = .default,
        defaults: UserDefaults = CadenceDefaults.store
    ) throws {
        guard let backupURL = pendingRestoreURL(defaults: defaults) else {
            // The launch is also where a stale app-group marker gets reconciled against the key it
            // mirrors. Without this, a marker that outlived its restore would refuse every widget
            // write from then on, and only a reinstall would clear it.
            CadenceStoreSupport.setRestorePending(false, inStoreDirectory: storeDirectoryURL)
            return
        }
        guard isBackupDirectory(backupURL, fileManager: fileManager) else {
            quarantinePendingRestore(
                backupURL: backupURL,
                reason: "The backup folder is missing, or no longer looks like a Cadence backup.",
                defaults: defaults,
                storeDirectoryURL: storeDirectoryURL
            )
            throw CocoaError(.fileReadNoSuchFile)
        }

        do {
            try applyRestore(from: backupURL, into: storeDirectoryURL, fileManager: fileManager)
        } catch {
            quarantinePendingRestore(
                backupURL: backupURL,
                reason: error.localizedDescription,
                // The one thing the banner cannot infer from prose: this failure left files
                // somewhere other than where the user's store lives (T-1100).
                retainedOriginalsPath: (error as? RestoreRollbackFailure)?.retainedOriginalsPath,
                defaults: defaults,
                storeDirectoryURL: storeDirectoryURL
            )
            throw error
        }

        clearFailedRestore(defaults: defaults)
        clearPendingRestore(defaults: defaults, storeDirectoryURL: storeDirectoryURL)
    }

    /// Stage, verify, swap. Every `throw` in here leaves the live store exactly as it was.
    private static func applyRestore(
        from backupURL: URL,
        into storeDirectoryURL: URL,
        fileManager: FileManager
    ) throws {
        _ = try createBackupIfStoreExists(
            reason: .preRestore,
            storeDirectoryURL: storeDirectoryURL,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)

        let stagingURL = storeDirectoryURL.appendingPathComponent(restoreStagingDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let stagedNames = try stageBackupContents(of: backupURL, into: stagingURL, fileManager: fileManager)
        try verifyStagedRestore(
            at: stagingURL,
            from: backupURL,
            stagedNames: stagedNames,
            fileManager: fileManager
        )
        try swapStagedRestore(
            at: stagingURL,
            names: stagedNames,
            into: storeDirectoryURL,
            fileManager: fileManager
        )
    }

    private static func stageBackupContents(
        of backupURL: URL,
        into stagingURL: URL,
        fileManager: FileManager
    ) throws -> [String] {
        let backupContents = try fileManager.contentsOfDirectory(
            at: backupURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        var stagedNames: [String] = []
        for source in backupContents where source.lastPathComponent != manifestName {
            try fileManager.copyItem(at: source, to: stagingURL.appendingPathComponent(source.lastPathComponent))
            stagedNames.append(source.lastPathComponent)
        }
        return stagedNames
    }

    /// A staged copy only earns the right to replace the live store if it is complete.
    ///
    /// Three things have to hold: the store file itself is present, everything the backup's own
    /// manifest claims is present, and every staged item is byte-for-byte the same size as the
    /// item it was copied from. The last one is the point — a copy that stopped early still leaves
    /// a file at the destination, so an existence check alone would wave a truncated store through
    /// and swap it over a good one.
    private static func verifyStagedRestore(
        at stagingURL: URL,
        from backupURL: URL,
        stagedNames: [String],
        fileManager: FileManager
    ) throws {
        let stagedNameSet = Set(stagedNames)
        guard stagedNameSet.contains(CadenceStoreSupport.storeFilename) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let manifestItems = Set(manifest(at: backupURL, fileManager: fileManager)?.items ?? [])
            .subtracting([manifestName])
        guard manifestItems.isSubset(of: stagedNameSet) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        for name in stagedNames {
            guard let sourceSize = itemSize(of: backupURL.appendingPathComponent(name), fileManager: fileManager),
                  let stagedSize = itemSize(of: stagingURL.appendingPathComponent(name), fileManager: fileManager),
                  sourceSize == stagedSize else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    /// Move the live items aside, move the verified ones in, and only then drop the old copy.
    ///
    /// Several files have to change together and no single rename covers all of them, so this is
    /// the one window that cannot be made atomic outright. The displaced directory is what closes
    /// it: anything that throws part-way puts every displaced item back where it was.
    ///
    /// **T-1100 — the rollback used to delete the displaced directory whether or not it had
    /// emptied it.** Both compensating operations were `try?`, and the removal beneath them was
    /// unconditional, so a rollback that could not move an original back deleted that original a
    /// line later: the one outcome this whole staged design exists to prevent, reached through the
    /// code written to prevent it. A single filesystem fault is not the case that needs
    /// arguing — the forward move and the compensating move are the same operation on the same
    /// volume, so whatever refused one is available to refuse the other.
    ///
    /// The rule now: **nothing here removes a directory it did not empty.** A rollback that leaves
    /// anything behind retains that folder under `unrestoredOriginalsDirectoryPrefix` and reports
    /// where, and both the removal *and* the move-back stop being swallowed — a removal that fails
    /// makes the move-back onto the same path fail, which is now recorded rather than lost.
    private static func swapStagedRestore(
        at stagingURL: URL,
        names: [String],
        into storeDirectoryURL: URL,
        fileManager: FileManager
    ) throws {
        let displacedURL = storeDirectoryURL.appendingPathComponent(restoreDisplacedDirectoryName, isDirectory: true)
        // A displaced directory that is already here is not this call's scratch: it is the
        // originals of a swap that never finished — the process killed mid-move, or a rollback
        // that could not complete. Removing it to reuse the path is the same deletion the catch
        // below refuses to make, one launch later. Retaining it first `throw`s if it cannot,
        // before anything live has been touched.
        if fileManager.fileExists(atPath: displacedURL.path) {
            _ = try retainUnrestoredOriginals(at: displacedURL, in: storeDirectoryURL, fileManager: fileManager)
        }
        try fileManager.createDirectory(at: displacedURL, withIntermediateDirectories: true)

        var displacedNames: [String] = []
        var installedNames: [String] = []
        do {
            for item in existingStoreItems(in: storeDirectoryURL, fileManager: fileManager) {
                try fileManager.moveItem(at: item, to: displacedURL.appendingPathComponent(item.lastPathComponent))
                displacedNames.append(item.lastPathComponent)
            }
            for name in names {
                try fileManager.moveItem(
                    at: stagingURL.appendingPathComponent(name),
                    to: storeDirectoryURL.appendingPathComponent(name)
                )
                installedNames.append(name)
            }
        } catch {
            // Only the items this call put there. Anything still sitting in the store directory
            // under a staged name is an original that was never displaced, and deleting that is
            // the very failure this method exists to prevent.
            for name in installedNames {
                try? fileManager.removeItem(at: storeDirectoryURL.appendingPathComponent(name))
            }
            var unrestoredNames: [String] = []
            for name in displacedNames {
                do {
                    try fileManager.moveItem(
                        at: displacedURL.appendingPathComponent(name),
                        to: storeDirectoryURL.appendingPathComponent(name)
                    )
                } catch {
                    unrestoredNames.append(name)
                }
            }
            guard unrestoredNames.isEmpty else {
                // The originals still in there are the only copy of themselves. If even the
                // retaining move fails, the displaced directory keeps its own name and is reported
                // under it — still not deleted, which is the whole promise.
                let retainedURL = (try? retainUnrestoredOriginals(
                    at: displacedURL,
                    in: storeDirectoryURL,
                    fileManager: fileManager
                )) ?? displacedURL
                throw RestoreRollbackFailure(
                    underlyingReason: error.localizedDescription,
                    unrestoredItemNames: unrestoredNames.sorted(),
                    retainedOriginalsPath: retainedURL.path
                )
            }
            // Empty by the loop above, and only then removed.
            try? fileManager.removeItem(at: displacedURL)
            throw error
        }

        try? fileManager.removeItem(at: displacedURL)
    }

    /// Move a folder of originals somewhere no restore will reuse, and answer where it went.
    ///
    /// The timestamped name is the point: two failures a week apart are two folders, not one
    /// overwriting the other, and `-2` suffixes settle the same-second collision the way
    /// `uniqueBackupDirectory` already does for backups. The prefix is not in
    /// `CadenceStoreSupport.managedStoreItemNames`, so no store scan, backup or migration reads
    /// what is inside it as part of the store.
    private static func retainUnrestoredOriginals(
        at displacedURL: URL,
        in storeDirectoryURL: URL,
        now: Date = Date(),
        fileManager: FileManager
    ) throws -> URL {
        let baseName = "\(unrestoredOriginalsDirectoryPrefix) \(DateFormatters.backupFolderTimestamp.string(from: now))"
        var candidate = storeDirectoryURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = storeDirectoryURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.moveItem(at: displacedURL, to: candidate)
        return candidate
    }

    /// Take a failing restore off the launch path without throwing away what it was.
    ///
    /// Clearing alone would stop the loop, and that is what the old code did for a backup folder
    /// that no longer parses — but it also erases the fact that the user asked for a restore, which
    /// is the one thing they need to see afterwards. Quarantining moves the intent out of the key
    /// the launch reads and into a record the startup banner names, so a second attempt is a
    /// decision the user makes rather than something a launch does to itself.
    private static func quarantinePendingRestore(
        backupURL: URL,
        reason: String,
        retainedOriginalsPath: String? = nil,
        defaults: UserDefaults,
        storeDirectoryURL: URL? = nil
    ) {
        let record = FailedRestoreRecord(
            backupPath: backupURL.path,
            backupName: backupURL.lastPathComponent,
            failedAt: Date(),
            reason: reason,
            retainedOriginalsPath: retainedOriginalsPath
        )
        if let data = try? JSONEncoder.cadenceBackupEncoder.encode(record) {
            defaults.set(data, forKey: failedRestoreDefaultsKey)
        }
        clearPendingRestore(defaults: defaults, storeDirectoryURL: storeDirectoryURL)
    }

    /// The size of one backed-up item, whether it is a file or one of the store's sidecar folders.
    private static func itemSize(of url: URL, fileManager: FileManager) -> Int64? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return directorySize(url, fileManager: fileManager)
        }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    /// Where every entry point on this type that was not handed a directory looks — eight of them:
    /// `backupRootURL`, `createBackupIfStoreExists(reason:)`, `listBackups()`,
    /// `cleanUpAutomaticBackups()`, `deleteAllBackups()`, `deleteRetainedUnrestoredOriginals()`,
    /// `setSharedRestorePendingMarker` and `performPendingRestoreIfNeeded()`.
    ///
    /// **T-1448.** This was `CadenceStoreSupport.primaryStoreDirectoryURL()`, which answers the
    /// app-group store and nothing else — so on a launch redirected by `CADENCE_UI_TEST_STORE_ID`
    /// the backups this type managed were the signed-in person's while the store the app had open
    /// was private. Backups are siblings of the store items (`backupRootURL(for:)`), so the two
    /// disagreeing is not a matter of taste: it is this type operating on a store the app is not
    /// using.
    private static func defaultStoreDirectoryURL() throws -> URL {
        try storeDirectoryURL(in: ProcessInfo.processInfo.environment)
    }

    /// Where the two **listings** look — `unmanagedBackupDirectories()` and
    /// `unmanagedStoreDirectories()`, and nothing else ([[T-1852]]).
    ///
    /// They are the entry points that want the live store directory in order to exclude it from a
    /// read-only list, and going through `defaultStoreDirectoryURL()` meant that opening Settings →
    /// Data Safety — or running a unit test that called either one — *created* the store directory
    /// it was asking about. `nil` rather than `throws` because a live directory that cannot be
    /// resolved is already an ordinary input here: both listings take `URL?` and simply exclude
    /// nothing.
    private static func defaultStoreDirectoryLocation() -> URL? {
        try? storeDirectoryLocation(in: ProcessInfo.processInfo.environment)
    }

    /// The resolution itself, with its inputs injected so a test can drive **both** halves — the
    /// redirected one and, more importantly, the unset one, which has to keep answering exactly
    /// the production path or this change reaches the shipping app.
    ///
    /// **[[T-1530]] widened "redirected" to include the test host.** It asked
    /// `privateStoreDirectory` and therefore only about `CADENCE_UI_TEST_STORE_ID`, which a plain
    /// `xcodebuild test` never sets — so inside `CadenceTests` every no-argument entry point above
    /// resolved the signed-in person's app-group directory while the app under test had a
    /// throwaway store open. It now asks `redirectedStoreDirectory`, the same one
    /// `PersistenceController.resolvedStoreURL()` asks. The unset case is unchanged and is
    /// asserted in both directions, because it is the shipping app's.
    static func storeDirectoryURL(
        in environment: [String: String],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) throws -> URL {
        let storeDirectoryURL = try storeDirectoryLocation(
            in: environment,
            temporaryDirectory: temporaryDirectory,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
        return storeDirectoryURL
    }

    /// **The same resolution, composed and never created ([[T-1852]]).**
    ///
    /// The redirect is asked here and nowhere else on this type — `storeDirectoryURL(in:)` above is
    /// this plus one `createDirectory`, which is the shape that keeps the creating and the
    /// non-creating answers from drifting apart. Two copies of the redirect question is exactly how
    /// the store and its backups came to disagree in [[T-1530]].
    ///
    /// The read-only listings take this one: `unmanagedBackupDirectories()` and
    /// `unmanagedStoreDirectories()` want the live directory only in order to **exclude** it, and
    /// before this they created the signed-in person's store directory merely by asking where it
    /// was. On a host with no writable app-group container this also *answers* where the unredirected
    /// store would be instead of refusing, because only the `createDirectory` is denied there
    /// ([[T-1850]]).
    static func storeDirectoryLocation(
        in environment: [String: String],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let redirectedStoreDirectoryURL = CadenceUITestStoreDirectory.redirectedStoreDirectory(
            in: environment,
            temporaryDirectory: temporaryDirectory
        ) else {
            return try CadenceStoreSupport.storeDirectoryLocation(fileManager: fileManager)
        }
        return redirectedStoreDirectoryURL
    }

    private static func existingStoreItems(in storeDirectoryURL: URL, fileManager: FileManager = .default) -> [URL] {
        CadenceStoreSupport.storeItemURLs(in: storeDirectoryURL, fileManager: fileManager)
    }

    private static func backupRootURL(for storeDirectoryURL: URL) -> URL {
        storeDirectoryURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    private static func uniqueBackupDirectory(
        for date: Date,
        reason: StoreBackupReason,
        storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let backupRootURL = backupRootURL(for: storeDirectoryURL)
        let baseName = "\(DateFormatters.backupFolderTimestamp.string(from: date))-\(reason.rawValue)"
        var candidate = backupRootURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = backupRootURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static func isBackupDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let manifestURL = url.appendingPathComponent(manifestName)
        let storeURL = url.appendingPathComponent(CadenceStoreSupport.storeFilename)
        return fileManager.fileExists(atPath: manifestURL.path)
            && fileManager.fileExists(atPath: storeURL.path)
    }

    private static func manifest(at url: URL, fileManager: FileManager = .default) -> StoreBackupManifest? {
        let manifestURL = url.appendingPathComponent(manifestName)
        guard fileManager.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder.cadenceBackupDecoder.decode(StoreBackupManifest.self, from: data)
    }

    private static func purgeAutomaticBackups(storeDirectoryURL: URL, fileManager: FileManager = .default) throws {
        try cleanUpAutomaticBackups(storeDirectoryURL: storeDirectoryURL, fileManager: fileManager)
    }

    static func automaticBackupSnapshotsToRemove(
        _ snapshots: [StoreBackupSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [StoreBackupSnapshot] {
        let startupDisplayName = StoreBackupReason.startup.displayName
        let preRestoreDisplayName = StoreBackupReason.preRestore.displayName
        let startupBackups = snapshots
            .filter { $0.reason == startupDisplayName }
            .sorted { $0.createdAt > $1.createdAt }
        let preRestoreBackups = snapshots
            .filter { $0.reason == preRestoreDisplayName }
            .sorted { $0.createdAt > $1.createdAt }

        var keptIDs = retainedStartupBackupIDs(
            startupBackups,
            now: now,
            calendar: calendar
        )
        keptIDs.formUnion(preRestoreBackups.prefix(maxPreRestoreBackups).map(\.id))

        return snapshots.filter { snapshot in
            (snapshot.reason == startupDisplayName || snapshot.reason == preRestoreDisplayName)
                && !keptIDs.contains(snapshot.id)
        }
    }

    private static func retainedStartupBackupIDs(
        _ backups: [StoreBackupSnapshot],
        now: Date,
        calendar inputCalendar: Calendar
    ) -> Set<String> {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let today = calendar.startOfDay(for: now)
        var retained = Set<String>()
        var retainedDayBuckets = Set<String>()
        var retainedWeekBuckets = Set<String>()

        func ageInDays(for date: Date) -> Int? {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day
        }

        func dayBucket(for date: Date) -> String {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        }

        func weekBucket(for date: Date) -> String {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
        }

        func rememberBuckets(for snapshot: StoreBackupSnapshot) {
            guard let age = ageInDays(for: snapshot.createdAt), age >= 0 else { return }
            if age < dailyStartupRetentionDays {
                retainedDayBuckets.insert(dayBucket(for: snapshot.createdAt))
            } else if age < dailyStartupRetentionDays + weeklyStartupRetentionWeeks * 7 {
                retainedWeekBuckets.insert(weekBucket(for: snapshot.createdAt))
            }
        }

        for snapshot in backups.prefix(denseStartupBackupCount) {
            retained.insert(snapshot.id)
            rememberBuckets(for: snapshot)
        }

        for snapshot in backups.dropFirst(denseStartupBackupCount) {
            guard let age = ageInDays(for: snapshot.createdAt) else { continue }
            if age < 0 {
                retained.insert(snapshot.id)
            } else if age < dailyStartupRetentionDays {
                let bucket = dayBucket(for: snapshot.createdAt)
                if retainedDayBuckets.insert(bucket).inserted {
                    retained.insert(snapshot.id)
                }
            } else if age < dailyStartupRetentionDays + weeklyStartupRetentionWeeks * 7 {
                let bucket = weekBucket(for: snapshot.createdAt)
                if retainedWeekBuckets.insert(bucket).inserted {
                    retained.insert(snapshot.id)
                }
            }
        }
        return retained
    }

    private static func directorySize(_ url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        ) else {
            return 0
        }

        return enumerator.reduce(into: Int64(0)) { total, item in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
                return
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
    }
}

private extension JSONEncoder {
    static var cadenceBackupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var cadenceBackupDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - T-1366: what a launch's startup passes cost, and which of them refused

/// Every stage a launch runs before the first frame that this instrument can time from inside
/// `PersistenceController`.
///
/// It is not the whole of launch and does not pretend to be: view composition, the initial
/// `@Query` fetches, image decoding and the first frame follow this work, the initial CloudKit
/// import is asynchronous and nothing here waits for it, and none of those are reachable from this
/// file. What was measured before this was **none of it** — [[T-1329]]'s medians are in-memory
/// fixture numbers for four of the maintenance passes, taken with no disk, no preflight and no
/// container open in the picture at all.
nonisolated enum CadenceStartupStage: String, Hashable, CaseIterable {
    /// Legacy-store migration, a pending restore, and the startup backup copy. File work, so its
    /// cost follows store *bytes* rather than row counts — the reason it cannot be inferred from
    /// any of the fixture numbers already in the ledger.
    case preflight
    /// Opening the CloudKit-backed `ModelContainer` on the real store.
    case containerOpen
    case pursuitMigration
    case noteMigration
    case tagSync
    case integrityRepair
    case focusReconciliation
    /// The one save at the end, which only happens when a pass reported a change.
    case maintenanceSave
}

/// What a stage's own result says it did. **`noChange` and `refused` are stored apart**, which is
/// the thing the audit asks for by name: "nothing to do" and "could not do it" read the same in
/// three of these passes today, and a launch that silently failed to repair looks exactly like a
/// launch with nothing to repair.
nonisolated enum CadenceStartupStageOutcome: String, Hashable {
    /// The pass ran and reported that it changed the store.
    case changed
    /// The pass ran and reported there was nothing to do. A **result**.
    case noChange
    /// The pass reported it could not do its work. A **failure**, never a result.
    case refused
    /// The pass ran and its answer **cannot separate** the two above from this call site. Recorded
    /// as its own outcome rather than folded into `noChange`, because calling an unknown a clean
    /// result is the defect, not the reporting of it.
    ///
    /// **No startup pass produces this any more, and the case stays** ([[T-1402]]). All three that
    /// did — the pursuit migration, the tag sync and the focus reconcile — now answer
    /// `CadenceMaintenancePassOutcome`, so `performStartupMaintenance` classifies nothing as
    /// indeterminate and `CadenceStartupCostInstrumentTests` asserts that as an equality rather
    /// than the subset it could only assert before. The vocabulary is kept because a *future* pass
    /// added with a two-reading `Bool` must be recordable as what it is; deleting the case would
    /// leave the next such pass with nowhere to go but `noChange`, which is the defect.
    case indeterminate
    /// A stage with no change vocabulary at all: it either completed or threw.
    case completed
}

/// A stage's verdict, built at the call site out of what that pass actually returns.
nonisolated struct CadenceStartupStageVerdict: Hashable {
    let outcome: CadenceStartupStageOutcome
    /// Why it refused, or why its outcome is indeterminate. Never user text: a refusal reason goes
    /// through `PersistenceController.instrumentReason(for:)`, which is built from an error's type
    /// and `NSError` domain and code alone.
    let note: String?
    /// A count the pass reported about itself — rows inserted, rows repaired — with no content in
    /// it. `nil` where the pass reports no number at all, which is not the same as reporting zero.
    let count: Int?

    static func changed(_ count: Int?) -> Self {
        Self(outcome: .changed, note: nil, count: count)
    }

    static var noChange: Self {
        Self(outcome: .noChange, note: nil, count: nil)
    }

    static func refused(_ reason: String) -> Self {
        Self(outcome: .refused, note: reason, count: nil)
    }

    static func indeterminate(_ why: String) -> Self {
        Self(outcome: .indeterminate, note: why, count: nil)
    }

    static var completed: Self {
        Self(outcome: .completed, note: nil, count: nil)
    }

    /// The verdict for a pass that answers `CadenceMaintenancePassOutcome` — which, since
    /// [[T-1402]], is all three of the passes that used to answer `indeterminate`.
    ///
    /// **`couldNotRead` becomes `refused` and not `noChange`, and that is the whole ticket.** The
    /// note is the pass's own vocabulary rather than an error's text: these three report that they
    /// could not read, not *what* they could not read, so there is nothing here that could carry a
    /// title or a path even by accident.
    ///
    /// `changed` carries no count: none of the three reports a number about itself, and inventing
    /// a `0` for a pass that changed something would be worse than saying nothing —
    /// `CadenceStartupStageRecord.count` is `nil` for "reported no number", which is not the same
    /// as a number that happens to be zero.
    static func forMaintenancePass(_ outcome: CadenceMaintenancePassOutcome) -> Self {
        switch outcome {
        case .changed: return .changed(nil)
        case .nothingToDo: return .noChange
        case .couldNotRead: return .refused("passCouldNotRead")
        }
    }
}

nonisolated struct CadenceStartupStageRecord: Hashable {
    let stage: CadenceStartupStage
    let duration: TimeInterval
    let outcome: CadenceStartupStageOutcome
    let note: String?
    let count: Int?
}

/// One launch's measured startup cost.
nonisolated struct CadenceStartupCostReport: Hashable {
    let recordedAt: Date
    /// In the order the launch ran them.
    let stages: [CadenceStartupStageRecord]
    let totalDuration: TimeInterval
    /// Physical footprint at the end of startup maintenance, or `nil` when the kernel would not
    /// answer. Never `0` — `CadenceProcessFootprint.currentBytes()` returns nothing rather than a
    /// figure no live process can have.
    let footprintBytes: Int?

    /// **A report with no stages in it refuses to exist.** An instrument that timed nothing and
    /// reports a total of zero is the false clean sweep this ticket is written against.
    init?(recordedAt: Date, stages: [CadenceStartupStageRecord], totalDuration: TimeInterval, footprintBytes: Int?) {
        guard !stages.isEmpty, totalDuration.isFinite, totalDuration >= 0 else { return nil }
        guard stages.allSatisfy({ $0.duration.isFinite && $0.duration >= 0 }) else { return nil }
        self.recordedAt = recordedAt
        self.stages = stages
        self.totalDuration = totalDuration
        self.footprintBytes = footprintBytes
    }

    func stage(_ stage: CadenceStartupStage) -> CadenceStartupStageRecord? {
        stages.first { $0.stage == stage }
    }

    /// The stages this report is entitled to speak about. A stage outside it was not reached by
    /// this launch — a store that failed preflight never opens a container, and a launch whose
    /// passes all reported no change never saves.
    var measuredStages: Set<CadenceStartupStage> {
        Set(stages.map(\.stage))
    }

    /// Stages whose own result could not separate a no-op from a failure. Non-empty is not a bug in
    /// this report; it is the report saying what the pass would not tell it.
    var indeterminateStages: [CadenceStartupStage] {
        stages.filter { $0.outcome == .indeterminate }.map(\.stage)
    }

    var refusedStages: [CadenceStartupStage] {
        stages.filter { $0.outcome == .refused }.map(\.stage)
    }
}

/// Why the startup ledger has no number.
nonisolated enum CadenceStartupLedgerSilence: String, Hashable {
    case instrumentDisabled
    case nothingRecorded
    case reportUnreadable
}

nonisolated enum CadenceStartupLedgerReading: Hashable {
    case recorded(CadenceStartupCostReport)
    case silent(CadenceStartupLedgerSilence)

    var report: CadenceStartupCostReport? {
        switch self {
        case let .recorded(report): return report
        case .silent: return nil
        }
    }

    var silence: CadenceStartupLedgerSilence? {
        switch self {
        case .recorded: return nil
        case let .silent(silence): return silence
        }
    }
}

/// The durable half of the startup instrument: the most recent launch's stage costs.
///
/// Opt-in through `enabledDefaultsKey`. With it unset `begin(defaults:)` answers `nil`, every
/// `measure` on that `nil` runs its body and does nothing else, and `lastReport(defaults:)`
/// answers `.silent(.instrumentDisabled)` rather than an empty report.
nonisolated enum CadenceStartupCostLedger {
    static let enabledDefaultsKey = "cadence.instrument.startupCost.enabled"
    static let lastReportDefaultsKey = "cadence.instrument.startupCost.lastReport"

    static func isEnabled(defaults: UserDefaults = CadenceDefaults.store) -> Bool {
        defaults.bool(forKey: enabledDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = CadenceDefaults.store) {
        if enabled {
            defaults.set(true, forKey: enabledDefaultsKey)
        } else {
            defaults.removeObject(forKey: enabledDefaultsKey)
        }
    }

    /// A recorder for this launch, or `nil` when nobody asked for one.
    static func begin(
        defaults: UserDefaults = CadenceDefaults.store,
        nanoseconds: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        wallClock: @escaping () -> Date = Date.init,
        footprint: @escaping () -> Int? = CadenceProcessFootprint.currentBytes
    ) -> CadenceStartupCostRecorder? {
        guard isEnabled(defaults: defaults) else { return nil }
        return CadenceStartupCostRecorder(
            defaults: defaults,
            nanoseconds: nanoseconds,
            wallClock: wallClock,
            footprint: footprint
        )
    }

    static func lastReport(defaults: UserDefaults = CadenceDefaults.store) -> CadenceStartupLedgerReading {
        guard isEnabled(defaults: defaults) else { return .silent(.instrumentDisabled) }
        guard let payload = defaults.dictionary(forKey: lastReportDefaultsKey) else {
            return .silent(.nothingRecorded)
        }
        guard let report = CadenceStartupCostReport(storagePayload: payload) else {
            return .silent(.reportUnreadable)
        }
        return .recorded(report)
    }

    static func clearStoredState(defaults: UserDefaults = CadenceDefaults.store) {
        defaults.removeObject(forKey: lastReportDefaultsKey)
    }

    static func store(_ report: CadenceStartupCostReport, defaults: UserDefaults) {
        defaults.set(report.storagePayload, forKey: lastReportDefaultsKey)
    }
}

extension CadenceStartupCostReport {
    nonisolated fileprivate var storagePayload: [String: Any] {
        var payload: [String: Any] = [
            "recordedAt": recordedAt.timeIntervalSince1970,
            "total": totalDuration,
            "stages": stages.map { record -> [String: Any] in
                var encoded: [String: Any] = [
                    "stage": record.stage.rawValue,
                    "duration": record.duration,
                    "outcome": record.outcome.rawValue,
                ]
                if let note = record.note { encoded["note"] = note }
                if let count = record.count { encoded["count"] = count }
                return encoded
            },
        ]
        if let footprintBytes { payload["footprint"] = footprintBytes }
        return payload
    }

    nonisolated fileprivate init?(storagePayload payload: [String: Any]) {
        guard let recordedAt = (payload["recordedAt"] as? NSNumber)?.doubleValue,
              recordedAt > 0,
              let total = (payload["total"] as? NSNumber)?.doubleValue,
              let rawStages = payload["stages"] as? [[String: Any]]
        else { return nil }

        var stages: [CadenceStartupStageRecord] = []
        for raw in rawStages {
            guard let rawStage = raw["stage"] as? String,
                  let stage = CadenceStartupStage(rawValue: rawStage),
                  let duration = (raw["duration"] as? NSNumber)?.doubleValue,
                  let rawOutcome = raw["outcome"] as? String,
                  let outcome = CadenceStartupStageOutcome(rawValue: rawOutcome)
            else { return nil }
            stages.append(
                CadenceStartupStageRecord(
                    stage: stage,
                    duration: duration,
                    outcome: outcome,
                    note: raw["note"] as? String,
                    count: (raw["count"] as? NSNumber)?.intValue
                )
            )
        }

        self.init(
            recordedAt: Date(timeIntervalSince1970: recordedAt),
            stages: stages,
            totalDuration: total,
            footprintBytes: (payload["footprint"] as? NSNumber)?.intValue
        )
    }
}

/// The live half: one per launch, handed down into `PersistenceController.performStartupMaintenance`.
nonisolated final class CadenceStartupCostRecorder {
    private let defaults: UserDefaults
    private let nanoseconds: () -> UInt64
    private let wallClock: () -> Date
    private let footprint: () -> Int?
    private let started: UInt64
    private var lastMark: UInt64
    private var stages: [CadenceStartupStageRecord] = []

    init(
        defaults: UserDefaults,
        nanoseconds: @escaping () -> UInt64,
        wallClock: @escaping () -> Date,
        footprint: @escaping () -> Int?
    ) {
        self.defaults = defaults
        self.nanoseconds = nanoseconds
        self.wallClock = wallClock
        self.footprint = footprint
        let now = nanoseconds()
        self.started = now
        self.lastMark = now
    }

    /// Closes the stage that has been running since the last mark.
    func finished(_ stage: CadenceStartupStage, _ verdict: CadenceStartupStageVerdict) {
        let now = nanoseconds()
        stages.append(
            CadenceStartupStageRecord(
                stage: stage,
                duration: Self.seconds(from: lastMark, to: now),
                outcome: verdict.outcome,
                note: verdict.note,
                count: verdict.count
            )
        )
        lastMark = now
    }

    /// Writes this launch's report, or nothing if it timed nothing.
    @discardableResult
    func commit() -> CadenceStartupCostReport? {
        guard let report = CadenceStartupCostReport(
            recordedAt: wallClock(),
            stages: stages,
            totalDuration: Self.seconds(from: started, to: nanoseconds()),
            footprintBytes: footprint()
        ) else { return nil }
        CadenceStartupCostLedger.store(report, defaults: defaults)
        return report
    }

    private static func seconds(from start: UInt64, to end: UInt64) -> TimeInterval {
        guard end > start else { return 0 }
        return TimeInterval(end - start) / 1_000_000_000
    }
}

/// Measuring through the **optional**, so an uninstrumented launch runs the body and nothing else.
///
/// `recorder?.measure { … }` would skip the body entirely when the recorder is `nil`, which is how
/// an instrument comes to change the behaviour it is supposed to observe. This is also why the
/// method is reached on a lowercase receiver rather than through a type: `CadenceFirstLaunchEmpty-
/// StoreTests` derives the set of passes a launch runs by reading `Type.member(` call shapes out of
/// `performStartupMaintenance`'s own body, and an instrument that added itself to that set would
/// make the derivation name it as a sixth startup pass.
extension Optional where Wrapped == CadenceStartupCostRecorder {
    func measure<Value>(
        _ stage: CadenceStartupStage,
        _ body: () -> Value,
        classifying verdict: (Value) -> CadenceStartupStageVerdict
    ) -> Value {
        guard let recorder = self else { return body() }
        let value = body()
        recorder.finished(stage, verdict(value))
        return value
    }

    func finished(_ stage: CadenceStartupStage, _ verdict: CadenceStartupStageVerdict) {
        self?.finished(stage, verdict)
    }

    @discardableResult
    func commit() -> CadenceStartupCostReport? {
        self?.commit()
    }
}
