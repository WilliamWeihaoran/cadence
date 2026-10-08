import Foundation
import Testing
@testable import Cadence

/// **T-1107.** Two forms put a section label exactly as far from the block above it as from the
/// block it names, which is to say attached to neither: macOS Settings' Contexts pane stacked its
/// eyebrows and cards as four siblings of one 16pt `VStack`, and `CreateGoalSheet` stacked every
/// label and control as siblings of one 20pt `VStack`. Both now group each label with the block it
/// names at `CadenceSectionLabelMetrics.labelToNamedBlock`, leaving the larger outer spacing to
/// separate whole sections.
///
/// The gap is **one** value, read by `CadenceFieldSection` as well, because it is one relation.
/// These assertions are about composition rather than a number: a pane can keep the right constant
/// and still put the label back in the outer stack, which is the defect.
struct CadenceSectionLabelGroupingTests {

    private static let fieldRowsFile = "Cadence/Shared/Components/CadenceFieldRows.swift"
    private static let contextsFile = "Cadence/macOS/Views/SettingsListManagementSections.swift"
    private static let dataSafetyFile = "Cadence/macOS/Views/SettingsDataSafetySection.swift"
    private static let aboutFile = "Cadence/macOS/Views/SettingsAboutSection.swift"
    private static let groupOpener = "CadenceSectionLabelMetrics.labelToNamedBlock"

    /// The constant has one definition and the shared titled group reads it, so a call site that
    /// reaches for it is reaching for the same number `CadenceFieldSection` already draws — not a
    /// second opinion that can drift from it.
    @Test func theLabelGapIsDeclaredOnceAndTheSharedTitledGroupReadsIt() throws {
        #expect(CadenceSectionLabelMetrics.labelToNamedBlock == 10)

        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile(Self.fieldRowsFile)
        )
        #expect(code.contains("struct CadenceFieldSection"), "non-vacuity: still the titled group's file")
        #expect(
            code.contains("spacing: title == nil ? 0 : \(Self.groupOpener)"),
            "CadenceFieldSection spells its own title gap again instead of reading the shared one"
        )
        // The literal it replaced is gone from that view, not merely supplemented.
        #expect(CadenceSourceScan.matchCount("spacing: title == nil \\? 0 : 10", in: code) == 0)
    }

    /// **The SP-1 site.** Both eyebrows in the Contexts pane open a grouping stack; neither is a
    /// bare sibling of the 16pt section stack any more.
    @Test func theContextsPaneGroupsEachEyebrowWithTheCardItNames() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.contextsFile))
        let body = try #require(
            CadenceSourceScan.declarationBody("struct SettingsContextsSection: View", in: code),
            "non-vacuity: the Contexts section declaration was not found"
        )
        #expect(CadenceSourceScan.matchCount("SettingsSectionLabel\\(", in: body) == 2)
        #expect(CadenceSourceScan.matchCount("SettingsCard \\{", in: body) == 2)
        // The outer separation between the two sections is deliberately unchanged.
        #expect(CadenceSourceScan.matchCount("VStack\\(alignment: \\.leading, spacing: 16\\)", in: body) == 1)

        let stranded = Self.eyebrowsOutsideAGroup(in: body, drawnBy: "SettingsSectionLabel(")
        #expect(
            stranded.isEmpty,
            "eyebrow(s) still stacked as a sibling of the section stack: \(stranded.joined(separator: " | "))"
        )
    }

    // **`theGoalSheetGroupsEveryLabelWithTheControlItNames` left with [[T-2079]].**
    //
    // It was R38's site: every label in `CreateGoalSheet` had to be `fieldGroup`'s first child
    // rather than a bare `fieldLabel(` stacked as a sibling, and the sheet's two date fields
    // had to stop spelling their own `6` instead of
    // `CadenceSectionLabelMetrics.labelToNamedBlock`. The sheet is deleted. The metric has one
    // definition and the shared titled group still reads it, which is the first test in this
    // suite, and the other three sites are untouched.

    /// **T-1126.** The four panes that still hand-stacked the same pair, one positional check each.
    ///
    /// Per pane rather than per file, and positional rather than counted, for the reason the
    /// detector's own note gives: a file's count of grouping stacks matching its count of labels is
    /// satisfied by two labels inside one group. `declarationBody` is what makes "per pane" mean
    /// anything here — three of these panes share `SettingsListManagementSections.swift` with
    /// `SettingsContextsSection`, which T-1107 already converted and which would otherwise vouch
    /// for its neighbours.
    ///
    /// **Two eyebrows deliberately in scope that the ticket counted as non-offenders**: Settings →
    /// About's "Build" and the inactive-lists pane's empty-branch label are each their stack's
    /// first child, so neither sat below anything. They are grouped anyway, because a pane that
    /// draws its first heading 16pt from its card and its second 10pt from theirs has replaced one
    /// inconsistency with another. Every eyebrow in a converted pane is grouped; that is what makes
    /// `eyebrowsOutsideAGroup` the whole assertion rather than a list of exceptions.
    @Test func theFourRemainingSettingsPanesGroupEveryEyebrowWithTheBlockItNames() throws {
        let listManagement = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.contextsFile))
        let dataSafety = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.dataSafetyFile))
        let about = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.aboutFile))

        // (declaration, source, eyebrows the pane draws). The count is non-vacuity — it says the
        // scan found the pane it names — and the positional sweep below is the rule.
        let panes: [(declaration: String, code: String, eyebrows: Int)] = [
            ("struct SettingsCalendarSection: View", listManagement, 3),
            ("struct SettingsListsSection: View", listManagement, 7),
            // 2 since [[T-1532]]: "Available Backups" and "Other Backup Folders", the second of
            // which lists the backups directories beside store locations the app has left behind.
            // 3 since [[T-1680]]: "Other Cadence Data Folders", the *stores* the app is not using
            // — the `Recovery/` folder inside the live store directory, and the earlier store
            // locations — none of which the reset deletes and none of which any screen named.
            // 4 since [[T-3045]]: "Unrestored Store Files", the folders a restore moved aside.
            ("struct SettingsDataSafetySection: View", dataSafety, 4),
            ("struct SettingsAboutSection: View", about, 2)
        ]

        for pane in panes {
            let body = try #require(
                CadenceSourceScan.declarationBody(pane.declaration, in: pane.code),
                "non-vacuity: \(pane.declaration) was not found"
            )
            #expect(
                CadenceSourceScan.matchCount("SettingsSectionLabel\\(", in: body) == pane.eyebrows,
                "\(pane.declaration) draws a different number of eyebrows than this check was written against"
            )
            let stranded = Self.eyebrowsOutsideAGroup(in: body, drawnBy: "SettingsSectionLabel(")
            #expect(
                stranded.isEmpty,
                "\(pane.declaration): eyebrow(s) still stacked as a sibling of the section stack: \(stranded.joined(separator: " | "))"
            )
        }
    }

    /// The lines that draw an eyebrow without a grouping stack opening directly above them.
    ///
    /// Deliberately positional rather than a count: `spacing:` appearing somewhere in the same
    /// declaration proves nothing about which children the label was stacked with, and a count of
    /// grouping stacks equal to the count of labels is satisfied by two groups with both labels in
    /// one of them.
    private static func eyebrowsOutsideAGroup(in body: String, drawnBy call: String) -> [String] {
        let lines = body.components(separatedBy: "\n")
        return lines.indices.compactMap { index in
            guard lines[index].contains(call) else { return nil }
            let previous = index > 0 ? lines[index - 1] : ""
            guard !previous.contains(groupOpener) else { return nil }
            return lines[index].trimmingCharacters(in: .whitespaces)
        }
    }

    /// The detector above, against text that is not the repository — so the sweep it backs cannot
    /// be one reflow away from reporting a clean pane because it matched nothing at all.
    @Test func theGroupingDetectorSeparatesAStrandedLabelFromAGroupedOne() {
        let stranded = """
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionLabel(text: copy.archived)
            SettingsCard { rows }
        }
        """
        let grouped = """
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: CadenceSectionLabelMetrics.labelToNamedBlock) {
                SettingsSectionLabel(text: copy.archived)
                SettingsCard { rows }
            }
        }
        """
        #expect(Self.eyebrowsOutsideAGroup(in: stranded, drawnBy: "SettingsSectionLabel(").count == 1)
        #expect(Self.eyebrowsOutsideAGroup(in: grouped, drawnBy: "SettingsSectionLabel(").isEmpty)
    }
}
