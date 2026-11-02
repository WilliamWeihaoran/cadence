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
            // [[T-9944]]: + the section picker's rows.
            "Cadence/macOS/Views/TasksPanelSupportViews.swift": 2,
            // [[T-9944]]: the list picker's rows.
            "Cadence/macOS/Views/ContainerPickerSupportViews.swift": 1,
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
            // [[T-9944]]: these two lit `.cadencePlain`'s wash and stroke over their own hover fill.
            ("Cadence/macOS/Views/ContainerPickerSupportViews.swift", "private struct ContainerPickerRow: View"),
            ("Cadence/macOS/Views/TasksPanelSupportViews.swift", "private struct SectionPickerRow: View"),
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(row, in: try Self.code(path)), "\(row) moved")
            #expect(!body.contains("onHover"), "\(row) lights its own hover fill again")
        }
    }

    /// **[[T-9944]].** The list and section pickers' rows wear the row style and nothing else: one
    /// plate under the pointer, the keyboard highlight a fill at that plate's radius.
    @Test func theListAndSectionPickerRowsLightOnePlate() throws {
        for (path, row) in [
            ("Cadence/macOS/Views/ContainerPickerSupportViews.swift", "private struct ContainerPickerRow: View"),
            ("Cadence/macOS/Views/TasksPanelSupportViews.swift", "private struct SectionPickerRow: View"),
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(row, in: try Self.code(path)), "\(row) moved")
            #expect(CadenceSourceScan.matchCount("\\.buttonStyle\\(", in: body) == 1, "\(row) has more or fewer than one button style")
            #expect(body.contains(".buttonStyle(.cadenceMenuRow)"), "\(row) is not on the row style")
            #expect(!body.contains("cadencePlain"), "\(row) lights .cadencePlain's wash and stroke again")
            #expect(!body.contains("isHovered"), "\(row) paints its own hover fill under the row style's")
            // Non-vacuity: the keyboard highlight is still drawn, at the row style's radius.
            #expect(body.contains(".background(isHighlighted ? Theme.blue.opacity(0.08) : Color.clear)"), "\(row) lost its highlight")
            #expect(body.contains("RoundedRectangle(cornerRadius: CadenceMenuRowButtonStyle.cornerRadius)"), "\(row) clips at another radius")
        }
    }

    /// **[[T-9945]].** The Focus picker's task row keeps its own plate -- the brighter fill and the
    /// task-tinted stroke -- as its one hover layer, so its button lights nothing of its own.
    @Test func theFocusTaskRowsLightOnlyTheirOwnPlate() throws {
        for (path, row, fill) in [
            ("Cadence/macOS/Views/FocusPickerSupportViews.swift", "private struct FocusPickItemRow: View",
             ".background(Theme.surfaceElevated.opacity(isHovered ? 0.88 : 0.58))"),
            ("Cadence/macOS/Views/FocusSidebarSupportViews.swift", "struct FocusSidebarTaskRow: View",
             ".background(Theme.surfaceElevated.opacity(isHovered ? 0.78 : 0.52))"),
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(row, in: try Self.code(path)), "\(row) moved")
            // Non-vacuity: the row's own hover plate is still there.
            #expect(body.contains(fill), "\(row)'s hover fill moved")
            #expect(body.contains(".onHover { isHovered = $0 }"), "\(row) no longer tracks the pointer")
            #expect(CadenceSourceScan.matchCount("\\.buttonStyle\\(", in: body) == 1, "\(row) has more or fewer than one button style")
            #expect(body.contains(".buttonStyle(.plain)"), "\(row) lights a button-style wash over its own plate")
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

    /// **[[T-9621]].** A Cmd+K row's highlight IS its hover layer -- a hover moves it -- so the
    /// row's button lights nothing of its own. On `.cadencePlain(cornerRadius: 12)` a hovered row
    /// drew the style's blue wash and stroke on top of its tinted highlight, and once the arrow keys
    /// moved the highlight on, the row still under the pointer kept the blue wash: two rows lit.
    @Test func theCommandPaletteRowsLightOnlyTheirHighlight() throws {
        let source = try Self.code("Cadence/macOS/Views/GlobalSearchSupportViews.swift")
        for row in ["struct GlobalSearchResultRow: View", "struct GlobalSearchMoreResultsRow: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(row, in: source), "\(row) moved")
            // Non-vacuity: the highlight is still drawn on the label and a hover still reaches it.
            #expect(body.contains("isHighlighted ?"), "\(row) no longer draws its highlight")
            #expect(body.contains("onHover()"), "\(row) no longer hands its hover to the highlight")
            #expect(CadenceSourceScan.matchCount("\\.buttonStyle\\(", in: body) == 1, "\(row) has more or fewer than one button style")
            #expect(body.contains(".buttonStyle(.plain)"), "\(row) lights a button-style hover wash beside its highlight")
            #expect(!body.contains("cadencePlain"), "\(row) is back on .cadencePlain")
        }
    }
}
