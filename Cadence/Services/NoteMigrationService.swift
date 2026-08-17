import Foundation
import OSLog
import SwiftData

nonisolated struct NoteMigrationReport: Codable, Equatable {
    var source: String
    var startedAt: Date
    var finishedAt: Date
    var success: Bool
    var errorMessage: String?
    var existingNoteCount: Int = 0
    var canonicalDuplicateCount: Int = 0
    var legacyDailyScanned: Int = 0
    var legacyWeeklyScanned: Int = 0
    var legacyPermanentScanned: Int = 0
    var legacyDocumentScanned: Int = 0
    var legacyEventNoteScanned: Int = 0
    var insertedDaily: Int = 0
    var insertedWeekly: Int = 0
    var insertedPermanent: Int = 0
    var insertedList: Int = 0
    var insertedMeeting: Int = 0
    var skippedAlreadyMigrated: Int = 0
    var skippedCanonicalDuplicate: Int = 0

    var insertedTotal: Int {
        insertedDaily + insertedWeekly + insertedPermanent + insertedList + insertedMeeting
    }

    var legacyScannedTotal: Int {
        legacyDailyScanned + legacyWeeklyScanned + legacyPermanentScanned + legacyDocumentScanned + legacyEventNoteScanned
    }
}

nonisolated struct NoteMigrationHealthReport: Codable, Equatable {
    var noteCount: Int = 0
    var canonicalDuplicateCount: Int = 0
    var legacyWithoutCanonicalCount: Int = 0
    var orphanedListNoteCount: Int = 0
    var listNoteWithMultipleOwnersCount: Int = 0
    var meetingNoteMissingEventIDCount: Int = 0
    var meetingNoteMissingCalendarIDCount: Int = 0

    /// Every defect this report counts, summed. `meetingNoteMissingCalendarIDCount` used to be
    /// left out — so a store whose only problem was event notes that had lost their calendar ID
    /// reported `issueCount == 0` and read as *healthy* to `CadenceReadService`, which is the one
    /// consumer that decides whether to surface the report at all. A field worth counting is a
    /// field worth counting here; leaving one out makes the summary disagree with its own detail.
    var issueCount: Int {
        canonicalDuplicateCount +
            legacyWithoutCanonicalCount +
            orphanedListNoteCount +
            listNoteWithMultipleOwnersCount +
            meetingNoteMissingEventIDCount +
            meetingNoteMissingCalendarIDCount
    }
}

nonisolated enum NoteMigrationService {
    enum LegacyKind: String {
        case daily
        case weekly
        case permanent
        case document
        case eventNote = "event_note"
    }

    private struct MigrationTracking {
        var migratedSources: Set<String>
        var canonicalKeys: Set<String>
        var inserted = false
    }

    private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "NoteMigration")
    private static let lastReportKey = "noteMigration.lastReport.v1"

    @discardableResult
    static func migrateIfNeeded(
        in context: ModelContext,
        source: String = "unknown",
        saveChanges: Bool = true
    ) throws -> NoteMigrationReport {
        var report = NoteMigrationReport(
            source: source,
            startedAt: Date(),
            finishedAt: Date(),
            success: false
        )

        do {
            let result = try migrate(in: context, report: &report, saveChanges: saveChanges)
            record(result)
            log(result)
            return result
        } catch {
            report.finishedAt = Date()
            report.success = false
            report.errorMessage = error.localizedDescription
            record(report)
            logger.error("Note migration failed from \(source, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @discardableResult
    static func migrateAndRecordFailure(
        in context: ModelContext,
        source: String,
        saveChanges: Bool = true
    ) -> NoteMigrationReport? {
        do {
            return try migrateIfNeeded(in: context, source: source, saveChanges: saveChanges)
        } catch {
            return lastReport()
        }
    }

    static func lastReport() -> NoteMigrationReport? {
        guard let data = UserDefaults.standard.data(forKey: lastReportKey) else { return nil }
        return try? JSONDecoder().decode(NoteMigrationReport.self, from: data)
    }

    static func healthCheck(in context: ModelContext) throws -> NoteMigrationHealthReport {
        let notes = try context.fetch(FetchDescriptor<Note>())
        var report = NoteMigrationHealthReport()
        report.noteCount = notes.count
        report.canonicalDuplicateCount = canonicalDuplicateCount(in: notes)

        let canonicalKeys = Set(notes.map(\.canonicalKey))
        for legacy in try context.fetch(FetchDescriptor<DailyNote>()) {
            if !canonicalKeys.contains(canonicalKey(kind: .daily, dateKey: legacy.date, id: legacy.id)) {
                report.legacyWithoutCanonicalCount += 1
            }
        }
        for legacy in try context.fetch(FetchDescriptor<WeeklyNote>()) {
            if !canonicalKeys.contains(canonicalKey(kind: .weekly, weekKey: legacy.weekKey, id: legacy.id)) {
                report.legacyWithoutCanonicalCount += 1
            }
        }
        for legacy in try context.fetch(FetchDescriptor<PermNote>())
        where !canonicalKeys.contains(canonicalKey(kind: .permanent, id: legacy.id)) {
            report.legacyWithoutCanonicalCount += 1
        }
        for legacy in try context.fetch(FetchDescriptor<Document>()) {
            if !canonicalKeys.contains(canonicalKey(kind: .list, id: legacy.id)) {
                report.legacyWithoutCanonicalCount += 1
            }
        }
        for legacy in try context.fetch(FetchDescriptor<EventNote>()) {
            let key = canonicalKey(kind: .meeting, calendarEventID: legacy.calendarEventID, id: legacy.id)
            if !canonicalKeys.contains(key) {
                report.legacyWithoutCanonicalCount += 1
            }
        }

        for note in notes {
            switch note.kind {
            case .list:
                let ownerCount = (note.area == nil ? 0 : 1) + (note.project == nil ? 0 : 1)
                if ownerCount == 0 {
                    report.orphanedListNoteCount += 1
                } else if ownerCount > 1 {
                    report.listNoteWithMultipleOwnersCount += 1
                }
            case .meeting:
                if note.calendarEventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    report.meetingNoteMissingEventIDCount += 1
                }
                if note.calendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    report.meetingNoteMissingCalendarIDCount += 1
                }
            default:
                break
            }
        }
        return report
    }

    private static func migrate(
        in context: ModelContext,
        report: inout NoteMigrationReport,
        saveChanges: Bool
    ) throws -> NoteMigrationReport {
        let notes = try context.fetch(FetchDescriptor<Note>())
        report.existingNoteCount = notes.count
        report.canonicalDuplicateCount = canonicalDuplicateCount(in: notes)
        var tracking = MigrationTracking(
            migratedSources: Set(notes.compactMap(sourceKey(for:))),
            canonicalKeys: Set(notes.map(\.canonicalKey))
        )

        try migrateDailyNotes(in: context, report: &report, tracking: &tracking)
        try migrateWeeklyNotes(in: context, report: &report, tracking: &tracking)
        try migratePermanentNotes(in: context, report: &report, tracking: &tracking)
        try migrateDocumentNotes(in: context, report: &report, tracking: &tracking)
        try migrateEventNotes(in: context, report: &report, tracking: &tracking)

        if tracking.inserted && saveChanges {
            try context.save()
        }

        report.finishedAt = Date()
        report.success = true
        return report
    }

    private static func migrateDailyNotes(
        in context: ModelContext,
        report: inout NoteMigrationReport,
        tracking: inout MigrationTracking
    ) throws {
        for legacy in try context.fetch(FetchDescriptor<DailyNote>()) {
            report.legacyDailyScanned += 1
            let source = sourceKey(kind: .daily, id: legacy.id)
            let canonical = canonicalKey(kind: .daily, dateKey: legacy.date, id: legacy.id)
            guard shouldMigrate(source: source, canonical: canonical, migratedSources: tracking.migratedSources, canonicalKeys: tracking.canonicalKeys, report: &report) else {
                continue
            }
            context.insert(Note(
                id: legacy.id,
                kind: .daily,
                title: legacy.date,
                content: legacy.content,
                createdAt: legacy.createdAt,
                updatedAt: legacy.updatedAt,
                dateKey: legacy.date,
                legacySourceKind: LegacyKind.daily.rawValue,
                legacySourceID: legacy.id.uuidString
            ))
            tracking.migratedSources.insert(source)
            tracking.canonicalKeys.insert(canonical)
            report.insertedDaily += 1
            tracking.inserted = true
        }
    }

    private static func migrateWeeklyNotes(
        in context: ModelContext,
        report: inout NoteMigrationReport,
        tracking: inout MigrationTracking
    ) throws {
        for legacy in try context.fetch(FetchDescriptor<WeeklyNote>()) {
            report.legacyWeeklyScanned += 1
            let source = sourceKey(kind: .weekly, id: legacy.id)
            let canonical = canonicalKey(kind: .weekly, weekKey: legacy.weekKey, id: legacy.id)
            guard shouldMigrate(source: source, canonical: canonical, migratedSources: tracking.migratedSources, canonicalKeys: tracking.canonicalKeys, report: &report) else {
                continue
            }
            context.insert(Note(
                id: legacy.id,
                kind: .weekly,
                title: legacy.weekKey,
                content: legacy.content,
                createdAt: legacy.createdAt,
                updatedAt: legacy.updatedAt,
                weekKey: legacy.weekKey,
                legacySourceKind: LegacyKind.weekly.rawValue,
                legacySourceID: legacy.id.uuidString
            ))
            tracking.migratedSources.insert(source)
            tracking.canonicalKeys.insert(canonical)
            report.insertedWeekly += 1
            tracking.inserted = true
        }
    }

    private static func migratePermanentNotes(
        in context: ModelContext,
        report: inout NoteMigrationReport,
        tracking: inout MigrationTracking
    ) throws {
        for legacy in try context.fetch(FetchDescriptor<PermNote>()) {
            report.legacyPermanentScanned += 1
            let source = sourceKey(kind: .permanent, id: legacy.id)
            let canonical = canonicalKey(kind: .permanent, id: legacy.id)
            guard shouldMigrate(source: source, canonical: canonical, migratedSources: tracking.migratedSources, canonicalKeys: tracking.canonicalKeys, report: &report) else {
                continue
            }
            context.insert(Note(
                id: legacy.id,
                kind: .permanent,
                title: "Notepad",
                content: legacy.content,
                updatedAt: legacy.updatedAt,
                legacySourceKind: LegacyKind.permanent.rawValue,
                legacySourceID: legacy.id.uuidString
            ))
            tracking.migratedSources.insert(source)
            tracking.canonicalKeys.insert(canonical)
            report.insertedPermanent += 1
            tracking.inserted = true
        }
    }

    private static func migrateDocumentNotes(
        in context: ModelContext,
        report: inout NoteMigrationReport,
        tracking: inout MigrationTracking
    ) throws {
        for legacy in try context.fetch(FetchDescriptor<Document>()) {
            report.legacyDocumentScanned += 1
            let source = sourceKey(kind: .document, id: legacy.id)
            guard shouldMigrate(source: source, canonical: nil, migratedSources: tracking.migratedSources, canonicalKeys: tracking.canonicalKeys, report: &report) else {
                continue
            }
            context.insert(Note(
                id: legacy.id,
                kind: .list,
                title: legacy.title,
                content: legacy.content,
                order: legacy.order,
                createdAt: legacy.createdAt,
                updatedAt: legacy.updatedAt,
                legacySourceKind: LegacyKind.document.rawValue,
                legacySourceID: legacy.id.uuidString,
                area: legacy.area,
                project: legacy.project
            ))
            tracking.migratedSources.insert(source)
            tracking.canonicalKeys.insert(canonicalKey(kind: .list, id: legacy.id))
            report.insertedList += 1
            tracking.inserted = true
        }
    }

    private static func migrateEventNotes(
        in context: ModelContext,
        report: inout NoteMigrationReport,
        tracking: inout MigrationTracking
    ) throws {
        for legacy in try context.fetch(FetchDescriptor<EventNote>()) {
            report.legacyEventNoteScanned += 1
            let source = sourceKey(kind: .eventNote, id: legacy.id)
            let canonical = canonicalKey(kind: .meeting, calendarEventID: legacy.calendarEventID, id: legacy.id)
            guard shouldMigrate(source: source, canonical: canonical, migratedSources: tracking.migratedSources, canonicalKeys: tracking.canonicalKeys, report: &report) else {
                continue
            }
            context.insert(Note(
                id: legacy.id,
                kind: .meeting,
                title: legacy.title,
                content: legacy.content,
                createdAt: legacy.createdAt,
                updatedAt: legacy.updatedAt,
                calendarEventID: legacy.calendarEventID,
                calendarID: legacy.calendarID,
                eventDateKey: legacy.eventDateKey,
                eventStartMin: legacy.eventStartMin,
                eventEndMin: legacy.eventEndMin,
                legacySourceKind: LegacyKind.eventNote.rawValue,
                legacySourceID: legacy.id.uuidString
            ))
            tracking.migratedSources.insert(source)
            tracking.canonicalKeys.insert(canonical)
            report.insertedMeeting += 1
            tracking.inserted = true
        }
    }

    @discardableResult
    static func dailyNote(for dateKey: String, in context: ModelContext) throws -> Note {
        let existing = try context.fetch(FetchDescriptor<Note>())
            .first { $0.kind == .daily && $0.dateKey == dateKey }
        if let existing { return existing }

        let note = Note(kind: .daily, title: dateKey, dateKey: dateKey)
        context.insert(note)
        try context.save()
        return note
    }

    @discardableResult
    static func weeklyNote(for weekKey: String, in context: ModelContext) throws -> Note {
        let existing = try context.fetch(FetchDescriptor<Note>())
            .first { $0.kind == .weekly && $0.weekKey == weekKey }
        if let existing { return existing }

        let note = Note(kind: .weekly, title: weekKey, weekKey: weekKey)
        context.insert(note)
        try context.save()
        return note
    }

    /// The *primary* notepad note — the oldest one — creating it if the store has none.
    ///
    /// Notepad is no longer a singleton in the Notes tab, but this accessor still is, and
    /// deliberately: its callers are the single-editor notepad surfaces (the Today note panel's
    /// Notepad tab, the iOS notes panel, the MCP write service) which want one stable note, not a
    /// list. "Oldest" is what makes it stable — a plain `first` over an unordered fetch would
    /// return a different note run to run once more than one exists, so those surfaces would show
    /// a different notepad each launch. Oldest is also the note an upgrading user already had, so
    /// nothing they were looking at moves.
    ///
    /// Use `permanentNotes(in:)` where a list is wanted and `createPermanentNote(in:)` to add one.
    @discardableResult
    static func permanentNote(in context: ModelContext) throws -> Note {
        if let existing = try permanentNotes(in: context).first { return existing }

        let note = Note(kind: .permanent, title: "Notepad")
        context.insert(note)
        try context.save()
        return note
    }

    /// Every notepad note, oldest first. Never creates one.
    static func permanentNotes(in context: ModelContext) throws -> [Note] {
        try context.fetch(FetchDescriptor<Note>())
            .filter { $0.kind == .permanent }
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.createdAt < $1.createdAt
            }
    }

    /// Adds a notepad note. Always inserts — this is the "New Note" button, not a lookup.
    ///
    /// Seeded with its title as a `# Heading` so the body's H1 is the rename control from the
    /// first keystroke, the same way list notes work.
    @discardableResult
    static func createPermanentNote(in context: ModelContext, title: String = "Untitled") throws -> Note {
        let note = Note(kind: .permanent, title: title, content: "# \(title)\n\n")
        context.insert(note)
        try context.save()
        return note
    }

    private nonisolated static func sourceKey(for note: Note) -> String? {
        guard !note.legacySourceKindRaw.isEmpty, !note.legacySourceID.isEmpty else { return nil }
        return "\(note.legacySourceKindRaw):\(note.legacySourceID)"
    }

    private nonisolated static func sourceKey(kind: LegacyKind, id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }

    /// Canonical key of a note this migration is *about to insert*, computed from the legacy row's
    /// fields. Uses `Note.canonicalKey`, the one definition of note identity — this file used to
    /// carry a second, subtly different copy that keyed every dateless daily note as `"daily:"`
    /// and never trimmed, which made it disagree with `DataIntegrityRepairService` about which
    /// notes are the same note.
    ///
    /// Each legacy row is migrated with `id: legacy.id`, so passing the legacy id here yields
    /// exactly the key the inserted note will report.
    private nonisolated static func canonicalKey(
        kind: NoteKind,
        dateKey: String = "",
        weekKey: String = "",
        calendarEventID: String = "",
        id: UUID
    ) -> String {
        Note.canonicalKey(kind: kind, dateKey: dateKey, weekKey: weekKey, calendarEventID: calendarEventID, id: id)
    }

    private static func shouldMigrate(
        source: String,
        canonical: String?,
        migratedSources: Set<String>,
        canonicalKeys: Set<String>,
        report: inout NoteMigrationReport
    ) -> Bool {
        if migratedSources.contains(source) {
            report.skippedAlreadyMigrated += 1
            return false
        }
        if let canonical, canonicalKeys.contains(canonical) {
            report.skippedCanonicalDuplicate += 1
            return false
        }
        return true
    }

    /// Permanent notes are excluded on purpose.
    ///
    /// `canonicalKey` maps every permanent note to the single key `"permanent"`, which is exactly
    /// right for the migration guard — one legacy `PermNote` must not be copied in twice, and must
    /// not be copied in at all if the app already made a notepad note before the migration ran —
    /// but it is no longer a statement about duplication. Notepad holds as many notes as the user
    /// makes, so counting them as duplicates would report a healthy store as broken and grow the
    /// count every time they wrote something down.
    private static func canonicalDuplicateCount(in notes: [Note]) -> Int {
        let counts = Dictionary(grouping: notes.filter { $0.kind != .permanent }, by: \.canonicalKey)
            .mapValues(\.count)
        return counts.values.reduce(0) { total, count in
            count > 1 ? total + count - 1 : total
        }
    }

    private static func record(_ report: NoteMigrationReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        UserDefaults.standard.set(data, forKey: lastReportKey)
    }

    private static func log(_ report: NoteMigrationReport) {
        if report.insertedTotal > 0 || report.canonicalDuplicateCount > 0 || report.skippedCanonicalDuplicate > 0 {
            logger.info(
                "Note migration completed from \(report.source, privacy: .public): inserted=\(report.insertedTotal), scanned=\(report.legacyScannedTotal), existingNotes=\(report.existingNoteCount), canonicalDuplicates=\(report.canonicalDuplicateCount), skippedCanonical=\(report.skippedCanonicalDuplicate)"
            )
        }
    }
}
