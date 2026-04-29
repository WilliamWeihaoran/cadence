import Foundation
import OSLog
import SwiftData

struct NoteMigrationReport: Codable, Equatable {
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

enum NoteMigrationService {
    enum LegacyKind: String {
        case daily
        case weekly
        case permanent
        case document
        case eventNote = "event_note"
    }

    private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "NoteMigration")
    private static let lastReportKey = "noteMigration.lastReport.v1"

    @discardableResult
    static func migrateIfNeeded(in context: ModelContext, source: String = "unknown") throws -> NoteMigrationReport {
        var report = NoteMigrationReport(
            source: source,
            startedAt: Date(),
            finishedAt: Date(),
            success: false
        )

        do {
            let result = try migrate(in: context, report: &report)
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
    static func migrateAndRecordFailure(in context: ModelContext, source: String) -> NoteMigrationReport? {
        do {
            return try migrateIfNeeded(in: context, source: source)
        } catch {
            return lastReport()
        }
    }

    static func lastReport() -> NoteMigrationReport? {
        guard let data = UserDefaults.standard.data(forKey: lastReportKey) else { return nil }
        return try? JSONDecoder().decode(NoteMigrationReport.self, from: data)
    }

    private static func migrate(in context: ModelContext, report: inout NoteMigrationReport) throws -> NoteMigrationReport {
        let notes = try context.fetch(FetchDescriptor<Note>())
        report.existingNoteCount = notes.count
        report.canonicalDuplicateCount = canonicalDuplicateCount(in: notes)
        var migratedSources = Set(notes.compactMap(sourceKey(for:)))
        var canonicalKeys = Set(notes.map(canonicalKey(for:)))
        var inserted = false

        for legacy in try context.fetch(FetchDescriptor<DailyNote>()) {
            report.legacyDailyScanned += 1
            let source = sourceKey(kind: .daily, id: legacy.id)
            let canonical = "daily:\(legacy.date)"
            guard shouldMigrate(source: source, canonical: canonical, migratedSources: migratedSources, canonicalKeys: canonicalKeys, report: &report) else {
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
            migratedSources.insert(source)
            canonicalKeys.insert(canonical)
            report.insertedDaily += 1
            inserted = true
        }

        for legacy in try context.fetch(FetchDescriptor<WeeklyNote>()) {
            report.legacyWeeklyScanned += 1
            let source = sourceKey(kind: .weekly, id: legacy.id)
            let canonical = "weekly:\(legacy.weekKey)"
            guard shouldMigrate(source: source, canonical: canonical, migratedSources: migratedSources, canonicalKeys: canonicalKeys, report: &report) else {
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
            migratedSources.insert(source)
            canonicalKeys.insert(canonical)
            report.insertedWeekly += 1
            inserted = true
        }

        for legacy in try context.fetch(FetchDescriptor<PermNote>()) {
            report.legacyPermanentScanned += 1
            let source = sourceKey(kind: .permanent, id: legacy.id)
            let canonical = "permanent"
            guard shouldMigrate(source: source, canonical: canonical, migratedSources: migratedSources, canonicalKeys: canonicalKeys, report: &report) else {
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
            migratedSources.insert(source)
            canonicalKeys.insert(canonical)
            report.insertedPermanent += 1
            inserted = true
        }

        for legacy in try context.fetch(FetchDescriptor<Document>()) {
            report.legacyDocumentScanned += 1
            let source = sourceKey(kind: .document, id: legacy.id)
            guard shouldMigrate(source: source, canonical: nil, migratedSources: migratedSources, canonicalKeys: canonicalKeys, report: &report) else {
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
            migratedSources.insert(source)
            canonicalKeys.insert("list:\(legacy.id.uuidString)")
            report.insertedList += 1
            inserted = true
        }

        for legacy in try context.fetch(FetchDescriptor<EventNote>()) {
            report.legacyEventNoteScanned += 1
            let source = sourceKey(kind: .eventNote, id: legacy.id)
            let canonical = legacy.calendarEventID.isEmpty ? source : "meeting:\(legacy.calendarEventID)"
            guard shouldMigrate(source: source, canonical: canonical, migratedSources: migratedSources, canonicalKeys: canonicalKeys, report: &report) else {
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
            migratedSources.insert(source)
            canonicalKeys.insert(canonical)
            report.insertedMeeting += 1
            inserted = true
        }

        if inserted {
            try context.save()
        }

        report.finishedAt = Date()
        report.success = true
        return report
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

    @discardableResult
    static func permanentNote(in context: ModelContext) throws -> Note {
        let existing = try context.fetch(FetchDescriptor<Note>())
            .first { $0.kind == .permanent }
        if let existing { return existing }

        let note = Note(kind: .permanent, title: "Notepad")
        context.insert(note)
        try context.save()
        return note
    }

    private static func sourceKey(for note: Note) -> String? {
        guard !note.legacySourceKindRaw.isEmpty, !note.legacySourceID.isEmpty else { return nil }
        return "\(note.legacySourceKindRaw):\(note.legacySourceID)"
    }

    private static func sourceKey(kind: LegacyKind, id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }

    private static func canonicalKey(for note: Note) -> String {
        switch note.kind {
        case .daily:
            return "daily:\(note.dateKey)"
        case .weekly:
            return "weekly:\(note.weekKey)"
        case .permanent:
            return "permanent"
        case .list:
            return "list:\(note.id.uuidString)"
        case .meeting:
            return note.calendarEventID.isEmpty ? "meeting-note:\(note.id.uuidString)" : "meeting:\(note.calendarEventID)"
        }
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

    private static func canonicalDuplicateCount(in notes: [Note]) -> Int {
        let counts = Dictionary(grouping: notes, by: canonicalKey(for:))
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
