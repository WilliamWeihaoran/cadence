import Foundation
import SwiftData

enum CadenceCoreNoteTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case notepad = "Notepad"

    var id: Self { self }

    var noteKind: NoteKind {
        switch self {
        case .today: return .daily
        case .week: return .weekly
        case .notepad: return .permanent
        }
    }
}

/// The four standing note kinds the Notes surfaces offer as tabs — **and the one place their names
/// and their order are written down** (T-3086).
///
/// **One vocabulary, three spellings before this.** The Mac's tab strip said `Daily` / `Weekly` /
/// `Notepad` / `Event Notes` as literals on `NotesView.NotesPage.title`; its own list columns said
/// `Daily Notes` / `Weekly Notes` / `Notepad` / `Event Notes` as four more literals a few hundred
/// lines down; and mobile said `Daily` / `Weekly` / `Events` / `Pad` as a third set here. Two of the
/// four words differed on two of the three surfaces, and nothing could have caught a fourth copy.
/// `label`, `columnTitle` and `shortLabel` are those three readings with one owner, and the case
/// order below is the fourth thing that had forked.
///
/// **The order is the Mac's, and mobile moved to meet it.** `allCases` ran `today, week, events,
/// notepad` here against the Mac's `daily, weekly, notepad, meeting` — the last two tabs
/// transposed, so the same strip put Notepad third on one platform and fourth on the other. This
/// is the Mac's order; changing it moves mobile tap targets, which is why it was an owner decision
/// rather than a tidy-up.
///
/// **One set, every host.** `iOSNotesView` is the phone's Notes tab, the iPad sidebar's Notes
/// destination and the Today inspector's Notes pane, and the strip is the same in all three. It was
/// not: the Today inspector ran a separate view built on the three `CadenceCoreNoteTab` cases, so
/// Event Notes was unreachable from it. See `iOSNotesView` for why the fourth tab belongs in a pane
/// that narrow.
///
/// **Which of the two labels a surface draws is a width, not a platform.** See
/// `usesFullLabels(isRegularWidth:headerWidth:)` and `fullLabelMinimumHeaderWidth`: the iPad's
/// Notes pane reads the Mac's words, the phone reads the abbreviations, and Today's 320pt Notes
/// inspector — regular width, and narrower than the phone's row budget — reads them too. That is
/// the measurement, not a concession: the iOS guide's "iPhone and iPad share one style; they differ
/// by layout" rule is about row, chip and header *vocabulary*, and this type is that vocabulary —
/// one set of words with a documented short form, the way `TaskBundle.shortLabel` is "Block".
///
/// The first two read "Daily" and "Weekly", not "Today" and "Week". They used to name a moment
/// because the surface only had one: both notes were pinned to the current day. Now that the
/// header carries a date picker, a tab reading "Today" could sit lit up beside a title reading
/// "Aug 13" — the header contradicting itself. The tab names the *kind* of note; the date beside
/// it names which one. The case names keep the older spelling on purpose: `coreTab` maps them
/// one-for-one onto `CadenceCoreNoteTab`, and a case name is not a word anybody reads on screen.
enum CadenceNotesTabVocabulary: String, CaseIterable, Identifiable {
    case today
    case week
    case notepad
    case events

    var id: Self { self }

    /// The tab's name, in full. **These are macOS's four words, and they are the words.** The Mac's
    /// `NotesView.NotesPage.title` spelled them as its own literals; a surface with the room for
    /// them reads them from here instead, so the two cannot drift into two vocabularies again.
    var label: String {
        switch self {
        case .today: return "Daily"
        case .week: return "Weekly"
        case .notepad: return "Notepad"
        case .events: return "Event Notes"
        }
    }

    /// Nothing in `shortLabel` may exceed this, or the strip stops fitting beside the title on the
    /// narrowest supported phone. Asserted in `CadenceTests`.
    static let shortLabelCharacterBudget = 6

    /// The least header width a surface needs before it may draw `label` instead of `shortLabel`.
    ///
    /// **Measured, not chosen.** The binding case is the Notepad tab, because its title is the
    /// constant word "Notes" under a `.fixedSize()` and so cannot give ground the way a date can:
    /// "Notes" (48.2pt at 17pt bold) + 8pt of stack spacing + the 8pt `Spacer` minimum + 8pt more
    /// + the full-label strip at the regular 12pt inset (306.9pt: each label at 13pt semibold plus
    /// two insets, floored at 44, 2pt apart) + four 44pt trailing controls at 8pt spacing (new
    /// note, template, AI, export) + the header's own 14pt gutters = **615.1pt**. 620 is that with
    /// five points of slack.
    ///
    /// The *dated* tabs ask for more on paper — a week straddling two months reads "Aug 31 – Sep 6"
    /// and wants 649pt — but that title is deliberately not `fixedSize`, and `iOSNotesHeader` says
    /// outright that when the row is over budget the date is the one that may shorten and the tab
    /// strip is not. So the dated case degrades as designed; the Notepad case is the one that would
    /// push the row, and it is the one this number is cut from.
    ///
    /// **Both sides of this are live hosts.** The iPad's Notes pane is 646pt at its narrowest
    /// (an 11" iPad in portrait, 834pt less the 188pt shell sidebar) and clears it; Today's Notes
    /// inspector is 320pt at its floor — regular width, and the whole reason this is a width and
    /// not a size class. At 320 the full-label strip alone overruns the row by ~15pt, which is the
    /// pushed row this threshold exists to refuse.
    static let fullLabelMinimumHeaderWidth: CGFloat = 620

    /// The tab's name where there is not room for `label`. Deliberately *not* the note kind's name:
    /// "Event Notes" and "Notepad" are the two that do not fit beside the title on a 402pt phone,
    /// so they read "Events" and "Pad" there. **Only the label changes.** `NoteKind.meeting`'s raw
    /// value is persisted in `Note.kindRaw` and is untouched by this type.
    var shortLabel: String {
        switch self {
        case .today: return "Daily"
        case .week: return "Weekly"
        case .notepad: return "Pad"
        case .events: return "Events"
        }
    }

    /// The heading of the list column that indexes this kind. macOS's Notes page draws one above
    /// each of its four lists; iOS's index column has no heading of its own, so this is read by the
    /// Mac alone — and is here, rather than beside those lists, because it is the third spelling of
    /// the same four things and the one most likely to drift next.
    var columnTitle: String {
        switch self {
        case .today: return "Daily Notes"
        case .week: return "Weekly Notes"
        case .notepad: return "Notepad"
        case .events: return "Event Notes"
        }
    }

    /// Whether a header of this width, at this size class, has the room for `label`.
    ///
    /// **`headerWidth <= 0` means "not measured yet" and answers `false`.** This is the opposite
    /// call from `CadenceNotesListMetrics.layout`, which assumes two columns for one frame to avoid
    /// flashing the phone's form on an iPad, and the costs are what differ: guessing wrong there
    /// shows the right content in the wrong arrangement, guessing wrong here draws a strip wider
    /// than the row it sits in. A frame of "Pad" is cheaper than a frame of a pushed row.
    static func usesFullLabels(isRegularWidth: Bool, headerWidth: CGFloat) -> Bool {
        guard isRegularWidth, headerWidth > 0 else { return false }
        return headerWidth >= fullLabelMinimumHeaderWidth
    }

    /// `nil` for the one tab that is a list of notes rather than a single standing note.
    var coreTab: CadenceCoreNoteTab? {
        switch self {
        case .today: return .today
        case .week: return .week
        case .notepad: return .notepad
        case .events: return nil
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
    /// Tabs whose fetch-or-create threw, so `nil` above means "failed" rather than "not asked
    /// for yet" (T-849). Empty on every call site that predates this — `loadOrCreateCoreNotes`
    /// is the only writer.
    var failedTabs: Set<CadenceCoreNoteTab> = []

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
    ///
    /// **`nil` used to mean two different things (T-849).** `try?` on each of the three collapses
    /// "the fetch-or-create threw" into the same `nil` a caller would see if the note simply had
    /// not loaded yet — except the latter cannot happen here: `dailyNote`, `weeklyNote` and
    /// `permanentNote` all create the note on a miss, so a `nil` reaching this function is always
    /// a failure. Every caller used to read it as the harmless case anyway and showed a spinner
    /// that was never going to resolve. The three `try?`s stay — they are the simplest way to ask
    /// "did this throw" — but the hoisted overload below turns each `nil` into a named entry in
    /// `failedTabs` instead of silently discarding it, and does so per note, so one throwing fetch
    /// does not stop the other two from loading.
    static func loadOrCreateCoreNotes(
        in modelContext: ModelContext,
        dayKey: String = DateFormatters.todayKey()
    ) -> CadenceCoreNoteState {
        loadOrCreateCoreNotes(
            today: try? NoteMigrationService.dailyNote(for: dayKey, in: modelContext),
            week: try? NoteMigrationService.weeklyNote(
                for: CadenceNoteDateNavigation.weekKey(forDayKey: dayKey),
                in: modelContext
            ),
            notepad: try? NoteMigrationService.permanentNote(in: modelContext)
        )
    }

    /// The same assembly with the three fetches hoisted out, so the failure path is exercisable
    /// without a genuinely throwing `ModelContext` — an in-memory container will not reliably
    /// fail a fetch or a save on demand. Same shape as
    /// `HabitNotificationReconcileSupport.scheduleReconcile`, for the same reason: `nil` here can
    /// only mean the caller's fetch threw, because `note(for:)` below never returns `nil` on its
    /// own account.
    static func loadOrCreateCoreNotes(today: Note?, week: Note?, notepad: Note?) -> CadenceCoreNoteState {
        var state = CadenceCoreNoteState()
        state.today = today
        state.week = week
        state.notepad = notepad
        if today == nil { state.failedTabs.insert(.today) }
        if week == nil { state.failedTabs.insert(.week) }
        if notepad == nil { state.failedTabs.insert(.notepad) }
        return state
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

    /// **The shared note commit.** Every iOS editor host writes through here, and so does macOS's
    /// Today notes panel; macOS's Notes page has its own `persistEditorContentIfNeeded` because it
    /// deliberately does not save the context.
    ///
    /// `MarkdownNoteTitleSync.apply` is the T-223 fix. The `# H1` -> `note.title` rule was private
    /// to `NoteEditorPane`, so it never ran on this path and every iOS list-note row read
    /// "Untitled". It runs before the save so the rename lands in the same transaction as the body
    /// it came from, and it is a no-op for the kinds whose title is not their heading -- daily and
    /// weekly notes reaching this from `NotePanel` are unaffected.
    static func update(_ note: Note, content: String, in modelContext: ModelContext, syncTags: Bool = true) {
        note.content = content
        note.updatedAt = Date()
        MarkdownNoteTitleSync.apply(to: note, content: content)
        if syncTags {
            TagSupport.syncNoteTagsFromMarkdownCommittingInsertions(note, in: modelContext)
        }
        try? modelContext.save()
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
