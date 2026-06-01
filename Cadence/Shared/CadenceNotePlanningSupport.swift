import Foundation
import SwiftData

enum CadenceCoreNoteTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case notepad = "Notepad"

    var id: Self { self }

    var compactTitle: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .notepad: return "Notepad"
        }
    }

    var subtitle: String {
        switch self {
        case .today:
            guard let today = DateFormatters.date(from: DateFormatters.todayKey()) else {
                return "Today"
            }
            return DateFormatters.longDate.string(from: today)
        case .week:
            return DateFormatters.weekLabel(from: DateFormatters.currentWeekKey())
        case .notepad:
            return "Permanent notes"
        }
    }
}

struct CadenceCoreNoteState {
    var today: Note?
    var week: Note?
    var notepad: Note?

    func note(for tab: CadenceCoreNoteTab) -> Note? {
        switch tab {
        case .today: return today
        case .week: return week
        case .notepad: return notepad
        }
    }
}

enum CadenceCoreNoteSupport {
    static func loadOrCreateCoreNotes(in modelContext: ModelContext) -> CadenceCoreNoteState {
        CadenceCoreNoteState(
            today: try? NoteMigrationService.dailyNote(for: DateFormatters.todayKey(), in: modelContext),
            week: try? NoteMigrationService.weeklyNote(for: DateFormatters.currentWeekKey(), in: modelContext),
            notepad: try? NoteMigrationService.permanentNote(in: modelContext)
        )
    }

    static func note(for tab: CadenceCoreNoteTab, in modelContext: ModelContext) throws -> Note {
        switch tab {
        case .today:
            return try NoteMigrationService.dailyNote(for: DateFormatters.todayKey(), in: modelContext)
        case .week:
            return try NoteMigrationService.weeklyNote(for: DateFormatters.currentWeekKey(), in: modelContext)
        case .notepad:
            return try NoteMigrationService.permanentNote(in: modelContext)
        }
    }

    static func update(_ note: Note, content: String, in modelContext: ModelContext, syncTags: Bool = true) {
        note.content = content
        note.updatedAt = Date()
        if syncTags {
            TagSupport.syncNoteTagsFromMarkdown(note, in: modelContext)
        }
        try? modelContext.save()
    }
}

enum CadenceListNoteSupport {
    static func notes(for area: Area?, project: Project?, in notes: [Note]) -> [Note] {
        if let area {
            return notes.filter { $0.kind == .list && $0.area?.id == area.id }
        }
        if let project {
            return notes.filter { $0.kind == .list && $0.project?.id == project.id }
        }
        return []
    }

    static func firstOrCreateNote(for area: Area?, project: Project?, in modelContext: ModelContext) -> Note? {
        let descriptor = FetchDescriptor<Note>()
        let fetchedNotes = (try? modelContext.fetch(descriptor)) ?? []
        if let existing = notes(for: area, project: project, in: fetchedNotes).first {
            return existing
        }

        guard area != nil || project != nil else { return nil }
        let created = Note(kind: .list, title: defaultTitle(for: area, project: project))
        attach(created, to: area, project: project)
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    static func attach(_ note: Note, to area: Area?, project: Project?) {
        note.area = area
        note.project = project
    }

    static func defaultTitle(for area: Area?, project: Project?) -> String {
        area?.name ?? project?.name ?? "Untitled Note"
    }
}
