import Foundation
import Testing
@testable import Cadence

/// **[[T-11221]]: the Mac list board and the iOS/iPadOS list board read one column tint, one
/// lifecycle line and one archived empty state** (one app on two platforms, [[T-8201]]).
///
/// The rules are pinned by VALUE through the shared types both boards read; the iOS wiring by
/// source scan, since `CadenceTests` builds for macOS and never compiles `Cadence/iOS/`. The card's
/// strike rule is pinned beside the card's other settled styles, in
/// `CadenceCodexFunctionalParityTests.boardCardsUseTheRowsSettledStateForAllThreeStyles`.
@MainActor
struct CadenceBoardColumnParityTests {
    private static let iOSBoardFile = "Cadence/iOS/iOSListSupportViews.swift"
    private static let macHeaderFile = "Cadence/macOS/Views/KanbanColumnSupportViews.swift"
    private static let macColumnFile = "Cadence/macOS/Views/KanbanSectionColumnView.swift"
    private static let macBoardFile = "Cadence/macOS/Views/KanbanListSectionSupportViews.swift"

    private func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: - Column tint

    /// Default is neutral on both boards -- the Mac's reading. iOS drew its forced
    /// `defaultColorHex`, a colour nobody chose.
    @Test func defaultIsNeutralAndAConfiguredColumnIsItsOwnHex() {
        let defaultColumn = TaskSectionConfig(name: TaskSectionDefaults.defaultName)
        let doing = TaskSectionConfig(name: "Doing", colorHex: "#4a90d9")

        #expect(CadenceBoardColumnTint.base(for: defaultColumn) == .neutral)
        #expect(CadenceBoardColumnTint.dot(for: defaultColumn) == .neutral)
        #expect(CadenceBoardColumnTint.base(for: doing) == .section(hex: "#4a90d9"))
        #expect(CadenceBoardColumnTint.dot(for: doing) == .section(hex: "#4a90d9"))
    }

    /// Completed, or settling into it, is green on the dot; the base -- the Mac column's chrome --
    /// keeps the column's own colour.
    @Test func aCompletedOrSettlingColumnsDotIsGreenButItsBaseIsNot() {
        let shipped = TaskSectionConfig(name: "Shipped", colorHex: "#4a90d9", isCompleted: true)
        let doing = TaskSectionConfig(name: "Doing", colorHex: "#4a90d9")

        #expect(CadenceBoardColumnTint.dot(for: shipped) == .completed)
        #expect(CadenceBoardColumnTint.base(for: shipped) == .section(hex: "#4a90d9"))
        #expect(CadenceBoardColumnTint.dot(for: doing, isPendingCompletion: true) == .completed)
        #expect(CadenceBoardColumnTint.dot(for: doing, isPendingCompletion: false) == .section(hex: "#4a90d9"))
    }

    /// A name that exists only on a task has no config; iOS draws it in the list's colour.
    @Test func anUnconfiguredColumnTakesTheListsColour() {
        #expect(CadenceBoardColumnTint.base(for: nil) == .listAccent)
        #expect(CadenceBoardColumnTint.dot(for: nil) == .listAccent)
    }

    @Test func bothBoardsReadTheSharedTint() throws {
        let iOS = try code(Self.iOSBoardFile)
        #expect(iOS.contains("CadenceBoardColumnTint.dot(for: config(for: name)).color(listAccent: accent)"))
        #expect(!iOS.contains("Color(hex: config.colorHex)"), "the iOS board spells its own dot again")

        let header = try code(Self.macHeaderFile)
        #expect(header.contains("CadenceBoardColumnTint.dot(for: section, isPendingCompletion: isPendingCompletion)"))
        let column = try code(Self.macColumnFile)
        #expect(column.contains("CadenceBoardColumnTint.base(for: section).color(listAccent: Theme.dim)"))
        #expect(!column.contains("section.isDefault ? Theme.dim"), "the Mac column spells its own tint again")
    }

    // MARK: - Lifecycle line

    @Test func theLifecycleLineSaysCompletedThenCompletingThenNothing() {
        #expect(CadenceBoardColumnLifecycleCopy.label(isCompleted: true) == "Completed")
        #expect(CadenceBoardColumnLifecycleCopy.label(isCompleted: true, isPendingCompletion: true) == "Completed")
        #expect(CadenceBoardColumnLifecycleCopy.label(isCompleted: false, isPendingCompletion: true) == "Completing…")
        #expect(CadenceBoardColumnLifecycleCopy.label(isCompleted: false) == nil)
    }

    @Test func bothBoardsDrawTheSharedLifecycleLine() throws {
        let header = try code(Self.macHeaderFile)
        #expect(header.contains("CadenceBoardColumnLifecycleCopy.label("))
        #expect(header.contains("CadenceBoardColumnLifecycleLine(label: lifecycle)"))
        #expect(!header.contains("\"Completing…\""), "the Mac header spells its own words again")

        let iOS = try code(Self.iOSBoardFile)
        #expect(iOS.contains("CadenceBoardColumnLifecycleCopy.label(isCompleted: config(for: name)?.isCompleted ?? false)"))
        #expect(iOS.contains("lifecycleLabel: lifecycleLabel(for: column.title)"), "the iOS board never hands the column its line")
        #expect(iOS.contains("CadenceBoardColumnLifecycleLine(label: lifecycleLabel)"), "the iOS column never draws the line")
    }

    // MARK: - Archived empty board

    /// Show Archived with no archived column: the Mac drew a blank page where iOS said why.
    @Test func bothArchivedBoardsSayWhyTheyAreEmptyInTheSameWords() throws {
        #expect(CadenceEmptyStateCopy.listKanbanArchivedSystemImage == "archivebox")
        #expect(CadenceEmptyStateCopy.listKanbanSystemImage == "square.grid.3x2")

        let mac = try code(Self.macBoardFile)
        #expect(mac.contains("if columns.isEmpty && showArchivedBinding.wrappedValue {"))
        #expect(mac.contains("message: CadenceEmptyStateCopy.listKanbanArchivedTitle"))
        #expect(mac.contains("subtitle: CadenceEmptyStateCopy.listKanbanArchivedSubtitle"))
        #expect(mac.contains("icon: CadenceEmptyStateCopy.listKanbanArchivedSystemImage"))

        let panel = try #require(
            CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: try code(Self.iOSBoardFile)),
            "the iOS list board is gone"
        )
        #expect(panel.contains("? CadenceEmptyStateCopy.listKanbanArchivedSystemImage"))
        #expect(panel.contains(": CadenceEmptyStateCopy.listKanbanSystemImage"))
        #expect(!panel.contains("\"archivebox\""), "the iOS board spells its own glyph again")
    }
}
