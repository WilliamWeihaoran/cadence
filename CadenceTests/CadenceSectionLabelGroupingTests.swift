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
    private static let goalSheetFile = "Cadence/macOS/Sheets/CreateGoalSheet.swift"
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

    /// **The R38 site.** Every label in the goal sheet is `fieldGroup`'s first child, and the two
    /// date fields that were already grouped no longer spell their own `6`.
    @Test func theGoalSheetGroupsEveryLabelWithTheControlItNames() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(Self.goalSheetFile))
        #expect(code.contains("struct CreateGoalSheet: View"), "non-vacuity: still the sheet")

        // The bare-label spelling is gone, not supplemented: there is nothing left to stack.
        #expect(
            CadenceSourceScan.matchCount("fieldLabel\\(", in: code) == 0,
            "the goal sheet can still drop a bare label into the section stack"
        )
        // Eleven controls, plus the helper's own declaration.
        #expect(CadenceSourceScan.matchCount("fieldGroup", in: code) == 12)
        #expect(
            code.contains("VStack(alignment: .leading, spacing: \(Self.groupOpener))"),
            "the goal sheet's field group no longer reads the shared gap"
        )

        let body = try #require(
            CadenceSourceScan.declarationBody("var body: some View", in: code),
            "non-vacuity: the sheet's body was not found"
        )
        #expect(CadenceSourceScan.matchCount("VStack\\(alignment: \\.leading, spacing: 20\\)", in: body) == 1)
        // The two date groups used to be the only grouped pair in the sheet, at their own 6.
        #expect(
            CadenceSourceScan.matchCount("VStack\\(alignment: \\.leading, spacing: 6\\)", in: body) == 0,
            "a field group in the goal sheet still spells its own gap"
        )
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
