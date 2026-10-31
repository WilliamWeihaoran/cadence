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

/// [[T-9485]]: a read-only note's task embed ticks a subtask on a near-miss of its circle instead
/// of letting the tap fall through to the card's open-task gesture.
struct CadenceIOSMarkdownPreviewEmbedSubtaskHitTests {
    @Test func theSubtaskCircleTakesATapAcrossItsFrameAndRowPitch() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownPreview.swift")
        let block = try #require(CadenceSourceScan.declarationBody("private struct iOSMarkdownPreviewTaskEmbedBlock: View", in: source))
        let body = CadenceSourceScan.strippingComments(block)
        let start = try #require(body.range(of: "onToggleSubtask?(task.id, subtask.id)"))
        let tail = String(body[start.upperBound...])
        let label = try #require(tail.components(separatedBy: ".buttonStyle(.plain)").first)
        #expect(label.contains(".frame(width: 22, height: 22)"), "non-vacuity: the slice holds the subtask circle")
        #expect(label.contains(".onTapGesture") == false, "non-vacuity: the slice stopped at the subtask button")
        #expect(CadenceSourceScan.matchCount(#"\.frame\(width: 22, height: 22\)\s*\.iOSExpandedHitArea\(3\)"#, in: label) == 1,
                "the subtask circle is hit only on its glyph, so a near-miss opens the task")
    }
}

/// [[T-9511]]: the note editor's Outline and Unlinked mentions links take a tap across the 44pt row
/// they are framed to, not only on their 12pt words.
struct CadenceIOSNoteNavigationLinkHitTests {
    @Test func bothLinksAreTheirWholeFrame() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        let bar = try #require(CadenceSourceScan.declarationBody("private var noteNavigation:", in: source))
        let body = CadenceSourceScan.strippingComments(bar)
        #expect(body.contains("showsOutline = true") && body.contains("showsUnlinkedMentions = true"), "non-vacuity: the slice holds both links")
        let framed = #"\.frame\(minHeight: 44\)\s*\.contentShape\(Rectangle\(\)\)"#
        #expect(CadenceSourceScan.matchCount(framed, in: body) == 2, "a link takes a tap only on its words")
    }
}

/// [[T-9513]]: the date-jump popover's Today/Now row takes a tap across its padded row, not only
/// the 34pt frame inside it -- the padding is inside the label, before the content shape.
struct CadenceIOSDateJumpNowRowHitTests {
    @Test func theNowRowIsItsWholePaddedRow() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSDateJumpTitle.swift")
        let popover = try #require(CadenceSourceScan.declarationBody("private struct iOSDateJumpPopover: View", in: source))
        let body = CadenceSourceScan.strippingComments(popover)
        let start = try #require(body.range(of: "onNow()"), "non-vacuity: the slice holds the return-to-now button")
        let tail = String(body[start.upperBound...])
        let label = try #require(tail.components(separatedBy: ".buttonStyle(.iosPressable)").first)
        #expect(label.contains("Text(nowTitle)"), "non-vacuity: the slice holds the now label")
        let padded = #"minHeight: 34\)\s*\.padding\(\.horizontal, 10\)\s*\.padding\(\.top, 8\)\s*\.padding\(\.bottom, 6\)\s*\.contentShape\(Rectangle\(\)\)"#
        #expect(CadenceSourceScan.matchCount(padded, in: label) == 1, "the now row's padding is outside its hit shape")
        let after = try #require(tail.components(separatedBy: ".buttonStyle(.iosPressable)").dropFirst().first)
        let beforeDivider = try #require(after.components(separatedBy: "Divider()").first)
        #expect(!beforeDivider.contains(".padding("), "padding outside the button style is dead space around the target")
    }
}
