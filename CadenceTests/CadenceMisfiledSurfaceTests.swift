import Foundation
import Testing
@testable import Cadence

// MARK: - T-281 / T-283 / T-288: a surface that is not shared, and a name that lies

/// Three tickets, one disease: a thing whose *location or name* tells the next reader something
/// the code does not do.
///
/// **All of it is a source scan, and it has to be.** `CadenceTests` builds for macOS, so nothing
/// under `Cadence/iOS/` (a whole-file `#if os(iOS)`) exists at test time — `iOSNoteEditorSheetHeader`
/// and `iOSTodayView` cannot be named, never mind instantiated. And the T-288 half is a claim about
/// *which folder a file is in*, which is not a runtime fact at all: it is exactly the kind of rule
/// only a scan can hold. Each suite below carries a non-vacuity assertion so a path mistake reads
/// as red rather than as a pass.

// MARK: - T-288

/// `Shared/Components/` is the inventory `CLAUDE.md` sends an agent to before writing a new shared
/// view. A whole-file `#if os(macOS)` in it reads as available to both platforms and is not — the
/// `CompactTagStrip` failure mode with a platform fence supplying the misdirection.
///
/// The rule is about the **whole file**, not about fences. A shared component with a fenced branch
/// inside it is genuinely shared and stays; a file whose every line is one platform's is misfiled.
@MainActor
struct SharedComponentsPlatformFenceTests {

    /// The sweep. Whole-file means the first non-blank, non-import, non-comment line opens a
    /// platform fence that the file's last such line closes.
    ///
    /// It runs over a `CadenceScanInstrument` rather than over a bare predicate, and that is the
    /// T-161 point rather than a style choice: blinding the detector to `false` used to leave
    /// **this** test green — "no offenders" is what a clean repo and a dead instrument both look
    /// like — and the only thing that noticed was the separate self-check below, which nothing
    /// obliged anyone to write. Now the witnesses are a precondition of the sweep, so a blind
    /// detector fails here too.
    @Test func sharedComponentsFolderHoldsNoWholeFilePlatformFence() throws {
        let offenders = try misfiledFenceInstrument().sweep(
            try misfiledSwiftFiles(under: "Cadence/Shared/Components"),
            // The folder held 22 files after T-288 moved four out.
            atLeast: 15,
            including: "Cadence/Shared/Components/CadenceTagChip.swift",
            read: misfiledSourceFile
        )
        #expect(
            offenders.isEmpty,
            "whole-file platform fence under Shared/Components: \(offenders)"
        )
    }

    /// The instrument's literal witnesses say it can still tell the two shapes apart; this says the
    /// two shapes it was tuned on are the two shapes the *repo* actually holds. Both halves are
    /// wanted — a fixture pair cannot be retuned by an edit to the tree, and a tree pair cannot go
    /// stale against the fixtures without one of these failing.
    @Test func theWholeFileFenceDetectorAgreesWithTwoKnownFiles() throws {
        let instrument = try misfiledFenceInstrument()
        // Yes: every line of it is macOS's, which is why T-288 moved it here.
        #expect(
            instrument.fires(on: try misfiledSourceFile("Cadence/macOS/Views/CadenceButtons.swift"))
        )
        // No: shared, and it carries an *inner* `#if os(macOS)` — the case the rule must not catch.
        let chip = try misfiledSourceFile("Cadence/Shared/Components/CadenceTagChip.swift")
        #expect(chip.contains("#if os("), "non-vacuity: the chip no longer fences anything")
        #expect(instrument.fires(on: chip) == false)
    }

    /// Where the four went, and that they went whole. A move that dropped the fence would compile
    /// the AppKit one into the iOS build; a move that left a copy behind would be worse than not
    /// moving it.
    @Test func theFourMovedComponentsLiveOnTheMacOSSurface() throws {
        let moved = [
            "Cadence/macOS/Views/CadenceButtons.swift": "struct CadenceActionButton",
            "Cadence/macOS/Views/CadenceContextPicker.swift": "struct CadenceContextPickerButton",
            "Cadence/macOS/Views/CommitmentSharedViews.swift": "struct CommitmentPageHeader",
            "Cadence/macOS/CadenceScrollElasticity.swift": "func cadenceSoftPageBounce()"
        ]
        for (path, needle) in moved {
            let source = try misfiledSourceFile(path)
            #expect(source.contains(needle), "\(path) does not declare \(needle)")
            #expect(source.hasPrefix("#if os(macOS)"), "\(path) lost its fence in the move")
            #expect(
                FileManager.default.fileExists(
                    atPath: misfiledRepositoryRoot()
                        .appendingPathComponent("Cadence/Shared/Components")
                        .appendingPathComponent((path as NSString).lastPathComponent)
                        .path
                ) == false,
                "\((path as NSString).lastPathComponent) is still in Shared/Components too"
            )
        }
    }
}

// MARK: - T-283

/// An `iPad`-prefixed name is a claim that only one device reaches the thing. For three of these it
/// was false, and `iPadInboxView`'s own doc comment said so in as many words while the name stayed.
///
/// What the suite pins is the pair: the honest names are the ones the callers spell, **and** the
/// three genuinely two-pane-only types keep their prefix. Renaming those too would have turned a
/// name that carries information into one that does not, which is the same defect pointing the
/// other way.
@MainActor
struct TodayAndInboxNamingTests {

    /// No live source spells the four retired names, and the files that carried them are gone.
    ///
    /// Two sweeps, because a rename half-lands in two different ways. Over **code** the rule is
    /// absolute — a retired name there is either a dangling reference or the old name creeping
    /// back. Over **comments** it is nearly absolute: this codebase writes its history into doc
    /// comments, so the two files that record the rename itself are allowed to say what the names
    /// were, and nothing else is. That allowlist is two entries and named, which is the point —
    /// a third file explaining the rename is a third file that has to justify itself.
    @Test func noLiveSourceSpellsARetiredIPadName() throws {
        let retired = ["iPadInboxView", "iPadTodayView", "iPadTodayCompactViews", "iPadTodayScheduleViews"]
        let recordsTheRename: Set<String> = [
            "Cadence/iOS/iOSInboxView.swift",
            "Cadence/iOS/iPadTodaySupportViews.swift"
        ]

        var scanned = 0
        var inCode: [String] = []
        var inProse: [String] = []
        for path in try misfiledSwiftFiles(under: "Cadence") {
            scanned += 1
            let raw = try misfiledSourceFile(path)
            let code = CadenceSourceScan.strippingComments(raw)
            for name in retired {
                if misfiledSpellsWord(name, in: code) { inCode.append("\(path): \(name)") }
                if misfiledSpellsWord(name, in: raw), !recordsTheRename.contains(path) {
                    inProse.append("\(path): \(name)")
                }
            }
        }
        #expect(scanned > 400, "walked only \(scanned) files under Cadence")
        #expect(inCode.isEmpty, "retired iPad names in code: \(inCode.sorted())")
        #expect(inProse.isEmpty, "retired iPad names in comments: \(inProse.sorted())")

        // Non-vacuity for the allowlist: both entries must still be the record they are excused
        // for being. An entry that stops mentioning the old name is an entry to delete, not keep.
        for path in recordsTheRename.sorted() {
            let raw = try misfiledSourceFile(path)
            #expect(
                retired.contains { misfiledSpellsWord($0, in: raw) },
                "\(path) is allowlisted but no longer records the rename"
            )
        }

        for name in retired {
            #expect(
                FileManager.default.fileExists(
                    atPath: misfiledRepositoryRoot()
                        .appendingPathComponent("Cadence/iOS/\(name).swift").path
                ) == false,
                "Cadence/iOS/\(name).swift is still there"
            )
        }
    }

    /// The honest names exist, in the files named for them, and the callers reach them.
    @Test func theRenamedTodayAndInboxSurfacesAreTheOnesCallersSpell() throws {
        let declarations = [
            "Cadence/iOS/iOSInboxView.swift": "struct iOSInboxView: View {",
            "Cadence/iOS/iOSTodayView.swift": "struct iOSTodayView: View {",
            "Cadence/iOS/iOSTodayCompactViews.swift": "struct iOSCompactTodayView: View {",
            "Cadence/iOS/iOSTodaySchedulePanel.swift": "struct iOSSchedulePanel: View {"
        ]
        for (path, declaration) in declarations {
            let code = CadenceSourceScan.strippingComments(try misfiledSourceFile(path))
            #expect(code.contains(declaration), "\(path) does not declare \(declaration)")
        }

        // The two renamed types, at every caller the ticket listed — including the compact shell,
        // which is the width the old names claimed could not reach them.
        let callers = [
            "Cadence/iOS/iOSCompactTabShell.swift": ["iOSTodayView()", "iOSInboxView()"],
            "Cadence/iOS/iOSRootView.swift": ["iOSTodayView()"],
            "Cadence/iOS/iOSSearchView.swift": ["iOSTodayView()", "iOSInboxView()"],
            "Cadence/iOS/iOSTasksTabView.swift": [
                "iOSTodayView(showsCompactHeader: false)",
                "iOSInboxView(showsCompactHeader: false)"
            ],
            "Cadence/iOS/iOSTasksPageView.swift": ["iOSInboxView(showsCompactHeader: false)"]
        ]
        for (path, needles) in callers {
            let code = CadenceSourceScan.strippingComments(try misfiledSourceFile(path))
            for needle in needles {
                #expect(code.contains(needle), "\(path) does not call \(needle)")
            }
        }
    }

    /// The exception, kept deliberately. These three are built only by `iOSTodayView`'s two-pane
    /// layout, which `CadenceTodayLayoutSupport.layout(...)` returns only at regular width — so the
    /// prefix is a fact about them rather than a leftover.
    @Test func theTwoPaneOnlyTypesKeepTheirIPadPrefix() throws {
        let support = try misfiledSourceFile("Cadence/iOS/iPadTodaySupportViews.swift")
        for name in ["iPadTodayTaskHeader", "iPadTodayInspectorSwitcher", "iPadTodaySidePanel"] {
            #expect(support.contains(name), "iPadTodaySupportViews.swift no longer declares \(name)")
        }

        // And they are reached from the two-pane branch only. `twoPaneTodayLayout` is the one
        // `CadenceTodayLayoutSupport.layout(...)` gates on width; the compact host must name none
        // of them.
        let compact = CadenceSourceScan.strippingComments(
            try misfiledSourceFile("Cadence/iOS/iOSTodayCompactViews.swift")
        )
        #expect(compact.contains("struct iOSCompactTodayView"), "non-vacuity: wrong file read")
        for name in ["iPadTodayTaskHeader", "iPadTodayInspectorSwitcher"] {
            #expect(compact.contains(name) == false, "the compact host reaches \(name)")
        }
    }
}

// MARK: - T-281

/// Two note-editor sheets drew one header, written twice. `af03fb1` made the two spellings
/// identical and deferred the extraction; the reason it recorded was about the sheets' surrounding
/// chrome, which is not the thing that would have been extracted. Two identical bodies is the state
/// the event sheet's header was in once before, and from there it drifted three ways.
@MainActor
struct NoteEditorSheetHeaderTests {

    /// The shared view exists, spells the ramp once, and reads the width itself so neither sheet
    /// has to name those numbers.
    @Test func oneSharedViewOwnsTheNoteEditorHeaderRamp() throws {
        let code = CadenceSourceScan.strippingComments(
            try misfiledSourceFile("Cadence/iOS/iOSNoteEditorSheetHeader.swift")
        )
        #expect(code.contains("struct iOSNoteEditorSheetHeader"), "non-vacuity: wrong file read")

        for needle in [
            "SectionEyebrowLabel(text: eyebrow)",
            "size: isRegularWidth ? 24 : 22, weight: .bold",
            ".lineLimit(2)",
            ".frame(maxWidth: .infinity, alignment: .leading)",
            ".frame(maxHeight: isRegularWidth ? .infinity : nil, alignment: .topLeading)",
            ".padding(.horizontal, isRegularWidth ? 20 : 18)",
            ".padding(.vertical, isRegularWidth ? 20 : 14)",
            ".background(Theme.surface)",
            "@Environment(\\.horizontalSizeClass)"
        ] {
            #expect(code.contains(needle), "the shared header does not spell \(needle)")
        }

        // The accessory slot is what lets the event sheet keep its commit notice inside the block
        // without the linked sheet growing an empty one.
        #expect(code.contains("@ViewBuilder let accessory: Accessory"))
        #expect(code.contains("where Accessory == EmptyView"))
    }

    /// Neither sheet re-declares the block. This is the assertion the ticket asked for, and it is
    /// written over the *whole file* rather than a function body: a second copy pasted into a new
    /// private var elsewhere in either file is exactly the regression.
    @Test func neitherNoteSheetReDeclaresTheHeaderBlock() throws {
        let sheets = [
            "Cadence/iOS/iOSEventNoteEditorSheet.swift",
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift"
        ]
        for path in sheets {
            let raw = try misfiledSourceFile(path)
            let code = CadenceSourceScan.strippingComments(raw)

            // The stripper blanks comments to spaces of equal length, so the stripped string is
            // never shorter — `!=` plus equal length is the pair that actually holds.
            #expect(code != raw, "\(path): nothing was stripped, so the scan read prose")
            #expect(code.count == raw.count, "\(path): the stripper changed length")

            #expect(code.contains("iOSNoteEditorSheetHeader("), "\(path) does not call the shared header")

            for ramp in [
                "isRegularWidth ? 24 : 22",
                "isRegularWidth ? 20 : 18",
                "isRegularWidth ? 20 : 14",
                "isRegularWidth ? .infinity : nil"
            ] {
                #expect(code.contains(ramp) == false, "\(path) still spells \(ramp)")
            }
            // The eyebrow + title pairing is the block itself; a sheet drawing its own is the copy
            // coming back under a different name.
            #expect(
                code.contains("SectionEyebrowLabel(") == false,
                "\(path) draws its own eyebrow again"
            )
        }
    }

    /// The event sheet's commit notice still rides inside the header block rather than being
    /// dropped by the extraction — the one behavioural difference between the two sheets, and the
    /// easiest thing for a "just call the shared view" edit to lose.
    @Test func theEventSheetKeepsItsCommitNoticeInsideTheHeader() throws {
        let code = CadenceSourceScan.strippingComments(
            try misfiledSourceFile("Cadence/iOS/iOSEventNoteEditorSheet.swift")
        )
        #expect(code.contains("private var commitNoticeBanner: some View"), "non-vacuity: wrong file")
        #expect(
            CadenceSourceScan.matchCount(
                "iOSNoteEditorSheetHeader\\(eyebrow: subtitle, title: title\\) \\{[^}]*commitNoticeBanner",
                in: code
            ) == 1,
            "the commit notice is no longer the header's accessory"
        )

        // Regex self-check: the needle above must match the shape it claims and reject the bare
        // call, or a `== 1` over a pattern that matches anything proves nothing.
        let bare = "iOSNoteEditorSheetHeader(eyebrow: subtitle, title: title)"
        #expect(
            CadenceSourceScan.matchCount(
                "iOSNoteEditorSheetHeader\\(eyebrow: subtitle, title: title\\) \\{[^}]*commitNoticeBanner",
                in: bare
            ) == 0
        )
    }
}

// MARK: - Scan helpers

/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree), so read relative to it rather than resolving anything.
private func misfiledRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func misfiledSourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: misfiledRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields
/// absolute paths, and the repo-relative form is what the assertions above read.
private func misfiledSwiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = misfiledRepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let name = element as? String, name.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(name)"
    }
}

/// The whole-file-fence detector, as an instrument that cannot be built once it has stopped
/// discriminating. The witnesses are literals rather than repo files on purpose — see
/// `CadenceScanInstrument`.
private func misfiledFenceInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "whole-file platform fence",
        fires: """
        #if os(macOS)
        import SwiftUI

        struct Everything: View {
            var body: some View { Text("every line of me is one platform's") }
        }
        #endif
        """,
        // The nearest miss, not a distant one: this file *does* open on `#if os(macOS)` and *does*
        // close on `#endif`, so a detector that only looked at its first and last code lines would
        // call it misfiled. It is shared code with two fenced branches in it.
        andNotOn: """
        #if os(macOS)
        import AppKit
        #endif

        struct Shared {
            var label: String { "shared" }
        }

        #if DEBUG
        extension Shared { static let probe = Shared() }
        #endif
        """,
        by: misfiledIsWholeFilePlatformFence
    )
}

/// True when *every* line of code in the file sits inside one leading platform fence — i.e. the
/// file's first code line is `#if os(...)` and its last is the matching `#endif`.
///
/// Deliberately not "the file contains `#if os(macOS)`": a shared component with a fenced branch
/// inside it is the case this rule must leave alone, and `CadenceTagChip` is exactly that.
private func misfiledIsWholeFilePlatformFence(_ source: String) -> Bool {
    let code = CadenceSourceScan.strippingComments(source)
    let lines = code
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard let first = lines.first, let last = lines.last else { return false }
    guard first.hasPrefix("#if os("), last == "#endif" else { return false }

    // The opening fence must be the one the trailing `#endif` closes, not a nested pair that
    // happens to bookend the file.
    var depth = 0
    for (index, line) in lines.enumerated() {
        if line.hasPrefix("#if") {
            depth += 1
        } else if line == "#endif" {
            depth -= 1
            if depth == 0 { return index == lines.count - 1 }
        }
    }
    return false
}

/// A whole-word match, so `iPadTodayView` does not fire on `iPadTodayViewModel` and — the one that
/// matters here — `iPadTodayCompactViews` does not fire on `iPadTodayCompactViewsSomething`.
private func misfiledSpellsWord(_ word: String, in source: String) -> Bool {
    CadenceSourceScan.matchCount("\\b\(word)\\b(?![A-Za-z0-9_])", in: source) > 0
}
