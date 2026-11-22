import SwiftUI
import Testing
@testable import Cadence

/// **[[T-12741]].** An archived tag's row in Settings > Tags said so differently on each platform:
/// the Mac drew an "Archived" pill beside the title and kept the title at full ink, the phone dimmed
/// the title and drew no word at all. No hardware or input constraint separates the two
/// ([[T-8201]]), and the archived context rows on the same screens already agree (muted title, the
/// word "Archived"). Both tag rows now take the title ink and the pill from
/// `CadenceTagSettingsRowStyle` / `CadenceTagSettingsStatusPill`.
///
/// A view cannot be rendered here, so the decision is pinned directly and each platform's row is
/// read from source for its use of it.
@MainActor
struct CadenceTagSettingsArchivedRowTests {

    private static func body(_ declaration: String, in file: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
        return try #require(CadenceSourceScan.declarationBody(declaration, in: source),
                            "\(file) no longer declares \(declaration)")
    }

    private static func squeezed(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }

    @Test func anArchivedTagWearsTheArchivedPillAndALiveTagNone() {
        #expect(CadenceTagSettingsRowStyle.statusLabel(isArchived: true) == "Archived")
        #expect(CadenceTagSettingsRowStyle.statusLabel(isArchived: false) == nil)
    }

    @Test func anArchivedTagsTitleIsMutedAsTheArchivedContextRowsAre() {
        #expect(CadenceTagSettingsRowStyle.titleInk(isArchived: true) == Theme.muted)
        #expect(CadenceTagSettingsRowStyle.titleInk(isArchived: false) == Theme.text)
    }

    /// The phone's row, the half that drew no word at all.
    @Test func theIOSTagRowDrawsTheSharedPillBesideItsTitle() throws {
        let file = "Cadence/iOS/iOSSettingsTagsSection.swift"
        let display = Self.squeezed(try Self.body("private var displayContent", in: file))
        #expect(display.contains("CadenceTagSettingsRowStyle.statusLabel(isArchived:tag.isArchived)"),
                "the iOS tag row no longer asks whether to say Archived")
        #expect(display.contains("CadenceTagSettingsStatusPill(text:"),
                "the iOS tag row no longer draws the shared Archived pill")
        let title = Self.squeezed(try Self.body("private var tagTitle", in: file))
        #expect(title.contains("CadenceTagSettingsRowStyle.titleInk(isArchived:tag.isArchived)"),
                "the iOS tag title must take the shared archived ink")
    }

    /// **[[T-19604]].** At accessibility sizes the phone broke the pill into `Archive` over `d`. The
    /// one shared pill holds to a single line at its ideal width, on both platforms at once.
    @Test func theSharedArchivedPillNeverWraps() throws {
        let pill = Self.squeezed(try Self.body("struct CadenceTagSettingsStatusPill", in: "Cadence/Shared/CadenceSettingsSharedViews.swift"))
        #expect(pill.contains(".lineLimit(1)"), "the Archived pill may wrap again")
        #expect(pill.contains(".fixedSize()"), "the Archived pill no longer holds its ideal width, so a narrow row squeezes it")
    }

    /// **[[T-19604]].** The phone's title broke mid-word down twelve lines at accessibility sizes,
    /// squeezed by the pill beside it. The pill drops under the title when the row stacks, and the
    /// title's wrap is bounded and ends in an ellipsis instead of running uncapped.
    @Test func theIOSTagTitleKeepsItsWidthAndABoundedWrapAtAccessibilitySizes() throws {
        let file = "Cadence/iOS/iOSSettingsTagsSection.swift"
        let display = Self.squeezed(try Self.body("private var displayContent", in: file))
        #expect(display.contains("AnyLayout(VStackLayout(alignment:.leading,spacing:5)):AnyLayout(HStackLayout(spacing:7))"),
                "the Archived pill no longer drops under the title when the row stacks")
        #expect(!display.contains("HStack(spacing:7){tagTitle"),
                "the title and pill sit in a fixed HStack again, so the pill squeezes the title at every size")

        let title = Self.squeezed(try Self.body("private var tagTitle", in: file))
        #expect(title.contains("?CadenceTagSettingsRowStyle.accessibilityTitleLineLimit:1)"),
                "the iOS tag title no longer takes the shared bounded line limit at accessibility sizes")
        #expect(!title.contains("?nil:1)"), "the iOS tag title wraps uncapped again")
        #expect(title.contains(".truncationMode(.tail)"), "the iOS tag title must end in an ellipsis when it runs out of lines")
        #expect(CadenceTagSettingsRowStyle.accessibilityTitleLineLimit > 1,
                "accessibility sizes must still let a long name wrap past one line")
    }

    /// The Mac's row, the half whose title stayed at full ink.
    @Test func theMacTagRowDrawsTheSharedPillAndMutesItsTitle() throws {
        let file = "Cadence/macOS/Views/SettingsTagsSection.swift"
        let display = Self.squeezed(try Self.body("private var displayContent", in: file))
        #expect(display.contains("CadenceTagSettingsStatusPill(text:"),
                "the Mac tag row no longer draws the shared Archived pill")
        #expect(!display.contains("Text(\"Archived\")"),
                "the Mac tag row grew a second, hand-drawn Archived pill")
        let title = Self.squeezed(try Self.body("private var tagTitle", in: file))
        #expect(title.contains("CadenceTagSettingsRowStyle.titleInk(isArchived:tag.isArchived)"),
                "the Mac tag title must take the shared archived ink")
    }
}
