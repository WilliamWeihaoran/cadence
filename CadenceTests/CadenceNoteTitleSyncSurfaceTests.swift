import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-223: **editing a list note's `# H1` on iOS did not rename the note**, so every row in the iOS
/// list-notes column read "Untitled" — the title each note was born with.
///
/// `docs/CLAUDE_REFERENCE.md` documents the behaviour as one feature in two halves ("new notes
/// start with the title as the first H1, and editing that H1 syncs back"), and iOS shipped only the
/// first half:
/// `CadenceListNoteFiling.createNote` seeded `# Untitled`, and nothing on the platform ever read the
/// heading again. macOS had the second half as `NoteEditorPane.syncTitleFromH1IfNeeded` — a private
/// method on one view, containing a `hasPrefix` and a `trimmingCharacters` and nothing AppKit-shaped.
/// The fourth instance of that shape this repo has found, after `RemindersManager`,
/// `PrivacyDataResetService` and `ListDeleteHelpers`.
///
/// The rule is `MarkdownNoteTitleSync` in `Services/` now. The first half of this file pins the
/// decision directly — including the two edges a title sync has, a **deleted** H1 and a body with
/// **no** H1 — and the second half pins that both platforms' commit paths reach it, which for iOS
/// has to be a source scan: `Cadence/iOS/` is inside `#if os(iOS)` and this target builds for macOS.
@MainActor
struct CadenceNoteTitleSyncSurfaceTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    // MARK: - The rule

    /// The heading renames the note, trimmed, for the two kinds that opt in.
    @Test func theFirstH1RenamesAListOrNotepadNote() {
        #expect(
            MarkdownNoteTitleSync.title(
                from: "# Grocery list\n\n- milk",
                kind: .list,
                currentTitle: "Untitled"
            ) == "Grocery list"
        )
        #expect(
            MarkdownNoteTitleSync.title(
                from: "#    Spaced   \nbody",
                kind: .permanent,
                currentTitle: "Notepad"
            ) == "Spaced"
        )
        // A one-line body with no trailing newline is still a heading.
        #expect(
            MarkdownNoteTitleSync.title(from: "# Only line", kind: .list, currentTitle: "Untitled")
                == "Only line"
        )
    }

    /// Only `.list` and `.permanent` opt in. A daily or weekly note's title is its date key, and a
    /// `.meeting` note's header carries a real editable title field — renaming those from a heading
    /// would fight the surface that already owns the name.
    @Test func theOtherThreeKindsAreNeverRenamedByTheirHeading() {
        for kind in [NoteKind.daily, .weekly, .meeting] {
            #expect(!MarkdownNoteTitleSync.syncsTitleFromH1(kind), "\(kind) opted in")
            #expect(
                MarkdownNoteTitleSync.title(
                    from: "# Standup\n\nnotes",
                    kind: kind,
                    currentTitle: "2026-08-21"
                ) == nil
            )
        }
        #expect(MarkdownNoteTitleSync.syncsTitleFromH1(.list))
        #expect(MarkdownNoteTitleSync.syncsTitleFromH1(.permanent))
    }

    /// **The deleted-H1 edge.** Removing the heading is not a rename — the title keeps its last
    /// synced value rather than reverting or clearing.
    ///
    /// This is macOS's shipped answer and the fix carries it across unchanged. Clearing would mean a
    /// user who selects the heading and starts retyping watches the row read "Untitled" for the
    /// duration of the retype; reverting has nothing to revert to, because a note's title keeps no
    /// history. So `nil` — "the body says nothing about the name" — rather than `""`.
    @Test func deletingTheH1KeepsTheLastSyncedTitle() throws {
        let context = try makeContext()
        let note = Note(kind: .list, title: "Untitled", content: "# Grocery list\n\n- milk")
        context.insert(note)

        MarkdownNoteTitleSync.apply(to: note, content: note.content)
        #expect(note.title == "Grocery list")

        // The heading line is gone; the body it introduced is not.
        let beheaded = "\n\n- milk"
        #expect(MarkdownNoteTitleSync.title(from: beheaded, kind: .list, currentTitle: note.title) == nil)
        MarkdownNoteTitleSync.apply(to: note, content: beheaded)
        #expect(note.title == "Grocery list")
        #expect(note.displayTitle == "Grocery list")

        // Emptied rather than deleted — mid-rename, one keystroke after selecting the text.
        for midRename in ["# ", "#    ", "# \n\n- milk"] {
            MarkdownNoteTitleSync.apply(to: note, content: midRename)
            #expect(note.title == "Grocery list", "\(midRename) cleared the title")
        }
    }

    /// **The no-H1 edge, and the only-the-first-line rule.** A body that does not open with `# `
    /// says nothing about the note's name — prose, an `## H2`, a `#hashtag` with no space, a
    /// frontmatter fence, a leading blank line, and a real `# H1` further down are all silence.
    ///
    /// The last one is the one worth pinning: an `# H1` in the middle of a document is a section
    /// heading, and taking it as the title would rename a note from whatever section its author
    /// happened to write first.
    @Test func aBodyWithNoLeadingH1SaysNothingAboutTheTitle() {
        for content in [
            "",
            "just prose\n\n# Later heading",
            "## Subheading first",
            "#nospace",
            "#",
            "---\ntags: [a]\n---\n\n# Real heading",
            "\n# Heading after a blank line",
            " # Indented heading"
        ] {
            #expect(
                MarkdownNoteTitleSync.title(from: content, kind: .list, currentTitle: "Untitled") == nil,
                "\(content.debugDescription) was read as a title"
            )
        }
    }

    /// A heading that already matches the stored title is not a write. The commit paths run this on
    /// every commit, and a SwiftData assignment is a CloudKit change however equal the value is.
    @Test func aHeadingEqualToTheStoredTitleIsNotAWrite() {
        #expect(
            MarkdownNoteTitleSync.title(
                from: "# Grocery list\n\nbody",
                kind: .list,
                currentTitle: "Grocery list"
            ) == nil
        )
        // …and the comparison is against the *stored* title, untrimmed on the right-hand side only.
        #expect(
            MarkdownNoteTitleSync.title(
                from: "#   Grocery list  \n",
                kind: .list,
                currentTitle: "Grocery list"
            ) == nil
        )
    }

    // MARK: - The bug was the stored title

    /// **Which half was broken.** `Note.displayTitle` falls back to the literal `"Untitled"` for a
    /// `.list` note with a blank title, so "every row reads Untitled" has two possible causes and
    /// they need different fixes. It was the stored `title`: a note created by
    /// `CadenceListNoteFiling.createNote` carried the *model default* `"Untitled"` — a real string,
    /// not an empty one — and `displayTitle` was faithfully reporting it.
    ///
    /// So the fix had to write `title`, and no change to `displayTitle` would have helped: there is
    /// no fallback it could have grown that reaches the heading, because the heading lives in
    /// `content` and a fallback keyed on a blank title never fires here.
    ///
    /// **T-733 retired that stored default**, so a new list note is now born *blank* and the
    /// fallback is what names it. The T-223 rule this test is about is untouched by that and is
    /// asserted here in the shape it now has: born nameless, renamed by the first H1 the user
    /// types. What T-733 changed is which of the two halves is doing the naming before that
    /// keystroke — the fallback now, the stored word before.
    @Test func theStoredTitleWasTheBrokenHalfNotTheFallback() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)
        let note = try CadenceListNoteFiling.createNote(
            in: context,
            area: nil,
            project: project,
            order: 0
        )

        // Born nameless since T-733, with an empty H1 waiting for the first keystroke rather than
        // the word `Untitled` for it to land after.
        #expect(note.title.isEmpty)
        #expect(note.content == "# \n\n")
        // And the fallback is what a row reads — which is the half that was never the bug.
        #expect(note.displayTitle == "Untitled")

        // The user renames the heading. This is the whole T-223 ticket.
        CadenceCoreNoteSupport.update(note, content: "# Q3 launch checklist\n\n- ship it", in: context)
        #expect(note.title == "Q3 launch checklist")
        #expect(note.displayTitle == "Q3 launch checklist")

        // And a blank stored title still reads "Untitled" — the fallback is untouched.
        note.title = ""
        #expect(note.displayTitle == "Untitled")
    }

    /// The shared commit path is where iOS picks the rule up, so it is exercised end to end here:
    /// the same call every iOS editor host makes, against a real store.
    @Test func theSharedCommitPathRenamesTheNoteItCommits() throws {
        let context = try makeContext()
        let list = Note(kind: .list, title: "Untitled", content: "# Untitled\n\n")
        let notepad = Note(kind: .permanent, title: "Notepad", content: "")
        let daily = Note(kind: .daily, title: "", content: "", dateKey: "2026-08-21")
        for note in [list, notepad, daily] { context.insert(note) }

        CadenceCoreNoteSupport.update(list, content: "# Groceries\n\n- milk", in: context)
        CadenceCoreNoteSupport.update(notepad, content: "# Scratch\n\nthoughts", in: context)
        CadenceCoreNoteSupport.update(daily, content: "# Standup\n\nnotes", in: context)

        #expect(list.title == "Groceries")
        #expect(notepad.title == "Scratch")
        // Untouched: a daily note is named by its date, and `displayTitle` supplies that.
        #expect(daily.title.isEmpty)
        #expect(daily.displayTitle == "2026-08-21")
    }

    // MARK: - Both platforms reach it

    /// One decision, two commit paths, and **no third spelling of the `# ` test in a view**.
    ///
    /// Exact per-file counts rather than "contains", so removing *either* call site fails: macOS's
    /// Notes page has its own `persistEditorContentIfNeeded` (it deliberately does not save the
    /// context, so it cannot route through the shared update), and everything else on both platforms
    /// commits through `CadenceCoreNoteSupport.update`.
    @Test func bothCommitPathsCallTheOneRule() throws {
        try expectTitleSyncOccurrences(of: "MarkdownNoteTitleSync.apply(", at: [
            "Cadence/Shared/CadenceNotePlanningSupport.swift": 1,
            "Cadence/macOS/Views/NoteEditorPane.swift": 1
        ])

        // And nowhere else — including its own file, which declares it and does not call it.
        var callers: [String] = []
        for path in try titleSyncSwiftFiles() {
            let code = try titleSyncStrippingComments(titleSyncSource(path))
            let count = code.components(separatedBy: "MarkdownNoteTitleSync.apply(").count - 1
            guard count > 0 else { continue }
            callers.append("\(path):\(count)")
        }
        #expect(callers.sorted() == [
            "Cadence/Shared/CadenceNotePlanningSupport.swift:1",
            "Cadence/macOS/Views/NoteEditorPane.swift:1"
        ])
    }

    /// The retired private method must not come back under its old name, and the `# ` test itself
    /// has exactly two homes — neither of them a note view.
    ///
    /// `MarkdownEditorSupport` is the second home and is not a duplicate: it decides how to *style*
    /// a heading line inside the AppKit editor, which is a different question from what a document
    /// is called. Naming it here is the point — a bare "this string appears nowhere else" ban would
    /// have to be either wrong or silently excused.
    @Test func neitherPlatformKeepsItsOwnCopyOfTheRule() throws {
        var homes: [String] = []
        for path in try titleSyncSwiftFiles() {
            let code = try titleSyncStrippingComments(titleSyncSource(path))
            #expect(
                !code.contains("syncTitleFromH1"),
                "\(path) still spells the retired private method"
            )
            let count = code.components(separatedBy: "hasPrefix(\"# \")").count - 1
            guard count > 0 else { continue }
            homes.append("\(path):\(count)")
        }
        // Sorted ASCII, so `Services` precedes `macOS`.
        #expect(homes.sorted() == [
            // The rule.
            "Cadence/Services/MarkdownNoteSupport.swift:1",
            // Heading *styling* in the AppKit bridge — a different question from titling.
            "Cadence/macOS/Editor/MarkdownEditorSupport.swift:1"
        ])
    }

    /// **How iOS reaches the rule: by not writing `note.content` itself.** Every editor host on the
    /// platform commits through `CadenceCoreNoteSupport.update`, so there is no fifth surface to
    /// forget the sync on — which is exactly what `iOSNoteDetailSheet` (the editor reached from
    /// Search) was before this change: `content`, `updatedAt`, `save()` open-coded, so a note
    /// renamed from Search synced neither its title nor its inline `#tags`.
    ///
    /// Stated as **zero assignments** rather than as a list of hosts, because a list of hosts is a
    /// thing a new host is not on.
    @Test func noIOSSurfaceWritesANoteBodyWithoutTheSharedCommit() throws {
        for path in try titleSyncSwiftFiles() where path.hasPrefix("Cadence/iOS/") {
            let code = try titleSyncStrippingComments(titleSyncSource(path))
            #expect(
                code.titleSyncMatchCount(ofPattern: noteContentAssignmentPattern) == 0,
                "\(path) assigns a note body directly instead of calling CadenceCoreNoteSupport.update"
            )
        }

        // The needle is not vacuous: it matches the spelling that was there and not a read.
        #expect("note.content = content".titleSyncMatchCount(ofPattern: noteContentAssignmentPattern) == 1)
        #expect("existing.content += extra".titleSyncMatchCount(ofPattern: noteContentAssignmentPattern) == 1)
        #expect("get { note.content }".titleSyncMatchCount(ofPattern: noteContentAssignmentPattern) == 0)
        #expect("if note.content == other.content {".titleSyncMatchCount(ofPattern: noteContentAssignmentPattern) == 0)
        #expect("self.content = content()".titleSyncMatchCount(ofPattern: noteContentAssignmentPattern) == 0)

        // The four iOS hosts do reach the shared commit, so the zero above is an absence of
        // open-coding rather than an absence of editors.
        try expectTitleSyncOccurrences(of: "CadenceCoreNoteSupport.update(", at: [
            "Cadence/iOS/iOSNotesView.swift": 2,
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/iOS/iOSSearchSupportViews.swift": 1
        ])
    }

    // MARK: - The scan itself

    /// A scan that silently reads nothing passes every zero-count assertion above.
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInNoteTitleSyncSurface() throws {
        let files = try titleSyncSwiftFiles()

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Services/MarkdownNoteSupport.swift"))
        #expect(files.contains("Cadence/Shared/CadenceNotePlanningSupport.swift"))
        #expect(files.contains("Cadence/macOS/Views/NoteEditorPane.swift"))
        #expect(files.contains("Cadence/macOS/Editor/MarkdownEditorSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSNotesView.swift"))
        #expect(files.contains("Cadence/iOS/iOSSearchSupportViews.swift"))

        // Reading code, not an empty string.
        let rule = try titleSyncStrippingComments(titleSyncSource("Cadence/Services/MarkdownNoteSupport.swift"))
        #expect(rule.contains("nonisolated enum MarkdownNoteTitleSync"))
        // And the stripper really strips: this phrase is only in a doc comment.
        #expect(!rule.contains("one write path"))
    }
}

// MARK: - Source-reading helpers

// MARK: - T-733: the stored `"Untitled"` default

/// **A new note's title was pre-filled with the word `Untitled`, and typing appended to it.**
/// OBSERVED 2026-09-02 on a simulator: typing `Target` into a new note produced `UntitledTarget`.
///
/// The cause was that `Note.title` **defaulted** to the literal `"Untitled"`, so the word was
/// stored text rather than a placeholder. `NoteMigrationService.createPermanentNote` interpolated
/// that title straight into the seeded body (`"# \(title)\n\n"`), the editor put the caret at the
/// end of the heading, and the next keystroke extended the placeholder instead of replacing it.
///
/// **The decision was the user's: drop the stored default and migrate the rows that hold it.**
/// `Note.displayTitle` already falls back per kind — `"Notepad"` for `.permanent`, the date key for
/// `.daily`, `"Untitled"` for `.list` — so the default was redundant as well as in the way, and by
/// never being blank it shadowed every one of those fallbacks.
///
/// **This is the stored model default, not [[T-609]]'s sweep.** T-609 swept 32 inline
/// `isEmpty ? … : …` fallbacks at the *draw sites*, and its standing decision is that each site
/// keeps its own existing string. Nothing here re-words a draw site: `displayTitle`'s five
/// fallbacks are asserted below exactly as they were.
///
/// **The accepted cost, asserted rather than left to be discovered.** The migration also clears a
/// title someone deliberately typed as `Untitled`. The store cannot tell the two apart — they are
/// byte-for-byte the same value and the field carries no provenance — and the user was told this
/// and accepted it. `theMigrationAlsoClearsATitleAndItsMatchingHeadingAUserTypedOnPurpose` pins it
/// so that nobody narrows it later believing it was an oversight.
///
/// **T-741 widened that same accepted cost to the matching heading.** Clearing only `title` left
/// a `.list` or `.permanent` row's literal `"# Untitled"` heading in place, and
/// `MarkdownNoteTitleSync` reads that heading back on the note's very next content commit — so a
/// row this pass "fixed" wrote the word straight back into `title` at the next edit, and the
/// launch after that cleared it again: an oscillation, not a one-time cost. Fixing the heading
/// alongside the title is the same trade the paragraph above already made, one field over.
/// `aLegacyNotesRepairedTitleSurvivesItsNextContentCommit` is the reproduction, end to end.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceStoredNoteTitleDefaultTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    // MARK: - The default is gone

    /// Every kind is born blank, and `displayTitle` — untouched by this ticket — is what names it.
    @Test func aNewNoteOfEveryKindIsBornWithNoStoredTitle() {
        let kinds: [NoteKind] = [.daily, .weekly, .permanent, .list, .meeting]
        for kind in kinds {
            #expect(Note(kind: kind).title.isEmpty, "\(kind) is still born titled")
        }

        // The per-kind fallbacks, verbatim. T-609's rule is that each draw site keeps its own
        // string; this ticket moved the *default*, so these five must not have moved with it.
        #expect(Note(kind: .permanent).displayTitle == "Notepad")
        #expect(Note(kind: .list).displayTitle == "Untitled")
        #expect(Note(kind: .meeting).displayTitle == "Event Note")
        #expect(Note(kind: .daily).displayTitle == "Daily Note")
        #expect(Note(kind: .daily, dateKey: "2026-08-21").displayTitle == "2026-08-21")
        #expect(Note(kind: .weekly).displayTitle == "Weekly Note")
        #expect(Note(kind: .weekly, weekKey: "2026-W35").displayTitle == "2026-W35")
    }

    /// **The reproduction, as close as a unit test gets to the simulator.** The "New Note" button
    /// is `createPermanentNote`; the user then types into the H1 the editor seeded, and the commit
    /// path syncs the heading back to `title`.
    ///
    /// The old spelling is asserted beside the new one so the failure this closes is legible: with
    /// a seeded `# Untitled` and a caret at the end of that line, `Target` lands as `UntitledTarget`
    /// — which is the string the simulator produced, not a reconstruction of it.
    @Test func typingIntoANewNotepadNoteNoLongerExtendsAPlaceholder() throws {
        let context = try makeContext()
        let note = try NoteMigrationService.createPermanentNote(in: context)

        #expect(note.title.isEmpty)
        #expect(note.content == "# \n\n")
        #expect(note.displayTitle == "Notepad")

        // What the user types, at the caret the editor leaves them at: the end of the H1.
        let typed = note.content.replacingOccurrences(of: "# \n", with: "# Target\n")
        CadenceCoreNoteSupport.update(note, content: typed, in: context)

        #expect(note.title == "Target")
        #expect(note.displayTitle == "Target")

        // The defect, spelled out: the same keystrokes against the retired seed.
        let retiredSeed = "# Untitled\n\n"
        let retiredResult = retiredSeed.replacingOccurrences(of: "# Untitled\n", with: "# UntitledTarget\n")
        #expect(
            MarkdownNoteTitleSync.title(from: retiredResult, kind: .permanent, currentTitle: "Untitled")
                == "UntitledTarget"
        )
    }

    /// **A list note is born nameless too, and stays that way.**
    ///
    /// `CadenceListNoteFiling.seededContent` used to substitute `"Untitled"` for a blank title.
    /// That branch was unreachable while the model default was the same word, and dropping the
    /// default is exactly what would have made it fire — putting the word back through
    /// `MarkdownNoteTitleSync`, which reads the first line of the body and writes it to `title`. So
    /// the first commit would have re-titled the note `Untitled` and the load-time pass would have
    /// cleared it again on the next launch, forever. Asserted end to end rather than as a string
    /// comparison, because the loop is between three files.
    @Test func aNewListNoteIsNotRenamedBackToThePlaceholderByItsOwnSeededHeading() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)

        let note = try CadenceListNoteFiling.createNote(in: context, area: nil, project: project, order: 0)
        #expect(note.title.isEmpty)
        #expect(note.content == "# \n\n")

        // The user edits the body without touching the heading. The old seed would have named the
        // note `Untitled` here.
        CadenceCoreNoteSupport.update(note, content: "# \n\n- milk", in: context)
        #expect(note.title.isEmpty)
        #expect(note.displayTitle == "Untitled", "the row's copy is the fallback, not a stored word")

        // A real title still seeds a real heading; only the empty case changed.
        #expect(CadenceListNoteFiling.seededContent(for: "Kickoff") == "# Kickoff\n\n")
        #expect(CadenceListNoteFiling.seededContent(for: "  Kickoff  ") == "# Kickoff\n\n")
        #expect(CadenceListNoteFiling.seededContent(for: "   ") == "# \n\n")
        #expect(CadenceListNoteFiling.seededContent(for: "") == "# \n\n")
    }

    /// The default is gone from **both** places that carried it — the stored property and the
    /// initializer parameter — read as source, because a value test cannot tell a defaulted
    /// parameter from a stored default and this ticket is about both.
    @Test func neitherTheStoredPropertyNorTheInitializerStillTypesTheDefault() throws {
        let raw = try titleSyncSource("Cadence/Models/Note.swift")
        let code = try titleSyncStrippingComments(raw)
        #expect(code != raw, "non-vacuity: Note.swift carries no comments to strip")
        #expect(code.contains("@Model final class Note"), "non-vacuity: wrong file read")

        let dense = code.filter { !$0.isWhitespace }
        #expect(dense.contains("vartitle:String=\"\""), "the stored default is not the empty string")
        #expect(!dense.contains("vartitle:String=\"Untitled\""), "the stored default is back")
        #expect(!dense.contains("title:String=\"Untitled\","), "the initializer default is back")

        // And the same for the one factory that spelled it itself.
        let migration = try titleSyncStrippingComments(
            titleSyncSource("Cadence/Services/NoteMigrationService.swift")
        ).filter { !$0.isWhitespace }
        #expect(migration.contains("createPermanentNote(incontext:ModelContext,title:String=\"\")"))

        // The fallbacks stay in `displayTitle` — the word is allowed there, and only there, in this
        // file. Exactly one occurrence, so a fourth kind quietly gaining it is a failure.
        #expect(code.components(separatedBy: "\"Untitled\"").count - 1 == 1)
    }

    // MARK: - The load-time migration

    /// **Rows already on disk hold the word, and a property default cannot reach them.** A default
    /// is applied by the initializer, so it changes what *this* build creates and nothing else;
    /// there is no `SchemaMigrationPlan` in this project and this needs none, because no column is
    /// added, removed or retyped. It is a data edit at load, in the pass that already runs at every
    /// launch.
    @Test func theLoadTimePassClearsARowStillHoldingTheRetiredDefault() throws {
        let context = try makeContext()
        let legacy = Note(kind: .permanent, title: "Untitled", content: "# Untitled\n\nthoughts")
        let named = Note(kind: .list, title: "Grocery list", content: "# Grocery list\n\n- milk")
        context.insert(legacy)
        context.insert(named)
        try context.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")

        #expect(report.defaultNoteTitlesCleared == 1)
        #expect(report.changed)
        #expect(legacy.title.isEmpty)
        #expect(legacy.displayTitle == "Notepad")
        #expect(named.title == "Grocery list", "a real title is not a default")
    }

    /// **Idempotent by construction, not by a marker.** The predicate is "this title is exactly the
    /// retired default" and the edit makes it the empty string, which is not that literal — so the
    /// second run matches nothing. That is the whole argument: there is no "already migrated" flag
    /// to get out of step with the store, so a second launch, a second device, or a row that
    /// arrives from CloudKit after the pass ran all reach the same fixed point.
    ///
    /// Asserted as *no second write* rather than as "the title is still empty", which the run that
    /// cleared it a second time would also satisfy.
    @Test func runningTheMigrationTwiceIsAnEmptySecondPass() throws {
        let context = try makeContext()
        let legacy = Note(kind: .list, title: "Untitled", content: "")
        context.insert(legacy)
        try context.save()

        let first = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test-first")
        #expect(first.defaultNoteTitlesCleared == 1)
        #expect(first.changed)

        let second = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test-second")
        #expect(second.defaultNoteTitlesCleared == 0)
        #expect(second.changed == false, "the second pass found work to do")
        #expect(legacy.title.isEmpty)

        // A third, for the same reason a second is not enough on its own: the fixed point has to be
        // a fixed point, not an alternation.
        let third = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test-third")
        #expect(third.defaultNoteTitlesCleared == 0)
        #expect(third.changed == false)
    }

    /// **The literal, matched untrimmed and case-sensitively.** Everything here is a string a
    /// person typed; only the exact bytes the retired initializer wrote are the pass's business.
    @Test func theMigrationClearsOnlyTheExactRetiredLiteral() throws {
        let context = try makeContext()
        let survivors = [
            Note(kind: .list, title: " Untitled ", content: ""),
            Note(kind: .list, title: "untitled", content: ""),
            Note(kind: .list, title: "UNTITLED", content: ""),
            Note(kind: .list, title: "Untitled notes", content: ""),
            Note(kind: .list, title: "Untitled Task", content: ""),
            Note(kind: .list, title: "", content: "")
        ]
        for note in survivors { context.insert(note) }
        try context.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")

        #expect(report.defaultNoteTitlesCleared == 0)
        #expect(survivors.map(\.title) == [
            " Untitled ", "untitled", "UNTITLED", "Untitled notes", "Untitled Task", ""
        ])
    }

    /// **The accepted cost, pinned so it cannot be quietly narrowed.**
    ///
    /// A note whose title the user deliberately typed as `Untitled` is cleared too. There is no
    /// provenance on the field — the deliberate title and the one the old default wrote are the
    /// same six-and-two bytes — so no predicate can separate them, and the user was told this and
    /// accepted it rather than being handed a narrower rule that would miss real rows.
    ///
    /// What such a user loses is small and visible: a list note still reads `Untitled`, because
    /// that is `displayTitle`'s own fallback for the kind, and retyping the title restores it.
    @Test func theMigrationAlsoClearsATitleAndItsMatchingHeadingAUserTypedOnPurpose() throws {
        let context = try makeContext()
        // Indistinguishable from a default-titled row by construction: same six-and-two bytes as
        // the retired default, in both `title` and the heading it was interpolated into.
        let deliberate = Note(kind: .list, title: "Untitled", content: "# Untitled\n\nan essay about names")
        context.insert(deliberate)
        try context.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")

        #expect(report.defaultNoteTitlesCleared == 1)
        #expect(deliberate.title.isEmpty, "the accepted cost stopped being paid — was this narrowed?")
        #expect(deliberate.displayTitle == "Untitled", "and the row still reads the same word")
        // **T-741 widened the accepted cost to the heading too.** Leaving it alone did not avoid
        // touching the body — it guaranteed the note's next content commit would read this exact
        // line and write "Untitled" straight back into the field just cleared above.
        #expect(
            deliberate.content == "# \n\nan essay about names",
            "the matching heading survived, so the next content commit will put the title back"
        )
    }

    /// **T-741, end to end.** A pre-T-733 row carries the retired default in two places — the
    /// stored `title` and the literal `"# Untitled"` heading the old seed interpolated it into.
    /// Clearing only the first repaired nothing: `MarkdownNoteTitleSync` reads the second back on
    /// the note's very next content commit and writes the word straight into the field the pass
    /// just cleared, so the next launch clears it again, forever. This is the reproduction the
    /// ticket asked for — pre-T-733 data, built as a fixture rather than assumed — through the
    /// same three files (`Note`, `DataIntegrityRepairService`, `MarkdownNoteTitleSync`) the sibling
    /// test above names for the *new*-note path this one's fix cannot reach.
    @Test func aLegacyNotesRepairedTitleSurvivesItsNextContentCommit() throws {
        let context = try makeContext()
        let legacy = Note(kind: .list, title: "Untitled", content: "# Untitled\n\n- milk")
        context.insert(legacy)
        try context.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
        #expect(report.defaultNoteTitlesCleared == 1)
        #expect(legacy.title.isEmpty)
        // The repair blanked the matching heading too — the fixture for the edit below has to
        // build on *this* content, not the pre-repair one, or it just retypes "Untitled" itself.
        #expect(legacy.content == "# \n\n- milk")

        // The edit the ticket describes: the user touches the body, not the heading.
        CadenceCoreNoteSupport.update(legacy, content: legacy.content + "\n- eggs", in: context)

        #expect(legacy.title.isEmpty, "the next content commit put the retired default back")
        #expect(legacy.displayTitle == "Untitled", "and the row still reads the same word either way")

        // And the fixed point holds under a second launch, with no further edits: the pre-T-741
        // failure was that this alternated forever.
        let second = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test-second")
        #expect(second.defaultNoteTitlesCleared == 0, "nothing left to clear — the row is not oscillating")
        #expect(legacy.title.isEmpty)
    }

    /// A store with nothing wrong is left alone, which is the property every pass in this service
    /// has to keep: `performStartupMaintenance` only saves when something changed, so a pass that
    /// reports work it did not do writes to CloudKit on every launch.
    @Test func aStoreWithNoRetiredDefaultsReportsNoChange() throws {
        let context = try makeContext()
        let note = Note(kind: .permanent, title: "", content: "# \n\n")
        context.insert(note)
        try context.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
        #expect(report.defaultNoteTitlesCleared == 0)
        #expect(report.changed == false)
    }
}

private extension String {
    func titleSyncMatchCount(ofPattern pattern: String) -> Int {
        var count = 0
        var searchRange = startIndex..<endIndex
        while let found = range(of: pattern, options: .regularExpression, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<endIndex
        }
        return count
    }
}

/// Matches an **assignment** to a `.content` property whose receiver is a note-ish identifier —
/// `=` or `+=`, with `==` excluded by the lookahead.
///
/// Scoped by receiver rather than by the bare `.content`, because `iOSChoicePicker` and
/// `iOSSettingsComponents` each hold a `self.content = content()` for a `@ViewBuilder` closure and
/// those are not note bodies. Same lesson as T-227/T-233: the claim is about structure, so the
/// needle has to be.
private let noteContentAssignmentPattern = "\\b(note|existing|target|draft)\\.content\\s*\\+?=(?!=)"

private func expectTitleSyncOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try titleSyncStrippingComments(titleSyncSource(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func titleSyncRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`, for the reason
/// `CadenceNoteFolderSurfaceTests` records: `#filePath` can name the repo through a symlinked
/// prefix (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and
/// the literal does not, and the resulting empty read passes every zero-count assertion.
private func titleSyncSwiftFiles() throws -> [String] {
    let directory = titleSyncRepositoryRoot().appendingPathComponent("Cadence")
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "Cadence/\(relativePath)"
    }
}

private func titleSyncSource(_ relativePath: String) throws -> String {
    try String(contentsOf: titleSyncRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func titleSyncStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
