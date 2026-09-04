import Foundation
import Testing
@testable import Cadence

/// **A third icon-only control shape (T-796), found by an outside audit while T-674's
/// `.onTapGesture` sweep was landing.** A `Menu` whose whole label is a bare
/// `Image(systemName:)` is invisible to both `CadenceIconOnlyButtonAccessibilityTests` (keys on
/// the literal `Button`) and `CadenceIconOnlyTapGestureAccessibilityTests` (keys on
/// `.onTapGesture`) — neither rule's needle occurs on a `Menu` at all.
///
/// **Measured fresh rather than trusted against the ticket's own four-day-old count.** The ticket
/// named four sites in four files; a whole-tree walk on 2026-09-04 found seven `Menu`s whose whole
/// label is a bare `Image`, and only **two** are still unnamed. Two of the ticket's original four —
/// `MarkdownEditorView.swift`'s `MarkdownReferenceMenuButton` and
/// `iOSCalendarSettingsSection.swift`'s `repickMenu` — already carry `.accessibilityLabel(…)` by
/// the time this suite was written, fixed by other work in between. A third,
/// `iOSCalendarSettingsSection.swift`'s second `connectionMenu` (an iOS mirror of
/// `SettingsListManagementSections.swift`'s desktop one, both named), and
/// `iOS/iOSMarkdownAccessoryViews.swift`'s "More formatting" menu were always clean. The two still
/// open are `ListNotesHeaderView`'s "new note" menu
/// (`Cadence/macOS/Views/ListNotesViewSupportViews.swift`) and the row overflow menu in
/// `Cadence/iOS/iOSCalendarBundleDetailSheet.swift`, both fixed alongside this suite.
struct CadenceIconOnlyMenuAccessibilityTests {

    private func detector() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "icon-only Menu with no accessible name",
            fires: """
            Menu {
                Button("New Note", action: onNewNote)
                Button("New Note in Folder...", action: onNewNoteInFolder)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            """,
            // The nearest control that must be left alone: same `Menu`/`label:` shape, a title
            // string on the trigger instead of a bare glyph, so there is something for VoiceOver
            // to read without any modifier at all.
            andNotOn: """
            Menu("Move to Folder") {
                Button("Notes", action: onSelectNotes)
            }
            """,
            by: { Self.unnamedIconOnlyMenuCount(in: $0) > 0 }
        )
    }

    /// How many `Menu`s in the file draw nothing but an `Image` as their `label:` and state no
    /// name.
    ///
    /// Unlike the `.onTapGesture` sweep this does not need a character-count window: a `Menu`'s
    /// `label:` closure is a syntactic span found by brace balancing
    /// (`CadenceSourceScan.matchedRange`), so there is no ambiguity about where the label ends —
    /// only about whether a naming modifier follows it, which `chainNamesTheControl` answers the
    /// same way the button sweep's `namesItself` does.
    static func unnamedIconOnlyMenuCount(in source: String) -> Int {
        guard source.contains("Menu") else { return 0 }
        let code = CadenceSourceScan.codeOnly(source)
        var count = 0
        var cursor = code.startIndex

        while let hit = code.range(of: "Menu", range: cursor..<code.endIndex) {
            cursor = hit.upperBound
            // Word boundaries on both sides, so `MenuStyle` and a hypothetical `fooMenu` variable
            // read do not register as the type name.
            if hit.lowerBound > code.startIndex {
                let previous = code[code.index(before: hit.lowerBound)]
                if previous.isLetter || previous.isNumber || previous == "_" { continue }
            }
            if hit.upperBound < code.endIndex {
                let next = code[hit.upperBound]
                if next.isLetter || next.isNumber || next == "_" { continue }
            }

            let afterKeyword = skippingWhitespace(from: hit.upperBound, in: code)
            // `Menu("Title") { … }` and `Menu(systemImage:content:)` both open with `(`, not `{`;
            // either already states a visible title or is a different initialiser shape, so only
            // the trailing-closure `Menu { … } label: { … }` form — the one every site in the
            // tree that draws a bare glyph uses — is read here.
            guard afterKeyword < code.endIndex, code[afterKeyword] == "{" else { continue }
            guard let content = CadenceSourceScan.matchedRange(after: afterKeyword, in: code, open: "{", close: "}") else { continue }

            let afterContent = skippingWhitespace(from: code.index(after: content.upperBound), in: code)
            guard String(code[afterContent...].prefix(6)) == "label:" else { continue }
            let labelStart = skippingWhitespace(from: code.index(afterContent, offsetBy: 6), in: code)
            guard labelStart < code.endIndex, code[labelStart] == "{" else { continue }
            guard let label = CadenceSourceScan.matchedRange(after: labelStart, in: code, open: "{", close: "}") else { continue }

            let trimmedLabel = String(code[label]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLabel.hasPrefix("Image(") else { continue }
            if !chainNamesTheControl(after: label.upperBound, in: code) { count += 1 }
        }
        return count
    }

    /// How far past the label's closing brace a `.accessibilityLabel` (or `.cadenceControlLabel`)
    /// still counts as the same modifier chain — the same 1,200-character/line-prefix rule
    /// `CadenceIconOnlyButtonAccessibilityTests.namesItself` uses for a `Button`'s label.
    private static func chainNamesTheControl(after end: String.Index, in code: String) -> Bool {
        guard end < code.endIndex else { return false }
        let tail = code[code.index(after: end)...].prefix(1_200)
        var chain = ""
        for line in tail.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty || trimmed.hasPrefix(".") || trimmed.hasPrefix(")") else { break }
            chain += "\n" + trimmed
        }
        return chain.contains(".accessibilityLabel(") || chain.contains(".cadenceControlLabel(")
    }

    private static func skippingWhitespace(from start: String.Index, in code: String) -> String.Index {
        var index = start
        while index < code.endIndex, code[index] == " " || code[index] == "\n" || code[index] == "\t" {
            index = code.index(after: index)
        }
        return index
    }

    @Test func noIconOnlyMenuInTheAppIsLeftWithoutAnAccessibleName() throws {
        let offenders = try detector().sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            // 565 files at the time of writing; the floor only rules out a walk that found one
            // folder and called it the app.
            atLeast: 400,
            including: "Cadence/macOS/Views/ListNotesViewSupportViews.swift",
            read: CadenceSourceScan.sourceFile
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders.sorted()) draws a Menu whose whole label is an Image and states no name. \
            Add .cadenceControlLabel(…) (macOS) or .accessibilityLabel(…) (iOS).
            """
        )
    }

    /// The five real files this ticket is about, each read fresh: the two the ticket's own count
    /// had already gone stale on, the two fixed alongside this suite, and the one that was always
    /// clean. Non-vacuity for the fixed pair, and a guard against re-trusting a stale count for
    /// the other three.
    @Test func everyRealMenuTheTicketNamedIsNowClean() throws {
        let files = [
            "Cadence/macOS/Views/ListNotesViewSupportViews.swift",
            "Cadence/macOS/Editor/MarkdownEditorView.swift",
            "Cadence/iOS/iOSCalendarSettingsSection.swift",
            "Cadence/iOS/iOSCalendarBundleDetailSheet.swift",
            "Cadence/iOS/iOSMarkdownAccessoryViews.swift",
        ]
        for path in files {
            let source = try CadenceSourceScan.sourceFile(path)
            #expect(Self.unnamedIconOnlyMenuCount(in: source) == 0, "\(path) still has an unnamed icon-only Menu")
        }
        // The two this suite actually changed carry the name it added, so the zero above is the
        // fix rather than a detector that stopped looking.
        let listNotes = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesViewSupportViews.swift")
        #expect(listNotes.contains(#".cadenceControlLabel("New note")"#))
        let bundleDetail = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBundleDetailSheet.swift")
        #expect(bundleDetail.contains(#".accessibilityLabel("Task actions")"#))
    }

    /// The detector against the two shapes it must not confuse: a titled `Menu`, and a `Menu`
    /// whose bare-glyph label already carries a name.
    @Test func theIconOnlyMenuDetectorSeesABareGlyphAndLeavesANamedOrTitledOneAlone() throws {
        let instrument = try detector()

        #expect(
            instrument.fires(on: """
            Menu {
                Button("Edit", action: open)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            """),
            "the detector cannot see an unnamed icon-only Menu"
        )
        #expect(
            instrument.fires(on: """
            Menu {
                Button("Edit", action: open)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Task actions")
            """) == false,
            "a Menu already carrying .accessibilityLabel reads as unnamed"
        )
        #expect(
            instrument.fires(on: """
            Menu("Sort By") {
                Button("Date", action: sortByDate)
            }
            """) == false,
            "a Menu with a visible title is being counted as icon-only"
        )
    }
}
