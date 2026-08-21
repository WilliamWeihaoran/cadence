import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-223: **editing a list note's `# H1` on iOS did not rename the note**, so every row in the iOS
/// list-notes column read "Untitled" — the title each note was born with.
///
/// `CLAUDE.md` documents the behaviour as one feature in two halves ("new notes start with the title
/// as the first H1, and editing that H1 syncs back"), and iOS shipped only the first half:
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
    /// `CadenceListNoteFiling.createNote` carries the *model default* `"Untitled"` — a real string,
    /// not an empty one — and `displayTitle` was faithfully reporting it.
    ///
    /// So the fix had to write `title`, and no change to `displayTitle` would have helped: there is
    /// no fallback it could have grown that reaches the heading, because the heading lives in
    /// `content` and a fallback keyed on a blank title never fires here.
    @Test func theStoredTitleWasTheBrokenHalfNotTheFallback() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)
        let note = CadenceListNoteFiling.createNote(
            in: context,
            area: nil,
            project: project,
            order: 0
        )

        // Born titled, and titled with a real string — this is why `displayTitle` was not the bug.
        #expect(note.title == "Untitled")
        #expect(!note.title.isEmpty)
        #expect(note.displayTitle == "Untitled")
        #expect(note.content == "# Untitled\n\n")

        // The user renames the heading. This is the whole ticket.
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
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
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
