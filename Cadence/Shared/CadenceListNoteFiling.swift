import Foundation
import SwiftData

// **This file is the half of the folder convention a headless process may compile** ([[T-1122]]).
//
// It was one file with the four SwiftUI rows that draw folders — `NoteFolderSectionHeader`,
// `NoteFolderGroupList`, `NoteFolderListRow`, `NoteFolderMoveMenu` — which put SwiftUI and
// `Theme` into everything that wanted the path rule. `CadenceMCPServer` compiles *files*, not
// functions, so `create_list_note` could not reach `CadenceListNoteFiling.createNote` without
// also compiling those four views and the whole design-token file into a command-line tool.
// T-1122 recorded the refusal with that measurement and named the split as the condition that
// would lift it; this is the split. `CadenceNoteFolderSupport.swift` keeps the grouping and the
// views, and imports nothing new to do it.
//
// Nothing else moved and nothing changed shape: the rule below is byte-for-byte the one both
// platforms have been calling. `CadenceListNoteSupport` came with it from
// `CadenceNotePlanningSupport.swift` for the same reason — `createNote` calls `attach`, and that
// file reaches `MarkdownNoteTitleSync`, `NoteTemplate` and `CadenceNoteDateNavigation`, none of
// which the server target compiles.

// A note folder is a **convention over a string**, not a model. `Note.folderPath` is a plain
// `String` with a default of `""`, exactly as `TaskSectionConfig` is a convention over JSON in a
// raw column — so the convention only exists as long as every reader and writer agrees on it, and
// until T-193 the only agreement was four macOS call sites that happened to share one private
// helper.
//
// **The convention, read off `NoteFolderSheet.normalizedFolderPath` and its three co-readers rather
// than invented here:**
//
// - The separator is `/`.
// - A path carries **no leading and no trailing separator**, and no empty components: the writer
//   splits on `/`, trims each component, drops the empties and rejoins.
// - The **root is the empty string**, and so is a path that normalizes to nothing (`"/"`, `"  "`,
//   `"//"`). There is no `nil` — `Note.folderPath` is non-optional.
// - **Nesting is representable and is not a tree.** `"Planning/Research"` is a legal path (it is
//   the macOS sheet's own placeholder) but every surface groups on the *whole* normalized string,
//   so `Planning` and `Planning/Research` are two sibling groups rather than a parent and a child.
//   That is what macOS does today; `components(_:)` and `depth(_:)` exist so a future tree can be
//   built without re-deciding the storage format, and nothing reads them yet.
// - Folders apply to **`.list` notes only**. Nothing writes `folderPath` on a daily, weekly,
//   notepad or event note, and the four-tab Notes page never reads it. The callers here all pass
//   `CadenceListNoteSupport.notes(for:project:in:)`, which already filters on the kind.
//
// **Normalization happens on read as well as on write, and that is load-bearing.**
// `DataIntegrityRepairService.mergeNoteFields` copies `folderPath` from a merged duplicate with
// `fillEmptyString`, which trims to decide "unset" and then assigns the source's value **raw** —
// so a path that was never normalized can arrive from a merge, from CloudKit, or from a build
// older than the convention. `groups(for:)` normalizes every path it reads for exactly that
// reason. (In practice that merge cannot reach a list note at all: `Note.canonicalKey` is
// `"list:\(id)"`, unique per note, so two list notes are never duplicates. The read-side
// normalization is what makes that a nice-to-have rather than the thing holding the invariant up.)

// MARK: - The path convention

nonisolated enum CadenceNoteFolderPath {
    static let separator = "/"

    /// The root folder. **Exactly the empty string** — `DataIntegrityRepairService.fillEmptyString`
    /// treats a whitespace-trimmed-empty `folderPath` as "unset", so any other sentinel (`"/"`,
    /// `"Notes"`) would read as a real folder to the merge pass.
    static let root = ""

    /// What the root group is called where it has to be named. The grouped column deliberately
    /// draws **no** heading over it — see `CadenceNoteFolderGroup.showsHeader`.
    static let rootDisplayName = "Notes"

    /// Stable identity for a path, so a `ForEach` over groups has something non-empty to key on.
    static let rootID = "__root__"

    /// The one normalizer. Split on the separator, trim each component, drop the empties, rejoin.
    ///
    /// This is byte-for-byte the algorithm `ListNotesView` carried privately; it is out here so the
    /// second platform cannot arrive at a second spelling of it, and so it can be tested.
    static func normalized(_ raw: String) -> String {
        raw
            .split(separator: Character(separator))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    static func isRoot(_ path: String) -> Bool {
        normalized(path).isEmpty
    }

    /// The path's segments, outermost first. Nothing renders a tree today; this exists so the
    /// storage format does not have to be re-decided when something does.
    static func components(_ path: String) -> [String] {
        let normalized = normalized(path)
        return normalized.isEmpty ? [] : normalized.components(separatedBy: separator)
    }

    /// 0 for the root, 1 for `"Planning"`, 2 for `"Planning/Research"`.
    static func depth(_ path: String) -> Int {
        components(path).count
    }

    /// The whole path, which is what a heading shows — not the leaf. A group keyed on the whole
    /// string must be labelled with the whole string or `Planning/Research` and `Admin/Research`
    /// would draw two headings reading "Research".
    static func displayName(for path: String) -> String {
        let normalized = normalized(path)
        return normalized.isEmpty ? rootDisplayName : normalized
    }

    static func id(for path: String) -> String {
        let normalized = normalized(path)
        return normalized.isEmpty ? rootID : normalized
    }

    /// Folder order: **the root sorts last**, everything else case-insensitively ascending.
    ///
    /// Root-last is macOS's rule and it is the right way round — a heading-less run of notes reads
    /// as "the rest" at the bottom of a column and as an unlabelled mystery at the top.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        if left.isEmpty { return false }
        if right.isEmpty { return true }
        if left.caseInsensitiveCompare(right) == .orderedSame { return left < right }
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }

    /// Every distinct real folder in a set of raw paths, normalized and ordered — what a
    /// "move to folder" menu lists. The root is **not** in it: "No Folder" is its own item, not a
    /// folder you move into.
    static func names(in rawPaths: [String]) -> [String] {
        Array(Set(rawPaths.map(normalized).filter { !$0.isEmpty })).sorted(by: precedes)
    }
}

// MARK: - Filing

/// Creating a list note and moving one between folders — **the** two writers of `folderPath`.
///
/// Both platforms call these, so normalization on write has exactly one owner. macOS carried
/// `addNote(folderPath:)`, `applyFolderRequest` and `defaultNoteContent` privately; iOS would
/// otherwise have had to copy all three, and the copy is where the separator, the trimming or the
/// seeded heading drifts.
enum CadenceListNoteFiling {
    /// A new list note, filed where it was asked for.
    ///
    /// `order` is the list's current note count, which is what macOS passed — it puts a new note at
    /// the end of whichever folder it lands in, because `CadenceNoteFolderGrouping.precedes` sorts
    /// on `order` inside a group.
    ///
    /// **T-497, the existence half of the `try? save()` rule.** This inserted a note, swallowed the
    /// save and handed the note back, and both callers then *selected* it — so the editor opened on
    /// a note the store may never have taken. There is no halfway reading of that: the note either
    /// exists or it does not, and a re-render cannot repair the difference the way it repairs a
    /// field edit. `commitInsert` deletes the note again when the commit is refused, so the caller
    /// gets an error instead of a selection pointing at nothing.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    /// - Parameter title: The note's title, which is also its seeded `# H1`. Defaults to the empty
    ///   string, which is what both `+` buttons pass and what `Note.title` already held: a note
    ///   born on either platform is untitled and the editor names it from the first line typed.
    ///   **It is a parameter rather than a second write after the fact** because the two are one
    ///   rule — `MarkdownNoteTitleSync` keeps `title` equal to the first `# H1` of the body, and a
    ///   caller that set `title` itself and left `seededContent` reading the default would create
    ///   the one state that rule exists to prevent. `create_list_note` is the caller that needs it
    ///   ([[T-1122]]): `MarkdownNoteSupport.swift` is not in `CadenceMCPServer`'s Sources phase, so
    ///   that process cannot run the sync and has to be born in step instead.
    static func createNote(
        in modelContext: ModelContext,
        area: Area?,
        project: Project?,
        title: String = "",
        folderPath: String = CadenceNoteFolderPath.root,
        order: Int,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Note {
        let note = Note(kind: .list)
        CadenceListNoteSupport.attach(note, to: area, project: project)
        note.title = title
        note.order = order
        note.folderPath = CadenceNoteFolderPath.normalized(folderPath)
        note.content = seededContent(for: note.title)
        modelContext.insert(note)
        try CadencePendingChangePersistence.commitInsert(of: note, in: modelContext, commit: commit)
        return note
    }

    /// Files a note under a folder **without committing**, for the one caller that must not commit
    /// per note: `CadenceArchiveImportService`, which restores hundreds of notes and saves once for
    /// the whole import (T-1086).
    ///
    /// **The name is the contract (T-1093).** This used to be called `move`, and every interactive
    /// call site on both platforms reached for it and got a write the store never took — no
    /// `save()`, no `try?`, no persistence helper, so not one half of the `try? save()` rule could
    /// see it: there was no commit in any frame to hang a swallow on, and the row visibly changed
    /// folder on the strength of the next unrelated autosave. A door that does not commit is a fine
    /// thing for an importer to have and a trap for a view, so it says so at the call site.
    /// `noNoteFolderMoveSkipsTheCommitOutsideTheImporter` pins it to that one caller.
    ///
    /// `nonisolated` because the importer runs off the main actor. It is a pure write to one plain
    /// `String` property, so there was never anything main-actor about it — the annotation is the
    /// target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default being opted out of, not a
    /// concurrency claim being made.
    nonisolated static func fileWithoutCommitting(_ note: Note, toFolder rawPath: String) {
        note.folderPath = CadenceNoteFolderPath.normalized(rawPath)
    }

    /// Moves a note into a folder, or out of every folder when handed anything that normalizes to
    /// the root — **and commits it** (T-1093).
    ///
    /// The shape is `NoteActionSupport.move(_:toArea:modelContext:commit:)`'s, which is the same
    /// sentence about the same model: capture the field, write it, and put it back when the store
    /// refuses the commit. `commitEdit` rather than `rollback()` for the reason
    /// `CadencePendingChangePersistence.commitEdit` gives — one `ModelContext` app-wide, so a
    /// refused filing must not take the note somebody is typing in the pane beside the column.
    ///
    /// The undo restores the **raw** previous string rather than re-normalizing it. A path can
    /// arrive un-normalized from a merge or from CloudKit (see this file's header), and "nothing
    /// was changed" has to mean the bytes the note had, not a tidied version of them.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    static func move(
        _ note: Note,
        toFolder rawPath: String,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let previousFolderPath = note.folderPath
        fileWithoutCommitting(note, toFolder: rawPath)
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            note.folderPath = previousFolderPath
        }
    }

    /// A new note opens onto its own title as an H1, which is what the markdown editor keeps in
    /// step with `note.title`.
    ///
    /// **A nameless note gets an empty heading, not the word (T-733).** This used to substitute
    /// `"Untitled"` for a blank title, which was harmless only while `Note.title` defaulted to that
    /// same word: every new list note was born titled, so the branch never fired. With the stored
    /// default gone the branch became the thing that put it back — `MarkdownNoteTitleSync` reads
    /// the first line of the body and writes it to `title`, so a body seeded `# Untitled` renames
    /// the note to `Untitled` on its first commit and the repair pass clears it again on the next
    /// launch. `"# \n\n"` is still an H1, so it is still the rename control from the first
    /// keystroke; it is just empty, and an empty H1 is the one case `MarkdownNoteTitleSync`
    /// deliberately says nothing about.
    static func seededContent(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "# \(trimmed)\n\n"
    }
}

// MARK: - Attachment

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
