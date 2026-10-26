import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// T-248 / T-249: Settings → Templates split its card unconditionally — iOS on
/// `horizontalSizeClass == .regular` alone, macOS on nothing at all — with a fixed chooser column
/// beside a `maxWidth: .infinity` editor and no floor under what was left. On the primary target
/// device in what was then its default configuration (iPad Pro 11", portrait, the then-188pt shell
/// sidebar docked, no multitasking — a 646pt pane) the editor was drawn **16pt wide**. No current
/// shell produces that pane: 834 is under the 865pt dock threshold, so the portrait pane is all 834
/// ([[T-4500]]). The device panes are asserted through `CadenceRootShellLayout.detailWidth` in
/// `theTargetIPadSplitsInLandscapeDockedOrFoldedAndNotInPortrait`.
///
/// The values below are the same arithmetic an `NSHostingView` reproduction of the shipped modifier
/// chain measured: 0.0 at a 570pt pane, 16.0 at 646, 146.0 at 776, 204.0 at 834, 392.0 at 1022 and
/// 580.0 at 1210 on iOS with the 260pt chooser, each 4pt more since [[T-4515]] trimmed it to 256; 0.0 at 570, 100.0 at 696, 144.0 at 740, 364.0 at 960 and 604.0 at 1200 on
/// macOS. They are restated here as a *chrome* translation rather than as a second floor — see
/// `iOSCardContentWidth` / `desktopCardContentWidth` below.
struct CadenceSettingsTemplatesCardLayoutTests {

    // MARK: - The chrome between the pane and the card

    /// iOS: the 248pt settings rail, its 1pt divider, `settingsDetailScroll`'s 28pt padding on each
    /// side and `iOSSettingsCard`'s 16pt inset on each side. 337pt of shell before the split
    /// `HStack` sees anything.
    ///
    /// This lives in the test rather than in `CadenceSettingsTemplatesCardLayout` on purpose: every
    /// term belongs to the settings shell, and re-stating them beside the floor would be a second
    /// copy that nothing keeps in step. The layout type asks about the width it is handed; this
    /// function is only how a pane figure from the ticket is turned into one.
    ///
    /// The `.frame(maxWidth: 920)` on the detail column binds above 1257pt of pane and so does not
    /// reach any figure asserted here.
    private static func iOSCardContentWidth(paneWidth: CGFloat) -> CGFloat {
        paneWidth - 248 - 1 - 56 - 32
    }

    /// macOS: the same rail and divider, the same 28pt detail padding, and `CadenceSettingsCard`'s
    /// 14pt inset. 333pt.
    private static func desktopCardContentWidth(paneWidth: CGFloat) -> CGFloat {
        paneWidth - 248 - 1 - 56 - 28
    }

    /// What the editor half is actually left with once the chooser, the divider and the two gaps
    /// have taken theirs — the number the bug was about.
    ///
    /// **`max(0, …)`, and the clamp was not there first.** The raw subtraction comes out at −60 on
    /// iOS and −26 on macOS at a 570pt pane, and the run that caught it is the reason this comment
    /// exists: an `NSHostingView` cannot report a negative width, so the measured figure at 570 is
    /// **0.0** on both surfaces and the editor is simply gone. Modelling the chain without the
    /// clamp made this helper disagree with the measurement it is here to reproduce.
    private static func editorWidth(cardContentWidth: CGFloat, isDesktop: Bool) -> CGFloat {
        max(0, cardContentWidth
            - CadenceSettingsTemplatesCardLayout.chooserWidth(isDesktop: isDesktop)
            - CadenceSettingsTemplatesCardLayout.columnSpacing * 2
            - CadenceSettingsTemplatesCardLayout.columnDividerWidth)
    }

    // MARK: - The floor

    /// The floor is the notes editor's, **by reference and not by value**.
    ///
    /// The value assertions alone cannot fail against a typed `320`, which is the exact shape
    /// `Cadence/Shared/AGENTS.md` warns about: a test named for a property that survives the
    /// mutation removing it. So the spelling is pinned too, the same way
    /// `CadencePaneWidthRuleHomesTests.theNotesFloorStillBorrowsTodaysInspectorFloorByReference`
    /// pins the borrow one link up the chain.
    @Test func theEditorFloorIsBorrowedFromTheNotesEditorRatherThanInvented() throws {
        #expect(
            CadenceSettingsTemplatesCardLayout.minimumEditorWidth
                == CadenceNotesListMetrics.minimumEditorWidth
        )
        #expect(
            CadenceSettingsTemplatesCardLayout.minimumEditorWidth
                == CadenceTodayLayoutSupport.inspectorPaneMinWidth
        )
        #expect(CadenceSettingsTemplatesCardLayout.minimumEditorWidth == 320)

        let house = try settingsCardStrippingComments(
            settingsCardSource("Cadence/Shared/CadenceRegularPaneLayout.swift")
        )
        #expect(
            settingsCardOccurrences(of: "CadenceNotesListMetrics.minimumEditorWidth", in: house) == 1,
            "the templates floor has stopped borrowing the notes editor's and typed one of its own"
        )
    }

    @Test func theTwoColumnFloorIsTheSumOfTheColumnsAndTheGapsBetweenThem() {
        // 256 + 16 + 1 + 16 + 320 (the chooser lost 4pt to T-4515)
        #expect(CadenceSettingsTemplatesCardLayout.twoColumnMinimumWidth(isDesktop: false) == 609)
        // 230 + 16 + 1 + 16 + 320
        #expect(CadenceSettingsTemplatesCardLayout.twoColumnMinimumWidth(isDesktop: true) == 583)
    }

    /// The point of a floor: at exactly the floor the editor gets exactly its minimum, and one point
    /// under it there are not two columns any more. A floor that is off by the divider or by one of
    /// the two 16pt gaps fails here rather than shipping a 15pt-short editor.
    @Test func atTheFloorTheEditorGetsExactlyItsMinimumAndNotAPointLess() {
        for isDesktop in [false, true] {
            let floor = CadenceSettingsTemplatesCardLayout.twoColumnMinimumWidth(isDesktop: isDesktop)

            #expect(
                Self.editorWidth(cardContentWidth: floor, isDesktop: isDesktop)
                    == CadenceSettingsTemplatesCardLayout.minimumEditorWidth
            )
            #expect(
                CadenceSettingsTemplatesCardLayout.layout(
                    isRegularWidth: true, hostWidth: floor, isDesktop: isDesktop
                ) == .twoColumn
            )
            #expect(
                CadenceSettingsTemplatesCardLayout.layout(
                    isRegularWidth: true, hostWidth: floor - 1, isDesktop: isDesktop
                ) == .oneColumn
            )
        }
    }

    // MARK: - The device the ticket was filed from

    /// Every pane width the ticket measured, on iOS, with the form each now resolves to.
    ///
    /// Measured history, and kept as such: 646 was the iPad Pro 11" in portrait with the then-188pt
    /// sidebar docked and is the case that shipped a 16pt editor; 834 was the same device folded and
    /// 1022 landscape docked. Which panes the device produces *today* is the next test's question.
    @Test func everyMeasuredPaneResolvesToTheFormItsEditorWidthEarns() {
        let cases: [(pane: CGFloat, editorBefore: CGFloat, layout: CadenceSettingsCardLayout)] = [
            // Editor widths at today's 256pt chooser: four more than the 260pt one measured.
            (570, 0, .oneColumn),
            (646, 20, .oneColumn),
            (776, 150, .oneColumn),
            (834, 208, .oneColumn),
            (945, 319, .oneColumn),
            (946, 320, .twoColumn),
            (950, 324, .twoColumn),
            (1022, 396, .twoColumn),
            (1210, 584, .twoColumn),
        ]

        for row in cases {
            let content = Self.iOSCardContentWidth(paneWidth: row.pane)

            // The chrome translation still reproduces the measured editor widths, so the layout
            // assertion beside it is about the same geometry the bug was measured in.
            #expect(
                Self.editorWidth(cardContentWidth: content, isDesktop: false) == row.editorBefore,
                "the iOS chrome chain no longer reproduces \(row.editorBefore)pt at a \(row.pane)pt pane"
            )
            #expect(
                CadenceSettingsTemplatesCardLayout.layout(
                    isRegularWidth: true, hostWidth: content, isDesktop: false
                ) == row.layout,
                "a \(row.pane)pt pane resolves to the wrong form"
            )
        }
    }

    /// The target device's real panes, read from the shell rather than restated ([[T-4500]]).
    ///
    /// An 11" iPad Pro in portrait is a drawer shell, so the pane is 834 sidebar out or folded, and
    /// the card is one column (a 208pt editor). In landscape the sidebar docks and leaves **946**,
    /// which the 260pt chooser left four points short of the split (a 316pt editor). The owner
    /// ruled on 2026-10-26 to trim those 4pt ([[T-4515]]): with the 256pt chooser 946 is exactly
    /// the floor, a 320pt editor, so both landscape configurations split and portrait does not.
    @Test func theTargetIPadSplitsInLandscapeDockedOrFoldedAndNotInPortrait() {
        let cases: [(window: CGFloat, folded: Bool, pane: CGFloat, layout: CadenceSettingsCardLayout)] = [
            (834, false, 834, .oneColumn),
            (834, true, 834, .oneColumn),
            (1_210, false, 946, .twoColumn),
            (1_210, true, 1_210, .twoColumn),
        ]

        for row in cases {
            let pane = CadenceRootShellLayout.detailWidth(windowWidth: row.window, isCollapsed: row.folded)
            #expect(pane == row.pane, "window \(row.window) folded \(row.folded) gave pane \(pane)")
            #expect(
                CadenceSettingsTemplatesCardLayout.layout(
                    isRegularWidth: true,
                    hostWidth: Self.iOSCardContentWidth(paneWidth: pane),
                    isDesktop: false
                ) == row.layout,
                "window \(row.window) folded \(row.folded) (pane \(pane)) resolves to the wrong form"
            )
        }
    }

    /// macOS's own measured set. The window floor is 960 and the stored sidebar is 264, so 696 is
    /// the ordinary minimum pane and 570 the worst case (390pt sidebar); the MacBook Pro 14" target
    /// at 1512 leaves 1248 and keeps both columns.
    @Test func theDesktopCardSplitsOnAFullSizedWindowAndNotOnTheFloorOne() {
        let cases: [(pane: CGFloat, editorBefore: CGFloat, layout: CadenceSettingsCardLayout)] = [
            (570, 0, .oneColumn),
            (696, 100, .oneColumn),
            (740, 144, .oneColumn),
            (916, 320, .twoColumn),
            (960, 364, .twoColumn),
            (1200, 604, .twoColumn),
            (1248, 652, .twoColumn),
        ]

        for row in cases {
            let content = Self.desktopCardContentWidth(paneWidth: row.pane)

            #expect(
                Self.editorWidth(cardContentWidth: content, isDesktop: true) == row.editorBefore,
                "the macOS chrome chain no longer reproduces \(row.editorBefore)pt at a \(row.pane)pt pane"
            )
            #expect(
                CadenceSettingsTemplatesCardLayout.layout(
                    isRegularWidth: true, hostWidth: content, isDesktop: true
                ) == row.layout,
                "a \(row.pane)pt pane resolves to the wrong form"
            )
        }
    }

    // MARK: - The two inputs that are not the width

    @Test func compactWidthIsAlwaysOneColumnHoweverWideTheCardIs() {
        #expect(
            CadenceSettingsTemplatesCardLayout.layout(
                isRegularWidth: false, hostWidth: 2000, isDesktop: false
            ) == .oneColumn
        )
    }

    /// Unmeasured resolves to the fallback, which is the opposite of
    /// `CadenceNotesListMetrics.layout`'s call and deliberately so: the guess that is wrong for one
    /// frame here is the one that draws the 16pt editor.
    @Test func anUnmeasuredCardRendersTheFallbackRatherThanTheSplit() {
        for isDesktop in [false, true] {
            #expect(
                CadenceSettingsTemplatesCardLayout.layout(
                    isRegularWidth: true, hostWidth: 0, isDesktop: isDesktop
                ) == .oneColumn
            )
        }
    }

    // MARK: - Both surfaces actually read it

    /// `Cadence/iOS/` is invisible to this target, so the only way to pin the iOS call site is to
    /// read it as text — and the macOS one is read the same way so the two cannot drift.
    ///
    /// This is the assertion that would have failed before the fix: both files spelled their chooser
    /// column as a bare `.frame(width:)` literal with nothing deciding whether to draw it.
    @Test func bothTemplateCardsGateOnTheSharedRuleAndSpellNoColumnWidthOfTheirOwn() throws {
        let surfaces = [
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
            "Cadence/macOS/Views/SettingsTemplatesSection.swift",
        ]

        for path in surfaces {
            let code = try settingsCardStrippingComments(settingsCardSource(path))

            #expect(
                settingsCardOccurrences(of: "CadenceSettingsTemplatesCardLayout.layout(", in: code) == 1,
                "\(path) does not ask the shared rule which form to draw"
            )
            #expect(
                settingsCardOccurrences(of: "chooserWidth(isDesktop:", in: code) == 1,
                "\(path) does not take its chooser width from the shared rule"
            )
            #expect(
                settingsCardOccurrences(of: "onGeometryChange", in: code) == 1,
                "\(path) never measures the width it is handed, so the gate has nothing to read"
            )
            for literal in [".frame(width: 260)", ".frame(width: 230)"] {
                #expect(
                    settingsCardOccurrences(of: literal, in: code) == 0,
                    "\(path) has gone back to a typed chooser width (\(literal))"
                )
            }
        }
    }

    /// Non-vacuity for the scan above: the helper really reads these files, and the stripper really
    /// strips. `SettingsTemplatesSection.swift`'s prose names `iOSTemplateSettingsChip` once, in the
    /// comment explaining why the desktop fallback reuses its rows instead — so raw source sees it
    /// and stripped source does not.
    @Test func theSourceScanReachesTheFilesAndTheStripperStrips() throws {
        let path = "Cadence/macOS/Views/SettingsTemplatesSection.swift"
        let raw = try settingsCardSource(path)

        #expect(raw.count > 2000, "the scan read \(raw.count) bytes and cannot be doing its job")
        #expect(settingsCardOccurrences(of: "iOSTemplateSettingsChip", in: raw) == 1)
        #expect(
            settingsCardOccurrences(
                of: "iOSTemplateSettingsChip",
                in: try settingsCardStrippingComments(raw)
            ) == 0
        )
    }
}

// MARK: - Source-reading helpers

/// Prefixed and private, matching `CadencePaneWidthRuleHomesTests` and the three suites it copied
/// them from. Hoisting the four into one shared helper is a separate change from this one.
private func settingsCardRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func settingsCardSource(_ relativePath: String) throws -> String {
    try String(
        contentsOf: settingsCardRepositoryRoot().appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

private func settingsCardStrippingComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}

private func settingsCardOccurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}
