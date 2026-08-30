import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-497: the seven condemned `try? save()` sites T-322 classified and did not fix.**
///
/// T-322 wrote the rule (`AGENTS.md`, "The `try? save()` rule") and carried sixteen offenders; four
/// were fixed with the rule and twelve went into `CadenceSaveCommitDisciplineTests`' two exemption
/// lists by function name. This file is the seven of those twelve that needed no product decision:
///
/// **Tier 1, the existence half** — the function inserts, so a refused commit leaves the context
/// and the store disagreeing about whether a row exists, and a re-render cannot repair that the way
/// it repairs a field edit:
///
/// - `CadenceListNoteFiling.createNote` — both note columns then *select* what it returned.
/// - `SettingsTagsSection.createTag` and `iOSSettingsTagsSection.createTag`, one function on two
///   platforms, fixed as a pair.
/// - `iOSCalendarEventEditSheet.openEventNote`, the sharpest of the four: it inserts a note **and
///   presents it**, so the screen the user lands on is itself the report that the note exists.
///
/// **Tier 2, the report half** — three inline row editors, where collapsing back to the display row
/// is the dismissal:
///
/// - `SettingsTagsSection.saveEdits` (the tag catalog card).
/// - `TagPickerPopoverViews.saveEdits` and `.archive` (the picker's edit sheet).
///
/// **Tier 3 is deliberately still exempt.** `iOSSearchSupportViews` and
/// `iOSTaskDetailSheet.finishEditingAndDismiss` are "flush an in-place edit, then close" over a
/// field the user still has focus in, and what *undo* means there is a product decision, not a
/// mechanical one. The three Tier 2 editors are not that case: their fields are drafts held in
/// `@State`, so restoring the model does not fight a caret.
///
/// **Why the file is split the way it is.** Only `CadenceListNoteFiling.createNote` is a static
/// helper a test can call, so it carries the behavioural half — run against a real container with
/// a `commit` that throws, because a `save()` that throws cannot be provoked out of an in-memory
/// container and an undo path no test can reach is an undo path no test can prove. The other six
/// are `private func`s on SwiftUI views, three of them inside `#if os(iOS)` which this macOS test
/// target does not compile at all, so the only instrument available is a source scan. Each
/// assertion below is labelled accordingly.
@MainActor
struct CadenceTagAndNoteCommitSurfaceTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    // MARK: - Behavioural: the one site a test can call

    /// **Behavioural.** The success path: the note is in the store — read through a *second*
    /// context, so the assertion cannot be satisfied by the creating context's own memory — and
    /// nothing is left pending for some other screen's save to finish later.
    @Test func acommittedListNoteIsInTheStoreBeforeTheColumnSelectsIt() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let project = Project(name: "Launch")
        modelContext.insert(project)
        try modelContext.save()

        let note = try CadenceListNoteFiling.createNote(
            in: modelContext,
            area: nil,
            project: project,
            folderPath: "Planning",
            order: 0
        )

        #expect(!modelContext.hasChanges, "the new note is still pending after createNote returned")
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Note>()).map(\.folderPath) == ["Planning"],
            "the store does not hold the note the column is about to select"
        )
        #expect(note.folderPath == "Planning")
    }

    /// **Behavioural.** The failure path, and the whole point of the ticket: the note is gone from
    /// the context as well as the store, so the caller cannot select a row that does not exist.
    ///
    /// Asserted from a second context because a single-context read passes against the bug — the
    /// creating context answers with the note it is holding whether or not the save threw.
    @Test func arefusedListNoteCreationLeavesNoNoteInTheContextOrTheStore() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let project = Project(name: "Launch")
        modelContext.insert(project)
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try CadenceListNoteFiling.createNote(
                in: modelContext,
                area: nil,
                project: project,
                folderPath: "Planning",
                order: 0,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(
            try modelContext.fetch(FetchDescriptor<Note>()).isEmpty,
            "the context still holds a note the store refused"
        )
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Note>()).isEmpty)
    }

    /// **Behavioural.** `commitInsert` un-inserts what *it* inserted and nothing else. This is the
    /// app's single `ModelContext`, so a refused note creation must not take the rename someone
    /// left pending on another screen with it — which is what a `rollback()` undo would do.
    @Test func arefusedListNoteCreationLeavesUnrelatedPendingWorkAlone() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let project = Project(name: "Launch")
        modelContext.insert(project)
        try modelContext.save()

        project.name = "Launch & Learn"

        #expect(throws: CommitRefused.self) {
            try CadenceListNoteFiling.createNote(
                in: modelContext,
                area: nil,
                project: project,
                folderPath: "Planning",
                order: 0,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(project.name == "Launch & Learn", "the refused note creation discarded an unrelated edit")
        try modelContext.save()
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Project>()).map(\.name) == ["Launch & Learn"],
            "the unrelated edit could no longer be committed"
        )
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Note>()).isEmpty)
    }

    // MARK: - Source shape: Tier 1

    /// **Source shape.** Both note columns treat the selection as the report that the note exists,
    /// so it sits below a `catch` that returns. The macOS half could in principle be behavioural
    /// and is not, for the reason the file header gives: `addNote` is a `private func` on a
    /// SwiftUI `View`.
    @Test func bothNoteColumnsSelectANewNoteOnlyOnACommittedInsert() throws {
        let filing = try scanned("Cadence/Shared/CadenceNoteFolderSupport.swift")
        let create = try declarationBody(named: "createNote", in: filing)
        #expect(create.contains("modelContext.insert(note)"))
        #expect(create.contains("CadencePendingChangePersistence.commitInsert(of: note, in: modelContext, commit: commit)"))
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: create) == 0, "createNote still swallows its save")

        for (path, report) in [
            ("Cadence/macOS/Views/ListNotesView.swift", "select(.list(note.id), clearsRequestedEventNote: false)"),
            ("Cadence/iOS/iOSListNotesView.swift", "selectedNoteID = note.id")
        ] {
            let view = try scanned(path)
            let add = try declarationBody(named: "addNote", in: view)
            #expect(add.contains("try CadenceListNoteFiling.createNote("), "\(path) does not commit its insert")
            #expect(
                add.contains("createFailureNotice = CadencePendingChangePersistence.editFailureNotice"),
                "\(path) does not name the failure with the shared sentence"
            )
            #expect(reportFollowsTheCatch(report, in: add), "\(path) selects the note above its failure branch")
            #expect(
                view.contains("CadenceInlineFailureNotice(text: createFailureNotice)"),
                "\(path) sets a notice it never draws"
            )
        }
    }

    /// **Source shape.** The tag creators are one function on two platforms, so they are asserted
    /// as one: clearing the draft is the only report either screen makes, and on both it now sits
    /// below the `catch`.
    @Test func bothTagCreatorsClearTheDraftOnlyOnACommittedInsert() throws {
        for (path, clear, notice) in [
            (
                "Cadence/macOS/Views/SettingsTagsSection.swift",
                "clearCreateFields()",
                "CadenceInlineFailureNotice(text: createFailureNotice)"
            ),
            (
                "Cadence/iOS/iOSSettingsTagsSection.swift",
                "clearDraft()",
                "CadenceInlineFailureNotice(text: createFailureNotice)"
            )
        ] {
            let view = try scanned(path)
            let create = try declarationBody(named: "createTag", in: view)
            #expect(create.contains("modelContext.insert(tag)"))
            #expect(create.contains("CadencePendingChangePersistence.commitInsert(of: tag, in: modelContext)"))
            #expect(CadenceSourceScan.matchCount(#"try\?"#, in: create) == 0, "\(path) still swallows its save")
            #expect(create.contains("createFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
            #expect(reportFollowsTheCatch(clear, in: create), "\(path) clears the draft above its failure branch")
            #expect(view.contains(notice), "\(path) sets a notice it never draws")
        }
    }

    /// **Source shape, and iOS-only — this file is behind `#if os(iOS)`.** The event-note button
    /// inserts a note and opens it, so presenting the editor *is* the success report and has to sit
    /// below the `catch`.
    ///
    /// The insert closure records what it inserted rather than assuming: `noteForEditing` returns
    /// an existing note as often as it makes one, and un-inserting an existing note on a refused
    /// commit would delete a note the user already had.
    @Test func theEventNoteButtonOpensTheEditorOnlyOnACommittedInsert() throws {
        let sheet = try scanned("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        let open = try declarationBody(named: "openEventNote", in: sheet)

        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: open) == 0, "openEventNote still swallows its save")
        #expect(open.contains("var inserted: [any PersistentModel] = []"))
        #expect(open.contains("inserted.append($0)"), "the undo would reach a note it did not insert")
        #expect(open.contains("CadencePendingChangePersistence.commitInsert(of: inserted, in: modelContext)"))
        #expect(open.contains("actionError = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            reportFollowsTheCatch("presentedEventNote = note", in: open),
            "the sheet presents the note above its failure branch"
        )

        // The notice this failure is reported through has to be in *both* layouts. It was in the
        // compact one only, so at regular width every failure this sheet reports was invisible.
        #expect(
            CadenceSourceScan.matchCount(#"\n\s+actionErrorNotice\n"#, in: sheet) == 2,
            "actionErrorNotice is not in both form layouts"
        )
    }

    // MARK: - Source shape: Tier 2

    /// **Source shape.** The three inline row editors. Each collapses back to its display row —
    /// `isEditing = false`, `editingTag = nil` — which is a dismissal without a sheet to say so
    /// with, and each now does it only below a `catch`.
    ///
    /// The undo is a field snapshot, never `rollback()`, for the reason
    /// `CadencePendingChangePersistence.commitEdit` documents: one `ModelContext` for the whole
    /// app, and the tag picker in particular opens over a task inspector with edits pending behind
    /// it. `CadenceEditorSaveCommitSurfaceTests.everyRollbackCallSiteInTheAppIsADeleteCommit` is
    /// the census that keeps that true app-wide.
    @Test func theInlineTagEditorsCollapseOnlyOnACommittedEdit() throws {
        let catalog = try scanned("Cadence/macOS/Views/SettingsTagsSection.swift")
        let rowSave = try declarationBody(named: "saveEdits", in: catalog)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: rowSave) == 0, "saveEdits still swallows its save")
        #expect(rowSave.contains("CadencePendingChangePersistence.commitEdit(in: modelContext)"))
        // Five fields written, five fields restored.
        #expect(CadenceSourceScan.matchCount(#"tag\.\w+ = previous\w+"#, in: rowSave) == 5)
        #expect(rowSave.contains("saveFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(reportFollowsTheCatch("isEditing = false", in: rowSave), "the row collapses above its failure branch")
        #expect(catalog.contains("CadenceInlineFailureNotice(text: saveFailureNotice)"))

        let picker = try scanned("Cadence/macOS/Views/TagPickerPopoverViews.swift")
        let sheetSave = try declarationBody(named: "saveEdits", in: picker)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: sheetSave) == 0)
        #expect(sheetSave.contains("CadencePendingChangePersistence.commitEdit(in: modelContext)"))
        #expect(CadenceSourceScan.matchCount(#"tag\.\w+ = previous\w+"#, in: sheetSave) == 5)
        #expect(sheetSave.contains("editFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(reportFollowsTheCatch("editingTag = nil", in: sheetSave), "the sheet closes above its failure branch")

        let archive = try declarationBody(named: "archive", in: picker)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: archive) == 0)
        #expect(archive.contains("CadencePendingChangePersistence.commitEdit(in: modelContext)"))
        #expect(CadenceSourceScan.matchCount(#"tag\.\w+ = previous\w+"#, in: archive) == 2)
        #expect(archive.contains("editFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(reportFollowsTheCatch("editingTag = nil", in: archive), "the sheet closes above its failure branch")

        #expect(picker.contains("CadenceInlineFailureNotice(text: failureNotice)"))
        #expect(picker.contains("failureNotice: editFailureNotice"), "the sheet is never handed the notice")

        // Neither editor undoes an in-place edit by discarding the app's pending work.
        for (path, source) in [
            ("Cadence/macOS/Views/SettingsTagsSection.swift", catalog),
            ("Cadence/macOS/Views/TagPickerPopoverViews.swift", picker)
        ] {
            #expect(
                CadenceSourceScan.matchCount(#"\.rollback\(\)"#, in: source) == 0,
                "\(path) undoes an edit with a rollback"
            )
        }
    }

    // MARK: - Non-vacuity

    /// Non-vacuity for every scan above: the reader really opened these six files, `scanned` really
    /// strips comments, the ordering helper really distinguishes the two orders it is asked about,
    /// and each `== 0` needle matches the spelling it hunts.
    @Test func thesourceScanActuallyReadsTheseTagAndNoteSurfaces() throws {
        for (path, marker) in [
            ("Cadence/Shared/CadenceNoteFolderSupport.swift", "enum CadenceListNoteFiling"),
            ("Cadence/macOS/Views/ListNotesView.swift", "struct ListNotesView: View"),
            ("Cadence/iOS/iOSListNotesView.swift", "struct iOSListNotesView: View"),
            ("Cadence/macOS/Views/SettingsTagsSection.swift", "struct SettingsTagsSection: View"),
            ("Cadence/iOS/iOSSettingsTagsSection.swift", "struct iOSTagsSettingsSection: View"),
            ("Cadence/macOS/Views/TagPickerPopoverViews.swift", "struct TagPickerPopover: View"),
            ("Cadence/iOS/iOSCalendarEventEditSheet.swift", "private func openEventNote()")
        ] {
            #expect(try scanned(path).contains(marker), "\(path) did not read as itself")
        }

        // The ordering helper is the load-bearing one: every "only on a committed X" assertion is
        // it. It must reject the pre-fix order and accept the post-fix one.
        let broken = """
        report()
        do { try commit() } catch { notice = text; return }
        """
        let fixed = """
        do { try commit() } catch { notice = text; return }
        report()
        """
        #expect(!reportFollowsTheCatch("report()", in: broken))
        #expect(reportFollowsTheCatch("report()", in: fixed))
        #expect(!reportFollowsTheCatch("report()", in: "do { try commit() } catch { return }"))
        #expect(!reportFollowsTheCatch("report()", in: "report()"), "a body with no catch is not ordered")

        // The stripper itself, on a literal rather than on whichever file happens to carry a
        // comment: it blanks the comment, keeps the code, and does not change the length.
        let commented = "let a = 1 // note\n"
        let blanked = CadenceSourceScan.strippingComments(commented)
        #expect(blanked != commented, "the comment stripper removed nothing")
        #expect(blanked.count == commented.count, "the comment stripper changed the length")
        #expect(blanked.contains("let a = 1"), "the comment stripper blanked live code")
        #expect(!blanked.contains("note"), "the comment stripper left the comment in place")

        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try? modelContext.save()") == 1)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try CadencePendingChangePersistence.commitEdit(in: c) {}") == 0)
        #expect(CadenceSourceScan.matchCount(#"tag\.\w+ = previous\w+"#, in: "tag.name = previousName") == 1)
        #expect(CadenceSourceScan.matchCount(#"tag\.\w+ = previous\w+"#, in: "tag.name = name") == 0)
        #expect(CadenceSourceScan.matchCount(#"\.rollback\(\)"#, in: "modelContext.rollback()") == 1)
        #expect(CadenceSourceScan.matchCount(#"\n\s+actionErrorNotice\n"#, in: "\n    actionErrorNotice\n    x\n    actionErrorNotice\n") == 2)
        #expect(CadenceSourceScan.matchCount(#"\n\s+actionErrorNotice\n"#, in: "\n    private var actionErrorNotice: some View {\n") == 0)
    }

    // MARK: - Helpers

    /// The three readers this suite used to declare privately. They moved to
    /// `CadenceCommitSurfaceScan` when T-503 needed the same three for four more screens; the
    /// reasoning that used to live here is on them.
    private func scanned(_ path: String) throws -> String {
        try CadenceCommitSurfaceScan.scanned(path)
    }

    private func declarationBody(named name: String, in source: String) throws -> String {
        try CadenceCommitSurfaceScan.declarationBody(named: name, in: source)
    }

    private func reportFollowsTheCatch(_ report: String, in body: String) -> Bool {
        CadenceCommitSurfaceScan.reportFollowsTheCatch(report, in: body)
    }
}
