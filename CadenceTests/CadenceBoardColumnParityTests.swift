import Foundation
import SwiftUI
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
    private static let iOSEditorFile = "Cadence/iOS/iOSListEditorViews.swift"

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
        typealias Copy = CadenceBoardColumnLifecycleCopy
        #expect(Copy.line(isCompleted: true, isArchived: true)?.label == "Completed")
        #expect(Copy.line(isCompleted: true, isArchived: false, isPendingCompletion: true)?.label == "Completed")
        #expect(Copy.line(isCompleted: false, isArchived: false, isPendingCompletion: true)?.label == "Completing…")
        // The countdown draws in completion's colour, as it always has.
        #expect(Copy.line(isCompleted: false, isArchived: false, isPendingCompletion: true)?.state == .completed)
        #expect(Copy.line(isCompleted: false, isArchived: false) == nil)
    }

    /// **[[T-18034]].** Every column on the Show Archived board is archived; one archived without
    /// being completed said nothing at all under its header on either board. It says the iPad list
    /// editor's word for the same state ([[T-16132]]), in that state's amber.
    @Test func anArchivedColumnThatWasNeverCompletedSaysArchivedInAmber() throws {
        let line = try #require(CadenceBoardColumnLifecycleCopy.line(isCompleted: false, isArchived: true))
        #expect(line.label == "Archived")
        #expect(line.state == .archived)
        #expect(line.state.color == Theme.amber)
        let completed = try #require(CadenceBoardColumnLifecycleCopy.line(isCompleted: true, isArchived: true))
        #expect(completed.label == "Completed" && completed.state == .completed, "completed still wins over archived")
        #expect(completed.state.color == Theme.green)
    }

    /// [[T-16132]]: completing a column archives it ([[T-15722]]), so the order is the whole
    /// decision -- the iPad's list editor said "Archived" where the Mac's Show Archived board says
    /// "Completed" over the same column.
    @Test func aColumnsStateIsCompletedBeforeArchived() {
        typealias State = CadenceBoardColumnLifecycleState
        #expect(State.of(isCompleted: true, isArchived: true) == .completed)
        #expect(State.of(isCompleted: true, isArchived: false) == .completed)
        #expect(State.of(isCompleted: false, isArchived: true) == .archived)
        #expect(State.of(isCompleted: false, isArchived: false) == .active)
        #expect(State.of(isCompleted: true, isArchived: true).label == CadenceBoardColumnLifecycleCopy.line(isCompleted: true, isArchived: true)?.label)
        #expect(State.completed.color == CadenceBoardColumnTint.completed.color(listAccent: Theme.dim))
        #expect(State.archived.label == "Archived")
        #expect(State.active.label == "Active")
    }

    @Test func theListEditorRowReadsTheSharedState() throws {
        let editor = try code(Self.iOSEditorFile)
        #expect(editor.contains("Text(lifecycle.state.label)"), "the iOS row spells its own state word again")
        #expect(editor.contains(".foregroundStyle(lifecycle.state.color)"), "the iOS row spells its own state colour again")
        #expect(!editor.contains("if lifecycle.isArchived { return Theme.amber }"))
        let support = try code("Cadence/iOS/iOSColumnWindDownSupport.swift")
        #expect(support.contains("CadenceBoardColumnLifecycleState.of(isCompleted: isCompleted, isArchived: isArchived)"))
        #expect(!support.contains("if isArchived { return \"Archived\" }"))
    }

    @Test func bothBoardsDrawTheSharedLifecycleLine() throws {
        let header = try code(Self.macHeaderFile)
        #expect(header.contains("CadenceBoardColumnLifecycleCopy.line("))
        #expect(header.contains("isArchived: section.isArchived,"), "the Mac header hands the line no archived state ([[T-18034]])")
        #expect(header.contains("CadenceBoardColumnLifecycleLine(line: lifecycle)"))
        #expect(!header.contains("\"Completing…\""), "the Mac header spells its own words again")

        let iOS = try code(Self.iOSBoardFile)
        #expect(iOS.contains("CadenceBoardColumnLifecycleCopy.line("))
        #expect(iOS.contains("isArchived: config?.isArchived ?? false"), "the iOS board hands the line no archived state ([[T-18034]])")
        #expect(iOS.contains("lifecycleLine: lifecycleLine(for: column.title)"), "the iOS board never hands the column its line")
        #expect(iOS.contains("CadenceBoardColumnLifecycleLine(line: lifecycleLine)"), "the iOS column never draws the line")

        // [[T-18034]]: the line draws in its state's colour, so "Archived" is amber, not green.
        let line = try code("Cadence/Shared/CadenceBoardColumnTint.swift")
        #expect(line.contains(".foregroundStyle(line.state.color)"), "the lifecycle line paints every state one colour again")
    }

    // MARK: - Lifecycle offer

    /// **[[T-13101]].** An archived column offers Unarchive and no Complete / Reopen on either
    /// platform. The iOS list editor always drew it so; the Mac's Show Archived board still offered
    /// the header circle, the popover's "Complete Column" / "Reopen Column" and Cmd+Return.
    @Test func anArchivedColumnOffersNoCompletionToggleAndDefaultOffersNone() {
        let doing = TaskSectionConfig(name: "Doing")
        let shipped = TaskSectionConfig(name: "Shipped", isCompleted: true)
        let parked = TaskSectionConfig(name: "Parked", isArchived: true)
        let parkedDone = TaskSectionConfig(name: "Parked Done", isCompleted: true, isArchived: true)
        let defaultColumn = TaskSectionConfig(name: TaskSectionDefaults.defaultName)

        #expect(CadenceBoardColumnLifecycleOffer.offersCompletionToggle(doing))
        #expect(CadenceBoardColumnLifecycleOffer.offersCompletionToggle(shipped))
        #expect(!CadenceBoardColumnLifecycleOffer.offersCompletionToggle(parked))
        #expect(!CadenceBoardColumnLifecycleOffer.offersCompletionToggle(parkedDone))
        #expect(!CadenceBoardColumnLifecycleOffer.offersCompletionToggle(defaultColumn))

        // The flag form the iOS editor row calls agrees with the config form.
        #expect(CadenceBoardColumnLifecycleOffer.offersCompletionToggle(supportsLifecycle: true, isArchived: false))
        #expect(!CadenceBoardColumnLifecycleOffer.offersCompletionToggle(supportsLifecycle: true, isArchived: true))
        #expect(!CadenceBoardColumnLifecycleOffer.offersCompletionToggle(supportsLifecycle: false, isArchived: false))
    }

    /// Both editors read the shared offer: the Mac's header circle, popover button, Cmd+Return
    /// registration and convergence guard (counted in `CadenceKanbanColumnLifecycleSurfaceTests`),
    /// and the iOS editor row's Complete / Reopen pair.
    @Test func bothColumnEditorsReadTheSharedLifecycleOffer() throws {
        let header = try code(Self.macHeaderFile)
        #expect(header.components(separatedBy: "CadenceBoardColumnLifecycleOffer.offersCompletionToggle(section)").count - 1 == 2)
        let column = try code(Self.macColumnFile)
        #expect(column.components(separatedBy: "CadenceBoardColumnLifecycleOffer.offersCompletionToggle(section)").count - 1 == 2)

        let row = try #require(
            CadenceSourceScan.declarationBody("private struct iOSSectionDraftRow: View", in: try code(Self.iOSEditorFile)),
            "the iOS column editor row is gone"
        )
        #expect(row.contains("if CadenceBoardColumnLifecycleOffer.offersCompletionToggle(supportsLifecycle: true, isArchived: lifecycle.isArchived) {"))
        #expect(row.contains("title: \"Unarchive\""))
        #expect(row.contains("title: \"Complete\""))
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
