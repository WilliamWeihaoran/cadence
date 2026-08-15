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

    /// The label the mobile notes header uses now that the tab strip shares one row with the
    /// page title. See `CadenceMobileNotesTab.shortLabel` for why these are shorter than
    /// `compactTitle`.
    var shortLabel: String {
        CadenceMobileNotesTab(coreTab: self).shortLabel
    }

    var noteKind: NoteKind {
        switch self {
        case .today: return .daily
        case .week: return .weekly
        case .notepad: return .permanent
        }
    }
}

/// The four tabs the mobile Notes screen offers, in order.
///
/// This exists as a shared type — rather than the private enum the compact notes view used to
/// carry — because the labels have a width budget that is worth asserting on: the tab strip now
/// shares one row with the back control and the word "Notes", instead of sitting on a row of its
/// own under a title that just repeated the selected tab.
///
/// `shortLabel` is deliberately *not* the note kind's name. "Event Notes" and "Notepad" are the
/// two that do not fit beside the title on a 402pt phone, so they read "Events" and "Pad" here.
/// **Only the label changes.** `NoteKind.meeting`'s raw value is persisted in `Note.kindRaw` and
/// is untouched by this type.
enum CadenceMobileNotesTab: String, CaseIterable, Identifiable {
    case today
    case week
    case events
    case notepad

    var id: Self { self }

    /// Nothing here may exceed this, or the strip stops fitting beside the title on the narrowest
    /// supported phone. Asserted in `CadenceTests`.
    static let shortLabelCharacterBudget = 6

    var shortLabel: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .events: return "Events"
        case .notepad: return "Pad"
        }
    }

    /// `nil` for the one tab that is a list of notes rather than a single standing note.
    var coreTab: CadenceCoreNoteTab? {
        switch self {
        case .today: return .today
        case .week: return .week
        case .events: return nil
        case .notepad: return .notepad
        }
    }

    init(coreTab: CadenceCoreNoteTab) {
        switch coreTab {
        case .today: self = .today
        case .week: self = .week
        case .notepad: self = .notepad
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

    /// Returns `nil` — having created nothing — when the store could not be read.
    ///
    /// `(try? fetch(…)) ?? []` would make a failed read indistinguishable from a store holding no
    /// notes, and the two mean opposite things here: the second says "create this list's note",
    /// the first says "I cannot tell whether one exists". Acting on the wrong one writes a *second*
    /// list note, and because the panel shows the first match, the user opens their list to a blank
    /// page with their writing still on disk behind it. This is the reasoning
    /// `CadenceTaskMutationSupport.deleteTasks` spells out at length; the caller shows its loading
    /// state instead, which is recoverable.
    static func firstOrCreateNote(for area: Area?, project: Project?, in modelContext: ModelContext) -> Note? {
        let descriptor = FetchDescriptor<Note>()
        guard let fetchedNotes = try? modelContext.fetch(descriptor) else { return nil }
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

enum CadenceNoteTemplateInsertionSupport {
    static func contentByApplying(_ template: NoteTemplate, to currentContent: String) -> String {
        let trimmed = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return template.body }
        return trimmed + "\n\n" + template.body
    }

    static func apply(_ template: NoteTemplate, to note: Note, in modelContext: ModelContext) {
        CadenceCoreNoteSupport.update(
            note,
            content: contentByApplying(template, to: note.content),
            in: modelContext
        )
    }
}
