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

/// The four tabs the iOS Notes surface offers, in order.
///
/// **One set, every host.** `iOSNotesView` is the phone's Notes tab, the iPad sidebar's Notes
/// destination and the Today inspector's Notes pane, and the strip is the same in all three. It was
/// not: the Today inspector ran a separate view built on the three `CadenceCoreNoteTab` cases, so
/// Event Notes was unreachable from it. See `iOSNotesView` for why the fourth tab belongs in a pane
/// that narrow.
///
/// This exists as a shared type — rather than the private enum the compact notes view used to
/// carry — because the labels have a width budget that is worth asserting on: the tab strip shares
/// one row with the back control and the word "Notes", instead of sitting on a row of its own under
/// a title that just repeated the selected tab.
///
/// `shortLabel` is deliberately *not* the note kind's name. "Event Notes" and "Notepad" are the
/// two that do not fit beside the title on a 402pt phone, so they read "Events" and "Pad" here.
/// **Only the label changes.** `NoteKind.meeting`'s raw value is persisted in `Note.kindRaw` and
/// is untouched by this type.
///
/// The first two read "Daily" and "Weekly", not "Today" and "Week". They used to name a moment
/// because the surface only had one: both notes were pinned to the current day. Now that the
/// header carries a date picker, a tab reading "Today" could sit lit up beside a title reading
/// "Aug 13" — the header contradicting itself. The tab names the *kind* of note; the date beside
/// it names which one. This is also what the macOS Notes page has always called them.
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
        case .today: return "Daily"
        case .week: return "Weekly"
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
    /// Loads the three standing notes for a given day.
    ///
    /// `dayKey` defaulted to today because for a long time it *was* today: the day was hardcoded
    /// here, which is what pinned the whole mobile Notes surface to the current date — no picker,
    /// no arrows, no way to reach yesterday except by searching for text you had already written.
    /// macOS had a calendar jump the whole time (`NotesView.NotesDateJumpButton`). The default
    /// stays so the callers that genuinely mean "now" — the macOS Today panel — read as before.
    ///
    /// The week is derived from the day rather than passed separately, so the two can never
    /// disagree about which week is on screen.
    static func loadOrCreateCoreNotes(
        in modelContext: ModelContext,
        dayKey: String = DateFormatters.todayKey()
    ) -> CadenceCoreNoteState {
        CadenceCoreNoteState(
            today: try? NoteMigrationService.dailyNote(for: dayKey, in: modelContext),
            week: try? NoteMigrationService.weeklyNote(for: CadenceNoteDateNavigation.weekKey(forDayKey: dayKey), in: modelContext),
            notepad: try? NoteMigrationService.permanentNote(in: modelContext)
        )
    }

    static func note(
        for tab: CadenceCoreNoteTab,
        in modelContext: ModelContext,
        dayKey: String = DateFormatters.todayKey()
    ) throws -> Note {
        switch tab {
        case .today:
            return try NoteMigrationService.dailyNote(for: dayKey, in: modelContext)
        case .week:
            return try NoteMigrationService.weeklyNote(for: CadenceNoteDateNavigation.weekKey(forDayKey: dayKey), in: modelContext)
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

    static func attach(_ note: Note, to area: Area?, project: Project?) {
        note.area = area
        note.project = project
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
