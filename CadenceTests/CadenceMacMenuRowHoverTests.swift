import Foundation
import Testing
@testable import Cadence

/// **[[T-9465]].** A Mac choice-menu row lights ONE hover layer at one radius.
///
/// The rows took `.buttonStyle(.cadencePlain)` -- whose own hover wash is a 10pt fill plus stroke
/// around the label -- and then added a second plate on top at 6pt (`CreateTaskPickerHover`,
/// `TaskPickerRowHover`, `CalendarPickerRowHover`, `ContextPickerRowHover`, a hand-rolled
/// `isHovered` fill, or `.cadenceHoverHighlight(cornerRadius: 6)`), so one pointer drew two
/// rounded rectangles that disagreed at the corners. `.cadenceMenuRow` is now the one plate.
@Suite struct CadenceMacMenuRowHoverTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// The style paints one fill at one radius, and no stroke.
    @Test func theRowStyleIsOneFillAtOneRadius() throws {
        let source = try Self.code("Cadence/Shared/CadenceHoverStyles.swift")
        let body = try #require(CadenceSourceScan.declarationBody(
            "private struct CadenceMenuRowButtonBody: View", in: source
        ))
        #expect(body.components(separatedBy: "RoundedRectangle(").count - 1 == 1, "the row style draws more than one plate")
        #expect(!body.contains("strokeBorder"), "the row style strokes its plate as well as filling it")
        #expect(body.contains("CadenceHoverTracking(isHovered: $isHovered)"), "the row style does not track the pointer")
        #expect(CadenceMenuRowButtonStyle.cornerRadius == 6)
        #expect(CadenceMenuRowButtonStyle.hoverOpacity > 0)
        #expect(CadenceMenuRowButtonStyle.pressedOpacity > CadenceMenuRowButtonStyle.hoverOpacity)
    }

    /// No Mac control pairs `.cadencePlain`'s wash with a second hover plate of its own.
    @Test func noMacControlStacksASecondPlateOnCadencePlain() throws {
        var offenders: [String] = []
        var scanned = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/macOS") {
            let lines = try Self.code(path).components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for (index, line) in lines.enumerated() where line.contains(".buttonStyle(.cadencePlain") {
                scanned += 1
                for next in lines[(index + 1)..<min(index + 5, lines.count)]
                where next.contains(".cadenceHoverHighlight(") || next.contains("Hover())") {
                    offenders.append("\(path): \(next)")
                }
            }
        }
        #expect(scanned > 50, "non-vacuity: only \(scanned) .cadencePlain buttons under Cadence/macOS")
        #expect(offenders.isEmpty, "a second hover plate on .cadencePlain: \(offenders)")
    }

    /// Every menu the ticket named draws its rows with the row style, and the per-site plates are gone.
    @Test func theNamedMenusUseTheRowStyle() throws {
        let sites: [String: Int] = [
            "Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift": 2,
            "Cadence/macOS/Views/TasksPanelSupportViews.swift": 1,
            "Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift": 1,
            "Cadence/macOS/CadenceCalendarPicker.swift": 1,
            "Cadence/macOS/Views/CadenceContextPicker.swift": 1,
            "Cadence/macOS/Views/TagPickerPopoverViews.swift": 4,
            "Cadence/macOS/Views/TagPickerSupportViews.swift": 1,
            "Cadence/macOS/Views/TaskTitleInlineTagPicker.swift": 2,
        ]
        for (path, expected) in sites {
            let source = try Self.code(path)
            let uses = source.components(separatedBy: ".buttonStyle(.cadenceMenuRow)").count - 1
            #expect(uses == expected, "\(path) has \(uses) row-style buttons, expected \(expected)")
            for retired in ["CreateTaskPickerHover", "TaskPickerRowHover", "CalendarPickerRowHover", "ContextPickerRowHover"] {
                #expect(!source.contains(retired), "\(path) still spells \(retired)")
            }
        }
        // The two rows that hand-rolled a hover fill no longer track the pointer themselves.
        for (path, row) in [
            ("Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift", "struct TildeContainerPickerRow: View"),
            ("Cadence/macOS/Views/TaskTitleInlineTagPicker.swift", "private struct InlineTagPickerRow: View"),
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(row, in: try Self.code(path)), "\(row) moved")
            #expect(!body.contains("onHover"), "\(row) lights its own hover fill again")
        }
    }

    /// The task row's do-date, due-date and repeat chips light their own underline and 4pt wash;
    /// `.cadencePlain` added a third, 10pt blue layer around them.
    @Test func theTaskRowChipsLightOnlyTheirOwnHover() throws {
        let source = try Self.code("Cadence/macOS/Views/TasksPanelComponents.swift")
        for chip in ["isDoDateHovered", "isDueDateHovered", "isRepeatChipHovered"] {
            let wash = try #require(
                source.range(of: ".background(\(chip) ? Theme.surfaceElevated.opacity(0.55) : .clear)"),
                "non-vacuity: the \(chip) chip's wash moved"
            )
            let after = source[wash.upperBound...]
            let style = try #require(after.range(of: ".buttonStyle("), "the \(chip) chip has no button style")
            #expect(after[style.lowerBound...].hasPrefix(".buttonStyle(.plain)"),
                    "the \(chip) chip lights .cadencePlain's wash around its own")
        }
    }
}
