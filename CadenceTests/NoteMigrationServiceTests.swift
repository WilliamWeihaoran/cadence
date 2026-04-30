import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct NoteMigrationServiceTests {
    @Test func migrationCopiesLegacyNotesOnceAndPreservesMetadata() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Area")
        let project = Project(name: "Project")
        let daily = DailyNote(date: "2026-04-29")
        daily.content = "Daily content"
        let weekly = WeeklyNote(weekKey: "2026-W18")
        weekly.content = "Weekly content"
        let permanent = PermNote()
        permanent.content = "Permanent content"
        let document = Document(title: "List note")
        document.content = "List content"
        document.order = 7
        document.project = project
        let eventNote = EventNote(
            calendarEventID: "event-1",
            eventTitle: "Meeting",
            calendarID: "calendar-1",
            eventDateKey: "2026-04-29",
            eventStartMin: 600,
            eventEndMin: 630
        )
        eventNote.content = "Meeting content"

        context.insert(area)
        context.insert(project)
        context.insert(daily)
        context.insert(weekly)
        context.insert(permanent)
        context.insert(document)
        context.insert(eventNote)
        try context.save()

        let firstReport = try NoteMigrationService.migrateIfNeeded(in: context, source: "test-first")
        let secondReport = try NoteMigrationService.migrateIfNeeded(in: context, source: "test-second")

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 5)
        #expect(firstReport.success)
        #expect(firstReport.insertedTotal == 5)
        #expect(firstReport.legacyScannedTotal == 5)
        #expect(secondReport.success)
        #expect(secondReport.insertedTotal == 0)
        #expect(secondReport.skippedAlreadyMigrated == 5)
        #expect(notes.first { $0.kind == .daily }?.id == daily.id)
        #expect(notes.first { $0.kind == .daily }?.content == "Daily content")
        #expect(notes.first { $0.kind == .weekly }?.weekKey == "2026-W18")
        #expect(notes.first { $0.kind == .permanent }?.title == "Notepad")
        #expect(notes.first { $0.kind == .list }?.project?.id == project.id)
        #expect(notes.first { $0.kind == .list }?.order == 7)
        let migratedMeeting = notes.first { $0.kind == .meeting }
        #expect(migratedMeeting?.id == eventNote.id)
        #expect(migratedMeeting?.calendarID == "calendar-1")
        #expect(migratedMeeting?.eventStartMin == 600)
    }

    @Test func keyedCoreNoteLookupCreatesAndReusesNotes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let dailyA = try NoteMigrationService.dailyNote(for: "2026-04-29", in: context)
        let dailyB = try NoteMigrationService.dailyNote(for: "2026-04-29", in: context)
        let weeklyA = try NoteMigrationService.weeklyNote(for: "2026-W18", in: context)
        let weeklyB = try NoteMigrationService.weeklyNote(for: "2026-W18", in: context)
        let permanentA = try NoteMigrationService.permanentNote(in: context)
        let permanentB = try NoteMigrationService.permanentNote(in: context)

        #expect(dailyA.id == dailyB.id)
        #expect(weeklyA.id == weeklyB.id)
        #expect(permanentA.id == permanentB.id)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 3)
    }

    @Test func migrationSkipsCanonicalDuplicateWithoutCreatingSecondCoreNote() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let existing = Note(kind: .daily, title: "2026-04-29", content: "Existing", dateKey: "2026-04-29")
        let legacy = DailyNote(date: "2026-04-29")
        legacy.content = "Legacy"

        context.insert(existing)
        context.insert(legacy)
        try context.save()

        let report = try NoteMigrationService.migrateIfNeeded(in: context, source: "canonical-duplicate-test")
        let notes = try context.fetch(FetchDescriptor<Note>())

        #expect(notes.count == 1)
        #expect(notes.first?.id == existing.id)
        #expect(notes.first?.content == "Existing")
        #expect(report.insertedTotal == 0)
        #expect(report.skippedCanonicalDuplicate == 1)
    }

    @Test func migrationReportDetectsExistingCanonicalNoteDuplicates() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Note(kind: .meeting, title: "A", calendarEventID: "event-1"))
        context.insert(Note(kind: .meeting, title: "B", calendarEventID: "event-1"))
        try context.save()

        let report = try NoteMigrationService.migrateIfNeeded(in: context, source: "duplicate-diagnostic-test")

        #expect(report.insertedTotal == 0)
        #expect(report.canonicalDuplicateCount == 1)
        #expect(NoteMigrationService.lastReport()?.source == "duplicate-diagnostic-test")
        #expect(NoteMigrationService.lastReport()?.canonicalDuplicateCount == 1)
    }

    @Test func healthCheckReportsLegacyGapsAndBadRelationships() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Area")
        let project = Project(name: "Project")
        let orphanedListNote = Note(kind: .list, title: "Orphan")
        let doubleOwnedListNote = Note(kind: .list, title: "Double owned", area: area, project: project)
        let firstDaily = Note(kind: .daily, title: "Daily A", dateKey: "2026-04-29")
        let secondDaily = Note(kind: .daily, title: "Daily B", dateKey: "2026-04-29")
        let missingEventID = Note(kind: .meeting, title: "Meeting", calendarID: "calendar-1")
        let missingCalendarID = Note(kind: .meeting, title: "Meeting", calendarEventID: "event-1")
        let unmigratedLegacy = WeeklyNote(weekKey: "2026-W18")

        context.insert(area)
        context.insert(project)
        context.insert(orphanedListNote)
        context.insert(doubleOwnedListNote)
        context.insert(firstDaily)
        context.insert(secondDaily)
        context.insert(missingEventID)
        context.insert(missingCalendarID)
        context.insert(unmigratedLegacy)
        try context.save()

        let health = try NoteMigrationService.healthCheck(in: context)

        #expect(health.canonicalDuplicateCount == 1)
        #expect(health.legacyWithoutCanonicalCount == 1)
        #expect(health.orphanedListNoteCount == 1)
        #expect(health.listNoteWithMultipleOwnersCount == 1)
        #expect(health.meetingNoteMissingEventIDCount == 1)
        #expect(health.meetingNoteMissingCalendarIDCount == 1)
        #expect(health.issueCount == 5)
    }
}
