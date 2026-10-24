import Foundation
import Testing
@testable import Cadence

/// **T-5174.** iOS's Cancel/Save sheets dropped every edit on a swipe-down with no word, while the
/// task and event sheets refuse that swipe ([[T-3171]]'s rule: a swipe cannot discard an unsaved
/// draft).
///
/// (a) brought the two **edit** sheets under the rule and deliberately left the creation sheets
/// out. (b) is the owner's answer — **one rule for every sheet** — so New Task, New List, New
/// Context and Calendar quick-create now refuse the swipe once anything has been typed. A
/// "Discard new task?" prompt was declined: a dialog in front of a reflexive gesture.
///
/// **This file used to be the one whole-file `#if os(iOS)` file in `CadenceTests`**, which builds
/// for macOS: every test below compiled to nothing and had never run, here or in CI. The guard and
/// its snapshots are plain values with no UI in them, so they moved to `Cadence/Shared/` and the
/// guard is gone from this file's header. [[T-6222]] files the missing sweep.
///
/// The rule and the snapshots are driven directly; the sheet wiring is private SwiftUI state, so
/// it is pinned as source text.
@MainActor
@Suite
struct iOSEditSheetDismissGuardTests {

    // MARK: - Behavioural: the rule

    @Test func aSheetBlocksTheSwipeOnlyOnceItsDraftDiffersFromWhatItOpenedOn() {
        let opened = CadenceContextEditorDraftSnapshot(name: "Work", icon: "briefcase", colorHex: "#4A90E2")
        var edited = opened
        #expect(!CadenceSheetDismissGuard.blocksSwipe(opened: opened, current: edited))
        edited.name = "Office"
        #expect(CadenceSheetDismissGuard.blocksSwipe(opened: opened, current: edited))
        // Typed back to what it opened on: nothing to lose, so the swipe is allowed again.
        edited.name = "Work"
        #expect(!CadenceSheetDismissGuard.blocksSwipe(opened: opened, current: edited))
    }

    /// T-5174 (b), the half this commit landed: a creation sheet is no longer exempt.
    @Test func aCreationSheetBlocksOnceSomethingIsTypedAndAnUnloadedSheetNeverBlocks() {
        let opened = CadenceContextEditorDraftSnapshot(name: "", icon: "square.stack.fill", colorHex: "#4A90E2")
        let typed = CadenceContextEditorDraftSnapshot(name: "Half typed", icon: "square.stack.fill", colorHex: "#4A90E2")
        #expect(CadenceSheetDismissGuard.blocksSwipe(opened: opened, current: typed))
        // An untouched creation sheet still swipes away: there is nothing to lose.
        #expect(!CadenceSheetDismissGuard.blocksSwipe(opened: opened, current: opened))
        // Before the opening pass there is no snapshot, and the sheet's `@State` defaults — or the
        // normalisation a capture sheet runs in `onAppear` — are not an edit.
        #expect(!CadenceSheetDismissGuard.blocksSwipe(opened: nil, current: typed))
    }

    /// The capture sheets' snapshot: a tag picked with nothing typed is still work a swipe drops,
    /// and the two creation surfaces must answer the same way for the same draft.
    @Test func theCaptureSnapshotCountsTheTagSelectionBesideTheDraft() {
        var draft = CadenceScheduleDraft.quickCreate(
            dateKey: "2026-10-24", startMin: 9 * 60, opensTimed: true, kind: .task
        )
        let opened = CadenceCreateTaskDraftSnapshot(draft: draft, tagIDs: [])

        var tagged = opened
        tagged.tagIDs = ["tag-1"]
        #expect(CadenceSheetDismissGuard.blocksSwipe(opened: opened, current: tagged))

        draft.title = "Half typed"
        #expect(CadenceSheetDismissGuard.blocksSwipe(
            opened: opened, current: CadenceCreateTaskDraftSnapshot(draft: draft, tagIDs: [])
        ))
        // The quick-create sheet compares the bare draft; same typing, same answer.
        #expect(CadenceSheetDismissGuard.blocksSwipe(opened: opened.draft, current: draft))
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

    private static func listSnapshot(columns: [CadenceSectionDraft]) -> CadenceListEditorDraftSnapshot {
        CadenceListEditorDraftSnapshot(
            name: "Home",
            details: "",
            icon: "checklist",
            colorHex: "#4A90E2",
            selectedContextID: "none",
            selectedAreaID: "none",
            dueDateKey: "",
            hideEmptyDueDates: true,
            hideEmptySectionDueDates: true,
            columns: columns.map { CadenceListEditorDraftSnapshot.Column($0) }
        )
    }

    // MARK: - Source pins: every Cancel/Save sheet applies the guard, and snapshots once

    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    private static let guardCall =
        "CadenceSheetDismissGuard.blocksSwipe(opened: openedDraft, current: currentDraft)"

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
        // T-5174 (b): the snapshot is taken in every mode. An `if isEditing` around it is exactly
        // the exemption the owner removed.
        #expect(!load.contains("if isEditing { openedDraft"))
    }

    /// T-5174 (b): the two capture sheets, which have no `load()` — they snapshot in `onAppear`,
    /// *after* the normalisation that runs before the user has touched anything, and only once.
    @Test(arguments: [
        ("struct iOSCreateTaskSheet", "Cadence/iOS/iOSCreateTaskSheet.swift"),
        ("struct iOSCalendarQuickCreateSheet", "Cadence/iOS/iOSCalendarQuickCreateSheet.swift"),
    ])
    func theCaptureSheetRefusesASwipeOverAHalfTypedNewItem(declaration: String, path: String) throws {
        let sheet = try #require(CadenceSourceScan.declarationBody(declaration, in: try Self.code(path)))
        let hit = try #require(sheet.range(of: ".interactiveDismissDisabled("))
        let arguments = try #require(
            CadenceSourceScan.matchedBody(after: sheet.index(before: hit.upperBound), in: sheet, open: "(", close: ")")
        )
        #expect(arguments.contains(Self.guardCall))
        #expect(sheet.contains("if openedDraft == nil { openedDraft = currentDraft }"))
    }

    /// [[T-3240]]: `interactiveDismissDisabled` pushes an iPad popover out of its popover, so the
    /// guard is safe only while every presenter is a `.sheet`. All four guarded sheets are swept,
    /// not just the two editors (b) added the modifier to.
    @Test func everyPresenterOfTheGuardedSheetsIsASheet() throws {
        let iOSRoot = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence/iOS")
        let files = try FileManager.default.contentsOfDirectory(atPath: iOSRoot.path).filter { $0.hasSuffix(".swift") }
        var presenters = 0
        for file in files {
            let source = try Self.code("Cadence/iOS/\(file)")
            for needle in [
                "iOSListEditorSheet(mode:",
                "iOSContextEditorSheet(mode:",
                "iOSCreateTaskSheet(",
                "iOSCalendarQuickCreateSheet(",
            ] {
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
        #expect(presenters >= 9)
    }

    /// The guard's own file must stay out of `Cadence/iOS/`, or these tests go dark again without
    /// anything failing — which is exactly how (a)'s pins spent a day not running.
    @Test func theGuardLivesWhereTheMacOSTestTargetCanSeeIt() throws {
        let shared = try Self.code("Cadence/Shared/CadenceSheetDismissGuard.swift")
        #expect(shared.contains("enum CadenceSheetDismissGuard"))
        #expect(!shared.contains("#if os(iOS)"))
    }
}
