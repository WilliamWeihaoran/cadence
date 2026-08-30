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
        let retired = misfiledRetiredIPadNames
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

    /// The exception, kept deliberately. These two are built only by `iOSTodayView`'s two-pane
    /// layout, which `CadenceTodayLayoutSupport.layout(...)` returns only at regular width — so the
    /// prefix is a fact about them rather than a leftover.
    ///
    /// **It was three (T-493).** The side-panel enum was counted here on the strength of the same
    /// sentence and was never checked by the sweep below; it is `iOSTodaySidePanel` now, because a
    /// stored property on a view that lives at both widths reaches it on a phone. The reachability
    /// is still asserted — see `theRenamedSidePanelEnumIsReachedFromAWidthIndependentStoredProperty`
    /// — and the list of prefixed names is derived from source rather than typed here, by
    /// `everyIPadPrefixedTypeIsBuiltOnlyFromAWidthGatedHost`.
    @Test func theTwoPaneOnlyTypesKeepTheirIPadPrefix() throws {
        let support = try misfiledSourceFile("Cadence/iOS/iPadTodaySupportViews.swift")
        for name in ["iPadTodayTaskHeader", "iPadTodayInspectorSwitcher"] {
            #expect(support.contains(name), "iPadTodaySupportViews.swift no longer declares \(name)")
        }
        #expect(
            CadenceSourceScan.strippingComments(support).contains("enum iOSTodaySidePanel:"),
            "the side panel enum is not declared under its renamed, width-honest name"
        )

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

    /// **The reachability claim, over the whole surface rather than over one file.**
    ///
    /// `theTwoPaneOnlyTypesKeepTheirIPadPrefix` above checks that the *compact Today host* does not
    /// name the two kept views. That is one file out of ninety-odd, and the claim the prefix rests
    /// on is about all of them: nothing a compact width can reach may build these. This sweeps
    /// `Cadence/iOS/` and pins the exact set of files whose **code** names either view — prose is
    /// stripped first, because this file family records its own history in doc comments and three
    /// other files mention these names while building neither.
    ///
    /// Two files, each for its own reason: the one that declares them, and `iOSTodayView`, which
    /// builds them from `twoPaneTodayLayout` — the branch `CadenceTodayLayoutSupport.layout(...)`
    /// returns only at regular width. The chain from that branch to each call is walked below
    /// rather than inferred from the member names.
    @Test func nothingOutsideTheTwoPaneTodayHostBuildsATwoPaneOnlyView() throws {
        let instrument = try misfiledTwoPaneOnlyViewInstrument()
        let namers = try instrument.sweep(
            try misfiledSwiftFiles(under: "Cadence/iOS"),
            // 93 files at the time of writing; the floor sits well under it so an added file is
            // not a failure and a collapsed walk is.
            atLeast: 80,
            including: "Cadence/iOS/iOSTodayCompactViews.swift",
            read: misfiledSourceFile
        )
        #expect(
            namers == ["Cadence/iOS/iOSTodayView.swift", "Cadence/iOS/iPadTodaySupportViews.swift"],
            "a two-pane-only view is built outside Today's two-pane layout: \(namers)"
        )

        // The chain, inside the one host allowed to name them. `iPadTodayInspectorSwitcher` is
        // built in `twoPaneTodayLayout`'s own body; `iPadTodayTaskHeader` is built by
        // `todayTaskColumn`, whose only other mention is that same body. Counted over a scoped
        // body rather than asserted with a file-wide `contains`, which is what makes a second call
        // site fail here instead of passing on the first one.
        let host = CadenceSourceScan.codeOnly(try misfiledSourceFile("Cadence/iOS/iOSTodayView.swift"))
        #expect(host.contains("struct iOSTodayView: View {"), "non-vacuity: wrong file read")
        let twoPane = try #require(CadenceSourceScan.functionBody(named: "twoPaneTodayLayout", in: host))
        #expect(CadenceSourceScan.matchCount("iPadTodayInspectorSwitcher\\(", in: twoPane) == 1)
        #expect(CadenceSourceScan.matchCount("iPadTodayInspectorSwitcher\\(", in: host) == 1)
        #expect(CadenceSourceScan.matchCount("todayTaskColumn", in: twoPane) == 1)
        // The declaration plus that one use, and nothing else.
        #expect(CadenceSourceScan.matchCount("todayTaskColumn", in: host) == 2)
        #expect(CadenceSourceScan.matchCount("iPadTodayTaskHeader\\(", in: host) == 1)
    }

    /// **Why the third kept name stopped being kept (T-493).**
    ///
    /// `iPadTodaySupportViews.swift` used to say all three types were "built only by
    /// `iOSTodayView.twoPaneTodayLayout`" and that "a compact width cannot reach any of them". For
    /// the two views that is true and the sweep above holds it. For the side-panel enum it was
    /// false: `iOSTodayView` names it in the **default value of a stored property**
    /// (`@AppStorage("ios.today.sidePanel")`), which every construction of that view evaluates —
    /// and `iOSCompactTabShell`, `iOSTasksTabView` and `iOSSearchView` all construct it at compact
    /// width. So the enum is reached on an iPhone.
    ///
    /// The reach is what got the enum renamed rather than the sentence softened, so this test
    /// outlives the rename: it is the reason. If the stored property ever moves into the two-pane
    /// branch the enum becomes genuinely regular-width-only and this goes red, which is the right
    /// moment to reconsider the name — not a silent pass. Nothing persisted moved: the key is
    /// `ios.today.sidePanel` either way and the raw values are `notes` / `timeline`.
    @Test func theRenamedSidePanelEnumIsReachedFromAWidthIndependentStoredProperty() throws {
        let host = CadenceSourceScan.strippingComments(
            try misfiledSourceFile("Cadence/iOS/iOSTodayView.swift")
        )
        #expect(host.contains("struct iOSTodayView: View {"), "non-vacuity: wrong file read")
        #expect(
            CadenceSourceScan.matchCount(
                "@AppStorage\\(\"ios.today.sidePanel\"\\) private var sidePanelRaw = iOSTodaySidePanel",
                in: host
            ) == 1,
            "the width-independent stored property no longer reads the way the rename assumed"
        )
        // A stored property's initialiser runs in `init`, not in a layout branch. That is the
        // difference from the two views, and it is what this asserts rather than assumes.
        let code = CadenceSourceScan.codeOnly(try misfiledSourceFile("Cadence/iOS/iOSTodayView.swift"))
        let twoPane = try #require(CadenceSourceScan.functionBody(named: "twoPaneTodayLayout", in: code))
        #expect(twoPane.contains("iOSTodaySidePanel") == false)

        // And the three compact hosts really do construct the view that carries it, so the reach
        // above is a fact about the app rather than about one file.
        for path in [
            "Cadence/iOS/iOSCompactTabShell.swift",
            "Cadence/iOS/iOSTasksTabView.swift",
            "Cadence/iOS/iOSSearchView.swift"
        ] {
            let caller = CadenceSourceScan.codeOnly(try misfiledSourceFile(path))
            #expect(
                CadenceSourceScan.matchCount("iOSTodayView\\(", in: caller) >= 1,
                "\(path) no longer constructs iOSTodayView"
            )
        }
    }

    /// **The prefix rule, enumerated from the source instead of typed into a list (T-493).**
    ///
    /// This is the general half. `nothingOutsideTheTwoPaneTodayHostBuildsATwoPaneOnlyView` holds
    /// the rule for two names *somebody wrote down*, and that is exactly how the third one was
    /// missed for a fortnight: T-283 listed the kept names by hand, the enum was not in the list,
    /// and no test anywhere objected that a compact width reached it. So the names are read out of
    /// the tree here. Every `iPad`-prefixed type declared under `Cadence/iOS/` must appear in the
    /// table below with the host that builds it and the width test that gates that host — a new
    /// one fails until somebody writes those down, which is the reading the missing check would
    /// have forced.
    ///
    /// It found a fourth immediately: `iPadMacStyleRootShell`, which no reachability test had ever
    /// covered. It passes — `iOSRootView` builds it inside `if horizontalSizeClass == .regular` —
    /// but "passes" was not previously known.
    ///
    /// **What this cannot do**, and it is worth saying because this repo keeps finding comments
    /// that assert mechanisms the code lacks: it checks a *name* against a *gate*. A comment that
    /// invents a mechanism out of prose — T-352's "restored at launch" for a selection nothing
    /// persists — names no symbol and trips nothing here. That family is still read, not guarded.
    @Test func everyIPadPrefixedTypeIsBuiltOnlyFromAWidthGatedHost() throws {
        // Per prefixed type: the one file besides its own that may name it, and a whitespace-free
        // needle showing the build sits behind a width test in that file.
        let gated: [String: (host: String, gate: String)] = [
            "iPadMacStyleRootShell": (
                "Cadence/iOS/iOSRootView.swift",
                "ifhorizontalSizeClass==.regular{iPadMacStyleRootShell("
            ),
            "iPadTodayTaskHeader": (
                "Cadence/iOS/iOSTodayView.swift",
                "case.twoPane:twoPaneTodayLayout(width:width)"
            ),
            "iPadTodayInspectorSwitcher": (
                "Cadence/iOS/iOSTodayView.swift",
                "case.twoPane:twoPaneTodayLayout(width:width)"
            )
        ]

        let paths = try misfiledSwiftFiles(under: "Cadence/iOS")
        var declaredIn: [String: String] = [:]
        for path in paths {
            for name in misfiledIPadPrefixedDeclarations(in: try misfiledSourceFile(path)) {
                declaredIn[name] = path
            }
        }
        #expect(
            Set(declaredIn.keys) == Set(gated.keys),
            """
            an iPad-prefixed type under Cadence/iOS/ is not recorded with the width-gated host that \
            builds it: \(Set(declaredIn.keys).symmetricDifference(gated.keys).sorted())
            """
        )

        for (name, expectation) in gated.sorted(by: { $0.key < $1.key }) {
            let declaring = try #require(declaredIn[name])
            let namers = try misfiledPrefixedNameInstrument(for: name).sweep(
                paths,
                // 93 files at the time of writing; the floor sits well under it so an added file is
                // not a failure and a collapsed walk is.
                atLeast: 80,
                including: "Cadence/iOS/iOSTodayCompactViews.swift",
                read: misfiledSourceFile
            )
            #expect(
                namers == Set([declaring, expectation.host]).sorted(),
                "\(name) is named in code outside \(expectation.host): \(namers)"
            )

            let host = CadenceSourceScan.strippingComments(try misfiledSourceFile(expectation.host))
            #expect(
                host.filter { !$0.isWhitespace }.contains(expectation.gate),
                "\(expectation.host) no longer builds \(name) behind \(expectation.gate)"
            )
        }
    }

    /// The declaration extractor against text that is not the repository, so the sweep above cannot
    /// pass by reading nothing. It must find a declaration, ignore a *use* of the same name, ignore
    /// prose, and leave the renamed `iOS` neighbour alone.
    @Test func theIPadDeclarationExtractorReadsDeclarationsAndNotUses() {
        #expect(misfiledIPadPrefixedDeclarations(in: "struct iPadTodayTaskHeader: View {")
            == ["iPadTodayTaskHeader"])
        #expect(misfiledIPadPrefixedDeclarations(in: "enum iPadTodaySidePanel: String {")
            == ["iPadTodaySidePanel"])
        #expect(misfiledIPadPrefixedDeclarations(in: "nonisolated final class iPadThing: Sendable {")
            == ["iPadThing"])
        // The nearest misses: building one, extending one, and writing about one.
        #expect(misfiledIPadPrefixedDeclarations(in: "var body: some View { iPadTodayTaskHeader() }")
            .isEmpty)
        #expect(misfiledIPadPrefixedDeclarations(in: "extension iPadTodayTaskHeader { }").isEmpty)
        #expect(misfiledIPadPrefixedDeclarations(in: "/// struct iPadGhost: View {").isEmpty)
        // And the prefix is `iPad`, not any `i`-something.
        #expect(misfiledIPadPrefixedDeclarations(in: "enum iOSTodaySidePanel: String {").isEmpty)
    }

    // MARK: - T-494: the same sweep, over the docs that route agents

    /// **The rename half-landed in the place it does the most damage.**
    ///
    /// `noLiveSourceSpellsARetiredIPadName` above walks `Cadence/**/*.swift` and nothing else, so
    /// three retired names survived in `docs/IOS_AGENTS_REFERENCE.md` and `docs/CLAUDE_REFERENCE.md`
    /// — the two files an agent is *told* to read before touching the iOS surface. A dangling name
    /// in code is a compile error; a dangling name in a routing doc sends the next reader to a file
    /// that does not exist, and nothing anywhere says so.
    ///
    /// **What the widened sweep found, in full.** Extending it to every first-party markdown file
    /// turned up exactly those three and nothing else. Every other Cadence symbol named in the
    /// agent docs but absent from the tree — `SidebarAreaDropDelegate`, `SidebarProjectDropDelegate`,
    /// `TildeSectionPickerRow`, `TildeSectionSearchPanel` — is named by a sentence that exists to
    /// say it does not exist. Those are tombstones, which is the opposite defect and must stay.
    ///
    /// The walk covers the root guides, every scoped `AGENTS.md`, and `docs/`, minus the two ticket
    /// ledgers. `docs/TODO.md` and `docs/TODO_DONE.md` are *records*: an archive entry describing a
    /// rename has to spell the old name, and a sweep that forbade it would forbid the archive from
    /// being accurate. They are excluded by rule rather than allowlisted, because they change on
    /// almost every commit and an allowlist entry with a non-vacuity check would turn a routine
    /// ticket edit into a red suite.
    @Test func noAgentFacingDocSpellsARetiredIPadName() throws {
        let paths = try misfiledAgentFacingDocs()
        // `docs/refactor-phases-4-6.md` is an audit snapshot taken at `249b475` and says so in its
        // own header. Its findings cite the file names that existed *then*; rewriting them would
        // make the snapshot describe a tree it was not taken from. Allowlisted by name, with the
        // same non-vacuity check the code sweep uses on its allowlist.
        let snapshot = "docs/refactor-phases-4-6.md"

        var hits: [String] = []
        for name in misfiledRetiredIPadNames {
            let found = try misfiledRetiredNameInstrument(for: name).sweep(
                paths,
                // 29 first-party markdown files at the time of writing, minus the two ledgers.
                atLeast: 20,
                including: "docs/IOS_AGENTS_REFERENCE.md",
                read: misfiledSourceFile
            )
            hits.append(contentsOf: found.filter { $0 != snapshot }.map { "\($0): \(name)" })
        }
        #expect(hits.isEmpty, "retired iPad names in agent-facing docs: \(hits.sorted())")

        // The allowlist earns its place or it goes.
        let frozen = try misfiledSourceFile(snapshot)
        #expect(
            misfiledRetiredIPadNames.contains { misfiledSpellsWord($0, in: frozen) },
            "\(snapshot) is allowlisted but no longer names a retired surface"
        )

        // And the walk really reached the two files the ticket named, rather than a list that
        // happens to be long enough.
        for path in ["docs/IOS_AGENTS_REFERENCE.md", "docs/CLAUDE_REFERENCE.md", "Cadence/iOS/AGENTS.md"] {
            #expect(paths.contains(path), "the doc walk missed \(path)")
        }
        #expect(paths.contains("docs/TODO.md") == false, "the ticket ledger is inside the sweep")
        #expect(paths.contains("docs/TODO_DONE.md") == false, "the archive is inside the sweep")
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
    ///
    /// **[[T-492]] changed one of those needles and what this test is.** The horizontal margin was
    /// in the list as the literal `.padding(.horizontal, isRegularWidth ? 20 : 18)`, so this test
    /// was *pinning the copy in place*: T-281 closed a duplication between two sheets and opened
    /// one against `iOSEditorSheetMetrics.gutter(isRegularWidth:)`, then asserted the new copy was
    /// present. The needle now names the shared figure instead.
    ///
    /// The rest of the list stays source-shape and has to: `Cadence/iOS/` is fenced out of this
    /// target, so `iOSNoteEditorSheetHeader` cannot be named here, never mind rendered. The gutter
    /// is the exception, and that is the second half of the fix — `iOSEditorSheetMetrics` sits
    /// outside `#if os(iOS)` precisely so the macOS test target can read it, so the margin the
    /// header draws is now a **value** this target can evaluate rather than characters it can only
    /// match.
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
            ".padding(.horizontal, iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth))",
            ".padding(.vertical, isRegularWidth ? 20 : 14)",
            ".background(Theme.surface)",
            "@Environment(\\.horizontalSizeClass)"
        ] {
            #expect(code.contains(needle), "the shared header does not spell \(needle)")
        }

        // The copy is gone, not merely joined by the shared call — the pair is what makes this an
        // assertion about the file rather than about one line of it.
        #expect(
            code.contains("isRegularWidth ? 20 : 18") == false,
            "the shared header spells the host gutter ramp again"
        )

        // **The behavioural half.** 20 and 18 used to exist in this target only as characters in
        // the needle above. They are a figure the header reads now, and one this target can
        // evaluate, so a change to the margin the header actually draws is visible from macOS.
        // `iOSEditorSheetMetricsTests` owns the figure; this states that the header is downstream
        // of it, which is the thing T-492 changed.
        #expect(iOSEditorSheetMetrics.gutter(isRegularWidth: true) == 20)
        #expect(iOSEditorSheetMetrics.gutter(isRegularWidth: false) == 18)

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

    /// **The gutter the extraction did not take with it.**
    ///
    /// `iOSEditorSheetMetrics.gutter(isRegularWidth:)` is where "the margin between an editor
    /// sheet's content and the edge of its host" is decided — 20 regular, 18 compact — and its own
    /// comment says it exists so that figure is "stated once instead of being a
    /// `isRegularWidth ? 20 : 18` in each of them". Five surfaces read it, one of them
    /// (`iOSAINoteActionsViews`) a note surface. `iOSNoteEditorSheetHeader` spells the ternary.
    ///
    /// The sweep is the instrument that was missing: nothing in this target looked for a
    /// hand-rolled copy of that ramp, which is how T-281 could close one duplication by opening an
    /// instance of another — and how its own sibling test came to assert the copy is there
    /// (`oneSharedViewOwnsTheNoteEditorHeaderRamp`).
    ///
    /// **[[T-492]] closed it and the allowlist is down to the definition.** The offender was
    /// excluded **by name**, on the T-449 pattern, and that is what made the fix one line of view
    /// source and one line of test source. `misfiledGutterRampAllowed` now holds one path — the
    /// file that declares `gutter` — so the loop below over "everything excused" and the sweep's
    /// own verdict have stopped being two different populations.
    @Test func noEditorSheetSurfaceSpellsTheHostGutterRampItself() throws {
        let instrument = try misfiledGutterRampInstrument()
        let offenders = try instrument.sweep(
            try misfiledSwiftFiles(under: "Cadence/iOS"),
            atLeast: 80,
            including: "Cadence/iOS/iOSEditorSheetMetrics.swift",
            read: misfiledSourceFile
        ).filter { !misfiledGutterRampAllowed.contains($0) }
        #expect(offenders.isEmpty, "hand-rolled editor-sheet gutter ramp: \(offenders)")

        // The exclusion must still be what it is excused for being. An allowlist entry that has
        // stopped spelling the ramp is one to delete, not one to keep carrying — which is exactly
        // what happened to the second entry when T-492 fixed the file it named.
        for path in misfiledGutterRampAllowed.sorted() {
            #expect(
                instrument.fires(on: try misfiledSourceFile(path)),
                "\(path) is allowlisted but no longer spells the ramp"
            )
        }
        let metrics = CadenceSourceScan.codeOnly(
            try misfiledSourceFile("Cadence/iOS/iOSEditorSheetMetrics.swift")
        )
        #expect(
            metrics.contains("static func gutter(isRegularWidth: Bool) -> CGFloat"),
            "the allowlisted definition is no longer a definition"
        )
    }

    /// **No call site hands the shared header a width**, which is the shape the extraction would
    /// come apart in. Threading `isRegularWidth:` back in from either sheet would compile, would
    /// look like an answer to "does the trait reach the 320pt rail", and would put the ramp's
    /// *input* back in two places while leaving the ramp itself in one — the drift T-281 closed,
    /// one level down.
    ///
    /// Source-shape, and it can only be: `Cadence/iOS/` is fenced out of this target, so the header
    /// cannot be named here, never mind rendered. See the suite comment.
    @Test func noCallSiteHandsTheSharedHeaderAWidth() throws {
        var callSites = 0
        for path in try misfiledSwiftFiles(under: "Cadence/iOS") {
            let code = CadenceSourceScan.codeOnly(try misfiledSourceFile(path))
            callSites += CadenceSourceScan.matchCount("iOSNoteEditorSheetHeader\\(", in: code)
            #expect(
                CadenceSourceScan.matchCount(
                    "iOSNoteEditorSheetHeader\\([^)]*(isRegular|SizeClass|width:)",
                    in: code
                ) == 0,
                "\(path) parameterises the shared header by width"
            )
        }
        // Non-vacuity for the walk: the two sheets call it, and nothing else does. The declaring
        // file is deliberately not one of them — its convenience initialiser delegates to
        // `self.init`, so a count of two here is also the statement that there is no third sheet.
        #expect(callSites == 2, "found \(callSites) calls to the shared header")

        // And the view takes three things, none of them a width. It reads the trait itself, which
        // is the whole reason neither sheet names those numbers any more.
        let header = CadenceSourceScan.codeOnly(
            try misfiledSourceFile("Cadence/iOS/iOSNoteEditorSheetHeader.swift")
        )
        for declaration in [
            "let eyebrow: String",
            "let title: String",
            "@ViewBuilder let accessory: Accessory"
        ] {
            #expect(header.contains(declaration), "the shared header no longer declares \(declaration)")
        }
        #expect(
            CadenceSourceScan.matchCount("let (isRegular|isCompact|horizontalSizeClass)", in: header) == 0,
            "the shared header stores a width"
        )
    }

    /// **The trait cannot be rewritten between the sheet and the rail, because nothing in this tree
    /// rewrites it.**
    ///
    /// T-447's first predicate is that `iOSNoteEditorSheetHeader` reading
    /// `@Environment(\.horizontalSizeClass)` itself sees the same value the sheet around it
    /// branches on — "the same trait either way *in theory*", since a `.frame(width: 320)` is not a
    /// scene trait. Whether SwiftUI re-derives it somewhere inside `NavigationStack` → `HStack` →
    /// `.frame` is a device question and stays one. The other half is not, and it is the half an
    /// *edit* could break: if no view in `Cadence/` writes that key into the environment, there is
    /// nothing between the two readers that could hand them different answers.
    ///
    /// Swept over the whole app rather than over the two sheets, because the modifier that would
    /// break it could be applied by any ancestor — a shell, a root view, a presenter.
    @Test func nothingInTheAppRewritesTheHorizontalSizeClassBetweenTheSheetAndItsHeader() throws {
        let offenders = try misfiledSizeClassOverrideInstrument().sweep(
            try misfiledSwiftFiles(under: "Cadence"),
            atLeast: 400,
            including: "Cadence/iOS/iOSNoteEditorSheetHeader.swift",
            read: misfiledSourceFile
        )
        #expect(offenders.isEmpty, "the horizontal size class is written in: \(offenders)")

        // Non-vacuity for the claim this supports: all three files still *read* the trait whose
        // agreement is being argued for.
        for path in [
            "Cadence/iOS/iOSNoteEditorSheetHeader.swift",
            "Cadence/iOS/iOSEventNoteEditorSheet.swift",
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift"
        ] {
            let code = CadenceSourceScan.codeOnly(try misfiledSourceFile(path))
            #expect(
                code.contains("@Environment(\\.horizontalSizeClass)"),
                "\(path) no longer reads the trait it is asserted to share"
            )
        }
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

/// The one file allowed to spell the editor-sheet gutter ramp: the one that **defines** it.
///
/// It held a second entry until [[T-492]] — `iOSNoteEditorSheetHeader`, the copy T-281 opened while
/// closing a different duplication — and that entry is deleted rather than kept, which is the point
/// of naming an offender instead of writing a general exclusion: the allowlist shrinks to nothing
/// but the definition, and a set of exactly one is a set that cannot quietly absorb the next one.
/// See `noEditorSheetSurfaceSpellsTheHostGutterRampItself`.
private let misfiledGutterRampAllowed: Set<String> = [
    "Cadence/iOS/iOSEditorSheetMetrics.swift"
]

private func misfiledGutterRampInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "hand-rolled editor-sheet gutter ramp",
        fires: """
        struct Sheet: View {
            var body: some View {
                content.padding(.horizontal, isRegularWidth ? 20 : 18)
            }
        }
        """,
        // The nearest miss, not a distant one: the same padding on the same sheet, taken from the
        // one place that decides it. A detector keyed on "20" or on ".padding(.horizontal" would
        // fire on this.
        andNotOn: """
        struct Sheet: View {
            var body: some View {
                content.padding(.horizontal, iOSEditorSheetMetrics.gutter(isRegularWidth: isRegularWidth))
            }
        }
        """,
        by: misfiledSpellsItsOwnGutterRamp
    )
}

private func misfiledSpellsItsOwnGutterRamp(_ source: String) -> Bool {
    CadenceSourceScan.matchCount("isRegularWidth \\? 20 : 18", in: CadenceSourceScan.codeOnly(source)) > 0
}

private func misfiledTwoPaneOnlyViewInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "names a two-pane-only Today view",
        fires: """
        struct Elsewhere: View {
            var body: some View { iPadTodayTaskHeader(eyebrow: "", title: "") }
        }
        """,
        // The nearest miss: prose naming the view, which is how this file family records its own
        // history, plus the enum that used to be a third `iPad` name — genuinely reached at both
        // widths, renamed by T-493, and still the thing this detector must not sweep up.
        andNotOn: """
        /// `iPadTodayTaskHeader` is the row this one replaced on macOS.
        struct Elsewhere: View {
            @AppStorage("k") private var raw = iOSTodaySidePanel.notes.rawValue
            var body: some View { Text("iPadTodayInspectorSwitcher") }
        }
        """,
        by: misfiledNamesATwoPaneOnlyView
    )
}

private func misfiledNamesATwoPaneOnlyView(_ source: String) -> Bool {
    let code = CadenceSourceScan.codeOnly(source)
    return ["iPadTodayTaskHeader", "iPadTodayInspectorSwitcher"].contains {
        misfiledSpellsWord($0, in: code)
    }
}

/// Every `iPad`-prefixed **type declaration** in a file, read out of the source rather than listed.
///
/// The list is the point (T-493). T-283 wrote the kept prefixed names into a literal, one was left
/// out, and the omission was invisible for as long as nobody re-derived it. Comments are stripped
/// first, because this file family argues about the prefix in prose and an argument declares
/// nothing; `extension` is deliberately not a keyword here, since extending a type does not
/// introduce a name that could be wrong.
private func misfiledIPadPrefixedDeclarations(in source: String) -> Set<String> {
    let code = CadenceSourceScan.strippingComments(source)
    guard let regex = try? NSRegularExpression(
        pattern: "\\b(?:struct|enum|class|actor|protocol)\\s+(iPad[A-Za-z0-9_]*)"
    ) else { return [] }

    var names: Set<String> = []
    for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
        guard let captured = Range(match.range(at: 1), in: code) else { continue }
        names.insert(String(code[captured]))
    }
    return names
}

/// "This file's **code** spells `name`", for one prefixed type at a time.
///
/// `codeOnly` rather than `strippingComments` because the negative witness is prose: three files
/// under `Cadence/iOS/` discuss these names in doc comments while building none of them, and a
/// detector that counted those would report every history note as a reachability failure.
private func misfiledPrefixedNameInstrument(for name: String) throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "code naming \(name)",
        fires: """
        struct Elsewhere: View {
            var body: some View { \(name)() }
        }
        """,
        andNotOn: """
        /// `\(name)` is the row this one replaced on macOS.
        struct Elsewhere: View {
            var body: some View { EmptyView() }
        }
        """,
        by: { misfiledSpellsWord(name, in: CadenceSourceScan.codeOnly($0)) }
    )
}

private func misfiledSizeClassOverrideInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "writes the horizontal size class into the environment",
        fires: """
        struct Rail: View {
            var body: some View {
                content.environment(\\.horizontalSizeClass, .compact)
            }
        }
        """,
        // The nearest miss: *reading* the same key, which is what all three files in question do
        // and is exactly what this rule must leave alone.
        andNotOn: """
        struct Rail: View {
            @Environment(\\.horizontalSizeClass) private var horizontalSizeClass
            var body: some View { content.frame(width: 320) }
        }
        """,
        by: misfiledWritesTheHorizontalSizeClass
    )
}

private func misfiledWritesTheHorizontalSizeClass(_ source: String) -> Bool {
    CadenceSourceScan.matchCount(
        "\\.environment\\(\\s*\\\\\\.horizontalSizeClass",
        in: CadenceSourceScan.codeOnly(source)
    ) > 0
}

/// The names retired for claiming a device that reaches them anyway: four from T-283, and
/// `iPadTodaySidePanel` from T-493. One list, read by both the code sweep and the doc sweep — the
/// second was written because the first covered `Cadence/**/*.swift` only, so a name added to one
/// copy and not the other is the exact way this pair would drift apart again.
private let misfiledRetiredIPadNames = [
    "iPadInboxView",
    "iPadTodayView",
    "iPadTodayCompactViews",
    "iPadTodayScheduleViews",
    "iPadTodaySidePanel"
]

/// Every first-party markdown file an agent is routed through: the root guides, each scoped
/// `AGENTS.md`, and `docs/` — minus the two ticket ledgers, which are records rather than routing.
///
/// Enumerated with an explicit prune list rather than a whole-tree walk: an isolated verification
/// copy carries `.codex-build/SourcePackages`, several hundred vendored markdown files that have
/// nothing to do with Cadence and would make the `atLeast:` floor meaningless.
private func misfiledAgentFacingDocs() throws -> [String] {
    let pruned: Set<String> = [".git", ".build", ".codex-build", "node_modules", "DerivedData", "build"]
    let ledgers: Set<String> = ["docs/TODO.md", "docs/TODO_DONE.md"]
    let root = misfiledRepositoryRoot()
    guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }

    var paths: [String] = []
    for element in enumerator {
        guard let name = element as? String else { continue }
        if pruned.contains((name as NSString).lastPathComponent) {
            enumerator.skipDescendants()
            continue
        }
        guard name.hasSuffix(".md"), !ledgers.contains(name) else { continue }
        paths.append(name)
    }
    return paths.sorted()
}

/// Whole-word, so `iPadTodayView` does not fire on `iPadTodayViewModel`. The negative witness is
/// the longer name it must not swallow — the near miss `misfiledSpellsWord` exists to handle, now
/// pinned as a build requirement of the sweep rather than as a comment about it.
private func misfiledRetiredNameInstrument(for name: String) throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "retired iPad name \(name)",
        fires: "- **The host decides, the list draws.** `\(name)` holds the `@AppStorage` day key.",
        andNotOn: "- **The host decides, the list draws.** `\(name)Model` holds the `@AppStorage` day key.",
        by: { misfiledSpellsWord(name, in: $0) }
    )
}
