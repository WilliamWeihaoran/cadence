#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-18815.** The Mac list-family pickers hold one width. A macOS popover sizes to its content's
/// ideal size and a `Text`'s ideal width is its whole string on one line, so the `~` panel
/// (`minWidth: 200`), the list chip's popover (`minWidth: 190`) and the section chip's popover
/// (`minWidth: 170`) each stretched to the widest list or section name, while the `#` panel and tag
/// popover beside them held 240. A width is not observable from a unit test without a window, so
/// what is pinned is that every one of the five frames names the one shared figure, no bare
/// `minWidth:` remains, and every list-family row is one tail-truncated line.
@MainActor
struct CadenceMacListPickerWidthTests {
    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let file = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        return try #require(
            CadenceSourceScan.declarationBody(declaration, in: file),
            "could not read \(declaration)"
        ).filter { !$0.isWhitespace }
    }

    private static let pickers: [(declaration: String, path: String)] = [
        ("struct TildeContainerPicker: View", "Cadence/macOS/Views/TildeContainerPicker.swift"),
        ("struct ContainerPickerPopoverContent: View", "Cadence/macOS/Views/ContainerPickerSupportViews.swift"),
        ("struct TaskSectionPickerBadge: View", "Cadence/macOS/Views/TasksPanelSupportViews.swift"),
        ("struct TaskTitleInlineTagPicker: View", "Cadence/macOS/Views/TaskTitleInlineTagPicker.swift"),
        ("struct TagPickerPopover: View", "Cadence/macOS/Views/TagPickerPopoverViews.swift"),
    ]

    @Test func everyListFamilyPickerHoldsTheOneSharedWidth() throws {
        for picker in Self.pickers {
            let body = try Self.compactBody(picker.declaration, in: picker.path)
            #expect(
                CadenceSourceScan.matchCount(#"\.frame\(width:CadenceMacListPickerMetrics\.width\)"#, in: body) == 1,
                "\(picker.declaration) must hold the shared list-picker width"
            )
            #expect(!body.contains("minWidth:"), "\(picker.declaration): a bare minWidth lets one long name stretch the popover")
        }
    }

    @Test func theListPickersCapTheirScrolledHeightWithTheSharedFigure() throws {
        for picker in Self.pickers.prefix(2) {
            let body = try Self.compactBody(picker.declaration, in: picker.path)
            #expect(body.contains("ScrollViewReader{proxyinScrollView{"), "\(picker.declaration)")
            #expect(body.contains(".frame(maxHeight:CadenceMacListPickerMetrics.maxListHeight)"), "\(picker.declaration)")
        }
        let tilde = try Self.compactBody(Self.pickers[0].declaration, in: Self.pickers[0].path)
        #expect(tilde.contains(".id(index)"), "scrollTo needs each ~ row tagged with its highlight index")
        #expect(tilde.contains(".onChange(of:highlightIndex){_,_inproxy.scrollTo(clampedHighlightIndex)}"),
                "an arrow move must scroll the highlighted row into view")
    }

    @Test func theSharedFiguresAreTheTagPickersWidthAndTheListPickersHeight() {
        #expect(CadenceMacListPickerMetrics.width == 240)
        #expect(CadenceMacListPickerMetrics.maxListHeight == 320)
    }

    @Test func everyListFamilyRowIsOneTailTruncatedLine() throws {
        let rows: [(String, String, String)] = [
            ("struct TildeContainerPickerRow: View", "Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift", "name"),
            ("private struct ContainerPickerRow: View", "Cadence/macOS/Views/ContainerPickerSupportViews.swift", "name"),
            ("private struct SectionPickerRow: View", "Cadence/macOS/Views/TasksPanelSupportViews.swift", "section"),
        ]
        for (declaration, path, field) in rows {
            let body = try Self.compactBody(declaration, in: path)
            #expect(
                body.contains("Text(\(field)).font(.system(size:13)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)"),
                "\(declaration) must draw its name on one tail-truncated line"
            )
        }
    }
}
#endif
