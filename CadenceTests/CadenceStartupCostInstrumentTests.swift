import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1366, the startup half: every stage a launch runs is timed, and a pass that refused is no
/// longer filed as a pass with nothing to do.**
///
/// [[T-1329]] measured four of the maintenance passes against an in-memory fixture. What it could
/// not measure, and what nothing since has, is the rest of the launch: the backup/restore preflight
/// (file work, so its cost follows store *bytes*), the container open, and the one save at the end.
/// `PersistenceController` now carries an opt-in recorder that times all of them, and this suite
/// bounds what it produces.
///
/// **The second claim is the one with consequences.** Three of the five maintenance passes answer
/// `false`/`Void` for a clean run *and* for a run they could not complete —
/// `TagSupport.syncAllNoteTagsFromMarkdown` returns `false` for an unreadable `Note` table, an
/// unreadable `Tag` table, an empty store and a clean pass; `CadenceFocusLedger.reconcile` returns
/// `false` for a fetch it could not run and for a store with nothing to raise; and
/// `PursuitToGoalMigration.runIfNeeded` discards the `Bool` that `migrate` returns. Those three are
/// recorded as `indeterminate`, which is not the instrument being coy: it is the instrument
/// refusing to call an unknown a clean result. The two passes that *do* report a failure — note
/// migration and integrity repair, through their reports' `success` — are never `indeterminate`,
/// and that asymmetry is asserted in both directions so it cannot collapse quietly.
///
/// Nothing here touches the app-group store or the owner's container: the fixture is a disk-backed
/// store in a temporary directory and a `UserDefaults` suite of its own.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceStartupCostInstrumentTests {

    // MARK: - Opt-in, and the shape of silence

    /// With the instrument off there is no recorder, **and every pass still runs**.
    ///
    /// That second half is why `Optional.measure(_:_:classifying:)` exists rather than
    /// `recorder?.measure`: optional chaining would skip the body, so an instrument nobody enabled
    /// would silently delete five startup passes. The counter below is the proof, not the shape of
    /// the call site.
    @Test func anUninstrumentedLaunchHasNoRecorderAndStillRunsItsBody() throws {
        try withTemporaryDefaults("CadenceTests.startupCost") { defaults in
            #expect(CadenceStartupCostLedger.isEnabled(defaults: defaults) == false)
            let absent = CadenceStartupCostLedger.begin(defaults: defaults)
            #expect(absent == nil)

            var ran = 0
            let answer = absent.measure(.tagSync) { () -> Int in
                ran += 1
                return 7
            } classifying: { _ in .noChange }

            #expect(ran == 1, "the pass did not run without a recorder — the instrument changed the launch")
            #expect(answer == 7, "the pass's answer did not come back through the instrument")
            #expect(CadenceStartupCostLedger.lastReport(defaults: defaults).silence == .instrumentDisabled)

            // And with it on: a recorder exists, the body still runs exactly once, and the reader
            // comes back with something — so the silence above is an answer, not a dead reader.
            CadenceStartupCostLedger.setEnabled(true, defaults: defaults)
            #expect(CadenceStartupCostLedger.lastReport(defaults: defaults).silence == .nothingRecorded)
            let recorder = CadenceStartupCostLedger.begin(defaults: defaults)
            #expect(recorder != nil)
            ran = 0
            _ = recorder.measure(.tagSync) { () -> Int in
                ran += 1
                return 7
            } classifying: { _ in .noChange }
            #expect(ran == 1)
            recorder.commit()
            let report = try #require(
                CadenceStartupCostLedger.lastReport(defaults: defaults).report,
                "the ledger refused to read back the report it had just written"
            )
            #expect(report.measuredStages == [.tagSync])
        }
    }

    /// **A recorder that timed nothing writes nothing.** A report of zero stages and a total of
    /// zero seconds is the false clean sweep, so the report type refuses to be built.
    @Test func aRecorderThatTimedNothingRefusesToWriteAReport() throws {
        try withTemporaryDefaults("CadenceTests.startupCost") { defaults in
            CadenceStartupCostLedger.setEnabled(true, defaults: defaults)
            let recorder = try #require(CadenceStartupCostLedger.begin(defaults: defaults))

            #expect(recorder.commit() == nil, "a recorder with no stages wrote a report")
            #expect(CadenceStartupCostLedger.lastReport(defaults: defaults).silence == .nothingRecorded)

            // Non-vacuity: one stage is enough, so the refusal above is the emptiness.
            recorder.finished(.containerOpen, .completed)
            #expect(recorder.commit() != nil)
            #expect(CadenceStartupCostLedger.lastReport(defaults: defaults).report != nil)

            // And a stored payload whose stage list has gone comes back as a refusal, not as a
            // launch that cost nothing.
            defaults.set(
                ["recordedAt": Date().timeIntervalSince1970, "total": 1.5, "stages": [[String: Any]]()],
                forKey: CadenceStartupCostLedger.lastReportDefaultsKey
            )
            #expect(CadenceStartupCostLedger.lastReport(defaults: defaults).silence == .reportUnreadable)
        }
    }

    /// A refusal and a no-op land in different buckets and stay there.
    @Test func aRefusalIsNeverFiledAsAPassWithNothingToDo() throws {
        try withTemporaryDefaults("CadenceTests.startupCost") { defaults in
            CadenceStartupCostLedger.setEnabled(true, defaults: defaults)
            let recorder = try #require(CadenceStartupCostLedger.begin(defaults: defaults))

            // A real `ModelContainer` failure rather than a stub, so the reason is one the launch
            // could actually produce. The store is a file in a temporary directory that is not a
            // database; nothing here goes near the app group.
            let failure = try #require(try Self.realStoreOpenFailure(), "the fixture stopped failing")
            recorder.finished(.containerOpen, .refused(PersistenceController.instrumentReason(for: failure)))
            recorder.finished(.noteMigration, .noChange)
            recorder.finished(.tagSync, .indeterminate("falseIsCleanPassAndUnreadableTable"))
            recorder.finished(.integrityRepair, .changed(4))
            recorder.commit()

            let report = try #require(CadenceStartupCostLedger.lastReport(defaults: defaults).report)
            #expect(report.refusedStages == [.containerOpen])
            #expect(report.indeterminateStages == [.tagSync])
            #expect(report.stage(.noteMigration)?.outcome == .noChange)
            #expect(report.stage(.integrityRepair)?.outcome == .changed)
            #expect(report.stage(.integrityRepair)?.count == 4)
            let reason = try #require(report.stage(.containerOpen)?.note)
            #expect(!reason.isEmpty)
            #expect(report.stages.map(\.stage) == [.containerOpen, .noteMigration, .tagSync, .integrityRepair])
        }
    }

    /// The instrument's refusal reason cannot carry a file path or a note title even when the error
    /// it came from does. It is the error's Swift type, `NSError` domain and code, and nothing else.
    @Test func theStartupRefusalReasonCannotCarryUserText() {
        let leaky = NSError(
            domain: "CadenceFixtureDomain",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "/Users/someone/Library/Containers/Quarterly review.md is unreadable"]
        )
        let reason = PersistenceController.instrumentReason(for: leaky)

        #expect(reason.contains("CadenceFixtureDomain"))
        #expect(reason.contains("7"))
        #expect(!reason.contains("Quarterly"))
        #expect(!reason.contains("/Users/"))
        // Non-vacuity: the text is in the error this was reduced from.
        #expect(leaky.localizedDescription.contains("Quarterly"))
    }

    // MARK: - The measurement

    /// **A real launch's maintenance, measured on a disk-backed store.**
    ///
    /// This calls `PersistenceController.performStartupMaintenance` — the production body, not a
    /// replay of it ([[T-1108]]) — with a recorder, against a store with rows in it, and bounds
    /// what comes back. No duration threshold is asserted: a number of seconds is a fact about this
    /// machine, and pinning one is how [[T-1279]] and [[T-1296]] each turned an environment red.
    /// What is bounded is that **all five passes were timed**, that nothing claims to have cost
    /// less than nothing, that the parts never sum past the whole, and that the two passes with a
    /// `success` flag are never filed as indeterminate while the three without it always are.
    @Test func everyMaintenancePassIsTimedAndOnlyThePassesThatCannotTellSayIndeterminate() throws {
        let fixture = try DiskFixture()
        defer { fixture.tearDown() }

        try withTemporaryDefaults("CadenceTests.startupCost") { defaults in
            CadenceStartupCostLedger.setEnabled(true, defaults: defaults)
            let recorder = try #require(CadenceStartupCostLedger.begin(defaults: defaults))

            let openedAt = DispatchTime.now().uptimeNanoseconds
            let container = try fixture.openWritableContainer()
            recorder.finished(.containerOpen, .completed)
            let containerOpenSeconds = Double(DispatchTime.now().uptimeNanoseconds - openedAt) / 1_000_000_000

            PersistenceController.performStartupMaintenance(
                in: ModelContext(container),
                defaults: defaults,
                recorder: recorder
            )
            recorder.commit()

            let report = try #require(
                CadenceStartupCostLedger.lastReport(defaults: defaults).report,
                "a launch that ran five passes left no report"
            )

            let maintenance: [CadenceStartupStage] = [
                .pursuitMigration, .noteMigration, .tagSync, .integrityRepair, .focusReconciliation,
            ]
            #expect(
                Array(report.stages.map(\.stage).prefix(6)) == [.containerOpen] + maintenance,
                "the launch timed \(report.stages.map(\.stage.rawValue)), which is not the order it runs them in"
            )
            #expect(report.measuredStages.isSuperset(of: Set(maintenance)))

            // The asymmetry, both directions. `runIfNeeded` returns `Void` so the Pursuit pass can
            // never be anything else; the two passes carrying a `success` flag can never be this.
            #expect(report.stage(.pursuitMigration)?.outcome == .indeterminate)
            #expect(Set(report.indeterminateStages).isSubset(of: [.pursuitMigration, .tagSync, .focusReconciliation]))
            let noteMigration = try #require(report.stage(.noteMigration), "the note migration was not timed")
            let integrityRepair = try #require(report.stage(.integrityRepair), "the integrity repair was not timed")
            #expect(noteMigration.outcome != .indeterminate)
            #expect(integrityRepair.outcome != .indeterminate)

            for stage in report.stages {
                #expect(stage.duration.isFinite && stage.duration >= 0, "\(stage.stage.rawValue)")
                #expect(stage.note?.isEmpty != true, "\(stage.stage.rawValue) recorded an empty note")
            }
            let accounted = report.stages.reduce(0) { $0 + $1.duration }
            #expect(
                accounted <= report.totalDuration + 0.000_001,
                "the stages account for \(accounted)s of a \(report.totalDuration)s launch"
            )
            #expect(report.footprintBytes.map { $0 > 0 } ?? true, "a footprint of zero is not a reading")

            // Non-vacuity for the whole measurement: the fixture really holds rows, so five passes
            // that each did nothing would be the store's doing and not an empty one.
            let context = ModelContext(container)
            let taskRows = try context.fetch(FetchDescriptor<AppTask>()).count
            let noteRows = try context.fetch(FetchDescriptor<Note>()).count
            #expect(taskRows == DiskFixture.taskCount, "the fixture's tasks read as \(taskRows)")
            #expect(noteRows == DiskFixture.noteCount, "the fixture's notes read as \(noteRows)")

            print("""
                T-1366 startup measurement (disk-backed fixture, \
                \(DiskFixture.taskCount) AppTask + \(DiskFixture.noteCount) Note rows)
                  containerOpen(outside the recorder, sanity)=\(containerOpenSeconds)s
                  total=\(report.totalDuration)s footprint=\(report.footprintBytes as Int?)
                \(report.stages.map { "  \($0.stage.rawValue)=\($0.duration)s \($0.outcome.rawValue)\($0.note.map { " (\($0))" } ?? "")" }.joined(separator: "\n"))
                """)
        }
    }

    /// Every stage the launch path can reach is a case of `CadenceStartupStage`, and every case is
    /// one the launch path can reach — so a stage added to the enum and never recorded, or a stage
    /// recorded under a name the enum has lost, fails here rather than going unnoticed.
    @Test func theStageVocabularyIsTheOneTheLaunchActuallyRecords() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        #expect(source.count > 10_000, "the source read is too small to be PersistenceController")

        let recorded = Set(
            CadenceStartupStage.allCases.filter { source.contains(".\($0.rawValue)," ) || source.contains(".\($0.rawValue))") }
        )
        let unrecorded = Set(CadenceStartupStage.allCases).subtracting(recorded).map(\.rawValue).sorted()
        #expect(
            recorded == Set(CadenceStartupStage.allCases),
            "these stages exist in the vocabulary and are never recorded by a launch: \(unrecorded)"
        )
        #expect(CadenceStartupStage.allCases.count == 8)
    }

    // MARK: - Fixtures

    private static func realStoreOpenFailure() throws -> Error? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cadence-startup-cost-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("corrupt.store")
        try Data("this is not a database".utf8).write(to: storeURL)
        do {
            _ = try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(
                    "CadenceStartupCostFixture",
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

    /// A disk-backed store with enough in it that five inert passes are a claim about the passes.
    private struct DiskFixture {
        static let taskCount = 240
        static let noteCount = 60

        let directory: URL
        let storeURL: URL

        init() throws {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cadence-startup-cost-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            storeURL = directory.appendingPathComponent("fixture.store")

            let context = ModelContext(try openWritableContainer())
            let todayKey = DateFormatters.dateKey(from: Date(), calendar: .current)
            for index in 0..<Self.taskCount {
                let task = AppTask(title: "Task \(index)")
                if index.isMultiple(of: 2) { task.dueDate = todayKey }
                context.insert(task)
            }
            // `.list` and not `.permanent`: `Note.canonicalKey` answers the bare string
            // `"permanent"` for every permanent note by design — there is one of them — so a
            // fixture of sixty would be merged into one by the integrity repair this suite is
            // timing, and the population the tag sweep walks would not be the one it was seeded
            // with. Measured: sixty permanent notes in, one out.
            for index in 0..<Self.noteCount {
                context.insert(
                    Note(
                        kind: .list,
                        title: "Note \(index)",
                        content: "#tag\(index % 7) body for note \(index)"
                    )
                )
            }
            try context.save()
        }

        func openWritableContainer() throws -> ModelContainer {
            try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(
                    "CadenceStartupCostFixture",
                    schema: CadenceSchema.schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            )
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
