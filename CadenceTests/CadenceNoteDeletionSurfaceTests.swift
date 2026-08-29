import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-226: iOS could not delete a note. `modelContext.delete` under `Cadence/iOS/` reached
/// `SavedLink`, `Subtask`, tasks, bundles, goals, habits, areas, projects and contexts — never
/// `Note` — and `676ff3b` then shipped a note-management column that creates, files and moves
/// notes, so every note ever made on the device was permanent.
///
/// **Two kinds of test here, and both are load-bearing for a different reason.**
///
/// The behavioural half pins the *cleanup*, which is the part a hand-rolled second delete gets
/// wrong: a note's body references `MarkdownImageAsset` rows that nothing cascades to, so
/// `delete(note)` alone leaks `.externalStorage` bytes forever, while its `tags` must survive
/// because a tag is a first-class object that outlives the notes filed under it. That is reachable
/// from this macOS-built target because `ModelContext.deleteNote` lives in `Shared/`.
///
/// The source half pins that iOS *reaches* it. `Cadence/iOS/` is entirely inside `#if os(iOS)` and
/// this target builds for macOS, so there is no iOS symbol to reference and a source scan is the
/// only tool — the same arrangement `CadenceListDeletionSurfaceTests` and
/// `CadenceGoalListLinkSurfaceTests` use, with exact per-file counts rather than "contains",
/// comment-stripping rather than allowlisting, and a non-vacuity test so a broken reader cannot
/// make the absence assertions pass silently.
@MainActor
struct CadenceNoteDeletionSurfaceTests {

    // MARK: - Fixtures

    private func imageAsset(_ byte: UInt8) -> MarkdownImageAsset {
        MarkdownImageAsset(
            data: Data([byte]),
            mimeType: "image/png",
            pixelWidth: 20,
            pixelHeight: 20,
            displayWidth: 20
        )
    }

    /// The reference regex requires the reference to own its whole line, so fixtures build bodies
    /// out of lines rather than concatenating.
    private func imageLine(_ asset: MarkdownImageAsset) -> String {
        "![shot](cadence-image://\(asset.id.uuidString))"
    }

    private func danglingImageLine() -> String {
        "![gone](cadence-image://\(UUID().uuidString))"
    }

    // MARK: - What the delete actually cleans up

    /// The whole behavioural claim in one store: the note goes, the images **only it** referenced
    /// go with it, and everything else it merely pointed at stays.
    ///
    /// Each survivor is a different failure this pins. The shared asset is the over-collection
    /// failure — one bad sweep taking out the user's image library is a hazard this repo has
    /// already had to write a guard for. The tag is the over-cascade failure. The area is the
    /// "deleting a document deleted its folder" failure. And the surviving note proves the delete
    /// is scoped to one row at all.
    @Test func deletingANoteTakesTheImagesOnlyItReferencedAndNothingElse() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Documents", context: context)
        let tag = Cadence.Tag(name: "Spec")
        let exclusiveAsset = imageAsset(1)
        let sharedAsset = imageAsset(2)

        let doomed = Note(
            kind: .list,
            title: "Doomed",
            content: "Body text\n\(imageLine(exclusiveAsset))\n\(imageLine(sharedAsset))",
            area: area
        )
        let survivor = Note(
            kind: .list,
            title: "Survivor",
            content: "Still here\n\(imageLine(sharedAsset))",
            area: area
        )
        doomed.tags = [tag]
        survivor.tags = [tag]

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(tag)
        modelContext.insert(exclusiveAsset)
        modelContext.insert(sharedAsset)
        modelContext.insert(doomed)
        modelContext.insert(survivor)
        try modelContext.save()

        let doomedID = doomed.id
        modelContext.deleteNote(doomed)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<Note>()).map(\.id) == [survivor.id])
        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).map(\.id) == [sharedAsset.id])

        // The tag survives, and no longer claims a note that is gone.
        let tags = try modelContext.fetch(FetchDescriptor<Cadence.Tag>())
        #expect(tags.map(\.id) == [tag.id])
        #expect(Set((tags.first?.notes ?? []).map(\.id)) == [survivor.id])

        // The list the note was filed in is not a casualty of the note.
        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        #expect(areas.map(\.id) == [area.id])
        #expect((areas.first?.notes ?? []).map(\.id) == [survivor.id])
        #expect(!(areas.first?.notes ?? []).contains { $0.id == doomedID })
        #expect(try modelContext.fetch(FetchDescriptor<Context>()).count == 1)
    }

    /// A note whose images are all shared loses none of them — the sweep's exclusion set is the
    /// deleted note's id, not "everything this note mentioned".
    @Test func deletingANoteThatSharesEveryImageReclaimsNothing() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let asset = imageAsset(7)
        let doomed = Note(kind: .permanent, title: "A", content: imageLine(asset))
        let survivor = Note(kind: .permanent, title: "B", content: imageLine(asset))

        modelContext.insert(asset)
        modelContext.insert(doomed)
        modelContext.insert(survivor)
        try modelContext.save()

        modelContext.deleteNote(doomed)
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).map(\.id) == [asset.id])
    }

    // MARK: - What the confirmation promises

    /// The one thing this summary may not do. `images` is what the sweep will actually collect, so
    /// a reference to an asset row that is already gone must not be counted, and neither must an
    /// asset another note still shows. Counting the note's own image references — the obvious
    /// implementation — reports 3 where the truth is 1.
    @Test func theImageCountNeverPromisesAnImageThatSurvivesTheDelete() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let exclusiveAsset = imageAsset(1)
        let sharedAsset = imageAsset(2)
        let doomed = Note(
            kind: .list,
            title: "Doomed",
            content: [
                imageLine(exclusiveAsset),
                imageLine(sharedAsset),
                danglingImageLine()
            ].joined(separator: "\n")
        )
        let survivor = Note(kind: .list, title: "Survivor", content: imageLine(sharedAsset))

        modelContext.insert(exclusiveAsset)
        modelContext.insert(sharedAsset)
        modelContext.insert(doomed)
        modelContext.insert(survivor)
        try modelContext.save()

        #expect(CadenceNoteDeletionSummary.forNote(doomed, in: modelContext).images == 1)
    }

    /// **The promise, checked against the sweep instead of against a restatement of it (T-423).**
    ///
    /// `forNote`'s doc comment claimed `images` named "the exact set
    /// `deleteUnreferencedMarkdownImageAssets` will collect", and nothing compared the two. T-411
    /// then widened the sweep from `Note.content` to the seven fields of
    /// `CadenceMarkdownSourceInventory` while the summary went on reading surviving notes alone —
    /// so an image also pasted into a task's notes, or living in a legacy row the migration never
    /// deleted, was announced as about to be lost and then kept. The comment stayed true-looking
    /// the whole time because it was only ever checked against itself.
    ///
    /// So this runs the real delete and compares. The wrong direction is the safe one — the
    /// summary over-stated the *loss*, never the survival — but it is still a number on a
    /// confirmation that does not describe what the button does.
    ///
    /// The orphan is why the restriction in the promise is real rather than pedantic: the sweep
    /// collects it, this note is not why, and `images` must not claim credit for it.
    @Test func theImageCountMatchesWhatTheSweepActuallyCollects() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let exclusive = imageAsset(1)
        let alsoInATask = imageAsset(2)
        let alsoInALegacyRow = imageAsset(3)
        let orphan = imageAsset(4)

        let doomed = Note(
            kind: .list,
            title: "Doomed",
            content: [
                imageLine(exclusive),
                imageLine(alsoInATask),
                imageLine(alsoInALegacyRow)
            ].joined(separator: "\n")
        )
        let task = AppTask(title: "Wire the thing")
        task.notes = imageLine(alsoInATask)
        let legacy = DailyNote(date: "2026-08-21")
        legacy.content = imageLine(alsoInALegacyRow)

        for asset in [exclusive, alsoInATask, alsoInALegacyRow, orphan] {
            modelContext.insert(asset)
        }
        modelContext.insert(doomed)
        modelContext.insert(task)
        modelContext.insert(legacy)
        try modelContext.save()

        let doomedReferences = MarkdownImageAssetService.referencedIDs(in: doomed.content)
        let before = Set(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).map(\.id))
        // Non-vacuity: four rows, three of them referenced by the note under test.
        #expect(before.count == 4)
        #expect(doomedReferences.count == 3)

        let summary = CadenceNoteDeletionSummary.forNote(doomed, in: modelContext)
        #expect(!summary.hasUnknownImpact, "the fixture is fully readable")

        modelContext.deleteNote(doomed)
        try modelContext.save()

        let after = Set(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).map(\.id))
        // What the sweep did: the exclusive image and the pre-existing orphan went; the two the
        // task and the legacy row still reference stayed.
        #expect(after == [alsoInATask.id, alsoInALegacyRow.id])

        // The promise, spelled as the arithmetic rather than as a literal: everything this note
        // referenced that the delete actually took.
        #expect(summary.images == before.subtracting(after).intersection(doomedReferences).count)
        #expect(summary.images == 1)
        #expect(summary.lostItemLines.contains("1 embedded image"))
    }

    /// Words, tags and backlinks, and which of the three are losses. A note is a small enough
    /// object that the reassurance carries as much of the confirmation as the warning does.
    @Test func theSummaryCountsWordsAsLossAndTagsAndBacklinksAsSurvivors() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let specTag = Cadence.Tag(name: "Spec")
        let draftTag = Cadence.Tag(name: "Draft")
        let doomed = Note(kind: .list, title: "Doomed", content: "one two three four five")
        doomed.tags = [specTag, draftTag]

        // One backlink by title, one by stable id, and one note that mentions neither.
        let byTitle = Note(kind: .list, title: "Points here", content: "see [[Doomed]]")
        let byID = Note(
            kind: .list,
            title: "Also points",
            content: "see \(NoteReferenceParser.noteReferenceMarkdown(for: doomed))"
        )
        let unrelated = Note(kind: .list, title: "Quiet", content: "nothing here")

        modelContext.insert(specTag)
        modelContext.insert(draftTag)
        modelContext.insert(doomed)
        modelContext.insert(byTitle)
        modelContext.insert(byID)
        modelContext.insert(unrelated)
        try modelContext.save()

        let summary = CadenceNoteDeletionSummary.forNote(doomed, in: modelContext)
        #expect(summary.words == 5)
        #expect(summary.images == 0)
        #expect(summary.tags == 2)
        #expect(summary.backlinks == 2)
        #expect(!summary.isEmpty)

        // Only the losses are bulleted; the survivors get sentences that say they survive.
        #expect(summary.lostItemLines == ["5 words"])
        #expect(summary.retainedLine == "2 tags stay — deleting a note never deletes a tag.")
        #expect(summary.brokenLinkLine == "2 other notes link to this one. Those links will stop resolving.")
    }

    @Test func lostItemLinesOmitZeroesAndPluralize() {
        var one = CadenceNoteDeletionSummary()
        one.words = 1
        one.images = 1
        one.tags = 1
        one.backlinks = 1
        #expect(one.lostItemLines == ["1 word", "1 embedded image"])
        #expect(one.retainedLine == "1 tag stays — deleting a note never deletes a tag.")
        #expect(one.brokenLinkLine == "1 other note links to this one. That link will stop resolving.")

        var many = CadenceNoteDeletionSummary()
        many.words = 412
        many.images = 3
        #expect(many.lostItemLines == ["412 words", "3 embedded images"])
        #expect(many.retainedLine == nil)
        #expect(many.brokenLinkLine == nil)
    }

    /// An untouched note still gets a confirmation, and the confirmation still has to say
    /// something — the same reason `CadenceListDeletionSummary.isEmpty` is published rather than
    /// inferred from `lostItemLines`.
    @Test func aNoteWithNothingInItReportsEmptyRatherThanZeroLines() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let blank = Note(kind: .list, title: "Untitled", content: "   \n\n  ")
        modelContext.insert(blank)
        try modelContext.save()

        let summary = CadenceNoteDeletionSummary.forNote(blank, in: modelContext)
        #expect(summary.isEmpty)
        #expect(summary.lostItemLines.isEmpty)
    }

    /// **The folder line, restored by T-233.** It was on the confirmation once and came off because
    /// reading `note.folderPath` failed a test named for *writes* whose needle counted reads —
    /// `CadenceNoteFolderSurfaceTests.onlyTheSharedFilingHelperWritesAFolderPath`, now an assignment
    /// scan. It is on the summary rather than read off the note in the view so that the `""`-is-root
    /// convention is applied by `CadenceNoteFolderPath` and so that this line is pinnable here
    /// rather than only by a source scan.
    ///
    /// `nil` at the root, deliberately, and not `CadenceNoteFolderPath.rootDisplayName`: "Notes" is
    /// the heading a folder-less run of rows does **not** draw, and printing it in a confirmation
    /// would name a folder the user never made.
    @Test func theSummaryNamesTheFolderAndSaysNothingAtTheRoot() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let filed = Note(kind: .list, title: "Spec", content: "body", folderPath: "Planning")
        let nested = Note(kind: .list, title: "Spec", content: "body", folderPath: "/Planning/Research/")
        let unfiled = Note(kind: .list, title: "Spec", content: "body")
        let whitespace = Note(kind: .list, title: "Spec", content: "body", folderPath: "  /  ")
        for note in [filed, nested, unfiled, whitespace] { modelContext.insert(note) }
        try modelContext.save()

        #expect(CadenceNoteDeletionSummary.forNote(filed, in: modelContext).folder == "Planning")
        // Normalized on read, and the **whole** path — `Planning/Research` and `Admin/Research` are
        // two folders, so a leaf-only label would name them both "Research".
        #expect(CadenceNoteDeletionSummary.forNote(nested, in: modelContext).folder == "Planning/Research")
        #expect(CadenceNoteDeletionSummary.forNote(unfiled, in: modelContext).folder == nil)
        #expect(CadenceNoteDeletionSummary.forNote(whitespace, in: modelContext).folder == nil)

        // The three notes are otherwise identical, which is the reason the line exists: without it
        // the confirmation for any of them is the same screen.
        #expect(filed.displayTitle == unfiled.displayTitle)
        #expect(CadenceNoteDeletionSummary.forNote(filed, in: modelContext).lostItemLines
                == CadenceNoteDeletionSummary.forNote(unfiled, in: modelContext).lostItemLines)
    }

    /// The confirmation reads the folder off the summary, not off the note — one line, and the only
    /// `folderPath` mention in the sheet is none at all.
    @Test func theIOSConfirmationRendersTheFolderFromTheSummary() throws {
        let sheet = try strippingComments(sourceFile("Cadence/iOS/iOSNoteDeletionSupport.swift"))
        #expect(sheet.components(separatedBy: "summary.folder").count - 1 == 1)
        // Not through the note, so the sheet cannot decide for itself what `""` means.
        #expect(!sheet.contains("folderPath"))
    }

    // MARK: - Both platforms delete through the one helper

    /// The delete is `ModelContext.deleteNote` and nothing else, from exactly three places: the two
    /// macOS pages that already had it, and the one iOS modifier.
    ///
    /// Exact counts rather than "at least one", because the whole risk is a second delete path: a
    /// fourth call site means some surface has grown its own delete beside the confirmed one.
    @Test func bothPlatformsDeleteThroughTheOneSharedHelper() throws {
        try expectCallSites(of: "modelContext.deleteNote", at: [
            "Cadence/iOS/iOSNoteDeletionSupport.swift": 1,
            "Cadence/macOS/Views/ListNotesView.swift": 1,
            "Cadence/macOS/Views/NotesView.swift": 1
        ])

        // The image sweep is spelled in the cascades and in the shared note delete, and nowhere
        // else. A view calling it directly again is a view that has re-derived the cleanup.
        try expectCallSites(of: "deleteUnreferencedMarkdownImageAssets", at: [
            "Cadence/Services/CadenceListDeleteHelpers.swift": 4,
            "Cadence/Shared/CadenceNoteActionSupport.swift": 1,
            "Cadence/macOS/Views/ListNotesView.swift": 0,
            "Cadence/macOS/Views/NotesView.swift": 0
        ])

        // And macOS no longer keeps its own pasteboard copy of the note link.
        let macActions = try strippingComments(sourceFile("Cadence/macOS/Views/AIActionsSupportViews.swift"))
        #expect(!macActions.contains("NSPasteboard"))
        try expectCallSites(of: "CadenceNoteClipboard.copyMarkdownLink", at: [
            "Cadence/macOS/Views/AIActionsSupportViews.swift": 1,
            "Cadence/iOS/iOSNoteDeletionSupport.swift": 1
        ])
    }

    /// iOS reaches the shared delete from one file, behind one confirmation, and the two note
    /// surfaces only *request* it.
    @Test func theIOSDeleteIsRequestedByRowsAndPerformedOnlyByTheModifier() throws {
        try expectCallSites(of: "iOSNoteDeleteConfirmationSheet", at: [
            "Cadence/iOS/iOSNoteDeletionSupport.swift": 1,
            "Cadence/iOS/iOSListNotesView.swift": 0,
            "Cadence/iOS/iOSNotesView.swift": 0
        ])

        try expectCallSites(of: ".iOSNoteDeletion", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/iOS/iOSNotesView.swift": 1
        ])

        // The list-detail Notes column and the Notes tab's notepad rows — the two places macOS
        // offers a note delete from.
        try expectCallSites(of: "iOSNoteDeleteMenuButton", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/iOS/iOSNotesView.swift": 1,
            "Cadence/iOS/iOSNoteDeletionSupport.swift": 0
        ])

        // Copy Note Link was macOS-only too, and lands where macOS has it: the list-note row menu.
        try expectCallSites(of: "iOSNoteCopyLinkButton", at: [
            "Cadence/iOS/iOSListNotesView.swift": 1,
            "Cadence/iOS/iOSNoteDeletionSupport.swift": 0
        ])

        // Nothing else in the folder names the delete at all.
        for path in try swiftFiles(under: "Cadence/iOS") where path != "Cadence/iOS/iOSNoteDeletionSupport.swift" {
            let code = try strippingComments(sourceFile(path))
            #expect(
                !code.contains("deleteNote("),
                "\(path) deletes a note directly instead of going through iOSNoteDeletion"
            )
        }
    }

    /// Without this, every zero and every absence above could be passing because the reader
    /// returned an empty string — which is exactly what a `/tmp` against `/private/tmp` path
    /// mismatch produces on an isolated build tree.
    @Test func theSourceScanActuallyReadsTheseFilesInNoteDeletionSurface() throws {
        #expect(try swiftFiles(under: "Cadence").count > 300)
        #expect(try swiftFiles(under: "Cadence/Shared").contains("Cadence/Shared/CadenceNoteActionSupport.swift"))

        let iOSFiles = try swiftFiles(under: "Cadence/iOS")
        #expect(iOSFiles.contains("Cadence/iOS/iOSNoteDeletionSupport.swift"))
        #expect(iOSFiles.contains("Cadence/iOS/iOSListNotesView.swift"))
        #expect(iOSFiles.contains("Cadence/iOS/iOSNotesView.swift"))

        // And it must be reading *code*, through the same reader the absence checks use.
        let support = try strippingComments(sourceFile("Cadence/iOS/iOSNoteDeletionSupport.swift"))
        #expect(support.contains("struct iOSNoteDeleteConfirmationSheet: View"))
        #expect(support.contains("struct iOSNoteDeleteMenuButton: View"))
        #expect(support.contains("struct iOSNoteCopyLinkButton: View"))

        let helper = try strippingComments(sourceFile("Cadence/Shared/CadenceNoteActionSupport.swift"))
        #expect(helper.contains("func deleteNote(_ note: Note)"))
        #expect(helper.contains("struct CadenceNoteDeletionSummary"))

        let column = try strippingComments(sourceFile("Cadence/iOS/iOSListNotesView.swift"))
        #expect(column.contains("struct iOSListNotesView: View"))

        // And the stripper stripped: the shared helper explains the leak in prose, and none of the
        // assertions above may be reading prose.
        let raw = try sourceFile("Cadence/Shared/CadenceNoteActionSupport.swift")
        #expect(raw.contains("leaks every image that note was the last"))
        #expect(!helper.contains("leaks every image"))
    }

    // MARK: - T-298: a failed fetch is not an empty store

    /// **The summary used to understate the damage on a store hiccup**, which is the one direction
    /// a wrong number on a confirmation must not go. Both reads in `forNote(_:in:)` were
    /// `(try? …) ?? []`, so a failed fetch produced "0 embedded images" and no broken-link line —
    /// the smallest possible account of the delete, presented as fact, on the screen where the
    /// user says yes.
    ///
    /// The rule followed here is already settled twice in this codebase:
    /// `HabitNotificationReconcileSupport.reconcileInput` returns `nil` rather than `([], [])`
    /// because reconcile reads an empty desired set as "cancel everything", and
    /// `MarkdownTaskEmbedSupport.storeHoldsTask` returns `Bool?` so a failed read keeps the cached
    /// task. Same distinction, third site.
    @Test func aFailedStoreReadReportsUnknownImpactRatherThanZero() throws {
        let asset = imageAsset(1)
        let doomed = Note(kind: .list, title: "Doomed", content: imageLine(asset))
        let backlink = Note(kind: .list, title: "Points here", content: "see [[Doomed]]")
        let notes = [doomed, backlink]
        let assetIDs: Set<UUID> = [asset.id]

        // Both reads landed: the counts are a total, and the confirmation says nothing extra.
        let known = CadenceNoteDeletionSummary.forNote(
            doomed,
            allNotes: notes,
            survivingMarkdownTexts: [backlink.content],
            existingImageAssetIDs: assetIDs
        )
        #expect(!known.hasUnknownImpact)
        #expect(known.unknownImpactLine == nil)
        #expect(known.images == 1)
        #expect(known.backlinks == 1)

        // The note table could not be read. The backlink count collapses to zero and the image
        // count loses its survivor set — the summary has to say so rather than print the floor.
        let noNotes = CadenceNoteDeletionSummary.forNote(
            doomed,
            allNotes: nil,
            survivingMarkdownTexts: nil,
            existingImageAssetIDs: assetIDs
        )
        #expect(noNotes.hasUnknownImpact)
        #expect(noNotes.unknownImpactLine == CadenceNoteDeletionSummary.unknownImpactNotice)

        // The asset table could not be read: `images` reads 0 for a note that embeds one.
        let noAssets = CadenceNoteDeletionSummary.forNote(
            doomed,
            allNotes: notes,
            survivingMarkdownTexts: [backlink.content],
            existingImageAssetIDs: nil
        )
        #expect(noAssets.images == 0)
        #expect(noAssets.hasUnknownImpact)

        let neither = CadenceNoteDeletionSummary.forNote(
            doomed,
            allNotes: nil,
            survivingMarkdownTexts: nil,
            existingImageAssetIDs: nil
        )
        #expect(neither.hasUnknownImpact)

        // T-423 added a third fetch that can fail on its own: the note table read fine, but one of
        // the other six markdown sources did not. `images` then loses its survivor set the same
        // way, so the flag has to rise for this case too — and the backlink count, which does not
        // depend on it, stays exact.
        let noMarkdown = CadenceNoteDeletionSummary.forNote(
            doomed,
            allNotes: notes,
            survivingMarkdownTexts: nil,
            existingImageAssetIDs: assetIDs
        )
        #expect(noMarkdown.hasUnknownImpact)
        #expect(noMarkdown.backlinks == known.backlinks)

        // The words, the tags and the folder are read off the note itself and stay exact through
        // all of it — which is why this is a flag beside the counts rather than four `Int?`s.
        #expect(noNotes.words == known.words)
        #expect(noNotes.tags == known.tags)
        #expect(noNotes.folder == known.folder)
    }

    /// **A genuinely empty store is still a known zero.** This is the half that makes the flag
    /// worth having: if `[]` and `nil` both raised it, the notice would appear on the first note
    /// in a new install and mean nothing by the second.
    @Test func aGenuinelyEmptyStoreIsAKnownZeroAndNotAnUnknown() {
        let lonely = Note(kind: .list, title: "Only note", content: "one two three")
        let summary = CadenceNoteDeletionSummary.forNote(
            lonely,
            allNotes: [lonely],
            survivingMarkdownTexts: [],
            existingImageAssetIDs: []
        )

        #expect(!summary.hasUnknownImpact)
        #expect(summary.unknownImpactLine == nil)
        #expect(summary.images == 0)
        #expect(summary.backlinks == 0)
        #expect(summary.words == 3)
    }

    /// "Nothing has been written in this note yet." is the strongest claim on that screen, and an
    /// unread image table is exactly the case where it would be reassuring and false at once. So
    /// `isEmpty` answers `false` while the impact is unknown, whatever the counts say.
    @Test func anUnreadableStoreStopsTheConfirmationClaimingTheNoteIsEmpty() {
        let blank = Note(kind: .list, title: "Untitled", content: "   \n\n  ")

        let known = CadenceNoteDeletionSummary.forNote(
            blank,
            allNotes: [blank],
            survivingMarkdownTexts: [],
            existingImageAssetIDs: []
        )
        #expect(known.isEmpty)
        #expect(known.lostItemLines.isEmpty)

        let unknown = CadenceNoteDeletionSummary.forNote(
            blank,
            allNotes: nil,
            survivingMarkdownTexts: nil,
            existingImageAssetIDs: []
        )
        #expect(!unknown.isEmpty)
        #expect(unknown.unknownImpactLine != nil)
    }

    /// The notice names the direction of the doubt, because the doubt is one-sided: every count a
    /// failed fetch can move, it moves down. "Something went wrong" would leave "0 embedded
    /// images" on screen still reading as "no images".
    @Test func theUnknownImpactNoticeSaysTheDeleteMayBeLargerNotJustUncertain() {
        #expect(CadenceNoteDeletionSummary.unknownImpactNotice.contains("may remove more"))
        #expect(CadenceNoteDeletionSummary.unknownImpactNotice
                != CadenceNoteDeletionSummary.deleteFailureNotice)
    }

    /// The store-reading entry point may not coerce a failed fetch back to an empty one. A scan
    /// because the two `try?`s are inside a static function whose only observable difference is
    /// the flag the tests above already check — this pins the *shape*, so a well-meaning `?? []`
    /// cannot come back and leave those tests passing on the hoisted overload alone.
    @Test func theSummarysOwnFetchesKeepFailureDistinctFromEmptiness() throws {
        let raw = try sourceFile("Cadence/Shared/CadenceNoteActionSupport.swift")
        let source = try strippingComments(sourceFile("Cadence/Shared/CadenceNoteActionSupport.swift"))
        #expect(source != raw)
        #expect(source.count == raw.count)
        #expect(source.contains("struct CadenceNoteDeletionSummary"))

        let body = try #require(CadenceSourceScan.functionBody(named: "forNote", in: source))
        // It is the store-reading overload that was read, not the hoisted arithmetic one.
        #expect(body.contains("modelContext.fetch(FetchDescriptor<Note>())"))
        #expect(body.contains("modelContext.fetch(FetchDescriptor<MarkdownImageAsset>())"))
        // And neither read is flattened.
        #expect(!body.contains("?? []"))
        #expect(CadenceSourceScan.matchCount("\\?\\? \\[\\]", in: body) == 0)
        // The survivor set is the sweep's own, not a second opinion assembled from the note table
        // (T-423). A revert here is the exact shape that let the doc comment's promise go stale
        // while every behavioural test stayed green, so it is asserted positively rather than
        // left to the `?? []` check above to catch by accident.
        #expect(body.contains("CadenceMarkdownSourceInventory.liveMarkdownTexts("))
        #expect(body.contains("excludingNoteIDs: [note.id]"))
        // The needle compiles and discriminates; `matchCount` answers -1 for one that does not.
        #expect(CadenceSourceScan.matchCount("\\?\\? \\[\\]", in: "let x = y ?? []") == 1)
    }

    /// The confirmation renders the line, once, off the summary — the same arrangement the folder
    /// line uses, and for the same reason: `Cadence/iOS/` is invisible to this target.
    @Test func theIOSConfirmationRendersTheUnknownImpactLineFromTheSummary() throws {
        let raw = try sourceFile("Cadence/iOS/iOSNoteDeletionSupport.swift")
        let sheet = try strippingComments(sourceFile("Cadence/iOS/iOSNoteDeletionSupport.swift"))
        #expect(sheet != raw)
        #expect(sheet.count == raw.count)
        #expect(sheet.contains("struct iOSNoteDeleteConfirmationSheet: View"))

        #expect(sheet.components(separatedBy: "summary.unknownImpactLine").count - 1 == 1)
        // The row itself is now shared with the *list* confirmation (T-433) rather than private to
        // this sheet — one sentence, one amber row, two screens. `CadenceListDeletionSurfaceTests`
        // owns the pairing; this side just pins that the note sheet still draws it.
        #expect(sheet.contains("iOSDeleteUnknownImpactRow(line: unknownImpactLine)"))
        // It is drawn beside the counts it qualifies, not as a second red failure line: the
        // refused-delete notice keeps `Theme.red` and this keeps `Theme.amber`.
        #expect(sheet.contains("Theme.amber"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** `CadenceSharedBoardChromeTests` documents why: a mutation run
/// caught a version of that file asserting only that each file mentioned the shared component
/// somewhere, and reverting *one* of four call sites left it green.
///
/// Every needle above was checked against the real source before being written down. The substring
/// trap produced three defective assertions in this repo in a single day, and this file had a live
/// instance of it: `deleteNote(` alone also matches macOS's *private view method* of the same name,
/// which is why the needles carry their receiver (`modelContext.deleteNote`) or their leading dot
/// (`.iOSNoteDeletion`). The bare needle survives in exactly one place — the absence sweep over
/// `Cadence/iOS`, where matching too much is the safe direction.
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
