import Foundation
import Testing
@testable import Cadence

/// iOS controls whose drawn row is wider than the part that took a tap (agent `hunt1607ios`).
///
/// `Cadence/iOS/` is invisible to this macOS-built target, so each control is read as source.
/// The shared defect: `.buttonStyle(.plain)` and `.iosPressable` add no hit shape of their own,
/// so a label stretched by `.frame` is tappable only where it draws glyphs.

/// [[T-9481]]: the phone's landscape Focus layout draws the shared back control, not a private
/// chevron that was black where portrait's is blue and dead outside its glyph.
struct CadenceIOSFocusLandscapeBackButtonTests {
    @Test func theLandscapeLayoutDrawsTheSharedBackControl() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift")
        let layout = try #require(CadenceSourceScan.declarationBody("private func landscapeLayout(", in: source))
        #expect(layout.contains("sessionClock(fontSize: 66)"), "non-vacuity: the slice holds the landscape clock")
        #expect(layout.contains("iOSHeaderBackButton(action:"), "the landscape back control is not the shared one")
        #expect(!layout.contains("Image(systemName: \"chevron.left\")"), "a private chevron is back in the landscape header")
    }
}

/// [[T-9482]]: a note's Outline and Unlinked Mentions sheet rows take a tap across their width.
struct CadenceIOSNoteNavigationSheetRowTests {
    @Test func bothSheetRowsAreTheirWholeRow() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        let outline = try #require(CadenceSourceScan.declarationBody("private var outlineSheet:", in: source))
        let mentions = try #require(CadenceSourceScan.declarationBody("private var unlinkedMentionsSheet:", in: source))
        #expect(outline.contains("jumpToHeading(item)"), "non-vacuity: the slice holds the outline row")
        #expect(mentions.contains("linkMention(note)"), "non-vacuity: the slice holds the mention row")
        let rowShape = #"minHeight: 44, alignment: \.leading\)\s*\.contentShape\(Rectangle\(\)\)"#
        #expect(CadenceSourceScan.matchCount(rowShape, in: outline) == 1, "the outline row is dead beside its heading")
        #expect(CadenceSourceScan.matchCount(rowShape, in: mentions) == 1, "the mention row is dead beside its title")
    }
}

/// [[T-9483]]: the iOS list editor's Add Column row takes a tap across the form row.
struct CadenceIOSListEditorAddColumnRowTests {
    @Test func theAddColumnRowIsItsWholeRow() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListEditorViews.swift")
        let body = CadenceSourceScan.strippingComments(source)
        let start = try #require(body.range(of: "sectionDrafts.append(CadenceSectionDraft(name: \"\"))"))
        let tail = String(body[start.upperBound...].prefix(1_500))
        let label = try #require(tail.components(separatedBy: ".buttonStyle(.plain)").first)
        #expect(label.contains("Text(\"Add Column\")"), "non-vacuity: the slice holds the Add Column label")
        #expect(label.contains(".frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)"), "the row no longer spans the form")
        #expect(label.contains(".contentShape(Rectangle())"), "the row is dead beside its words")
    }
}
