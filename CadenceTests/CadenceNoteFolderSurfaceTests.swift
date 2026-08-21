import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-193: `Note.folderPath` was read or written in three macOS files plus
/// `DataIntegrityRepairService`, and nowhere under `Cadence/iOS`. So a folder made on a Mac was
/// invisible on the phone — and the sharper half, a note made on the phone always landed at the
/// root of a filing system the device could not draw.
///
/// **A folder is a convention over a string, not a model.** There is no folder record: a folder
/// exists for exactly as long as one note's `folderPath` names it. That makes the convention — the
/// separator, whether the string carries a leading or trailing one, what the root is, whether
/// nesting is representable — the whole feature, and it lived in one private function on one macOS
/// view. The first half of this file pins it as a value type; the second half pins the call sites,
/// so neither platform can grow a second spelling of "normalize a folder path".
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS. The helpers follow
/// `CadenceGoalListLinkSurfaceTests` — exact per-file counts rather than "contains",
/// comment-stripping rather than allowlisting, and a non-vacuity test so a broken scan cannot make
/// the absence assertions pass silently.
@MainActor
struct CadenceNoteFolderSurfaceTests {

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    @discardableResult
    private func note(
        _ title: String,
        folder: String,
        order: Int = 0,
        project: Project,
        in context: ModelContext
    ) -> Note {
        let note = Note(kind: .list, title: title, order: order, folderPath: folder)
        note.project = project
        context.insert(note)
        return note
    }

    // MARK: - The convention

    /// The normalizer, read off `ListNotesView.normalizedFolderPath` before it moved: split on `/`,
    /// trim each component, drop the empties, rejoin. So a path carries **no** leading or trailing
    /// separator and **no** empty components, whatever was typed into the sheet.
    @Test func aPathIsTrimmedSegmentsJoinedByOneSeparator() {
        #expect(CadenceNoteFolderPath.normalized("Planning") == "Planning")
        #expect(CadenceNoteFolderPath.normalized("/Planning") == "Planning")
        #expect(CadenceNoteFolderPath.normalized("Planning/") == "Planning")
        #expect(CadenceNoteFolderPath.normalized("/Planning/") == "Planning")
        #expect(CadenceNoteFolderPath.normalized("Planning/Research") == "Planning/Research")
        #expect(CadenceNoteFolderPath.normalized("Planning//Research") == "Planning/Research")
        #expect(CadenceNoteFolderPath.normalized("  Planning / Research  ") == "Planning/Research")
        #expect(CadenceNoteFolderPath.normalized("Planning/   /Research") == "Planning/Research")
        #expect(CadenceNoteFolderPath.normalized("Planning\n/Research") == "Planning/Research")
    }

    /// **The root is exactly the empty string**, and everything that normalizes to nothing lands on
    /// it. This is not a free choice: `DataIntegrityRepairService.mergeNoteFields` calls
    /// `fillEmptyString(\.folderPath, …)`, which decides "unset" by trimming to empty — so a
    /// sentinel of `"/"` or `"Notes"` would read to the repair pass as a real folder.
    @Test func everythingThatNormalizesToNothingIsTheRoot() {
        for raw in ["", " ", "/", "//", "   /   ", "\n", "/ /"] {
            #expect(CadenceNoteFolderPath.normalized(raw) == CadenceNoteFolderPath.root)
            #expect(CadenceNoteFolderPath.isRoot(raw))
        }
        #expect(CadenceNoteFolderPath.root.isEmpty)
        #expect(!CadenceNoteFolderPath.isRoot("Planning"))
        // The two halves of the repair pass's "unset" test agree with this one.
        #expect(CadenceNoteFolderPath.root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Normalizing a normalized path changes nothing — which is what makes it safe to run on read
    /// as well as on write, and running it on read is what protects the column from a raw value
    /// arriving from a merge, from CloudKit, or from a build older than the convention.
    @Test func normalizationIsIdempotent() {
        for raw in ["", "/", "Planning", " /Planning// Research /", "A/B/C"] {
            let once = CadenceNoteFolderPath.normalized(raw)
            #expect(CadenceNoteFolderPath.normalized(once) == once)
        }
    }

    /// Nesting is **representable and is not a tree**: `"Planning/Research"` is a legal path, and
    /// every surface groups on the whole string, so it is a sibling of `"Planning"` rather than its
    /// child. `components` and `depth` exist so that a real tree can be built later without
    /// re-deciding the storage format.
    @Test func nestingIsRepresentableAndFlatToday() {
        #expect(CadenceNoteFolderPath.components("Planning/Research") == ["Planning", "Research"])
        #expect(CadenceNoteFolderPath.components("/Planning/") == ["Planning"])
        #expect(CadenceNoteFolderPath.components("") == [])
        #expect(CadenceNoteFolderPath.depth("") == 0)
        #expect(CadenceNoteFolderPath.depth("Planning") == 1)
        #expect(CadenceNoteFolderPath.depth("Planning/Research") == 2)
        #expect(CadenceNoteFolderPath.separator == "/")
    }

    /// A heading shows the **whole** path, not the leaf: `Planning/Research` and `Admin/Research`
    /// group separately, so labelling either "Research" would draw two headings that read the same.
    @Test func aHeadingNamesTheWholePathAndTheRootHasItsOwnName() {
        #expect(CadenceNoteFolderPath.displayName(for: "Planning/Research") == "Planning/Research")
        #expect(CadenceNoteFolderPath.displayName(for: "/Planning/") == "Planning")
        #expect(CadenceNoteFolderPath.displayName(for: "") == "Notes")
        #expect(CadenceNoteFolderPath.id(for: "") == "__root__")
        #expect(CadenceNoteFolderPath.id(for: "Planning") == "Planning")
    }

    /// **The root sorts last.** macOS's rule, and the right way round: an unlabelled run of notes
    /// reads as "everything else" at the foot of a column and as a mystery at the top of one.
    @Test func theRootFolderSortsLastAndTheRestSortByName() {
        let sorted = ["zebra", "", "Admin", "beta", "Alpha"].sorted(by: CadenceNoteFolderPath.precedes)
        #expect(sorted == ["Admin", "Alpha", "beta", "zebra", ""])
    }

    /// Folder order has to be **total**: a case-insensitive compare calls `"Research"` and
    /// `"research"` equal, and `sorted(by:)` is not a stable sort, so without a tie-break two
    /// headings would swap places between renders.
    @Test func folderOrderIsTotal() {
        #expect(CadenceNoteFolderPath.precedes("Research", "research"))
        #expect(!CadenceNoteFolderPath.precedes("research", "Research"))
        let once = ["research", "Research", "RESEARCH"].sorted(by: CadenceNoteFolderPath.precedes)
        let twice = ["RESEARCH", "research", "Research"].sorted(by: CadenceNoteFolderPath.precedes)
        #expect(once == twice)
    }

    /// The "move to folder" menu's list: normalized, de-duplicated, and **without the root** —
    /// "No Folder" is its own item, not a folder you move into.
    @Test func theFolderMenuListsEveryRealFolderOnce() {
        let names = CadenceNoteFolderPath.names(in: ["/Planning/", "Planning", "", "  ", "Admin", "Planning/Research"])
        #expect(names == ["Admin", "Planning", "Planning/Research"])
        #expect(CadenceNoteFolderPath.names(in: ["", "/", " "]).isEmpty)
    }

    // MARK: - Grouping

    @Test func groupsPutRealFoldersFirstAndTheUnfiledNotesLast() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)

        note("Loose", folder: "", project: project, in: context)
        note("Zebra folder note", folder: "zebra", project: project, in: context)
        note("Admin note", folder: "Admin", project: project, in: context)

        let notes = try context.fetch(FetchDescriptor<Note>())
        let groups = CadenceNoteFolderGrouping.groups(for: notes)

        #expect(groups.map(\.folderPath) == ["Admin", "zebra", ""])
        #expect(groups.map(\.displayName) == ["Admin", "zebra", "Notes"])
        // The root draws no heading on either platform — a group labelled "Notes" inside a column
        // already headed "Notes" is the page describing the page you are on.
        #expect(groups.map(\.showsHeader) == [true, true, false])
        #expect(groups.map(\.isRoot) == [false, false, true])
        #expect(groups.map(\.id) == ["Admin", "zebra", "__root__"])
    }

    /// **The read-side normalization, and the reason it exists.**
    /// `DataIntegrityRepairService.fillEmptyString` assigns the source note's `folderPath`
    /// *verbatim* — it trims only to decide whether the target is unset. So a path that was never
    /// normalized can reach the store, and a column that grouped on the raw string would draw
    /// `Planning` twice.
    @Test func anUnnormalizedStoredPathGroupsWithItsNormalizedTwin() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)

        note("Clean", folder: "Planning", order: 0, project: project, in: context)
        note("Raw", folder: "/Planning/", order: 1, project: project, in: context)
        note("Spaced", folder: " Planning ", order: 2, project: project, in: context)

        let notes = try context.fetch(FetchDescriptor<Note>())
        let groups = CadenceNoteFolderGrouping.groups(for: notes)

        #expect(groups.count == 1)
        #expect(groups[0].folderPath == "Planning")
        #expect(groups[0].notes.map(\.title) == ["Clean", "Raw", "Spaced"])
        #expect(CadenceNoteFolderGrouping.folderNames(in: notes) == ["Planning"])
    }

    /// Row order inside a folder: `order`, then title, then `id`. Total, for the same reason
    /// `TaskOrdering.fallbackPrecedes` is — `order` is assigned per list, two notes routinely share
    /// one, and the title compare is case-insensitive so two notes can tie on both.
    @Test func rowOrderInsideAFolderIsTotal() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)

        let second = note("beta", folder: "Planning", order: 5, project: project, in: context)
        let first = note("alpha", folder: "Planning", order: 1, project: project, in: context)
        let sameOrder = note("Alpha", folder: "Planning", order: 1, project: project, in: context)

        #expect(CadenceNoteFolderGrouping.precedes(first, second))
        #expect(!CadenceNoteFolderGrouping.precedes(second, first))
        // Equal `order`, equal title under a case-insensitive compare: the id decides, and it
        // decides the same way both times it is asked.
        let forward = CadenceNoteFolderGrouping.precedes(first, sameOrder)
        #expect(forward != CadenceNoteFolderGrouping.precedes(sameOrder, first))
        #expect(forward == (first.id.uuidString < sameOrder.id.uuidString))
    }

    /// A folder with nothing in it cannot exist, because there is no folder record to keep —
    /// emptying a folder is how you delete it, and no group is invented for one.
    @Test func anEmptyFolderIsNotAGroup() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)
        let only = note("Filed", folder: "Planning", project: project, in: context)

        #expect(CadenceNoteFolderGrouping.groups(for: [only]).map(\.folderPath) == ["Planning"])

        CadenceListNoteFiling.move(only, toFolder: CadenceNoteFolderPath.root)

        #expect(CadenceNoteFolderGrouping.groups(for: [only]).map(\.folderPath) == [""])
        #expect(CadenceNoteFolderGrouping.folderNames(in: [only]).isEmpty)
        #expect(CadenceNoteFolderGrouping.groups(for: []).isEmpty)
    }

    // MARK: - Filing

    @Test func creatingANoteFilesItWhereItWasAskedFor() throws {
        let context = try makeContext()
        let area = Area(name: "Documents")
        context.insert(area)

        let filed = CadenceListNoteFiling.createNote(
            in: context,
            area: area,
            project: nil,
            folderPath: " /Planning/ Research/ ",
            order: 3
        )

        #expect(filed.folderPath == "Planning/Research")
        #expect(filed.kind == .list)
        #expect(filed.area?.id == area.id)
        #expect(filed.project == nil)
        #expect(filed.order == 3)
        #expect(filed.content == "# Untitled\n\n")
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
    }

    /// The default is the root, and anything that normalizes to nothing lands there too — so a
    /// sheet answered with whitespace cannot create a folder called `" "`.
    @Test func aNoteWithNoFolderLandsAtTheRoot() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)

        let plain = CadenceListNoteFiling.createNote(in: context, area: nil, project: project, order: 0)
        let whitespace = CadenceListNoteFiling.createNote(
            in: context,
            area: nil,
            project: project,
            folderPath: "  /  ",
            order: 1
        )

        #expect(plain.folderPath == CadenceNoteFolderPath.root)
        #expect(whitespace.folderPath == CadenceNoteFolderPath.root)
        #expect(CadenceNoteFolderGrouping.folderNames(in: [plain, whitespace]).isEmpty)
    }

    @Test func movingANoteNormalizesAndCanClearTheFolder() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)
        let moved = note("Note", folder: "", project: project, in: context)

        CadenceListNoteFiling.move(moved, toFolder: "/Planning//Research/")
        #expect(moved.folderPath == "Planning/Research")

        CadenceListNoteFiling.move(moved, toFolder: "")
        #expect(moved.folderPath == CadenceNoteFolderPath.root)
    }

    @Test func aNewNoteOpensOntoItsOwnTitleAsAHeading() {
        #expect(CadenceListNoteFiling.seededContent(for: "Kickoff") == "# Kickoff\n\n")
        #expect(CadenceListNoteFiling.seededContent(for: "  Kickoff  ") == "# Kickoff\n\n")
        #expect(CadenceListNoteFiling.seededContent(for: "   ") == "# Untitled\n\n")
        #expect(CadenceListNoteFiling.seededContent(for: "") == "# Untitled\n\n")
    }

    // MARK: - What the repair pass does to a folder

    /// **`DataIntegrityRepairService` cannot reach a list note's folder, and that is worth
    /// asserting rather than assuming.** Its one `folderPath` line is inside `mergeNoteFields`,
    /// which runs only for notes sharing a `canonicalKey` — and a list note's key is
    /// `"list:<uuid>"`, unique per note. So two list notes are never duplicates however identical
    /// they look, the merge never runs on them, and the folder assignment survives a repair pass
    /// untouched.
    ///
    /// The line is not dead weight to be removed: it is what stops a merge of two *notepad* notes
    /// (which all share the key `"permanent"`) from dropping a folder, should anything ever file
    /// one. What it must never do is invent a value — it copies raw, which is precisely why the
    /// grouping normalizes on read.
    @Test func aRepairPassLeavesTwoIdenticalListNotesAndTheirFoldersAlone() throws {
        let context = try makeContext()
        let project = Project(name: "Launch")
        context.insert(project)

        let filed = note("Same Title", folder: "Planning", order: 0, project: project, in: context)
        let unfiled = note("Same Title", folder: "", order: 1, project: project, in: context)
        try context.save()

        #expect(filed.canonicalKey != unfiled.canonicalKey)
        #expect(filed.canonicalKey == "list:\(filed.id.uuidString)")

        let report = try DataIntegrityRepairService.repairIfNeeded(
            in: context,
            source: "CadenceNoteFolderSurfaceTests",
            saveChanges: false
        )

        #expect(report.duplicateNotesMerged == 0)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 2)
        #expect(filed.folderPath == "Planning")
        #expect(unfiled.folderPath == CadenceNoteFolderPath.root)
    }

    // MARK: - Both platforms reach the one path

    /// **The call-site half.** `folderPath` is written in exactly two places outside its own
    /// declaration, both in the shared file, so neither platform can normalize a path its own way —
    /// which is what "a note created on iOS always lands at the root" was a symptom of.
    ///
    /// The scan is over `.folderPath` with the leading dot rather than the bare word, because both
    /// folder sheets hold a `@State private var folderPath` of their own: a bare-word count reports
    /// the local draft as a write to the model.
    @Test func onlyTheSharedFilingHelperWritesAFolderPath() throws {
        var offenders: [String] = []
        for path in try folderSwiftFiles(under: "Cadence") {
            let code = try folderStrippingComments(folderSource(path))
            let count = code.components(separatedBy: ".folderPath").count - 1
            guard count > 0 else { continue }
            offenders.append("\(path):\(count)")
        }

        #expect(offenders.sorted() == [
            // `self.folderPath = folderPath` in the initializer.
            "Cadence/Models/Note.swift:1",
            // `fillEmptyString(\.folderPath, …)` — a read of the key path, not a spelling of the
            // convention. See `aRepairPassLeavesTwoIdenticalListNotesAndTheirFoldersAlone`.
            "Cadence/Services/DataIntegrityRepairService.swift:1",
            // Two writes (`createNote`, `move`) and two reads (`groups`, `folderNames`).
            "Cadence/Shared/CadenceNoteFolderSupport.swift:4"
        ])
    }

    /// The grouping, the folder list, the filing and the row are one implementation each, reached
    /// from both platforms. Exact counts, not "contains": reverting *one* of these call sites has
    /// to fail.
    @Test func bothPlatformsReadTheSharedFolderSurface() throws {
        try expectFolderOccurrences(of: "CadenceNoteFolderGrouping.groups(", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/macOS/Views/ListNotesView.swift": 1
        ])
        try expectFolderOccurrences(of: "CadenceNoteFolderGrouping.folderNames(", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/macOS/Views/ListNotesView.swift": 1
        ])
        try expectFolderOccurrences(of: "CadenceListNoteFiling.createNote(", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/macOS/Views/ListNotesView.swift": 1
        ])
        // Twice each: the row's "Move to Folder" menu, and the folder sheet's answer.
        try expectFolderOccurrences(of: "CadenceListNoteFiling.move(", at: [
            "Cadence/iOS/iOSListNotesView.swift": 2,
            "Cadence/macOS/Views/ListNotesView.swift": 2
        ])
        try expectFolderOccurrences(of: "NoteFolderGroupList(", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/macOS/Views/ListNotesView.swift": 1
        ])
        try expectFolderOccurrences(of: "NoteFolderListRow(", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/macOS/Views/ListNotesListSupportViews.swift": 1
        ])
        try expectFolderOccurrences(of: "NoteFolderMoveMenu(", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/macOS/Views/ListNotesViewSupportViews.swift": 1
        ])
        // The heading is drawn by the shared column and by nothing else, so a platform cannot draw
        // a folder label of its own beside it.
        try expectFolderOccurrences(of: "NoteFolderSectionHeader(", at: [
            "Cadence/Shared/CadenceNoteFolderSupport.swift": 1,
            "Cadence/iOS/iOSListNotesView.swift": 0,
            "Cadence/macOS/Views/ListNotesViewSupportViews.swift": 0
        ])
    }

    /// The iOS list-detail Notes tab is the new column, and the single-note panel it replaced is
    /// **not routed to from anywhere**. `iOSListNotesPanel` called
    /// `CadenceListNoteSupport.firstOrCreateNote`, so it showed one note per list however many the
    /// list had — the reason "folders are invisible on iOS" understated the gap.
    @Test func theIOSListDetailNotesTabIsTheFolderColumn() throws {
        try expectFolderOccurrences(of: "iOSListNotesView(", at: [
            "Cadence/iOS/iOSListDetailView.swift": 1
        ])
        try expectFolderOccurrences(of: "iOSListNotesPanel(", at: [
            "Cadence/iOS/iOSListDetailView.swift": 0
        ])
        // No caller anywhere, which is what makes the panel dead rather than merely unrouted.
        for path in try folderSwiftFiles(under: "Cadence") {
            let code = try folderStrippingComments(folderSource(path))
            #expect(
                code.components(separatedBy: "iOSListNotesPanel(").count - 1 == 0,
                "\(path) still constructs iOSListNotesPanel"
            )
        }
    }

    /// The convention has one home, and no platform may declare a second copy of any part of it —
    /// a `CadenceNoteFolderPath` behind `#if os(iOS)` would compile, pass every test above, and be
    /// exactly the fork this change removes. `ListNoteFolderGroup`, the macOS-only struct that
    /// carried the `""`-is-root and `"__root__"`-is-its-id halves, is named here too: it is gone,
    /// and it must not come back.
    @Test func neitherPlatformDeclaresItsOwnCopyOfTheConvention() throws {
        let allowed = "Cadence/Shared/CadenceNoteFolderSupport.swift"
        let declarations = [
            "CadenceNoteFolderPath", "CadenceNoteFolderGroup", "CadenceNoteFolderGrouping",
            "CadenceListNoteFiling", "NoteFolderSectionHeader", "NoteFolderGroupList",
            "NoteFolderListRow", "NoteFolderMoveMenu",
            // The retired macOS-only spellings.
            "ListNoteFolderGroup", "ListNoteFolderGroupView"
        ]

        for path in try folderSwiftFiles(under: "Cadence") where path != allowed {
            let code = try folderStrippingComments(folderSource(path))
            for name in declarations {
                #expect(
                    code.range(of: "(struct|class|enum|typealias)\\s+\(name)\\b", options: .regularExpression) == nil,
                    "\(path) declares \(name)"
                )
            }
        }

        // And the home really does declare all eight.
        let home = try folderStrippingComments(folderSource(allowed))
        for name in declarations.prefix(8) {
            #expect(
                home.range(of: "(struct|enum)\\s+\(name)\\b", options: .regularExpression) != nil,
                "\(allowed) does not declare \(name)"
            )
        }
    }

    /// The iOS column reads the *existing* two-column floor rather than writing a seventh copy of
    /// the pane-width rule — a folder is a heading inside one column, not a third pane, so no
    /// arithmetic changed. `CadencePaneWidthRuleHomesTests` is what enforces the general rule;
    /// this pins that this surface joined it by delegating.
    @Test func theIOSFolderColumnBorrowsTheNotesSplitRatherThanInventingOne() throws {
        let code = try folderStrippingComments(folderSource("Cadence/iOS/iOSListNotesView.swift"))

        #expect(code.components(separatedBy: "CadenceNotesListMetrics.layout(").count - 1 == 1)
        #expect(code.components(separatedBy: "CadenceNotesListMetrics.regularColumnWidth").count - 1 == 1)
        for floorSpelling in ["MinimumWidth", "minimumEditorWidth", "columnDividerWidth"] {
            #expect(
                code.components(separatedBy: floorSpelling).count - 1 == 0,
                "iOSListNotesView has grown its own \(floorSpelling) instead of reading one"
            )
        }
    }

    // MARK: - The scan itself

    /// The counts above are only worth anything if the scan actually reads files, and a scan that
    /// silently returns nothing passes every zero-count assertion.
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
        let files = try folderSwiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Shared/CadenceNoteFolderSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSListNotesView.swift"))
        #expect(files.contains("Cadence/iOS/iOSListDetailView.swift"))
        #expect(files.contains("Cadence/macOS/Views/ListNotesView.swift"))
        #expect(files.contains("Cadence/macOS/Views/ListNotesListSupportViews.swift"))
        #expect(files.contains("Cadence/macOS/Views/ListNotesViewSupportViews.swift"))
        #expect(files.contains("Cadence/Services/DataIntegrityRepairService.swift"))

        // Reading *code*, not an empty string — a positive assertion over the same reader.
        let iOSColumn = try folderStrippingComments(folderSource("Cadence/iOS/iOSListNotesView.swift"))
        #expect(iOSColumn.contains("struct iOSListNotesView: View"))
        // And the stripper really strips: this sentence is only in a doc comment.
        #expect(!iOSColumn.contains("which showed exactly one note"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
private func expectFolderOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try folderStrippingComments(folderSource(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func folderRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func folderSwiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = folderRepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func folderSource(_ relativePath: String) throws -> String {
    try String(contentsOf: folderRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose.
private func folderStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
