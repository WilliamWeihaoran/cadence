import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-19's backup half. `PrivacyDataResetService` answers "delete my data"; nothing answered "give
/// me a copy I can keep". `StoreBackupManager` snapshots the store, but every copy lives inside the
/// app's own container, is an opaque SwiftData file, and is deleted by the reset — so it protects
/// against a bad launch and against nothing else.
///
/// The whole point of an archive is that it is **complete**, and completeness is exactly the
/// property that rots silently: a model added to `CadenceSchema` and not to the exporter produces a
/// backup that looks fine, restores nothing, and says so only years later. So the coverage check is
/// driven off the schema in the same two steps as `CadencePrivacyDataResetSurfaceTests`:
///
/// 1. `CadenceArchive.recordCountsByEntityName` must cover the schema *exactly*.
/// 1b. `probesByEntityName` must cover the schema *exactly* too — added by T-268, because without
///     it step 2 is a hand-written list and a model with a permanently empty table passes.
/// 2. Every entity's table must hold the row that was seeded for it.
///
/// **Why some of this reads source text.** `Cadence/iOS/` is inside `#if os(iOS)` and this target
/// builds for macOS, so an iOS call site has no symbol a test can reference. Same tool, same
/// caveats, and the same non-vacuity guard at the end as `CadencePrivacyDataResetSurfaceTests`.
@MainActor
struct CadenceDataExportSurfaceTests {

    // MARK: - The archive covers the whole schema

    /// Step 1: the archive's table list and the schema are the same set of entities.
    ///
    /// Both directions on purpose. A missing table means the export silently drops a live model;
    /// a stale one means the archive claims a type the app no longer persists.
    @Test func everySchemaEntityHasAnArchiveTable() {
        let schemaNames = Set(CadenceSchema.schema.entities.map(\.name))
        let tableNames = Set(CadenceArchive.recordCountsByEntityName.keys)

        #expect(
            tableNames == schemaNames,
            """
            archive tables and CadenceSchema disagree — \
            missing tables: \(schemaNames.subtracting(tableNames).sorted()), \
            stale tables: \(tableNames.subtracting(schemaNames).sorted())
            """
        )
        // Not an empty-set-equals-empty-set pass.
        #expect(schemaNames.count >= 20, "CadenceSchema reports only \(schemaNames.count) entities")
    }

    /// **Step 1b, and the half that was missing.** The probe table below must cover the schema
    /// exactly, or step 2 is only as complete as a hand-written list.
    ///
    /// **T-268.** Step 1 above is genuinely schema-driven; step 2 iterates `probesByEntityName`
    /// and nothing compared *that* to the schema. So a future `@Model` added to `CadenceSchema` and
    /// wired into `makeArchive` as a permanently empty table — `foos: []` plus its keypath — passed
    /// step 1 (the table exists), was never seeded (no probe), and was never counted (step 2 only
    /// looks at `probes.keys`). The whole suite stayed green over an archive that silently drops a
    /// live model, which is the one property an archive exists to have.
    ///
    /// `CadencePrivacyDataResetSurfaceTests.everySchemaEntityHasAProbe` has enforced exactly this
    /// on the wipe half since it was written; the copy half went without it. Stated in both
    /// directions for the same reasons: a missing probe means the export is unverified for a live
    /// model, a stale one means this file tests a type the app no longer persists.
    @Test func everySchemaEntityHasAnExportProbe() {
        let schemaNames = Set(CadenceSchema.schema.entities.map(\.name))
        let probeNames = Set(Self.probesByEntityName.keys)

        #expect(
            probeNames == schemaNames,
            """
            export probe table and CadenceSchema disagree — \
            missing probes: \(schemaNames.subtracting(probeNames).sorted()), \
            stale probes: \(probeNames.subtracting(schemaNames).sorted())
            """
        )
        // Not an empty-set-equals-empty-set pass.
        #expect(schemaNames.count >= 20, "CadenceSchema reports only \(schemaNames.count) entities")
    }

    /// **Step 2, and the test a dropped model has to fail.** One row of every schema entity goes
    /// into a store; the archive must come back holding one of each.
    ///
    /// Blanking any single table in `makeArchive` — `habits: []` for instance — leaves the type
    /// system happy, the app running, and this the only thing that notices.
    @Test func theArchiveHoldsOneRecordForEveryTypeInTheSchema() throws {
        let context = ModelContext(try makeContainer())
        let probes = Self.probesByEntityName
        for probe in probes.values {
            probe.seed(context)
        }
        try context.save()

        // Positive control: the seed landed. A store that never got rows would satisfy an
        // "every table is complete" claim vacuously if the assertion were phrased the other way.
        for probe in probes.values {
            #expect(try probe.count(context) == 1, "\(probe.name) was never seeded")
        }

        let archive = try CadenceDataExportService.makeArchive(in: context)

        for name in probes.keys.sorted() {
            let exported = archive.recordCount(forEntityNamed: name)
            #expect(
                exported == 1,
                "the archive holds \(exported.map { "\($0)" } ?? "no table") for \(name) — add it to CadenceDataExportService.makeArchive"
            )
        }
        #expect(archive.totalRecordCount == probes.count)
    }

    /// The legacy note models are migration sources with no UI, which is exactly why they are easy
    /// to leave out — and exactly when they matter: a backup taken before `NoteMigrationService`
    /// has run on a device is the only copy of those rows.
    @Test func theLegacyMigrationSourceModelsAreInTheArchive() {
        for name in ["DailyNote", "WeeklyNote", "PermNote", "EventNote", "Document", "Pursuit"] {
            #expect(
                CadenceArchive.recordCountsByEntityName[name] != nil,
                "\(name) has no archive table"
            )
        }
    }

    // MARK: - The archive is faithful

    /// Relationships travel as ids, so a graph has to come back joinable. Every foreign key on the
    /// busiest record is checked, plus the many-to-many that has no owning side.
    @Test func relationshipsAreExportedAsResolvableIDs() throws {
        let context = ModelContext(try makeContainer())

        let lifeContext = Context(name: "Work")
        let area = Area(name: "Home", context: lifeContext)
        let project = Project(name: "Kitchen", context: lifeContext, area: area)
        let goal = Goal(title: "Ship v1", context: lifeContext)
        let bundle = TaskBundle(title: "Morning", dateKey: "2026-08-20", startMin: 540, durationMinutes: 60)
        let tag = Tag(name: "errand")
        let task = AppTask(title: "Buy milk")
        task.area = area
        task.project = project
        task.goal = goal
        task.context = lifeContext
        task.bundle = bundle
        task.tags = [tag]
        let subtask = Subtask(title: "Find the receipt")
        subtask.parentTask = task

        context.insert(lifeContext)
        context.insert(area)
        context.insert(project)
        context.insert(goal)
        context.insert(bundle)
        context.insert(tag)
        context.insert(task)
        context.insert(subtask)
        try context.save()

        let archive = try CadenceDataExportService.makeArchive(in: context)
        let exportedTask = try #require(archive.tasks.first)

        #expect(exportedTask.areaID == area.id)
        #expect(exportedTask.projectID == project.id)
        #expect(exportedTask.goalID == goal.id)
        #expect(exportedTask.contextID == lifeContext.id)
        #expect(exportedTask.bundleID == bundle.id)
        #expect(exportedTask.tagIDs == [tag.id])

        let exportedArea = try #require(archive.areas.first)
        let exportedProject = try #require(archive.projects.first)
        let exportedSubtask = try #require(archive.subtasks.first)
        #expect(exportedArea.contextID == lifeContext.id)
        #expect(exportedProject.areaID == area.id)
        #expect(exportedSubtask.parentTaskID == task.id)
    }

    /// The two stored properties with no readers in feature code. `docs/CLAUDE_REFERENCE.md`
    /// records that both must survive because there is no `SchemaMigrationPlan` and removing them
    /// drops data; an export that skips them is the same loss by another route, so this exporter is
    /// deliberately their reader.
    @Test func theTwoLiveFieldsWithNoOtherReadersAreExported() throws {
        let context = ModelContext(try makeContainer())

        let goal = Goal(title: "Ship v1")
        goal.dependsOnGoalIDsJSON = "[\"11111111-1111-1111-1111-111111111111\"]"
        let task = AppTask(title: "Buy milk")
        task.calendarEventID = "legacy-event-identifier"
        context.insert(goal)
        context.insert(task)
        try context.save()

        let archive = try CadenceDataExportService.makeArchive(in: context)
        let exportedGoal = try #require(archive.goals.first)
        let exportedTask = try #require(archive.tasks.first)
        #expect(exportedGoal.dependsOnGoalIDsJSON == goal.dependsOnGoalIDsJSON)
        #expect(exportedTask.calendarEventID == "legacy-event-identifier")
    }

    /// A list's archived kanban columns are invisible to `sectionNames`' getter. The archive stores
    /// the raw JSON for that reason — reading through the filtered property would make the backup a
    /// silent delete, which is the bug `Area.sectionNames`' own doc comment records.
    @Test func archivedKanbanColumnsSurviveTheExport() throws {
        let context = ModelContext(try makeContainer())
        let area = Area(name: "Home")
        area.sectionConfigs = [
            TaskSectionConfig(name: "Default"),
            TaskSectionConfig(name: "Retired", isArchived: true),
        ]
        context.insert(area)
        try context.save()

        let archive = try CadenceDataExportService.makeArchive(in: context)
        let exported = try #require(archive.areas.first)
        #expect(exported.sectionConfigsRaw.contains("Retired"))
        #expect(!area.sectionNames.contains("Retired"), "the getter stopped filtering; this test no longer proves anything")
    }

    /// Image bytes, not just image metadata. Base64 makes the file larger; a backup of every note
    /// except its pictures is not a backup.
    @Test func markdownImageBytesAreInTheArchive() throws {
        let context = ModelContext(try makeContainer())
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        context.insert(
            MarkdownImageAsset(
                data: pngHeader,
                mimeType: "image/png",
                pixelWidth: 2,
                pixelHeight: 2,
                displayWidth: 2
            )
        )
        try context.save()

        let archive = try CadenceDataExportService.makeArchive(in: context)
        let exported = try #require(archive.markdownImageAssets.first)
        #expect(exported.data == pngHeader)

        // And through JSON, where `Data` becomes base64 — the step that would drop it.
        let decoded = try CadenceDataExportService.decode(try CadenceDataExportService.encode(archive))
        let decodedAsset = try #require(decoded.markdownImageAssets.first)
        #expect(decodedAsset.data == pngHeader)
    }

    // MARK: - The document

    /// The archive decodes to the value it was encoded from. This is what an import path would
    /// stand on, and it is *all* that is proven today: nothing writes a decoded archive back into a
    /// store, and this test must not be read as evidence that anything does.
    @Test func theArchiveRoundTripsThroughJSON() throws {
        let context = ModelContext(try makeContainer())
        for probe in Self.probesByEntityName.values {
            probe.seed(context)
        }
        try context.save()

        let archive = try CadenceDataExportService.makeArchive(in: context)
        let data = try CadenceDataExportService.encode(archive)
        let decoded = try CadenceDataExportService.decode(data)

        #expect(decoded == archive)
        #expect(decoded.formatVersion == CadenceDataExportService.formatVersion)
        #expect(decoded.schemaEntityNames == CadenceSchema.schema.entities.map(\.name).sorted())
    }

    /// **The bug the round trip found.** `JSONEncoder`'s stock `.iso8601` writes whole seconds, so
    /// every timestamp in the archive was truncated by up to a second and the value in memory was
    /// not the instant the file spelled. This pins the replacement: the archive's unit is the
    /// millisecond, `normalized(_:)` is idempotent, and normalizing then encoding then decoding is
    /// the identity — across the range a real store can hold, not just around today.
    ///
    /// It matters beyond tidiness: `TaskOrdering.fallbackPrecedes` breaks ties on `createdAt`, and
    /// rows written together share a second routinely, so second-precision timestamps turn a total
    /// order into ties.
    @Test func theArchiveStatesItsTimestampPrecision() throws {
        var dates: [Date] = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_770_000_000),
            Date(timeIntervalSince1970: 1_770_000_000.9999),
            Date(timeIntervalSinceReferenceDate: -3_000_000_000),  // 1905
            Date(timeIntervalSince1970: 4_102_444_800),            // 2100
        ]
        // A spread of sub-second offsets, because the failure mode is a fraction being dropped.
        for step in 0..<500 {
            dates.append(Date(timeIntervalSince1970: 1_770_000_000 + Double(step) * 0.0001371))
        }

        for date in dates {
            let normalized = CadenceArchiveTimestamp.normalized(date)
            #expect(
                abs(normalized.timeIntervalSince(date)) <= 0.001,
                "normalizing \(date) moved it by more than a millisecond"
            )
            #expect(
                CadenceArchiveTimestamp.normalized(normalized) == normalized,
                "normalizing is not idempotent at \(date)"
            )

            // The property the round trip stands on: the text the document holds parses back to
            // exactly the value that wrote it.
            let text = CadenceArchiveTimestamp.formatter.string(from: normalized)
            #expect(
                CadenceArchiveTimestamp.formatter.date(from: text) == normalized,
                "\(text) did not parse back to the instant that produced it"
            )
        }

        #expect(CadenceArchiveTimestamp.normalized(Date?.none) == nil)

        // And through the encoder the export actually uses, so this cannot pass while the
        // strategies are still wired to a different formatter.
        let context = ModelContext(try makeContainer())
        let task = AppTask(title: "Buy milk")
        task.createdAt = Date(timeIntervalSince1970: 1_770_000_000.123456)
        task.completedAt = Date(timeIntervalSince1970: 1_770_000_000.999888)
        context.insert(task)
        try context.save()

        let archive = try CadenceDataExportService.makeArchive(in: context)
        let data = try CadenceDataExportService.encode(archive)
        let roundTripped = try CadenceDataExportService.decode(data)
        let exported = try #require(archive.tasks.first)
        let decoded = try #require(roundTripped.tasks.first)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(decoded.createdAt == exported.createdAt)
        #expect(decoded.completedAt == exported.completedAt)
        #expect(
            text.contains("2026-02-02T02:40:00.123Z"),
            "the archive is no longer writing fractional seconds"
        )
    }

    /// Every timestamp the archive carries has to go through `normalized(_:)` — a `Date` field
    /// added later and assigned straight from the model encodes at the archive's precision and
    /// decodes to a *different* value than the one in hand, which is the whole of the bug above.
    ///
    /// Reflection rather than a list of fields, because a list is the thing that goes stale. The
    /// failure names the field.
    @Test func everyTimestampInTheArchiveIsAtTheArchivesPrecision() throws {
        let context = ModelContext(try makeContainer())
        for probe in Self.probesByEntityName.values {
            probe.seed(context)
        }
        try context.save()

        let archive = try CadenceDataExportService.makeArchive(in: context)
        let timestamps = archiveTimestamps(archive)

        // Non-vacuity: every seeded row carries at least one, plus the archive's own `exportedAt`.
        #expect(
            timestamps.count > Self.probesByEntityName.count,
            "the reflection walk found only \(timestamps.count) timestamps and cannot be doing its job"
        )
        for (path, date) in timestamps {
            #expect(
                CadenceArchiveTimestamp.normalized(date) == date,
                "\(path) is not normalized — assign it through CadenceArchiveTimestamp.normalized"
            )
        }
    }

    /// "Durable and inspectable" is a property of the bytes, not an intention. Pretty-printed with
    /// sorted keys so two exports diff cleanly, and dates as ISO-8601 rather than the reference
    /// interval doubles `JSONEncoder` uses by default.
    @Test func theArchiveIsInspectableText() throws {
        let context = ModelContext(try makeContainer())
        let task = AppTask(title: "Buy milk")
        task.createdAt = Date(timeIntervalSince1970: 1_770_000_000)
        context.insert(task)
        try context.save()

        let data = try CadenceDataExportService.encode(
            try CadenceDataExportService.makeArchive(in: context)
        )
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\n"), "the archive is not pretty-printed")
        #expect(text.contains("\"title\" : \"Buy milk\""))
        #expect(text.contains("2026-02-02T"), "dates are not ISO-8601")
        // Sorted keys: `appVersion` precedes `areas` precedes `contexts` at the top level.
        let appVersionIndex = try #require(text.range(of: "\"appVersion\""))
        let areasIndex = try #require(text.range(of: "\"areas\""))
        #expect(appVersionIndex.lowerBound < areasIndex.lowerBound, "keys are not sorted")
    }

    /// Two exports of an unchanged store must be the same bytes, or "keep last week's archive and
    /// diff it" is not a thing a user can do.
    @Test func theArchiveIsDeterministic() throws {
        let context = ModelContext(try makeContainer())
        for probe in Self.probesByEntityName.values {
            probe.seed(context)
        }
        try context.save()

        let pinnedDate = Date(timeIntervalSince1970: 1_770_000_000)
        let first = try CadenceDataExportService.exportArchive(in: context, exportedAt: pinnedDate, appVersion: "1.0 (1)")
        let second = try CadenceDataExportService.exportArchive(in: context, exportedAt: pinnedDate, appVersion: "1.0 (1)")

        #expect(first.data == second.data)
        #expect(first.recordCount == Self.probesByEntityName.count)
        #expect(first.recordCount > 0)
    }

    /// Dated so two archives are distinguishable in a folder, and *not* timestamped: the day is
    /// the unit a person keeps backups in.
    ///
    /// The day is asserted against the local calendar rather than a literal, because
    /// `DateFormatters.ymd` pins a locale and not a time zone — a literal here would be a test that
    /// passes in one time zone and fails five hours away.
    @Test func theSuggestedFilenameIsDatedAndCarriesNoExtension() throws {
        let date = Date(timeIntervalSince1970: 1_770_000_000)
        let filename = CadenceDataExportService.suggestedFilename(for: date)

        #expect(filename.hasPrefix("Cadence Archive "))
        let key = String(filename.dropFirst("Cadence Archive ".count))
        let parsed = try #require(DateFormatters.date(from: key), "\(key) is not a yyyy-MM-dd key")
        #expect(Calendar.current.isDate(parsed, inSameDayAs: date))
        // `.fileExporter` appends the content type's extension; a literal one here would double it.
        #expect(!filename.hasSuffix(".json"))
    }

    // MARK: - The wording both platforms show

    @Test func theOutcomeSentenceIsSharedAndCountsCorrectlyInDataExportSurface() {
        #expect(
            CadenceDataExportPresentation.successMessage(recordCount: 1, filename: "a.json")
                == "Exported 1 record to a.json."
        )
        #expect(
            CadenceDataExportPresentation.successMessage(recordCount: 42, filename: "a.json")
                == "Exported 42 records to a.json."
        )
        #expect(
            CadenceDataExportPresentation.failureMessage("disk full") == "Export failed: disk full"
        )
    }

    /// The one sentence a user needs before treating the archive as a safety net. It is in the
    /// shared copy so a view cannot quietly drop it while keeping the rest.
    @Test func theCopyAdmitsThereIsNoImportYet() {
        #expect(CadenceDataExportPresentation.description.contains("cannot read an archive back in yet"))
        #expect(CadenceDataExportPresentation.description.contains("outside Cadence"))
        #expect(CadenceDataExportPresentation.localBackupLocationNote.contains("inside Cadence's own container"))
    }

    // MARK: - Both platforms reach it, once each

    /// The T-161 test for this ticket. Delete either call site and this fails; nothing else would,
    /// because the service is a static function with no view attached and iOS's section is
    /// invisible to a macOS-built test target.
    @Test func bothPlatformsReachTheExportFromDataSafety() throws {
        try expectExportCallSites(
            of: "CadenceDataExportService.exportArchive",
            at: [
                "Cadence/iOS/iOSDataExportSettingsSection.swift": 1,
                "Cadence/macOS/Views/SettingsDataSafetySection.swift": 1,
            ]
        )
        try expectExportCallSites(
            of: "iOSDataExportSettingsSection",
            at: ["Cadence/iOS/iOSSettingsView.swift": 1]
        )
    }

    /// Data Safety is where the reset already lives and where both shipped documents point, so the
    /// export belongs in the same category rather than on a screen of its own.
    @Test func theIOSExportIsInTheDataSafetyCategory() throws {
        let source = try strippingExportComments(exportSourceFile("Cadence/iOS/iOSSettingsView.swift"))
        let range = try #require(source.range(of: "case .data:"))
        let tail = source[range.upperBound...]
        let nextCase = tail.range(of: "\n        case ")?.lowerBound ?? tail.endIndex

        #expect(
            tail[..<nextCase].contains("dataSafetySection"),
            "Settings > Data Safety no longer routes to the section holding the export"
        )
        #expect(source.contains("iOSDataExportSettingsSection()"))
    }

    /// One exporter, not two. A second `JSONEncoder` in a view is how the two platforms' archives
    /// come to disagree about date encoding while both look correct in isolation.
    @Test func neitherPlatformReSpellsTheExport() throws {
        let mentions = try exportFilesMentioning("CadenceDataExportService")
        #expect(
            mentions == [
                "Cadence/Services/CadenceDataExportService.swift",
                "Cadence/Shared/CadenceDataExportPresentation.swift",
                // T-813/T-817: the terminal recovery screen is a *third* export caller, deliberately
                // outside the loop below — it is not a Settings surface and does not show
                // `CadenceDataExportPresentation`'s copy, because "export an archive" is not what a
                // user needs to hear when every store this launch tried has already failed.
                "Cadence/Shared/Components/CadenceTerminalRecoveryView.swift",
                "Cadence/iOS/iOSDataExportSettingsSection.swift",
                "Cadence/macOS/Views/SettingsDataSafetySection.swift",
            ],
            "the exporter is reached from \(mentions.sorted())"
        )

        for path in [
            "Cadence/iOS/iOSDataExportSettingsSection.swift",
            "Cadence/macOS/Views/SettingsDataSafetySection.swift",
        ] {
            let source = try strippingExportComments(exportSourceFile(path))
            #expect(!source.contains("JSONEncoder"), "\(path) encodes the archive itself again")
            #expect(!source.contains("makeArchive"), "\(path) builds the archive itself again")
            // The copy comes from the shared enum, not from a literal beside it.
            #expect(source.contains("CadenceDataExportPresentation.description"), "\(path) re-spells the description")
            #expect(source.contains("CadenceDataExportPresentation.title"), "\(path) re-spells the title")
        }
    }

    /// The service must stay reachable from both platforms — the mistake this repo has made four
    /// times is a cross-platform capability written inside `#if os(macOS)` because that is where
    /// the author happened to be.
    @Test func theExportServiceIsNotPlatformGated() throws {
        let live = try strippingExportComments(
            exportSourceFile("Cadence/Services/CadenceDataExportService.swift")
        )
        #expect(!live.contains("#if os("), "the export service is platform-gated")
        #expect(!live.contains("import AppKit"))
        #expect(!live.contains("import UIKit"))
        #expect(live.contains("enum CadenceDataExportService"))
    }

    // MARK: - The scan itself

    /// The absence assertions above are worth nothing if the scan reads no files.
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInDataExportSurface() throws {
        let files = try exportSwiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Services/CadenceDataExportService.swift"))
        #expect(files.contains("Cadence/Shared/CadenceDataExportPresentation.swift"))
        #expect(files.contains("Cadence/iOS/iOSDataExportSettingsSection.swift"))
        #expect(files.contains("Cadence/macOS/Views/SettingsDataSafetySection.swift"))

        #expect(try strippingExportComments(exportSourceFile("Cadence/Services/CadenceDataExportService.swift"))
            .contains("func exportArchive"))
        #expect(try !exportFilesMentioning("CadenceDataExportService").isEmpty)
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    /// One live row per schema entity, keyed by the entity name `CadenceSchema` reports.
    /// Same construction as `CadencePrivacyDataResetSurfaceTests`', and deliberately so: the two
    /// halves of data safety — the wipe and the copy — should fail the same way when a model is
    /// added and only one of them is updated.
    private static var probesByEntityName: [String: ExportProbe] {
        let probes: [ExportProbe] = [
            exportProbe { Context(name: "Work") },
            exportProbe { Area(name: "Home") },
            exportProbe { Project(name: "Kitchen") },
            exportProbe { Pursuit(title: "Stay healthy") },
            exportProbe { Tag(name: "errand") },
            exportProbe { AppTask(title: "Buy milk") },
            exportProbe { TaskBundle(title: "Morning", dateKey: "2026-08-20", startMin: 540, durationMinutes: 60) },
            exportProbe { FocusSessionLog(minutes: 25, previousMinutes: 0, loggedAt: Date(), dayKey: "2026-08-20") },
            exportProbe { Subtask(title: "Find the receipt") },
            exportProbe { DailyNote(date: "2026-08-20") },
            exportProbe { WeeklyNote(weekKey: "2026-W34") },
            exportProbe { PermNote() },
            exportProbe { Document(title: "Spec") },
            exportProbe { Note(kind: .permanent, title: "Ideas") },
            exportProbe { SavedLink(title: "Docs", url: "https://example.com") },
            exportProbe { EventNote(calendarEventID: "evt-1", eventTitle: "Standup") },
            exportProbe {
                MarkdownImageAsset(
                    data: Data([0x89, 0x50, 0x4E, 0x47]),
                    mimeType: "image/png",
                    pixelWidth: 2,
                    pixelHeight: 2,
                    displayWidth: 2
                )
            },
            exportProbe { Goal(title: "Ship v1") },
            exportProbe { GoalListLink() },
            exportProbe { Habit(title: "Stretch") },
            exportProbe { HabitCompletion(date: "2026-08-20") },
        ]
        return Dictionary(uniqueKeysWithValues: probes.map { ($0.name, $0) })
    }
}

// MARK: - Schema-driven probes

private struct ExportProbe {
    let name: String
    let seed: @MainActor (ModelContext) -> Void
    let count: @MainActor (ModelContext) throws -> Int
}

@MainActor
private func exportProbe<T: PersistentModel>(_ make: @escaping @MainActor () -> T) -> ExportProbe {
    ExportProbe(
        name: String(describing: T.self),
        seed: { $0.insert(make()) },
        count: { try $0.fetchCount(FetchDescriptor<T>()) }
    )
}

// MARK: - Source-reading helpers
//
// Prefixed rather than shared with `CadencePrivacyDataResetSurfaceTests`: `CadenceTests` is a flat
// target with no module boundaries between files, so two files declaring `sourceFile(_:)` is a
// redeclaration error. The bodies are the same on purpose — including the `enumerator(atPath:)`
// choice, which exists because `#filePath` can name the repo through a symlinked prefix
// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves.

/// Every `Date` the archive carries, with a readable path to it, found by reflection so the walk
/// cannot go stale when a record gains a field.
///
/// `Data` and `UUID` are short-circuited: both reflect as collections of bytes, and descending into
/// an image asset's pixels would make this walk quadratic in the size of the store for no gain.
private func archiveTimestamps(_ archive: CadenceArchive) -> [(path: String, date: Date)] {
    var found: [(String, Date)] = []
    collectArchiveTimestamps(archive, path: "CadenceArchive", into: &found)
    return found.map { (path: $0.0, date: $0.1) }
}

private func collectArchiveTimestamps(_ value: Any, path: String, into found: inout [(String, Date)]) {
    if let date = value as? Date {
        found.append((path, date))
        return
    }
    if value is Data || value is UUID || value is String {
        return
    }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        if let wrapped = mirror.children.first?.value {
            collectArchiveTimestamps(wrapped, path: path, into: &found)
        }
        return
    }
    for (index, child) in mirror.children.enumerated() {
        let step = child.label.map { ".\($0)" } ?? "[\(index)]"
        collectArchiveTimestamps(child.value, path: path + step, into: &found)
    }
}

private func expectExportCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingExportComments(exportSourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func exportFilesMentioning(_ name: String) throws -> [String] {
    let pattern = "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_])"
    return try exportSwiftFiles(under: "Cadence")
        .filter {
            try strippingExportComments(exportSourceFile($0))
                .range(of: pattern, options: .regularExpression) != nil
        }
        .sorted()
}

private func exportRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func exportSwiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = exportRepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func exportSourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: exportRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func strippingExportComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}

/// **T-661.** The archive carries one field whose meaning does not travel with the file, and the
/// decision is that it stays and is *documented* rather than dropped.
///
/// `CadenceArchiveArea.linkedCalendarID` / `CadenceArchiveProject.linkedCalendarID` hold an
/// `EKCalendar.calendarIdentifier`, which Apple documents as local to one device. Restored onto a
/// different machine the field names a calendar that machine never issued, so calendar links do not
/// survive a cross-device restore. Dropping the field was the other option and was rejected: on the
/// origin machine the identifier is exact and this document is its only copy outside a store the
/// user can delete, so removing it would make the archive incomplete in the one direction a restore
/// works, to delete a value that is merely inert in the other — inert because [[T-624]]'s evidence
/// gate makes a foreign identifier read as unverified on the reading device rather than as a broken
/// link with a repair beside it.
///
/// These pin both halves. The value assertions make dropping the field a **red test** rather than a
/// silent narrowing of the backup, and the source scan makes deleting the sentence one too — the
/// sentence is the whole of what this ticket bought, so an undocumented field would be the ticket
/// quietly un-done.
@MainActor
struct CadenceArchiveCalendarLinkScopeTests {

    // MARK: - The field is still exported

    @Test func anAreasCalendarLinkReachesTheArchiveVerbatim() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Home")
        area.linkedCalendarID = "cal-issued-by-this-mac"
        context.insert(area)
        try context.save()

        let exported = try #require(CadenceDataExportService.makeArchive(in: context).areas.first)
        #expect(exported.linkedCalendarID == "cal-issued-by-this-mac",
                "the archive dropped an area's calendar link; T-661 decided to keep and document it")
    }

    @Test func aProjectsCalendarLinkReachesTheArchiveVerbatim() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let project = Project(name: "Kitchen")
        project.linkedCalendarID = "cal-issued-by-this-mac"
        context.insert(project)
        try context.save()

        let exported = try #require(CadenceDataExportService.makeArchive(in: context).projects.first)
        #expect(exported.linkedCalendarID == "cal-issued-by-this-mac",
                "the archive dropped a project's calendar link; T-661 decided to keep and document it")
    }

    /// And it survives the encoder, which is the form the user actually keeps. A field copied into
    /// the record and lost on the way to JSON is the same missing backup with a passing unit test.
    @Test func theCalendarLinkSurvivesTheJSONTheUserKeeps() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Home")
        area.linkedCalendarID = "cal-issued-by-this-mac"
        let project = Project(name: "Kitchen")
        project.linkedCalendarID = "cal-also-from-here"
        context.insert(area)
        context.insert(project)
        try context.save()

        let data = try CadenceDataExportService.encode(
            CadenceDataExportService.makeArchive(in: context)
        )
        let decoded = try CadenceDataExportService.decode(data)

        let decodedArea = try #require(decoded.areas.first)
        let decodedProject = try #require(decoded.projects.first)
        #expect(decodedArea.linkedCalendarID == "cal-issued-by-this-mac")
        #expect(decodedProject.linkedCalendarID == "cal-also-from-here")
    }

    /// An unlinked list exports the empty string rather than anything else, so a reader cannot tell
    /// "never linked" apart from "linked" by accident — the same distinction
    /// `CadenceCalendarLinkRowState.unlinked` draws in the app.
    @Test func anUnlinkedListExportsTheEmptyIdentifier() throws {
        let context = ModelContext(try CadenceTestStore.container())
        context.insert(Area(name: "Home"))
        try context.save()

        let exported = try #require(CadenceDataExportService.makeArchive(in: context).areas.first)
        #expect(exported.linkedCalendarID.isEmpty)
    }

    // MARK: - The sentence that is the fix

    /// A **source scan over the raw file**, comments included, because the deliverable here *is* a
    /// comment: T-661's own words are that the cheap half is a sentence rather than code. Nothing
    /// else in this suite would notice its removal.
    ///
    /// It reads the doc comment as *prose* rather than as bytes — `///` markers dropped, runs of
    /// whitespace collapsed, emphasis asterisks removed — so a reflow of the same sentence across
    /// different line breaks keeps passing and only deleting or rewording it fails. A scan that
    /// pinned the line breaks would be a scan the next `swift-format` run turns red for nothing.
    @Test func theExporterSaysCalendarLinksDoNotSurviveACrossDeviceRestore() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Services/CadenceDataExportService.swift")
        #expect(raw.count > 400, "the export service read as \(raw.count) characters")
        let prose = Self.docProse(raw)

        #expect(prose.contains("calendar links do not survive a cross-device restore"),
                "the archive no longer states that a calendar link is scoped to the machine that wrote it")
        #expect(prose.contains("T-661"), "the decision is unattributed, so the next reader re-argues it")
        #expect(prose.contains("EKCalendar.calendarIdentifier"),
                "the note does not say what the field actually holds")
        #expect(prose.contains("Dropping the field instead was the other option, and it was rejected"),
                "the archive records the decision without recording that the other branch was considered")
    }

    /// Without these the scan above is true of any file with enough text in it, and the reflow
    /// tolerance it claims is untested.
    @Test func theCrossDeviceRestoreNeedleIsNotVacuous() {
        let wrapped = """
            /// `EKCalendar.calendarIdentifier`, which Apple documents as local to one device. So **calendar
            /// links do not survive a cross-device restore**: read back on a different machine
            """
        let reflowed = """
            /// `EKCalendar.calendarIdentifier`, which Apple documents as local to one device.
            /// So **calendar links do not survive a cross-device restore**: read back on a
            /// different machine
            """
        let silent = "/// The field is copied straight into the archive: read back on a different machine"

        #expect(Self.docProse(wrapped).contains("calendar links do not survive a cross-device restore"))
        #expect(Self.docProse(reflowed).contains("calendar links do not survive a cross-device restore"),
                "the scan pins line breaks, so a reflow of the same sentence would fail it")
        #expect(!Self.docProse(silent).contains("calendar links do not survive a cross-device restore"))
    }

    /// A doc comment as the sentences it says: `///` dropped, emphasis dropped, whitespace runs
    /// collapsed to one space.
    private static func docProse(_ source: String) -> String {
        source
            .replacingOccurrences(of: "///", with: " ")
            .replacingOccurrences(of: "*", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
