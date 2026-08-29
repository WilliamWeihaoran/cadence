import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-187: list and context lifecycle was macOS-only. `ListDeleteHelpers` was `#if os(macOS)` in
/// `macOS/Services/`, contained no AppKit, and `Cadence/iOS/` called none of its three cascades.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning
/// `CadenceListDeletionSummary`'s arithmetic proves the confirmation counts truthfully; it proves
/// nothing about iOS *reaching* the cascade. `Cadence/iOS/` is entirely inside `#if os(iOS)` and
/// this target builds for macOS, so there is no iOS symbol to reference and the only available tool
/// is a source-text assertion. The precedent is `CadenceSharedTaskRowJobsTests` /
/// `CadenceSharedBoardChromeTests`, whose helpers this file follows: exact per-file counts rather
/// than "contains", comment-stripping rather than allowlisting, and a non-vacuity test so a broken
/// scan cannot make the absence assertions pass silently.
@MainActor
struct CadenceListDeletionSurfaceTests {

    // MARK: - What the confirmation promises

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    @Test func projectSummaryCountsOnlyItsOwnTasksListNotesAndLinks() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Ship")

        let task = AppTask(title: "Task")
        task.project = project
        let listNote = Note(kind: .list, title: "Spec")
        listNote.project = project
        // A daily note filed against the project is not a list note, and `deleteProject` leaves it.
        let dailyNote = Note(kind: .daily, title: "Monday")
        dailyNote.project = project
        let link = SavedLink(title: "Docs", url: "https://example.com")
        link.project = project

        modelContext.insert(project)
        modelContext.insert(task)
        modelContext.insert(listNote)
        modelContext.insert(dailyNote)
        modelContext.insert(link)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forProject(project, in: modelContext)
        #expect(summary.tasks == 1)
        #expect(summary.notes == 1)
        #expect(summary.links == 1)
        #expect(summary.projects == 0)
        #expect(!summary.isEmpty)
    }

    /// The area cascade recurses into nested projects, so the summary has to as well — an area
    /// confirmation that counted only `area.tasks` would under-report by every task in every child
    /// project, which is the largest number on the screen and the one the user is deciding on.
    @Test func areaSummaryRollsUpNestedProjects() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let projectA = Project(name: "A", area: area)
        let projectB = Project(name: "B", area: area)

        let areaTask = AppTask(title: "Area task")
        areaTask.area = area
        let projectTask = AppTask(title: "Project task")
        projectTask.project = projectA
        let areaNote = Note(kind: .list, title: "Area note")
        areaNote.area = area
        let projectNote = Note(kind: .list, title: "Project note")
        projectNote.project = projectB
        let link = SavedLink(title: "Link", url: "https://example.com")
        link.project = projectA

        modelContext.insert(area)
        modelContext.insert(projectA)
        modelContext.insert(projectB)
        modelContext.insert(areaTask)
        modelContext.insert(projectTask)
        modelContext.insert(areaNote)
        modelContext.insert(projectNote)
        modelContext.insert(link)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forArea(area, in: modelContext)
        #expect(summary.projects == 2)
        #expect(summary.tasks == 2)
        #expect(summary.notes == 2)
        #expect(summary.links == 1)
    }

    /// A task carrying both an `area` and a `project` under the same area appears in two of the
    /// relationship arrays the summary walks. The cascade dedupes by id; so must the count, or the
    /// confirmation inflates the number of tasks at stake.
    @Test func areaSummaryCountsATaskInBothAreaAndProjectOnce() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let project = Project(name: "A", area: area)
        let task = AppTask(title: "Filed twice")
        task.area = area
        task.project = project

        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(task)
        try modelContext.save()

        #expect(CadenceListDeletionSummary.forArea(area, in: modelContext).tasks == 1)
    }

    @Test func contextSummaryCountsAreasProjectsGoalsHabitsAndAllTheirTasks() throws {
        let modelContext = ModelContext(try container())
        let context = Context(name: "Work")
        let area = Area(name: "Area", context: context)
        let nested = Project(name: "Nested", context: context, area: area)
        let goal = Goal(title: "Goal", context: context)
        let habit = Habit(title: "Habit", context: context, goal: goal)

        let contextTask = AppTask(title: "Context task")
        contextTask.context = context
        let areaTask = AppTask(title: "Area task")
        areaTask.area = area
        let goalTask = AppTask(title: "Goal task")
        goalTask.goal = goal

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(nested)
        modelContext.insert(goal)
        modelContext.insert(habit)
        modelContext.insert(contextTask)
        modelContext.insert(areaTask)
        modelContext.insert(goalTask)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forContext(context, in: modelContext)
        #expect(summary.areas == 1)
        // The nested project is reachable through both `area.projects` and `context.projects`.
        #expect(summary.projects == 1)
        #expect(summary.goals == 1)
        #expect(summary.habits == 1)
        #expect(summary.tasks == 3)
    }

    @Test func lostItemLinesOmitZeroesPluralizeAndKeepCascadeOrder() {
        var summary = CadenceListDeletionSummary()
        summary.projects = 1
        summary.tasks = 12
        summary.links = 0

        #expect(summary.lostItemLines == ["1 project", "12 tasks"])

        var full = CadenceListDeletionSummary()
        full.areas = 2
        full.projects = 3
        full.goals = 1
        full.habits = 4
        full.tasks = 5
        full.notes = 1
        full.images = 6
        full.links = 2
        // Images sit between the notes they live in and the links, and are worded exactly as the
        // note confirmation words them (T-433).
        #expect(full.lostItemLines == [
            "2 areas", "3 projects", "1 goal", "4 habits", "5 tasks", "1 note",
            "6 embedded images", "2 saved links"
        ])

        var singular = CadenceListDeletionSummary()
        singular.images = 1
        #expect(singular.lostItemLines == ["1 embedded image"])
        #expect(!singular.isEmpty, "an image-only delete still loses something")

        #expect(CadenceListDeletionSummary().lostItemLines.isEmpty)
        #expect(CadenceListDeletionSummary().isEmpty)
    }

    /// An empty list still gets a confirmation, and the confirmation still has to say something. It
    /// reads "nothing else is filed here" rather than an empty bullet list, which is why `isEmpty`
    /// is a published property rather than `lostItemLines.isEmpty` inferred at the call site.
    @Test func anEmptyListSummaryIsEmptyRatherThanZeroLines() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Nothing here")
        modelContext.insert(area)
        try modelContext.save()

        #expect(CadenceListDeletionSummary.forArea(area, in: modelContext).isEmpty)
    }

    // MARK: - T-433, the image sweep the counts used to omit

    private func imageAsset(_ byte: UInt8) -> MarkdownImageAsset {
        MarkdownImageAsset(data: Data([byte]), mimeType: "image/png", pixelWidth: 20, pixelHeight: 20, displayWidth: 20)
    }

    private func imageMarkdown(_ asset: MarkdownImageAsset) -> String {
        "![shot](cadence-image://\(asset.id.uuidString))"
    }

    /// The headline case: an area holding image-bearing list notes. The confirmation used to have
    /// no `images` field at all, so those `.externalStorage` bytes went with no mention — beside a
    /// note confirmation that has said "N embedded images" since T-298.
    ///
    /// The surviving permanent note is the other half: an image the doomed note shares with a note
    /// that is staying is not reclaimed, so it is not counted. `images` is the sweep's collection,
    /// not a reference count.
    @Test func anAreaSummaryCountsTheImagesItIsTheLastReaderOf() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let doomedAsset = imageAsset(1)
        let sharedAsset = imageAsset(2)

        let listNote = Note(
            kind: .list,
            title: "Spec",
            content: "\(imageMarkdown(doomedAsset)) and \(imageMarkdown(sharedAsset))"
        )
        listNote.area = area
        let survivor = Note(kind: .permanent, title: "Notepad", content: imageMarkdown(sharedAsset))

        modelContext.insert(area)
        modelContext.insert(doomedAsset)
        modelContext.insert(sharedAsset)
        modelContext.insert(listNote)
        modelContext.insert(survivor)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forArea(area, in: modelContext)
        #expect(summary.notes == 1)
        #expect(summary.images == 1)
        #expect(!summary.hasUnknownImpact)
        #expect(summary.lostItemLines.contains("1 embedded image"))
    }

    /// **The case `excludingNoteIDs` cannot express.** A list cascade deletes its tasks too, and a
    /// task's `notes` is a markdown field the editor writes images into — the whole of T-411. The
    /// inventory's exclusion set takes note ids only, so the doomed task's body is still *live*
    /// when the confirmation is drawn and a naive survivor set counts it as a reference that stays.
    /// That would report zero images while the cascade reclaims one, which is the single direction
    /// this summary is not allowed to be wrong in.
    @Test func anAreaSummaryCountsAnImageOnlyItsDoomedTaskReferenced() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let asset = imageAsset(3)
        let task = AppTask(title: "Pasted a screenshot")
        task.notes = "Repro: \(imageMarkdown(asset))"
        task.area = area

        modelContext.insert(area)
        modelContext.insert(asset)
        modelContext.insert(task)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forArea(area, in: modelContext)
        #expect(summary.tasks == 1)
        #expect(summary.images == 1, "an image only a doomed task referenced is still destroyed by the cascade")
    }

    /// A task that is *not* going keeps its image, even when a doomed note shows the same one. The
    /// mirror of the test above: removing doomed bodies from the live set must remove one
    /// occurrence, not every row that happens to hold the same text.
    @Test func anAreaSummaryKeepsAnImageASurvivingTaskStillShows() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let asset = imageAsset(4)
        let body = "Repro: \(imageMarkdown(asset))"

        let doomedTask = AppTask(title: "Doomed")
        doomedTask.notes = body
        doomedTask.area = area
        // Same body, no container — Inbox, and the cascade does not touch it.
        let survivingTask = AppTask(title: "Survivor")
        survivingTask.notes = body

        modelContext.insert(area)
        modelContext.insert(asset)
        modelContext.insert(doomedTask)
        modelContext.insert(survivingTask)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forArea(area, in: modelContext)
        #expect(summary.tasks == 1)
        #expect(summary.images == 0, "the surviving task still shows that image, so nothing reclaims it")
    }

    /// **The claim the doc comment makes, measured against the cascade itself.** Every other count
    /// here is checked against a hand-built expectation; `images` is checked against what
    /// `deleteArea` actually collects, because the whole defect was a summary describing a sweep it
    /// had never been compared to.
    @Test func theAreaSummaryImageCountIsWhatTheCascadeActuallyReclaims() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let project = Project(name: "Nested", area: area)

        let noteAsset = imageAsset(5)
        let taskAsset = imageAsset(6)
        let sharedAsset = imageAsset(7)
        let untouchedAsset = imageAsset(8)

        let listNote = Note(kind: .list, title: "Spec", content: imageMarkdown(noteAsset))
        listNote.project = project
        let task = AppTask(title: "Screenshot")
        task.notes = "\(imageMarkdown(taskAsset)) \(imageMarkdown(sharedAsset))"
        task.area = area
        let survivor = Note(kind: .permanent, title: "Notepad", content: "\(imageMarkdown(sharedAsset)) \(imageMarkdown(untouchedAsset))")

        modelContext.insert(area)
        modelContext.insert(project)
        for asset in [noteAsset, taskAsset, sharedAsset, untouchedAsset] { modelContext.insert(asset) }
        modelContext.insert(listNote)
        modelContext.insert(task)
        modelContext.insert(survivor)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forArea(area, in: modelContext)
        let before = try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).count
        #expect(before == 4)

        #expect(modelContext.deleteArea(area))
        try modelContext.save()
        let after = try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).count

        #expect(summary.images == before - after, "the confirmation promised \(summary.images) images and the cascade took \(before - after)")
        #expect(summary.images == 2)
    }

    /// A context delete reaches its areas' and projects' notes, so it reaches their images too.
    @Test func aContextSummaryCountsImagesUnderItsAreasAndProjects() throws {
        let modelContext = ModelContext(try container())
        let context = Context(name: "Work")
        let area = Area(name: "Area", context: context)
        let project = Project(name: "Nested", context: context, area: area)
        let areaAsset = imageAsset(9)
        let projectAsset = imageAsset(10)

        let areaNote = Note(kind: .list, title: "Area note", content: imageMarkdown(areaAsset))
        areaNote.area = area
        let projectNote = Note(kind: .list, title: "Project note", content: imageMarkdown(projectAsset))
        projectNote.project = project

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(areaAsset)
        modelContext.insert(projectAsset)
        modelContext.insert(areaNote)
        modelContext.insert(projectNote)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forContext(context, in: modelContext)
        #expect(summary.images == 2)
    }

    /// A daily note filed against the list survives the cascade, so its image does too — the
    /// `.list` filter the other counts already respect, applied to the bytes.
    @Test func aSummaryLeavesTheImagesOfNotesTheCascadeDoesNotDelete() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Ship")
        let asset = imageAsset(11)
        let daily = Note(kind: .daily, title: "Monday", content: imageMarkdown(asset))
        daily.project = project

        modelContext.insert(project)
        modelContext.insert(asset)
        modelContext.insert(daily)
        try modelContext.save()

        let summary = CadenceListDeletionSummary.forProject(project, in: modelContext)
        #expect(summary.notes == 0)
        #expect(summary.images == 0)
        #expect(summary.isEmpty)
    }

    /// **A failed fetch is not an empty store**, ported from `CadenceNoteDeletionSummary` along
    /// with the count. Neither read can be made to fail against an in-memory container, which is
    /// why the arithmetic is reachable directly — see the seam's own note.
    @Test func anUnreadableStoreIsReportedRatherThanCountedAsZero() {
        let doomed = UUID()
        let doomedText = "![shot](cadence-image://\(doomed.uuidString))"

        var complete = CadenceListDeletionSummary()
        complete.applyImageSweep(
            doomedTexts: [doomedText],
            survivingMarkdownTexts: [],
            existingImageAssetIDs: [doomed]
        )
        #expect(complete.images == 1)
        #expect(!complete.hasUnknownImpact)
        #expect(complete.unknownImpactLine == nil)

        // The survivor set failed: the count moves up, which over-states the loss and is allowed.
        var survivorsUnread = CadenceListDeletionSummary()
        survivorsUnread.applyImageSweep(
            doomedTexts: [doomedText],
            survivingMarkdownTexts: nil,
            existingImageAssetIDs: [doomed]
        )
        #expect(survivorsUnread.images == 1)
        #expect(survivorsUnread.hasUnknownImpact)

        // The asset table failed: the count collapses to zero, which is the direction that
        // over-promises survival, so the flag is the only thing keeping the screen honest.
        var assetsUnread = CadenceListDeletionSummary()
        assetsUnread.applyImageSweep(
            doomedTexts: [doomedText],
            survivingMarkdownTexts: [],
            existingImageAssetIDs: nil
        )
        #expect(assetsUnread.images == 0)
        #expect(assetsUnread.hasUnknownImpact)
        #expect(assetsUnread.unknownImpactLine == CadenceNoteDeletionSummary.unknownImpactNotice)
        // And "nothing else is filed here" is never said while a read is outstanding.
        #expect(!assetsUnread.isEmpty)
    }

    /// One sentence, two confirmations. A second wording of the same caveat is the near-copy this
    /// file already bans for the cascade sentences.
    @Test func bothDeleteConfirmationsShareOneUnknownImpactSentenceAndOneRow() throws {
        var summary = CadenceListDeletionSummary()
        summary.hasUnknownImpact = true
        #expect(summary.unknownImpactLine == CadenceNoteDeletionSummary.unknownImpactNotice)

        // One call site each — the helper's needle is `name(`, so the declaration itself is not
        // counted. It is asserted separately below, in the file that owns the sentence.
        try expectCallSites(of: "iOSDeleteUnknownImpactRow", at: [
            "Cadence/iOS/iOSNoteDeletionSupport.swift": 1,
            "Cadence/iOS/iOSListDeletionSupport.swift": 1
        ])

        let noteSupport = try strippingComments(sourceFile("Cadence/iOS/iOSNoteDeletionSupport.swift"))
        #expect(
            noteSupport.components(separatedBy: "struct iOSDeleteUnknownImpactRow: View").count - 1 == 1,
            "the shared amber row is declared somewhere other than beside the sentence it prints"
        )

        let listSupport = try strippingComments(sourceFile("Cadence/iOS/iOSListDeletionSupport.swift"))
        #expect(listSupport.contains("summary.unknownImpactLine"))
        #expect(
            !listSupport.contains("Couldn't check everything"),
            "the list sheet spells the unknown-impact sentence instead of reading it"
        )
    }

    // MARK: - The cascades are no longer macOS-only

    /// The file moved to `Cadence/Services/` and shed its guard. The `#if os(macOS)` that remains is
    /// the single documented seam — macOS keeps the AppKit-shaped hooks around the shared
    /// task-deletion core — and a second one appearing here means somebody has started forking
    /// cascade behaviour per platform, which is precisely what T-187 exists to prevent.
    @Test func theCascadesLiveInServicesWithExactlyOnePlatformSeam() throws {
        // Stripped, because this file's own doc comment quotes the guard it no longer has.
        let moved = try strippingComments(sourceFile("Cadence/Services/CadenceListDeleteHelpers.swift"))
        #expect(moved.contains("extension ModelContext {"))
        #expect(moved.contains("func deleteContext("))
        #expect(moved.contains("func deleteArea("))
        #expect(moved.contains("func deleteProject("))
        #expect(moved.components(separatedBy: "#if os(macOS)").count - 1 == 1)
        #expect(moved.components(separatedBy: "#if os(iOS)").count - 1 == 0)

        // The old path is a comment-only tombstone. Sharing a base name with the moved file would
        // collide on `.stringsdata`, which is why the survivor carries the `Cadence` prefix.
        let tombstone = try strippingComments(sourceFile("Cadence/macOS/Services/ListDeleteHelpers.swift"))
        #expect(tombstone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// iOS reaches the shared cascades, from exactly one file and exactly once each.
    ///
    /// The counts are exact rather than "at least one" because the whole risk in T-187 is a second
    /// delete path: a call to `deleteArea` appearing in a *view* would mean some surface had grown
    /// its own unconfirmed delete beside the one `iOSListDeletion` modifier.
    @Test func iOSCallsTheSharedCascadesFromOnePlaceOnly() throws {
        try expectCallSites(of: "modelContext.deleteArea", at: [
            "Cadence/iOS/iOSListDeletionSupport.swift": 1
        ])
        try expectCallSites(of: "modelContext.deleteProject", at: [
            "Cadence/iOS/iOSListDeletionSupport.swift": 1
        ])
        try expectCallSites(of: "modelContext.deleteContext", at: [
            "Cadence/iOS/iOSListDeletionSupport.swift": 1
        ])

        for path in try swiftFiles(under: "Cadence/iOS") where path != "Cadence/iOS/iOSListDeletionSupport.swift" {
            let code = try strippingComments(sourceFile(path))
            for cascade in ["deleteArea(", "deleteProject(", "deleteContext("] {
                #expect(
                    !code.contains(cascade),
                    "\(path) calls \(cascade) directly instead of going through iOSListDeletion"
                )
            }
        }
    }

    /// One confirmation, built in one place. Every surface that offers a delete sets the binding the
    /// `iOSListDeletion` modifier owns; none of them constructs the sheet, and none of them deletes.
    @Test func everyIOSDeleteSurfaceGoesThroughTheOneConfirmation() throws {
        try expectCallSites(of: "iOSListDeleteConfirmationSheet", at: [
            "Cadence/iOS/iOSListDeletionSupport.swift": 1,
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSListsRegularPane.swift": 0,
            "Cadence/iOS/iOSSettingsView.swift": 0,
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift": 0
        ])

        // The modifier is attached on the two hosts, and only there: the iPad pane and the settings
        // list section *request* a deletion up to their host rather than owning a second sheet.
        try expectCallSites(of: ".iOSListDeletion", at: [
            "Cadence/iOS/iOSListViews.swift": 1,
            "Cadence/iOS/iOSSettingsView.swift": 1,
            "Cadence/iOS/iOSListsRegularPane.swift": 0,
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift": 0
        ])

        // Areas and projects on both the iPhone list and the iPad pane; contexts in settings.
        try expectCallSites(of: "iOSListDeleteMenuButton", at: [
            "Cadence/iOS/iOSListViews.swift": 2,
            "Cadence/iOS/iOSListsRegularPane.swift": 2,
            "Cadence/iOS/iOSSettingsView.swift": 1
        ])
    }

    /// The confirmation copy is the shared one, so the two platforms cannot come to describe the
    /// same cascade differently. macOS's three dialogs read it; nothing spells the sentence twice.
    @Test func bothPlatformsReadTheSameCascadeSentence() throws {
        try expectOccurrences(of: "cascadeSentence", at: [
            "Cadence/macOS/Views/SettingsView.swift": 3,
            "Cadence/macOS/Sheets/EditListSheet.swift": 2,
            "Cadence/iOS/iOSListDeletionSupport.swift": 1
        ])

        // Scoped to the three list cascades, not to the words "permanently deletes" — Data Safety's
        // own privacy-reset sentence is a different promise about a different operation and is
        // deliberately spelled where it is shown.
        let forbidden = [
            "deletes the area and",
            "deletes the project and",
            "deletes the context and"
        ]
        for path in try swiftFiles(under: "Cadence") where path != "Cadence/Shared/CadenceListDeletionSummary.swift" {
            let code = try strippingComments(sourceFile(path))
            for sentence in forbidden {
                #expect(
                    !code.contains(sentence),
                    "\(path) spells the cascade sentence itself instead of reading CadenceListDeletionKind"
                )
            }
        }
    }

    /// Without this, every zero and every absence assertion above could be passing because the
    /// reader returned an empty string.
    @Test func theSourceScanActuallyReadsTheseFilesInListDeletionSurface() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.contains("Cadence/Services/CadenceListDeleteHelpers.swift"))
        #expect(files.contains("Cadence/macOS/Services/ListDeleteHelpers.swift"))
        #expect(files.contains("Cadence/iOS/iOSListDeletionSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSListViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSListsRegularPane.swift"))
        #expect(files.contains("Cadence/iOS/iOSSettingsView.swift"))
        #expect(files.contains("Cadence/iOS/iOSSettingsTemplateAndListSections.swift"))
        #expect(files.contains("Cadence/macOS/Views/SettingsView.swift"))
        #expect(files.contains("Cadence/macOS/Sheets/EditListSheet.swift"))

        // And it must be reading *code*, through the same reader the absence checks use.
        let support = try strippingComments(sourceFile("Cadence/iOS/iOSListDeletionSupport.swift"))
        #expect(support.contains("struct iOSListDeleteConfirmationSheet: View"))
        #expect(support.contains("enum iOSListDeletionTarget: Identifiable"))

        let pane = try strippingComments(sourceFile("Cadence/iOS/iOSListsRegularPane.swift"))
        #expect(pane.contains("struct iOSListsRegularPane: View"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** `CadenceSharedBoardChromeTests` documents why: a mutation run
/// caught a version of that file asserting only that each file mentioned the shared component
/// somewhere, and reverting *one* of four call sites left it green.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
///
/// `expectCallSites` appends `(` and so only sees calls; a property read is neither called nor
/// passed, which is the spelling needed for `cascadeSentence`.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
