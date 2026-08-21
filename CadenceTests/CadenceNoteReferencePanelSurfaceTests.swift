import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-192: `NoteReferenceResolver` is shared, unguarded and platform-independent, and until now only
/// macOS asked it anything. iOS could *follow* a `[[link]]` into a sheet but a note could not tell
/// you what pointed back at it, so the same note answered "what links here" on a Mac and shrugged on
/// a phone.
///
/// **Two kinds of test here, and the second kind is the point.** The first half pins the new pure
/// decisions — which sections a panel offers, in what order, and what a chip says — plus the two
/// resolution properties the panel inherits rather than re-implements. The second half reads the real
/// source files and fails the moment iOS grows its own `NoteReferenceParser.noteReferences(...)`
/// beside the resolver, or a host stops handing the editor the note it is editing. The resolver was
/// already well covered by `NoteReferenceSupportTests` (id-over-title preference, title backlinks,
/// stable-id backlinks, the case-insensitive `[[Task:` form); what was never covered is anybody
/// *calling* it from iOS, which is exactly the shape of this gap.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The helpers follow `CadenceGoalListLinkSurfaceTests` and `CadenceSharedTaskRowJobsTests` — exact
/// per-file counts rather than "contains", comment-stripping rather than allowlisting, and a
/// non-vacuity test so a broken scan cannot make the absence assertions pass silently.
@MainActor
struct CadenceNoteReferencePanelSurfaceTests {

    // MARK: - Fixtures

    private func note(_ title: String, kind: NoteKind = .list, content: String = "") -> Note {
        Note(kind: kind, title: title, content: content)
    }

    // MARK: - The premise

    /// The ticket's first claim, asserted rather than assumed: the resolver has no platform in it.
    /// If a `#if os(` ever appears in this file, the panel's shared half stops being shared and the
    /// scan below is measuring the wrong thing.
    @Test func theResolverIsPlatformIndependent() throws {
        let source = try sourceFile("Cadence/Services/NoteReferenceSupport.swift")

        #expect(!source.contains("#if os("))
        #expect(!source.contains("import SwiftUI"))
        #expect(!source.contains("import AppKit"))
        #expect(!source.contains("import UIKit"))
    }

    // MARK: - Which sections a panel offers

    /// The three labels are the vocabulary macOS's `NoteReferenceStrip` already draws. They live
    /// beside the resolver so the second panel cannot rename one of them.
    @Test func theSectionsCarryTheVocabularyBothPanelsDraw() throws {
        // Both panels read it, and neither spells it. macOS's strip carried these three literals
        // until the second panel existed to disagree with them.
        let desktop = try strippingComments(sourceFile("Cadence/macOS/Views/NoteReferenceSupportViews.swift"))
        #expect(desktop.components(separatedBy: "NoteReferencePanelSection.").count - 1 == 6)
        #expect(!desktop.contains("\"Linked Notes\""))
        #expect(!desktop.contains("\"Task References\""))
        #expect(!desktop.contains("\"Backlinks\""))
        #expect(!desktop.contains("\"arrow.uturn.backward.circle\""))

        // The iOS panel takes the same route to the same three strings.
        let mobile = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift"))
        #expect(mobile.contains("label: section.label"))
        #expect(mobile.contains("systemImage: section.systemImage"))
        #expect(!mobile.contains("\"Backlinks\""))

        #expect(NoteReferencePanelSection.allCases == [.linkedNotes, .taskReferences, .backlinks])
        #expect(NoteReferencePanelSection.linkedNotes.label == "Linked Notes")
        #expect(NoteReferencePanelSection.taskReferences.label == "Task References")
        #expect(NoteReferencePanelSection.backlinks.label == "Backlinks")
        #expect(NoteReferencePanelSection.linkedNotes.systemImage == "doc.text")
        #expect(NoteReferencePanelSection.taskReferences.systemImage == "checkmark.circle")
        #expect(NoteReferencePanelSection.backlinks.systemImage == "arrow.uturn.backward.circle")
    }

    /// An empty section is not drawn as an empty section: a note with no backlinks says nothing
    /// about backlinks rather than reserving a band to say "none".
    @Test func onlyTheSectionsWithSomethingInThemAreOffered() {
        let target = note("Target")
        let task = AppTask(title: "Ship it")

        #expect(NoteReferencePanelContents().sections.isEmpty)
        #expect(NoteReferencePanelContents().isEmpty)

        #expect(NoteReferencePanelContents(backlinks: [target]).sections == [.backlinks])
        #expect(NoteReferencePanelContents(linkedTasks: [task]).sections == [.taskReferences])
        #expect(
            NoteReferencePanelContents(linkedNotes: [target], linkedTasks: [task], backlinks: [target])
                .sections == [.linkedNotes, .taskReferences, .backlinks]
        )
        #expect(!NoteReferencePanelContents(linkedNotes: [target]).isEmpty)
    }

    // MARK: - What the panel resolves to

    /// The whole panel out of one call, and every array of it comes from the resolver.
    @Test func onePassAnswersBothDirectionsAndTheTasks() {
        let target = note("Weekly Review", kind: .weekly, content: "Points at [[Project Brief]] and [[task:Ship it]].")
        let brief = note("Project Brief")
        let source = note("Standup", content: "Decided in [[Weekly Review]].")
        let unrelated = note("Other", content: "[[Someone Else]]")
        let task = AppTask(title: "Ship it")

        let contents = NoteReferencePanelSupport.contents(
            for: target,
            content: target.content,
            notes: [brief, source, unrelated, target],
            tasks: [task]
        )

        #expect(contents.linkedNotes.map(\.id) == [brief.id])
        #expect(contents.linkedTasks.map(\.id) == [task.id])
        #expect(contents.backlinks.map(\.id) == [source.id])
        #expect(contents.sections == [.linkedNotes, .taskReferences, .backlinks])
    }

    /// `content` is a separate argument because an editor's buffer runs ahead of `note.content`
    /// between commits, and the panel describes the text on screen.
    @Test func thePanelDescribesTheTextItIsGivenNotTheStoredNote() {
        let target = note("Target", content: "[[Project Brief]]")
        let brief = note("Project Brief")

        let stale = NoteReferencePanelSupport.contents(
            for: target,
            content: "",
            notes: [brief, target],
            tasks: []
        )

        #expect(stale.linkedNotes.isEmpty)
        #expect(stale.isEmpty)
    }

    /// **The ambiguous title-only reference, and the answer is macOS's answer.** `[[Notes]]` with two
    /// notes called "Notes" resolves to the first of them in the array the panel was handed — the
    /// resolver's `first(where:)`, unchanged — and it resolves *once*, not once per candidate. The
    /// panel does not get to flag it, offer a choice, or list both: this is inherited behaviour, and
    /// a second opinion about it would be a second answer for the same markdown.
    @Test func anAmbiguousTitleOnlyReferenceResolvesToTheFirstMatchLikeMacOS() {
        let target = note("Target", content: "See [[Standup]].")
        let firstStandup = note("Standup")
        let secondStandup = note("Standup")

        let contents = NoteReferencePanelSupport.contents(
            for: target,
            content: target.content,
            notes: [firstStandup, secondStandup, target],
            tasks: []
        )

        #expect(contents.linkedNotes.map(\.id) == [firstStandup.id])

        // And the other way round: the same reference, the same two candidates, the order of the
        // array is what picks. Nothing in the panel breaks the tie.
        let reversed = NoteReferencePanelSupport.contents(
            for: target,
            content: target.content,
            notes: [secondStandup, firstStandup, target],
            tasks: []
        )

        #expect(reversed.linkedNotes.map(\.id) == [secondStandup.id])
    }

    /// A stale title-only reference — the note it named is gone or renamed — is simply absent from the
    /// panel. It is not drawn as a broken chip, because macOS does not draw one either.
    @Test func anUnresolvableReferenceIsAbsentRatherThanBroken() {
        let target = note("Target", content: "See [[Deleted Note]] and [[task:Deleted Task]].")

        let contents = NoteReferencePanelSupport.contents(
            for: target,
            content: target.content,
            notes: [target],
            tasks: [AppTask(title: "Something else")]
        )

        #expect(contents.isEmpty)
        #expect(contents.sections.isEmpty)
    }

    /// The id-backed form outranks the title in the panel too, because it is the same resolver: a
    /// renamed target still reaches its chip, and the chip reads the *current* name.
    @Test func anIDBackedReferenceSurvivesARename() throws {
        let targetID = try #require(UUID(uuidString: "77777777-7777-7777-7777-777777777777"))
        let renamed = Note(id: targetID, kind: .list, title: "New name")
        let decoy = note("Old name")
        let source = note("Source", content: "See [[note:\(targetID.uuidString)|Old name]].")

        let contents = NoteReferencePanelSupport.contents(
            for: source,
            content: source.content,
            notes: [decoy, renamed, source],
            tasks: []
        )

        #expect(contents.linkedNotes.map(\.id) == [targetID])
        #expect(contents.linkedNotes.first?.displayTitle == "New name")
    }

    /// A note's own self-reference is not a backlink and not a linked note. Both directions exclude
    /// the subject, and the panel gets that for free by passing the id through.
    @Test func aNoteIsNeverItsOwnReference() {
        let target = note("Target", content: "See [[Target]].")

        let contents = NoteReferencePanelSupport.contents(
            for: target,
            content: target.content,
            notes: [target],
            tasks: []
        )

        #expect(contents.isEmpty)
    }

    /// Backlinks are matched on `displayTitle`, which is what macOS's editor pane passes — a daily
    /// note's title is its date key, and `[[2026-08-21]]` is a link a user can reasonably write.
    @Test func aDatedNoteIsReachableByTheTitleItActuallyShows() {
        let daily = Note(kind: .daily, title: "", dateKey: "2026-08-21")
        let source = note("Standup", content: "Carried over from [[2026-08-21]].")

        #expect(daily.displayTitle == "2026-08-21")

        let contents = NoteReferencePanelSupport.contents(
            for: daily,
            content: daily.content,
            notes: [source, daily],
            tasks: []
        )

        #expect(contents.backlinks.map(\.id) == [source.id])
    }

    // MARK: - What a chip says

    /// `.meeting` keeps its raw value because it is persisted, so `rawValue.capitalized` says
    /// "Meeting" — the retired name of the tab. One spelling, and it is the current one.
    @Test func theNoteKindLabelUsesTheAppsCurrentVocabulary() {
        #expect(NoteReferencePanelSupport.noteKindLabel(.daily) == "Daily note")
        #expect(NoteReferencePanelSupport.noteKindLabel(.weekly) == "Weekly note")
        #expect(NoteReferencePanelSupport.noteKindLabel(.permanent) == "Notepad")
        #expect(NoteReferencePanelSupport.noteKindLabel(.list) == "List note")
        #expect(NoteReferencePanelSupport.noteKindLabel(.meeting) == "Event note")
        #expect(NoteReferencePanelSupport.noteKindLabel(.meeting) != NoteKind.meeting.rawValue.capitalized)
    }

    @Test func aReferencedTaskFallsBackToWhereItActuallyIs() {
        let context = Context(name: "Work")
        let area = Area(name: "Documents", context: context)
        let filed = AppTask(title: "Draft")
        filed.area = area

        #expect(NoteReferencePanelSupport.taskFallbackSubtitle(filed) == "Documents")

        let loose = AppTask(title: "Loose end")
        #expect(NoteReferencePanelSupport.taskFallbackSubtitle(loose) == "Inbox")

        let done = AppTask(title: "Finished")
        done.status = .done
        #expect(NoteReferencePanelSupport.taskFallbackSubtitle(done) == "Completed")
    }

    /// The deadline wins the subtitle when there is one — the panel calls the same helper macOS's
    /// chip does, and this pins the two decisions it makes with the answer.
    @Test func theDeadlineOutranksTheContainerOnAReferencedTask() {
        let todayKey = "2026-08-21"
        let context = Context(name: "Work")
        let area = Area(name: "Documents", context: context)
        let overdue = AppTask(title: "Late")
        overdue.area = area
        overdue.dueDate = "2026-08-19"

        #expect(CadenceFocusSupport.dueLabel(forDueDateKey: overdue.dueDate, todayKey: todayKey) != nil)
        #expect(overdue.isOverdue(todayKey: todayKey))

        let undated = AppTask(title: "Whenever")
        undated.area = area
        #expect(CadenceFocusSupport.dueLabel(forDueDateKey: undated.dueDate, todayKey: todayKey) == nil)
        #expect(!undated.isOverdue(todayKey: todayKey))
    }

    // MARK: - The call sites

    /// **The half that closes the ticket.** The resolver was already right; nothing on iOS asked it.
    ///
    /// `NoteReferenceResolver.backlinks(` — with the `(`, because `backlinks:` is also the label of an
    /// argument at two of macOS's call sites and a bare `backlinks` count would include those.
    @Test func backlinksAreResolvedInExactlyThreePlaces() throws {
        var offenders: [String] = []
        for path in try swiftFiles(under: "Cadence") {
            let code = try strippingComments(sourceFile(path))
            let count = code.components(separatedBy: "NoteReferenceResolver.backlinks(").count - 1
            guard count > 0 else { continue }
            offenders.append("\(path):\(count)")
        }

        #expect(offenders.sorted() == [
            // The panel support, which is what iOS reaches.
            "Cadence/Services/MCPReadOnly/CadenceReadService.swift:1",
            "Cadence/Services/NoteReferenceSupport.swift:1",
            "Cadence/macOS/Views/NoteEditorPane.swift:1"
        ])
    }

    /// iOS resolves through `NoteReferencePanelSupport`, and `NoteReferencePanelSupport` is the
    /// resolver and nothing else. Exact counts, not "contains": reverting *one* of these three lines
    /// has to fail.
    @Test func thePanelSupportIsTheResolverAndTheEditorCallsIt() throws {
        try expectOccurrences(of: "NoteReferenceResolver.linkedNotes(", at: [
            "Cadence/Services/NoteReferenceSupport.swift": 1,
            "Cadence/Services/MCPReadOnly/CadenceReadService.swift": 1,
            "Cadence/macOS/Views/NoteEditorPane.swift": 1
        ])
        try expectOccurrences(of: "NoteReferenceResolver.linkedTasks(", at: [
            "Cadence/Services/NoteReferenceSupport.swift": 1,
            "Cadence/Services/MCPReadOnly/CadenceReadService.swift": 1,
            "Cadence/macOS/Views/NoteEditorPane.swift": 1
        ])

        try expectOccurrences(of: "NoteReferencePanelSupport.contents(", at: [
            "Cadence/iOS/iOSMarkdownEditingSurface.swift": 1
        ])
    }

    /// **No second derivation on iOS.** The parsers are reachable from the iOS target and it would be
    /// three lines to walk `[[…]]` again in a view; that is how the resolution rules would come to
    /// disagree with the ones `NoteReferenceSupportTests` pins. iOS may *write* reference markdown —
    /// that is the completion strip and the picker — and may not read it.
    @Test func iOSNeverDerivesReferencesItself() throws {
        var offenders: [String] = []
        for path in try swiftFiles(under: "Cadence/iOS") {
            let code = try strippingComments(sourceFile(path))
            for needle in [
                "NoteReferenceParser.noteReferences(",
                "NoteReferenceParser.taskReferences(",
                "NoteReferenceResolver."
            ] where code.contains(needle) {
                offenders.append("\(path) → \(needle)")
            }
        }

        #expect(offenders.isEmpty)
    }

    /// The panel is a view that exists, and the editor surface renders it. One call site: the panel
    /// belongs to the editor, not to each of the hosts, so a new note surface gets it by construction.
    @Test func theEditorSurfaceRendersOnePanel() throws {
        try expectOccurrences(of: "struct iOSNoteReferencePanel", at: [
            "Cadence/iOS/iOSMarkdownAccessoryViews.swift": 1
        ])
        try expectOccurrences(of: "iOSNoteReferencePanel(", at: [
            "Cadence/iOS/iOSMarkdownEditingSurface.swift": 1
        ])
    }

    /// **The panel reuses the strip that carries the `D-104` fix.** A note-reference chip and a `[[`
    /// completion suggestion sit in the same band of the same editor, so they are the same strip and
    /// the same pill — which also means the panel cannot inherit a page's 100pt bottom clearance into
    /// a 56pt viewport, because the reset is inside the thing it is built from.
    @Test func thePanelIsBuiltFromTheStripThatAlreadyResetsItsScrollMargins() throws {
        let accessories = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift"))

        // One strip type, one margin reset, and the panel is one of the strip's three callers.
        #expect(accessories.components(separatedBy: "struct iOSMarkdownSuggestionStrip").count - 1 == 1)
        #expect(accessories.components(separatedBy: ".contentMargins(.vertical, 0, for: .scrollContent)").count - 1 == 2)
        #expect(accessories.components(separatedBy: "iOSMarkdownSuggestionStrip(").count - 1 == 3)
        #expect(accessories.components(separatedBy: "iOSMarkdownSuggestionPill(").count - 1 == 4)

        // No second horizontal scroll view smuggled in beside them: the two `ScrollView(` in this
        // file are the picker sheet's vertical list and the strip's own row.
        #expect(accessories.components(separatedBy: "ScrollView(").count - 1 == 2)
    }

    /// The overdue deadline and the section accents are read from the shared vocabularies rather than
    /// spelled again: the same due-label helper macOS's chip calls, and `Theme` for every colour.
    @Test func thePanelBorrowsTheDueLabelAndSpendsNoColourOfItsOwn() throws {
        try expectOccurrences(of: "CadenceFocusSupport.dueLabel(", at: [
            "Cadence/iOS/iOSMarkdownAccessoryViews.swift": 1,
            "Cadence/macOS/Views/NoteReferenceSupportViews.swift": 1
        ])
        try expectOccurrences(of: "NoteReferencePanelSupport.noteKindLabel(", at: [
            "Cadence/iOS/iOSMarkdownAccessoryViews.swift": 1,
            "Cadence/iOS/iOSMarkdownEditingSurface.swift": 1,
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift": 1
        ])
        try expectOccurrences(of: "NoteReferencePanelSupport.taskFallbackSubtitle(", at: [
            "Cadence/iOS/iOSMarkdownAccessoryViews.swift": 1
        ])

        let accessories = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift"))
        #expect(!accessories.contains("Color(hex:"))

        // Word boundaries, not substrings. A bare `.contains(".white")` fires on
        // `.whitespacesAndNewlines`, of which this file has four — the check would have failed
        // against correct code and "passed" only once somebody deleted a `trimmingCharacters` call.
        #expect(accessories.matchCount(ofPattern: "\\.white(?![A-Za-z])") == 0)
        #expect(accessories.matchCount(ofPattern: "\\.black(?![A-Za-z])") == 0)
        #expect(accessories.matchCount(ofPattern: "\\.gray(?![A-Za-z])") == 0)
    }

    /// Every host that edits a real `Note` hands the editor that note, because "what points at this"
    /// has no subject otherwise. Exact counts so that dropping one host fails.
    ///
    /// The Notes page (`iOSNotesView.swift`, two call sites) and the list-detail Notes panel are
    /// deliberately absent and are **not** asserted at zero: each wants the same one-line argument,
    /// and asserting the gap would turn closing it into a test failure.
    @Test func everyNoteEditingHostHandsTheEditorItsNote() throws {
        try expectOccurrences(of: "editingNote: note", at: [
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift": 1,
            "Cadence/iOS/iOSEventNoteEditorSheet.swift": 1,
            "Cadence/iOS/iOSSearchSupportViews.swift": 1
        ])

        // And the editor treats it as optional rather than required, so the hosts editing a task's
        // notes field, a template or an event draft are unaffected.
        try expectOccurrences(of: "var editingNote: Note? = nil", at: [
            "Cadence/iOS/iOSMarkdownEditingSurface.swift": 1
        ])
    }

    // MARK: - The scan itself

    /// The counts above are only worth anything if the scan actually reads files, and a scan that
    /// silently returns nothing passes every zero-count and empty-offenders assertion. This is the
    /// test that stops them going vacuous — the exact failure mode that let a `/tmp` against
    /// `/private/tmp` path mismatch look like real regressions while the scan read nothing at all.
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
        let all = try swiftFiles(under: "Cadence")
        let ios = try swiftFiles(under: "Cadence/iOS")

        #expect(all.count > 300, "the source scan found \(all.count) files and cannot be doing its job")
        #expect(ios.count > 80, "the iOS scan found \(ios.count) files and cannot be doing its job")
        #expect(all.contains("Cadence/Services/NoteReferenceSupport.swift"))
        #expect(all.contains("Cadence/macOS/Views/NoteReferenceSupportViews.swift"))
        #expect(all.contains("Cadence/macOS/Views/NoteEditorPane.swift"))
        #expect(ios.contains("Cadence/iOS/iOSMarkdownAccessoryViews.swift"))
        #expect(ios.contains("Cadence/iOS/iOSMarkdownEditingSurface.swift"))
        #expect(ios.contains("Cadence/iOS/iOSMarkdownReferenceSupport.swift"))

        // And it must be reading *code*, not an empty string: positive assertions over the same
        // reader, including one needle the comment stripper has to have removed.
        let rawAccessories = try sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift")
        let accessories = try strippingComments(rawAccessories)
        #expect(accessories.contains("struct iOSNoteReferencePanel: View"))

        // A needle that is genuinely there, in a comment, and must be gone after stripping —
        // verified against the raw text in the line above so the check cannot be vacuous.
        #expect(rawAccessories.contains("`D-104` is about"))
        #expect(!accessories.contains("`D-104` is about"))

        let editor = try strippingComments(sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift"))
        #expect(editor.contains("struct iOSMarkdownEditingSurface: View"))

        // The iOS sweep must be reading the files it clears: this needle is present as live code in
        // the same tree the zero-count sweep above walks.
        #expect(editor.contains("NoteReferenceParser.taskReferenceMarkdown("))
    }
}

// MARK: - Source-reading helpers

private extension String {
    /// Regex match count, for scans where a bare substring would over-count. `.white` is inside
    /// `.whitespacesAndNewlines`; `.black` would be inside `.blackout` the day somebody writes one.
    func matchCount(ofPattern pattern: String) -> Int {
        var count = 0
        var searchRange = startIndex..<endIndex
        while let found = range(of: pattern, options: .regularExpression, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<endIndex
        }
        return count
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
