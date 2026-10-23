#if os(iOS)
import Foundation
import Testing
@testable import Cadence

/// T-5174 (a): **iOS's Edit List and Edit Context sheets dropped every edit on a swipe-down, with
/// no word**, while the task and event sheets refuse that swipe ([[T-3171]]'s rule: a swipe cannot
/// discard an unsaved draft). Both are Cancel/Save sheets whose fields are `@State` drafts written
/// only by `save()`. Now each snapshots its draft in `load()` and passes
/// `iOSEditSheetDismissGuard.blocksSwipe` to `.interactiveDismissDisabled`.
///
/// The creation modes are untouched on purpose: T-5174 (b) is the owner's decision.
///
/// The rule and the snapshots are driven directly; the sheet wiring is private SwiftUI state, so
/// it is pinned as source text.
@MainActor
@Suite
struct iOSEditSheetDismissGuardTests {

    // MARK: - Behavioural: the rule

    @Test func anEditSheetBlocksTheSwipeOnlyOnceItsDraftDiffersFromWhatItOpenedOn() {
        let opened = iOSContextEditorDraftSnapshot(name: "Work", icon: "briefcase", colorHex: "#4A90E2")
        var edited = opened
        #expect(!iOSEditSheetDismissGuard.blocksSwipe(isEditing: true, opened: opened, current: edited))
        edited.name = "Office"
        #expect(iOSEditSheetDismissGuard.blocksSwipe(isEditing: true, opened: opened, current: edited))
        // Typed back to what it opened on: nothing to lose, so the swipe is allowed again.
        edited.name = "Work"
        #expect(!iOSEditSheetDismissGuard.blocksSwipe(isEditing: true, opened: opened, current: edited))
    }

    @Test func aCreationSheetAndAnUnloadedSheetNeverBlock() {
        let opened = iOSContextEditorDraftSnapshot(name: "", icon: "square.stack.fill", colorHex: "#4A90E2")
        let typed = iOSContextEditorDraftSnapshot(name: "Half typed", icon: "square.stack.fill", colorHex: "#4A90E2")
        // T-5174 (b) is the owner's call: a creation sheet keeps today's behaviour.
        #expect(!iOSEditSheetDismissGuard.blocksSwipe(isEditing: false, opened: opened, current: typed))
        // Before `load()` there is no snapshot, and the sheet's `@State` defaults are not an edit.
        #expect(!iOSEditSheetDismissGuard.blocksSwipe(isEditing: true, opened: nil, current: typed))
    }

    @Test func aListDraftCountsAColumnRenameButNotAWindDownTheModelAlreadyTook() {
        var column = CadenceSectionDraft(name: "Doing")
        let opened = Self.listSnapshot(columns: [column])

        var renamed = column
        renamed.name = "In progress"
        #expect(opened != Self.listSnapshot(columns: [renamed]))

        var recoloured = column
        recoloured.colorHex = "#FF0000"
        #expect(opened != Self.listSnapshot(columns: [recoloured]))

        var dated = column
        dated.dueDate = "2026-10-30"
        #expect(opened != Self.listSnapshot(columns: [dated]))

        // `applyColumnWindDown` / `reopenColumn` write to the model at once, so the draft flag
        // that follows them is not an unsaved edit and must not hold the sheet.
        column.isArchived = true
        column.isCompleted = true
        #expect(opened == Self.listSnapshot(columns: [column]))

        #expect(opened != Self.listSnapshot(columns: []))
    }

    private static func listSnapshot(columns: [CadenceSectionDraft]) -> iOSListEditorDraftSnapshot {
        iOSListEditorDraftSnapshot(
            name: "Home",
            details: "",
            icon: "checklist",
            colorHex: "#4A90E2",
            selectedContextID: "none",
            selectedAreaID: "none",
            dueDateKey: "",
            hideEmptyDueDates: true,
            hideEmptySectionDueDates: true,
            columns: columns.map { iOSListEditorDraftSnapshot.Column($0) }
        )
    }

    // MARK: - Source pins: both edit sheets apply the guard, snapshot in load(), and are sheets

    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    private static let guardCall =
        "iOSEditSheetDismissGuard.blocksSwipe(isEditing: isEditing, opened: openedDraft, current: currentDraft)"

    @Test(arguments: [
        ("struct iOSListEditorSheet", "Cadence/iOS/iOSListEditorViews.swift"),
        ("struct iOSContextEditorSheet", "Cadence/iOS/iOSSettingsContextSection.swift"),
    ])
    func theEditSheetRefusesASwipeOverAnUnsavedDraft(declaration: String, path: String) throws {
        let sheet = try #require(CadenceSourceScan.declarationBody(declaration, in: try Self.code(path)))
        let hit = try #require(sheet.range(of: ".interactiveDismissDisabled("))
        let arguments = try #require(
            CadenceSourceScan.matchedBody(after: sheet.index(before: hit.upperBound), in: sheet, open: "(", close: ")")
        )
        #expect(arguments.contains(Self.guardCall))

        let load = try #require(CadenceSourceScan.functionBody(named: "load", in: sheet))
        #expect(load.contains("openedDraft = currentDraft"))
    }

    /// [[T-3240]]: `interactiveDismissDisabled` pushes an iPad popover out of its popover, so the
    /// guard is safe here only while every presenter is a `.sheet`.
    @Test func everyPresenterOfTheTwoEditorsIsASheet() throws {
        let iOSRoot = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence/iOS")
        let files = try FileManager.default.contentsOfDirectory(atPath: iOSRoot.path).filter { $0.hasSuffix(".swift") }
        var presenters = 0
        for file in files {
            let source = try Self.code("Cadence/iOS/\(file)")
            for needle in ["iOSListEditorSheet(mode:", "iOSContextEditorSheet(mode:"] {
                var cursor = source.startIndex
                while let hit = source.range(of: needle, range: cursor..<source.endIndex) {
                    cursor = hit.upperBound
                    presenters += 1
                    let before = source[source.startIndex..<hit.lowerBound]
                    let sheet = before.range(of: ".sheet(", options: .backwards)?.lowerBound
                    let popover = before.range(of: ".popover(", options: .backwards)?.lowerBound
                    #expect(sheet != nil, "\(file): \(needle) has no presenting .sheet")
                    if let sheet, let popover {
                        #expect(sheet > popover, "\(file): \(needle) is presented by a .popover")
                    }
                }
            }
        }
        #expect(presenters >= 6)
    }
}
#endif
