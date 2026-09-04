import Foundation
import Testing
@testable import Cadence

/// **T-791: a named copy is invisible to a naming ledger, so a "missing name" sweep understates
/// duplication by construction.**
///
/// T-672 found this the hard way: filed over ten sites, it found eleven, because the eleventh
/// (`FocusPickerSupportViews`' clear button) already carried `.cadenceControlLabel("Clear
/// search")` and so never appeared in any accessibility ledger at all — `CadenceSearchFieldClearButtonTests`
/// now pins the full population of eleven, not just the ten the ledger reported.
///
/// T-791 asks the same question of the two other T-674 follow-ups before either is treated as
/// fully closed: **T-673's row-removal glyph and T-674's private icon-button helper are both
/// idioms that plausibly appear elsewhere already named**, and a naming-gap sweep is structurally
/// blind to that. This file is the sweep, done by shape rather than by gap, with its findings.
///
/// **T-673's shape — a row's own glyph naming which row.** Measured 2026-09-04: every
/// `Image(systemName: "xmark"...)` button in the tree (19 sites) was read by hand rather than
/// swept for a missing label, because the defect T-673 fixed was never "no label" alone — it was
/// a label that named the *action* ("Remove") without the *subject* (which row). Two more
/// instances of the same idiom already existed and were never ledgered because they were already
/// correct: `CadenceTagChip.removeButton` (`.accessibilityLabel("Remove tag
/// \(CadenceTagChipStyle.displayName(for: tag))")`) and `iOSAINoteActionsViews.chipRow`
/// (`.accessibilityLabel("Clear \(chip.label)")`, which also draws a visible `Text(chip.label)`).
/// Every other `xmark` site is a **singleton** control (one "Close" per sheet, one "Clear date"
/// per field) with no "which one" question to answer, so T-673's subject-naming rule does not
/// apply to it. Nothing here needed a fix; the finding is that there was nothing to find.
///
/// **T-674's shape — a private helper wrapping `Button` around a bare `Image(systemName:)`.**
/// T-674 fixed four of these (`stepButton`, `timelineNavButton`, `actionButton`,
/// `focusRowIconButton`) by making their name parameter required. A shape sweep — by function
/// name (`*icon*`/`*glyph*`/`*Button*`) and by parameter label (`icon:`/`systemName:`), cross-
/// checked by reading every candidate — found **three more that already required a name and so
/// were never in `knownUnnamedIconButtonSites` at any point**: `TimelineBundleBlockSupportViews
/// .rowIconButton`, `TaskInspectorContentSupportViews.iconButton`, and
/// `SettingsTagsSection.rowButton`. Seven near-identical private helpers, not four, is the
/// duplication surface T-791 says an accessibility ledger cannot show — hoisting them into one
/// shared component (the `CadenceSearchFieldClearButton` treatment) is a separate design decision
/// with its own parameter list to work out and is deliberately not attempted here; this suite's
/// job is to make the population visible and keep it from silently losing the property T-674
/// established, not to perform the hoist.
///
/// `ListEditorSupportViews.ListEditorIconCell` is the same idiom as a `struct` rather than a
/// `func` and is not in the ledger below for that reason — a different declaration shape needs a
/// different reader, not a bent one.
///
/// **A sweep, not a parser.** This is not a whole-tree structural scan for the shape (T-796 and
/// T-797's `.onTapGesture` detectors show what that costs to build and validate); it is a name-
/// and-parameter-pattern search cross-checked by reading every candidate it turned up, which is
/// weaker than a proof of exhaustiveness but is what T-791 asks for: seeing the idiom, not the
/// naming gap, over the population that pattern search can reach.
struct CadenceIconOnlyHelperIdiomDuplicationTests {

    /// The seven private helpers, keyed by the file that declares them. T-674 fixed the first
    /// four; the last three already required a name before T-674 existed.
    private static let iconButtonHelperSites: [String: String] = [
        "Cadence/macOS/Views/HabitsFormSupportViews.swift": "stepButton",
        "Cadence/macOS/Views/GoalTimelineView.swift": "timelineNavButton",
        "Cadence/macOS/Views/SettingsSupportViews.swift": "actionButton",
        "Cadence/macOS/Views/FocusBundleTaskSupportViews.swift": "focusRowIconButton",
        "Cadence/macOS/Views/TimelineBundleBlockSupportViews.swift": "rowIconButton",
        "Cadence/macOS/Views/TaskInspectorContentSupportViews.swift": "iconButton",
        "Cadence/macOS/Views/SettingsTagsSection.swift": "rowButton",
    ]

    /// **The population T-791 says a naming-gap ledger cannot show.** Seven, not
    /// `knownUnnamedIconButtonSites`' four (T-611's remaining iOS two plus whatever T-674 was
    /// working through at the time) — the other three were never unnamed, so no accessibility
    /// sweep's report ever had a reason to mention them.
    @Test func sevenNearCopiesOfThePrivateIconButtonHelperExist() throws {
        #expect(Self.iconButtonHelperSites.count == 7)
        // Four of the seven are the files T-674's commit names as gaining the required parameter.
        let t674Fixed: Set<String> = [
            "Cadence/macOS/Views/HabitsFormSupportViews.swift",
            "Cadence/macOS/Views/GoalTimelineView.swift",
            "Cadence/macOS/Views/SettingsSupportViews.swift",
            "Cadence/macOS/Views/FocusBundleTaskSupportViews.swift",
        ]
        let alreadyNamed = Set(Self.iconButtonHelperSites.keys).subtracting(t674Fixed)
        #expect(alreadyNamed.count == 3, "expected exactly the three copies no ledger ever saw")
    }

    /// Each of the seven still draws the shape (a `Button` around a bare `Image(systemName:)`)
    /// and still requires a name for it — read from disk rather than assumed from the ledger
    /// above, so a helper that quietly stopped being this idiom, or quietly stopped naming
    /// itself, fails here rather than going unnoticed because the ledger still lists its file.
    @Test func everyIconButtonHelperInTheAppStillNamesItself() throws {
        for (path, funcName) in Self.iconButtonHelperSites {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            guard let body = CadenceSourceScan.functionBody(named: funcName, in: source) else {
                Issue.record("\(path) no longer declares \(funcName)(…)")
                continue
            }
            #expect(body.contains("Button"), "\(path).\(funcName) is no longer a Button")
            #expect(body.contains("Image(systemName:"), "\(path).\(funcName) is no longer an icon button")
            #expect(
                body.contains(".cadenceControlLabel(") || body.contains(".accessibilityLabel("),
                """
                \(path).\(funcName) stopped naming itself — this is exactly the regression a \
                naming-gap sweep would not have caught until VoiceOver reached it
                """
            )
        }
    }

    /// **The two T-673-shaped row-removal glyphs no ledger ever listed**, read fresh rather than
    /// assumed clean: each names the item it removes, not only the act of removing it.
    @Test func theTwoUnledgeredRowRemovalGlyphsNameTheirSubject() throws {
        let tagChip = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceTagChip.swift")
        )
        guard let removeBody = CadenceSourceScan.functionBody(named: "removeButton", in: tagChip) else {
            Issue.record("CadenceTagChip no longer declares removeButton(…)")
            return
        }
        #expect(removeBody.contains(#".accessibilityLabel("Remove tag \(CadenceTagChipStyle.displayName(for: tag))")"#))

        let aiNoteActions = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSAINoteActionsViews.swift")
        )
        guard let chipRowBody = CadenceSourceScan.declarationBody("var chipRow: some View", in: aiNoteActions) else {
            Issue.record("iOSAINoteActionsViews no longer declares chipRow")
            return
        }
        #expect(chipRowBody.contains(#".accessibilityLabel("Clear \(chip.label)")"#))
        // This one also draws a visible Text, so an icon-only sweep was never the rule that would
        // have reached it either way — a second, independent reason it carries no ledger entry.
        #expect(chipRowBody.contains("Text(chip.label)"))
    }
}
