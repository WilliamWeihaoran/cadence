import Foundation
import SwiftData

/// A portable, inspectable copy of everything Cadence persists.
///
/// **Why this exists beside `StoreBackupManager`.** That manager already snapshots the SQLite
/// store, and it restores — but every copy it makes lives *inside the app's own container*, next
/// to the store it is protecting, and `deleteCadenceDataAndLocalArtifacts` deletes all of them.
/// A lost device, a deleted app, or a reset takes the backups with the original. It is also an
/// opaque SwiftData store: the file format is CoreData's private schema, so it is readable by this
/// build of this app and by nothing else, including a future build after a schema change.
///
/// This archive is the other half: one JSON document the user can put somewhere Cadence cannot
/// reach, open in any text editor, and still read in ten years. It is a **complete** copy — every
/// entity in `CadenceSchema`, including the five legacy note models `NoteMigrationService` still
/// reads, and including the two live-but-unread fields (`Goal.dependsOnGoalIDsJSON`,
/// `AppTask.calendarEventID`) that must not be dropped because there is no `SchemaMigrationPlan`.
/// This exporter is currently their only reader.
///
/// **Export only, deliberately.** The archive *decodes* — `CadenceArchive` is `Codable` in both
/// directions and a round trip is pinned by `CadenceDataExportSurfaceTests` — but nothing applies a
/// decoded archive to a live store, because a restore into a CloudKit-synced container is not a
/// local operation: writing 4,000 rows back re-uploads them to every other device, and re-using the
/// original `id`s means the merge policy, not the user, decides which copy of a row wins. See
/// `docs/TODO.md` T-274 for what an import has to settle before it can be trusted.
///
/// **Relationships are stored as ids, not by nesting.** A task carries `areaID`; an area does not
/// carry its tasks. That keeps the document a flat set of tables — every row appears exactly once,
/// so a human can diff two exports, and an importer can rebuild the graph in one pass.
///
/// **T-661 — one field in here is scoped to the machine that wrote it, and it stays.**
/// `CadenceArchiveArea.linkedCalendarID` and `CadenceArchiveProject.linkedCalendarID` carry an
/// `EKCalendar.calendarIdentifier`, which Apple documents as local to one device. So **calendar
/// links do not survive a cross-device restore**: read back on a different machine the field names
/// a calendar that machine never issued, and an importer must treat it as meaningful only when the
/// archive is returning to the device that wrote it. Everything else in this document is
/// machine-independent; this is the one exception, and it is stated here rather than left for the
/// importer to discover.
///
/// **Dropping the field instead was the other option, and it was rejected.** On the origin machine
/// the identifier is exact, and this archive is its only copy outside a store the user can delete —
/// so dropping it would make the document incomplete in the one direction a restore actually works,
/// to remove a value that is merely inert in the other. Inert rather than harmful because both
/// readers of a stored link now gate on `CadenceCalendarLinkObservations` (T-624):
/// `CadenceCalendarLinkHealth.missingLinks` and `CadenceCalendarLinkRowState` report an identifier
/// the reading device has never seen alive as unverified, not as broken, so a foreign identifier
/// produces silence rather than a repair prompt that would overwrite the link the other device is
/// still using. Making the link genuinely *portable* is a different job: it needs the title and
/// source T-390 declined to store, which needs the `SchemaMigrationPlan` this project does not have.
nonisolated enum CadenceDataExportService {

    /// Bumped when the archive's *shape* changes in a way a reader must know about — a renamed
    /// key, a removed table, a changed relationship encoding. Adding a field to a record does not
    /// need a bump: an old reader ignores it and a new reader decodes it as absent.
    nonisolated static let formatVersion = 1

    /// The one call both Settings > Data Safety screens make. Neither may re-spell the encoder or
    /// the count: two exporters with two date strategies is how one platform's archive stops being
    /// readable by the other, and `CadenceDataExportSurfaceTests` fails if a second copy appears.
    ///
    /// It returns the row count with the bytes for the same reason `PrivacyDataResetOutcome`
    /// carries its backup count — the sentence the user reads afterwards is a claim about the
    /// data, so it is derived where the data is, not recomputed in a view.
    nonisolated static func exportArchive(
        in modelContext: ModelContext,
        exportedAt: Date = Date(),
        appVersion: String = currentAppVersion()
    ) throws -> CadenceDataExportOutcome {
        let archive = try makeArchive(in: modelContext, exportedAt: exportedAt, appVersion: appVersion)
        return CadenceDataExportOutcome(
            data: try encode(archive),
            recordCount: archive.totalRecordCount
        )
    }

    nonisolated static func encode(_ archive: CadenceArchive) throws -> Data {
        try archiveEncoder.encode(archive)
    }

    nonisolated static func decode(_ data: Data) throws -> CadenceArchive {
        try archiveDecoder.decode(CadenceArchive.self, from: data)
    }

    /// `Cadence Archive 2026-08-24.json`. A date and no clock time, because the user picks the
    /// destination and a same-day second export should read as a replacement, not a sibling.
    nonisolated static func suggestedFilename(for date: Date = Date()) -> String {
        "Cadence Archive \(DateFormatters.dateKey(from: date))"
    }

    /// **T-700.** Read off `CadenceAppBuildIdentity` rather than looked up again here. The two
    /// `Info.plist` keys were spelled twice — once there for both About screens, once here for the
    /// archive header — which is exactly the second hand-written copy that type's own doc comment
    /// names as how two surfaces come to disagree about which key holds the build number. A wrong
    /// key is a silent fallback rather than a crash, so nothing would have said so.
    ///
    /// The `bundle:` seam that used to be here was never passed by any caller, and the two copies
    /// had already drifted: this one fell back to `"0"` for the short version where the About
    /// screens fall back to `"1.0"`. One answer now, whichever it is.
    nonisolated static func currentAppVersion() -> String {
        "\(CadenceAppBuildIdentity.version) (\(CadenceAppBuildIdentity.build))"
    }

    // MARK: - Building

    nonisolated static func makeArchive(
        in modelContext: ModelContext,
        exportedAt: Date = Date(),
        appVersion: String = currentAppVersion()
    ) throws -> CadenceArchive {
        CadenceArchive(
            formatVersion: formatVersion,
            exportedAt: CadenceArchiveTimestamp.normalized(exportedAt),
            appVersion: appVersion,
            schemaEntityNames: CadenceSchema.schema.entities.map(\.name).sorted(),
            contexts: try records(Context.self, in: modelContext, CadenceArchiveContext.init),
            areas: try records(Area.self, in: modelContext, CadenceArchiveArea.init),
            projects: try records(Project.self, in: modelContext, CadenceArchiveProject.init),
            pursuits: try records(Pursuit.self, in: modelContext, CadenceArchivePursuit.init),
            tags: try records(Tag.self, in: modelContext, CadenceArchiveTag.init),
            tasks: try records(AppTask.self, in: modelContext, CadenceArchiveTask.init),
            taskBundles: try records(TaskBundle.self, in: modelContext, CadenceArchiveTaskBundle.init),
            focusSessions: try records(FocusSessionLog.self, in: modelContext, CadenceArchiveFocusSessionLog.init),
            subtasks: try records(Subtask.self, in: modelContext, CadenceArchiveSubtask.init),
            notes: try records(Note.self, in: modelContext, CadenceArchiveNote.init),
            savedLinks: try records(SavedLink.self, in: modelContext, CadenceArchiveSavedLink.init),
            markdownImageAssets: try records(MarkdownImageAsset.self, in: modelContext, CadenceArchiveMarkdownImageAsset.init),
            goals: try records(Goal.self, in: modelContext, CadenceArchiveGoal.init),
            goalListLinks: try records(GoalListLink.self, in: modelContext, CadenceArchiveGoalListLink.init),
            habits: try records(Habit.self, in: modelContext, CadenceArchiveHabit.init),
            habitCompletions: try records(HabitCompletion.self, in: modelContext, CadenceArchiveHabitCompletion.init),
            legacyDailyNotes: try records(DailyNote.self, in: modelContext, CadenceArchiveDailyNote.init),
            legacyWeeklyNotes: try records(WeeklyNote.self, in: modelContext, CadenceArchiveWeeklyNote.init),
            legacyPermNotes: try records(PermNote.self, in: modelContext, CadenceArchivePermNote.init),
            legacyEventNotes: try records(EventNote.self, in: modelContext, CadenceArchiveEventNote.init),
            legacyDocuments: try records(Document.self, in: modelContext, CadenceArchiveLegacyDocument.init)
        )
    }

    /// Every row of one model, as records, sorted by id.
    ///
    /// The sort is what makes two exports of an unchanged store byte-identical, so a user can keep
    /// last week's archive and diff it. It is applied to the *records* rather than to the fetch:
    /// `FetchDescriptor` cannot sort on `id` for every model here, and the records are where the
    /// `UUID` is uniformly reachable.
    private nonisolated static func records<Model: PersistentModel, Record: Identifiable>(
        _ type: Model.Type,
        in modelContext: ModelContext,
        _ make: (Model) -> Record
    ) throws -> [Record] where Record.ID == UUID {
        try modelContext.fetch(FetchDescriptor<Model>())
            .map(make)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private nonisolated static var archiveEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(CadenceArchiveTimestamp.formatter)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private nonisolated static var archiveDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(CadenceArchiveTimestamp.formatter)
        return decoder
    }
}

/// The archive's timestamp precision, stated rather than assumed.
///
/// JSON has no date type, so every `createdAt` travels as text — and text has a fixed number of
/// digits while a `Date` is a `Double`. Something has to give; the only real question is whether
/// the archive admits it. The first cut of this exporter used `JSONEncoder`'s stock `.iso8601`,
/// which writes **whole seconds**: `2026-02-02T02:40:00Z`. Every timestamp in the file was
/// silently truncated by up to a second, and `CadenceArchive` — a value the document is supposed
/// to describe — held an instant the document could not spell. `theArchiveRoundTripsThroughJSON`
/// failed on exactly that, for every seeded row, and it was right to.
///
/// Sub-second precision is not decorative here. `TaskOrdering.fallbackPrecedes` breaks ties on
/// `createdAt`, and rows inserted together — a recurrence spawn beside its source, a migration
/// pass, a bulk wind-down — share a second routinely. Truncating to seconds turns a total order
/// into ties, and restoring such an archive would reshuffle lists.
///
/// So the archive's unit is the **millisecond**, which ISO-8601 can write, and the exporter
/// normalizes to that unit *as it builds each record* rather than only as it writes. That is the
/// difference between a lossy encoder and a stated precision: after `normalized(_:)`, the value in
/// memory and the text in the file are the same instant, so `decode(encode(archive)) == archive`
/// holds exactly and an importer reading the file gets what the exporter had.
///
/// Normalizing is done by round-tripping through the formatter rather than by rounding the
/// `Double`, because the two do not agree: `(t * 1000).rounded() / 1000` and the formatter's own
/// parse land one ulp apart about half the time, measured over 2,000 samples. Formatting is the
/// operation the file performs, so it is the operation that defines the unit.
nonisolated enum CadenceArchiveTimestamp {

    /// `DateFormatters.archiveTimestamp`, not a formatter of this file's own: that file's opening
    /// line is "never create `DateFormatter()` inline elsewhere", and an exporter that walks every
    /// row in the store is exactly the caller that must not build one per timestamp.
    nonisolated static var formatter: DateFormatter { DateFormatters.archiveTimestamp }

    /// The instant this archive can actually represent. Idempotent, and verified so over 500
    /// dates spanning 1905 to 2100 by `theArchiveStatesItsTimestampPrecision`.
    nonisolated static func normalized(_ date: Date) -> Date {
        formatter.date(from: formatter.string(from: date)) ?? date
    }

    nonisolated static func normalized(_ date: Date?) -> Date? {
        date.map(normalized)
    }
}

/// One finished export: the bytes to write, and how many rows they hold.
nonisolated struct CadenceDataExportOutcome: Equatable, Sendable {
    let data: Data
    let recordCount: Int
}

// MARK: - The archive

/// One export, as a value. `Equatable` so the round trip can be asserted rather than eyeballed.
nonisolated struct CadenceArchive: Codable, Equatable, Sendable {
    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String
    /// What `CadenceSchema` reported when this file was written, so a reader can tell whether the
    /// archive predates a model it expects.
    var schemaEntityNames: [String]

    var contexts: [CadenceArchiveContext]
    var areas: [CadenceArchiveArea]
    var projects: [CadenceArchiveProject]
    var pursuits: [CadenceArchivePursuit]
    var tags: [CadenceArchiveTag]
    var tasks: [CadenceArchiveTask]
    var taskBundles: [CadenceArchiveTaskBundle]
    var focusSessions: [CadenceArchiveFocusSessionLog]
    var subtasks: [CadenceArchiveSubtask]
    var notes: [CadenceArchiveNote]
    var savedLinks: [CadenceArchiveSavedLink]
    var markdownImageAssets: [CadenceArchiveMarkdownImageAsset]
    var goals: [CadenceArchiveGoal]
    var goalListLinks: [CadenceArchiveGoalListLink]
    var habits: [CadenceArchiveHabit]
    var habitCompletions: [CadenceArchiveHabitCompletion]
    var legacyDailyNotes: [CadenceArchiveDailyNote]
    var legacyWeeklyNotes: [CadenceArchiveWeeklyNote]
    var legacyPermNotes: [CadenceArchivePermNote]
    var legacyEventNotes: [CadenceArchiveEventNote]
    var legacyDocuments: [CadenceArchiveLegacyDocument]

    /// Which table holds each `CadenceSchema` entity.
    ///
    /// Keyed by the entity name SwiftData reports, so a test can compare this table to
    /// `CadenceSchema.schema.entities` as a set: a model added to the schema and not to the export
    /// is then a **failing test**, not a silently incomplete backup. Same construction, and the
    /// same reason, as `CadencePrivacyDataResetSurfaceTests`' probe table.
    nonisolated static let recordCountsByEntityName: [String: any KeyPath<CadenceArchive, Int> & Sendable] = [
        "Context": \.contexts.count,
        "Area": \.areas.count,
        "Project": \.projects.count,
        "Pursuit": \.pursuits.count,
        "Tag": \.tags.count,
        "AppTask": \.tasks.count,
        "TaskBundle": \.taskBundles.count,
        "FocusSessionLog": \.focusSessions.count,
        "Subtask": \.subtasks.count,
        "Note": \.notes.count,
        "SavedLink": \.savedLinks.count,
        "MarkdownImageAsset": \.markdownImageAssets.count,
        "Goal": \.goals.count,
        "GoalListLink": \.goalListLinks.count,
        "Habit": \.habits.count,
        "HabitCompletion": \.habitCompletions.count,
        "DailyNote": \.legacyDailyNotes.count,
        "WeeklyNote": \.legacyWeeklyNotes.count,
        "PermNote": \.legacyPermNotes.count,
        "EventNote": \.legacyEventNotes.count,
        "Document": \.legacyDocuments.count,
    ]

    nonisolated func recordCount(forEntityNamed name: String) -> Int? {
        Self.recordCountsByEntityName[name].map { self[keyPath: $0] }
    }

    /// Total rows in the archive — the number the Settings screens report after an export.
    nonisolated var totalRecordCount: Int {
        Self.recordCountsByEntityName.values.reduce(0) { $0 + self[keyPath: $1] }
    }
}

// MARK: - Records

nonisolated struct CadenceArchiveContext: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String
    var icon: String
    var order: Int
    var isArchived: Bool

    init(_ model: Context) {
        id = model.id
        name = model.name
        colorHex = model.colorHex
        icon = model.icon
        order = model.order
        isArchived = model.isArchived
    }
}

nonisolated struct CadenceArchiveArea: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var desc: String
    var statusRaw: String
    var colorHex: String
    var icon: String
    var order: Int
    /// **T-661.** The `EKCalendar.calendarIdentifier` this area mirrors, copied verbatim.
    ///
    /// Kept, and **scoped to the machine that exported it**: the identifier is documented as local
    /// to one device, so a restore onto a different Mac or iPhone finds no such calendar and the
    /// link does not come back. See `CadenceDataExportService`'s note for why the field is shipped
    /// anyway rather than dropped, and why a foreign identifier is silent rather than falsely
    /// repairable on the reading device.
    var linkedCalendarID: String
    var loggedMinutes: Int
    var hideDueDateIfEmpty: Bool
    var hideSectionDueDateIfEmpty: Bool
    /// The raw JSON, not the decoded `sectionConfigs`. `sectionNames`' getter hides archived
    /// columns, and a backup that drops them is the same silent delete `Area.sectionNames`'
    /// doc comment records.
    var sectionNamesRaw: String
    var sectionConfigsRaw: String
    var contextID: UUID?

    init(_ model: Area) {
        id = model.id
        name = model.name
        desc = model.desc
        statusRaw = model.statusRaw
        colorHex = model.colorHex
        icon = model.icon
        order = model.order
        linkedCalendarID = model.linkedCalendarID
        loggedMinutes = model.loggedMinutes
        hideDueDateIfEmpty = model.hideDueDateIfEmpty
        hideSectionDueDateIfEmpty = model.hideSectionDueDateIfEmpty
        sectionNamesRaw = model.sectionNamesRaw
        sectionConfigsRaw = model.sectionConfigsRaw
        contextID = model.context?.id
    }
}

nonisolated struct CadenceArchiveProject: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var desc: String
    var statusRaw: String
    var colorHex: String
    var icon: String
    var dueDate: String
    var order: Int
    /// **T-661.** As `CadenceArchiveArea.linkedCalendarID`: kept, and meaningful only on the
    /// machine that wrote the archive.
    var linkedCalendarID: String
    var loggedMinutes: Int
    var hideDueDateIfEmpty: Bool
    var hideSectionDueDateIfEmpty: Bool
    var sectionNamesRaw: String
    var sectionConfigsRaw: String
    var contextID: UUID?
    var areaID: UUID?

    init(_ model: Project) {
        id = model.id
        name = model.name
        desc = model.desc
        statusRaw = model.statusRaw
        colorHex = model.colorHex
        icon = model.icon
        dueDate = model.dueDate
        order = model.order
        linkedCalendarID = model.linkedCalendarID
        loggedMinutes = model.loggedMinutes
        hideDueDateIfEmpty = model.hideDueDateIfEmpty
        hideSectionDueDateIfEmpty = model.hideSectionDueDateIfEmpty
        sectionNamesRaw = model.sectionNamesRaw
        sectionConfigsRaw = model.sectionConfigsRaw
        contextID = model.context?.id
        areaID = model.area?.id
    }
}

/// Retired concept, still in the schema so `PursuitToGoalMigration` can read pre-merge rows — so
/// still in the archive. An export that drops it is a lossy backup for anyone whose migration has
/// not run on every synced device yet.
nonisolated struct CadenceArchivePursuit: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var desc: String
    var icon: String
    var colorHex: String
    var kindRaw: String
    var statusRaw: String
    var order: Int
    var createdAt: Date
    var contextID: UUID?

    init(_ model: Pursuit) {
        id = model.id
        title = model.title
        desc = model.desc
        icon = model.icon
        colorHex = model.colorHex
        kindRaw = model.kindRaw
        statusRaw = model.statusRaw
        order = model.order
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        contextID = model.context?.id
    }
}

nonisolated struct CadenceArchiveTag: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var slug: String
    var name: String
    var desc: String
    var colorHex: String
    var order: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ model: Tag) {
        id = model.id
        slug = model.slug
        name = model.name
        desc = model.desc
        colorHex = model.colorHex
        order = model.order
        isArchived = model.isArchived
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        updatedAt = CadenceArchiveTimestamp.normalized(model.updatedAt)
    }
}

nonisolated struct CadenceArchiveTask: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var priorityRaw: String
    var statusRaw: String
    var dueDate: String
    var scheduledDate: String
    var scheduledStartMin: Int
    var estimatedMinutes: Int
    var actualMinutes: Int
    /// Nothing writes this a non-empty value any more, and this exporter is its only reader
    /// outside the three files that clear it. Values written by an earlier build may still be on
    /// disk or in CloudKit; a backup that omits the column is how they finally disappear.
    var calendarEventID: String
    var recurrenceRaw: String
    var recurrenceSeriesIDRaw: String
    var recurrenceSourceTaskIDRaw: String
    var recurrenceSpawnedTaskIDRaw: String
    var recurrenceOccurrenceIndex: Int
    var recurrenceEndModeRaw: String
    var recurrenceEndDate: String
    var recurrenceEndCount: Int
    var sectionName: String
    var order: Int
    var bundleOrder: Int
    var createdAt: Date
    var completedAt: Date?
    var areaID: UUID?
    var projectID: UUID?
    var goalID: UUID?
    var contextID: UUID?
    var bundleID: UUID?
    var tagIDs: [UUID]

    init(_ model: AppTask) {
        id = model.id
        title = model.title
        notes = model.notes
        priorityRaw = model.priorityRaw
        statusRaw = model.statusRaw
        dueDate = model.dueDate
        scheduledDate = model.scheduledDate
        scheduledStartMin = model.scheduledStartMin
        estimatedMinutes = model.estimatedMinutes
        actualMinutes = model.actualMinutes
        calendarEventID = model.calendarEventID
        recurrenceRaw = model.recurrenceRaw
        recurrenceSeriesIDRaw = model.recurrenceSeriesIDRaw
        recurrenceSourceTaskIDRaw = model.recurrenceSourceTaskIDRaw
        recurrenceSpawnedTaskIDRaw = model.recurrenceSpawnedTaskIDRaw
        recurrenceOccurrenceIndex = model.recurrenceOccurrenceIndex
        recurrenceEndModeRaw = model.recurrenceEndModeRaw
        recurrenceEndDate = model.recurrenceEndDate
        recurrenceEndCount = model.recurrenceEndCount
        sectionName = model.sectionName
        order = model.order
        bundleOrder = model.bundleOrder
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        completedAt = CadenceArchiveTimestamp.normalized(model.completedAt)
        areaID = model.area?.id
        projectID = model.project?.id
        goalID = model.goal?.id
        contextID = model.context?.id
        bundleID = model.bundle?.id
        tagIDs = (model.tags ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString }
    }
}

nonisolated struct CadenceArchiveTaskBundle: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var dateKey: String
    var startMin: Int
    var durationMinutes: Int
    var createdAt: Date

    init(_ model: TaskBundle) {
        id = model.id
        title = model.title
        dateKey = model.dateKey
        startMin = model.startMin
        durationMinutes = model.durationMinutes
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
    }
}

/// One row of the focus-time ledger. Exported because it is the only record of *when* logged time
/// was logged — the counters it reconciles are a single cumulative number — and because an archive
/// restored without it would hand every counter a ledger claiming a legacy total of whatever the
/// counter already held.
nonisolated struct CadenceArchiveFocusSessionLog: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var minutes: Int
    var previousMinutes: Int
    var loggedAt: Date
    var dayKey: String
    var taskID: UUID?
    var areaID: UUID?
    var projectID: UUID?

    init(_ model: FocusSessionLog) {
        id = model.id
        minutes = model.minutes
        previousMinutes = model.previousMinutes
        loggedAt = CadenceArchiveTimestamp.normalized(model.loggedAt)
        dayKey = model.dayKey
        taskID = model.task?.id
        areaID = model.area?.id
        projectID = model.project?.id
    }
}

nonisolated struct CadenceArchiveSubtask: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var isDone: Bool
    var order: Int
    var createdAt: Date
    var parentTaskID: UUID?

    init(_ model: Subtask) {
        id = model.id
        title = model.title
        isDone = model.isDone
        order = model.order
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        parentTaskID = model.parentTask?.id
    }
}

nonisolated struct CadenceArchiveNote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kindRaw: String
    var title: String
    var content: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date
    var dateKey: String
    var weekKey: String
    var calendarEventID: String
    var calendarID: String
    var eventDateKey: String
    var eventStartMin: Int
    var eventEndMin: Int
    var legacySourceKindRaw: String
    var legacySourceID: String
    var folderPath: String
    var areaID: UUID?
    var projectID: UUID?
    var tagIDs: [UUID]

    init(_ model: Note) {
        id = model.id
        kindRaw = model.kindRaw
        title = model.title
        content = model.content
        order = model.order
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        updatedAt = CadenceArchiveTimestamp.normalized(model.updatedAt)
        dateKey = model.dateKey
        weekKey = model.weekKey
        calendarEventID = model.calendarEventID
        calendarID = model.calendarID
        eventDateKey = model.eventDateKey
        eventStartMin = model.eventStartMin
        eventEndMin = model.eventEndMin
        legacySourceKindRaw = model.legacySourceKindRaw
        legacySourceID = model.legacySourceID
        folderPath = model.folderPath
        areaID = model.area?.id
        projectID = model.project?.id
        tagIDs = (model.tags ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString }
    }
}

nonisolated struct CadenceArchiveSavedLink: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var url: String
    var order: Int
    var createdAt: Date
    var areaID: UUID?
    var projectID: UUID?

    init(_ model: SavedLink) {
        id = model.id
        title = model.title
        url = model.url
        order = model.order
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        areaID = model.area?.id
        projectID = model.project?.id
    }
}

/// The one record carrying binary. `Data` encodes as base64 in JSON, which is ~33% larger than the
/// original bytes and the reason an archive of an image-heavy store is big — but the alternative,
/// exporting the metadata and leaving the pixels behind, is a backup that looks complete and
/// silently is not.
nonisolated struct CadenceArchiveMarkdownImageAsset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var data: Data
    var mimeType: String
    var originalFilename: String
    var altText: String
    var pixelWidth: Int
    var pixelHeight: Int
    var displayWidth: Double
    var createdAt: Date
    var updatedAt: Date

    init(_ model: MarkdownImageAsset) {
        id = model.id
        data = model.data
        mimeType = model.mimeType
        originalFilename = model.originalFilename
        altText = model.altText
        pixelWidth = model.pixelWidth
        pixelHeight = model.pixelHeight
        displayWidth = model.displayWidth
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        updatedAt = CadenceArchiveTimestamp.normalized(model.updatedAt)
    }
}

nonisolated struct CadenceArchiveGoal: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var desc: String
    var startDate: String
    var endDate: String
    var progressTypeRaw: String
    var targetHours: Double
    var loggedHours: Double
    var colorHex: String
    var icon: String
    var statusRaw: String
    var kindRaw: String
    var order: Int
    var createdAt: Date
    /// Persisted, with zero readers in feature code and no UI — and it must not be deleted,
    /// because there is no `SchemaMigrationPlan`. This exporter is the only thing that reads it.
    var dependsOnGoalIDsJSON: String
    var contextID: UUID?
    var pursuitID: UUID?
    var parentGoalID: UUID?

    init(_ model: Goal) {
        id = model.id
        title = model.title
        desc = model.desc
        startDate = model.startDate
        endDate = model.endDate
        progressTypeRaw = model.progressTypeRaw
        targetHours = model.targetHours
        loggedHours = model.loggedHours
        colorHex = model.colorHex
        icon = model.icon
        statusRaw = model.statusRaw
        kindRaw = model.kindRaw
        order = model.order
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        dependsOnGoalIDsJSON = model.dependsOnGoalIDsJSON
        contextID = model.context?.id
        pursuitID = model.pursuit?.id
        parentGoalID = model.parentGoal?.id
    }
}

nonisolated struct CadenceArchiveGoalListLink: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var goalID: UUID?
    var areaID: UUID?
    var projectID: UUID?

    init(_ model: GoalListLink) {
        id = model.id
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        goalID = model.goal?.id
        areaID = model.area?.id
        projectID = model.project?.id
    }
}

nonisolated struct CadenceArchiveHabit: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var icon: String
    var colorHex: String
    var frequencyTypeRaw: String
    var frequencyDaysRaw: String
    var targetCount: Int
    var order: Int
    var createdAt: Date
    /// Optional and never a sentinel: `nil` is "no reminder", `0` is midnight.
    var reminderMinuteOfDay: Int?
    var contextID: UUID?
    var pursuitID: UUID?
    var goalID: UUID?

    init(_ model: Habit) {
        id = model.id
        title = model.title
        icon = model.icon
        colorHex = model.colorHex
        frequencyTypeRaw = model.frequencyTypeRaw
        frequencyDaysRaw = model.frequencyDaysRaw
        targetCount = model.targetCount
        order = model.order
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        reminderMinuteOfDay = model.reminderMinuteOfDay
        contextID = model.context?.id
        pursuitID = model.pursuit?.id
        goalID = model.goal?.id
    }
}

nonisolated struct CadenceArchiveHabitCompletion: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var date: String
    var count: Int
    var createdAt: Date
    var habitID: UUID?

    init(_ model: HabitCompletion) {
        id = model.id
        date = model.date
        count = model.count
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        habitID = model.habit?.id
    }
}

// MARK: - Legacy records
//
// `DailyNote`, `WeeklyNote`, `PermNote`, `EventNote` and `Document` are migration sources only —
// `NoteMigrationService` folds them into `Note` and no UI reads them. They are still in
// `CadenceSchema`, so rows can still be on disk or arriving from CloudKit from a device that has
// not migrated. A backup taken *before* the migration runs is exactly when they matter, so they
// are exported under `legacy…` keys that say what they are rather than being quietly omitted.

nonisolated struct CadenceArchiveDailyNote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var date: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(_ model: DailyNote) {
        id = model.id
        date = model.date
        content = model.content
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        updatedAt = CadenceArchiveTimestamp.normalized(model.updatedAt)
    }
}

nonisolated struct CadenceArchiveWeeklyNote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var weekKey: String
    var content: String
    var createdAt: Date
    var updatedAt: Date

    init(_ model: WeeklyNote) {
        id = model.id
        weekKey = model.weekKey
        content = model.content
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        updatedAt = CadenceArchiveTimestamp.normalized(model.updatedAt)
    }
}

nonisolated struct CadenceArchivePermNote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var content: String
    var updatedAt: Date

    init(_ model: PermNote) {
        id = model.id
        content = model.content
        updatedAt = CadenceArchiveTimestamp.normalized(model.updatedAt)
    }
}

nonisolated struct CadenceArchiveEventNote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var calendarEventID: String
    var calendarID: String
    var title: String
    var content: String
    var eventDateKey: String
    var eventStartMin: Int
    var eventEndMin: Int
    var createdAt: Date
    var updatedAt: Date

    init(_ model: EventNote) {
        id = model.id
        calendarEventID = model.calendarEventID
        calendarID = model.calendarID
        title = model.title
        content = model.content
        eventDateKey = model.eventDateKey
        eventStartMin = model.eventStartMin
        eventEndMin = model.eventEndMin
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        updatedAt = CadenceArchiveTimestamp.normalized(model.updatedAt)
    }
}

nonisolated struct CadenceArchiveLegacyDocument: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date
    var areaID: UUID?
    var projectID: UUID?

    init(_ model: Document) {
        id = model.id
        title = model.title
        content = model.content
        order = model.order
        createdAt = CadenceArchiveTimestamp.normalized(model.createdAt)
        updatedAt = CadenceArchiveTimestamp.normalized(model.updatedAt)
        areaID = model.area?.id
        projectID = model.project?.id
    }
}

