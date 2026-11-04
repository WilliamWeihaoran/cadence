import Foundation
import Testing
@testable import Cadence

/// **[[T-10187]]: the iOS Local Data tiles wear the list-kind glyphs the choosers and the Mac use.**
///
/// Projects drew a flag — the app's Due Date / Priority glyph — and Contexts drew the stacked
/// squares every list chooser draws for a project. A project's glyph is `CadenceListKindIcon`'s
/// now, and contexts take `square.stack.fill`, the default every new context already wears, so
/// two adjacent tiles never share a symbol.
struct CadenceLocalDataTileGlyphTests {
    @Test func everyListKindHasItsOwnGlyph() {
        let glyphs = [
            CadenceListKindIcon.inbox, CadenceListKindIcon.area,
            CadenceListKindIcon.project, CadenceListKindIcon.context,
        ]
        #expect(Set(glyphs).count == glyphs.count, "two list kinds share a glyph")
        #expect(CadenceListKindIcon.context == Context(name: "Probe").icon, "the kind glyph is not a new context's own")
        #expect(CadenceListKindIcon.contextOutline + ".fill" == CadenceListKindIcon.context)
    }

    @Test func theContextsSettingsCategoryWearsTheContextGlyph() {
        #expect(CadenceSettingsCategoryKind.contexts.icon == CadenceListKindIcon.context)
        #expect(CadenceSettingsCategoryKind.contexts.icon != CadenceListKindIcon.project)
    }

    @Test func theLocalDataTilesReadTheListKindGlyphs() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsOverviewSections.swift")
        )
        let section = try #require(CadenceSourceScan.declarationBody("struct iOSLocalDataSettingsSection: View", in: source))
        for (title, glyph) in [
            ("Inbox", "inbox"), ("Contexts", "context"), ("Areas", "area"), ("Projects", "project"),
        ] {
            #expect(
                section.contains("iOSSettingsMetricTile(title: \"\(title)\", value: ") &&
                    CadenceSourceScan.matchCount(
                        #"title: ""# + title + #"", value: "[^"]*", icon: CadenceListKindIcon\."# + glyph + #","#,
                        in: section
                    ) == 1,
                "the \(title) tile does not read CadenceListKindIcon.\(glyph)"
            )
        }
        #expect(!section.contains("\"flag.fill\""), "a list tile wears the Due Date / Priority flag again")
        #expect(!section.contains("\"square.stack.3d.up.fill\""), "a tile spells the project glyph by hand")
    }

    /// Both platforms' empty Contexts rows draw the outline form of the same glyph.
    @Test func theContextsEmptyRowsWearTheContextGlyph() throws {
        for path in ["Cadence/iOS/iOSSettingsView.swift", "Cadence/macOS/Views/SettingsListManagementSections.swift"] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("systemImage: CadenceListKindIcon.contextOutline,"), "\(path)")
            #expect(!source.contains("\"square.stack.3d.up\""), "\(path) still draws the project's squares for contexts")
        }
    }
}
