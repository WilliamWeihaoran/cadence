import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-631: the six inline "create tag" doors, and the tag each of them left pending.**
///
/// `TagSupport.resolveTags(named:in:)` is handed its `ModelContext`, so by half 3 of the
/// `try? save()` rule its caller owns the unit of work. Six callers took that exemption and none of
/// them committed: `CreateTaskSheet.createTag`, `InlineTaskComposerView.createTag`,
/// `SchedulePanelComponents.TaskDetailPopover.createTag`, `NoteEditorPane.createTag`,
/// `iOSCreateTaskSheet.markerSuggestions` and `iOSTaskDetailComponents.iOSTaskTagPickerPopover.addTag`.
///
/// This is one `ModelContext` for the whole app, so the new `Tag` did not go away when the sheet
/// did. Cancel does not roll back — no composer calls `rollback()` — and
/// `TaskCreationService.createTask` un-inserts `[task] + subtasks` and has never known about the
/// tag, so **even a refused Add left one behind**. The row landed later, from whatever unrelated
/// screen saved next, which is why the symptom was a tag appearing in Settings › Tags minutes after
/// it was typed, from a different window.
///
/// **What the fix is.** `TagSupport.resolveTagsCommittingInsertions(named:in:commit:)` commits the
/// rows it had to mint, and only those, through
/// `CadencePendingChangePersistence.commitInsert(of:in:commit:)`; `TagSupport.committedTag` is its
/// non-throwing spelling for the six non-throwing `onCreateTag` closures. The moment the tag exists
/// is now the moment the user asked for it — the same answer `SettingsTagsSection.createTag` and
/// `iOSSettingsTagsSection.createTag` already gave for the same act on the same model (T-497).
///
/// **Why the split.** Unlike T-497's seven sites, this ticket's commit unit *is* reachable from a
/// test: `TagSupport` is a static enum in `Services/`, which this macOS target compiles. So the
/// undo path is asserted behaviourally, against a real container with a `commit` that throws —
/// a `save()` that throws cannot be provoked out of an in-memory container, and an undo path no
/// test can reach is an undo path no test can prove. The six surfaces themselves are `private
/// func`s on SwiftUI views, two of them inside `#if os(iOS)`, so those are source scans.
struct CadenceInlineTagCommitSurfaceTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    // MARK: - Behavioural: the commit unit itself

    /// **Behavioural.** The success path: the tag is in the store — read through a *second*
    /// context, so the assertion cannot be satisfied by the creating context's own memory — and
    /// nothing is left pending for another screen's save to finish later. That "nothing pending" is
    /// the whole ticket.
    @Test func acommittedInlineTagIsInTheStoreBeforeThePickerDrawsAChip() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)

        let resolved = try #require(
            try TagSupport.resolveTagsCommittingInsertions(named: ["urgent"], in: modelContext)
        )

        #expect(resolved.map(\.name) == ["urgent"])
        #expect(!modelContext.hasChanges, "the new tag is still pending after the creator returned")
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Cadence.Tag>()).map(\.name) == ["urgent"],
            "the store does not hold the tag the picker is about to draw a chip for"
        )
    }

    /// **Behavioural, and the defect itself.** A refused commit leaves no tag in the context *or*
    /// the store, so nothing is waiting for the next unrelated `save()` anywhere in the app.
    ///
    /// Asserted from a second context as well as the first, because a single-context read passes
    /// against the bug: the creating context answers with the row it is holding whether or not the
    /// save threw.
    @Test func arefusedInlineTagCreationLeavesNoTagPendingAnywhere() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)

        #expect(throws: CommitRefused.self) {
            try TagSupport.resolveTagsCommittingInsertions(
                named: ["urgent"],
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(
            try modelContext.fetch(FetchDescriptor<Cadence.Tag>()).isEmpty,
            "the context still holds a tag the store refused — this is the pending row T-631 is about"
        )
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Cadence.Tag>()).isEmpty)

        // **The symptom, stated directly.** T-631's tag did not appear when it was typed; it
        // appeared later, when some unrelated screen saved. So the assertion that matters is what
        // the *next* save commits — and it is nothing.
        //
        // `hasChanges` is deliberately not asserted here: SwiftData records the un-insert as a
        // pending deletion of a row it never held, so the flag stays `true` after a correct undo.
        // It is a true statement about the context and a false one about the store.
        try modelContext.save()
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Cadence.Tag>()).isEmpty,
            "the next unrelated save committed the tag the store had already refused"
        )
    }

    /// **Behavioural.** `commitInsert` un-inserts what *it* inserted and nothing else. This is the
    /// app's single `ModelContext`: a refused tag created from a popover must not take the note
    /// somebody is typing behind it, which is exactly what a `rollback()` undo would do — the
    /// reason `CadencePendingChangePersistence.commitEdit`'s doc gives for not offering one.
    @Test func arefusedInlineTagCreationLeavesUnrelatedPendingWorkAlone() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let project = Project(name: "Launch")
        modelContext.insert(project)
        try modelContext.save()

        project.name = "Launch & Learn"

        #expect(throws: CommitRefused.self) {
            try TagSupport.resolveTagsCommittingInsertions(
                named: ["urgent"],
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        }

        #expect(project.name == "Launch & Learn", "the refused tag creation discarded an unrelated edit")
        try modelContext.save()
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Project>()).map(\.name) == ["Launch & Learn"],
            "the unrelated edit could no longer be committed"
        )
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Cadence.Tag>()).isEmpty)
    }

    /// **Behavioural, and the sharpest edge of "only the rows this call minted".** Typing the name
    /// of a tag that already exists mints nothing, so there is no insert to commit and no undo to
    /// run — and an undo that ran anyway would **delete a tag the user already had**.
    ///
    /// The `commit` here throws and is never called, which is the assertion: the creator does not
    /// reach for the store at all when it has nothing new to put there.
    @Test func resolvingATagThatAlreadyExistsCommitsNothingAndCannotDeleteIt() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        modelContext.insert(Cadence.Tag(name: "urgent", slug: TagSupport.slug(for: "urgent"), order: 0))
        try modelContext.save()

        let resolved = try #require(
            try TagSupport.resolveTagsCommittingInsertions(
                named: ["Urgent"],
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            )
        )

        #expect(resolved.map(\.slug) == ["urgent"], "the existing tag was not matched")
        #expect(
            try ModelContext(modelContainer).fetch(FetchDescriptor<Cadence.Tag>()).map(\.name) == ["urgent"],
            "an existing tag was deleted by an undo that had nothing to undo"
        )
    }

    /// **Behavioural.** The pickers' spelling answers `nil` rather than an unsaved `Tag(name:)` —
    /// an object the store was never asked about, which four of the six surfaces used to hand back
    /// for the picker to draw as a chip.
    @Test func thePickerSpellingAnswersNilRatherThanATagTheStoreNeverTook() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)

        let refused = TagSupport.committedTag(
            named: "urgent",
            in: modelContext,
            commit: { _ in throw CommitRefused() }
        )

        #expect(refused == nil, "the picker was handed a tag the store refused")
        #expect(try modelContext.fetch(FetchDescriptor<Cadence.Tag>()).isEmpty)
        #expect(try ModelContext(modelContainer).fetch(FetchDescriptor<Cadence.Tag>()).isEmpty)

        let committed = try #require(TagSupport.committedTag(named: "urgent", in: modelContext))
        #expect(committed.name == "urgent")
        #expect(!modelContext.hasChanges)
    }

    // MARK: - Source shape: the six surfaces

    /// **Source shape.** Every one of the six creators reaches the commit, names the refusal with
    /// the shared sentence, and no longer falls back to `Tag(name:)`.
    ///
    /// The fallback is worth its own assertion. `?? Tag(name: name)` reads like defensive coding and
    /// is the opposite: it answers the picker with a `Tag` that exists nowhere but this expression,
    /// which the picker then selects and draws. The honest answer is `nil` and a sentence.
    @Test func everyInlineTagCreatorCommitsAndNamesTheRefusal() throws {
        let creators = [
            ("Cadence/macOS/Sheets/CreateTaskSheet.swift", "createTag", "actionError"),
            ("Cadence/macOS/Views/InlineTaskComposerView.swift", "createTag", "actionError"),
            ("Cadence/macOS/Views/SchedulePanelComponents.swift", "createTag", "tagFailureNotice"),
            ("Cadence/macOS/Views/NoteEditorPane.swift", "createTag", "tagFailureNotice"),
            ("Cadence/iOS/iOSCreateTaskSheet.swift", "createTag", "actionError"),
            ("Cadence/iOS/iOSTaskDetailComponents.swift", "addTag", "tagFailureNotice")
        ]

        for (path, name, notice) in creators {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            let body = try CadenceCommitSurfaceScan.declarationBody(named: name, in: view)

            #expect(
                body.contains("TagSupport.committedTag(named:"),
                "\(path).\(name) does not reach the committing creator"
            )
            #expect(
                CadenceSourceScan.matchCount(#"TagSupport\.resolveTags\("#, in: body) == 0,
                "\(path).\(name) still calls the non-committing resolver"
            )
            #expect(
                CadenceSourceScan.matchCount(#"\?\?\s*Tag\(name:"#, in: body) == 0,
                "\(path).\(name) still falls back to a Tag the store was never asked about"
            )
            #expect(
                body.contains("\(notice) = CadencePendingChangePersistence.editFailureNotice"),
                "\(path).\(name) does not name the failure with the shared sentence"
            )
            #expect(
                CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
                "\(path).\(name) swallows a commit"
            )
            // All six are one shape: `guard let tag = … else { notice; return }`, then the report.
            // Written out identically on purpose — this is the sentence T-631 found six different
            // answers to, and a seventh answer is what the uniformity is protecting against.
            #expect(
                body.contains("guard let tag = TagSupport.committedTag(named: name, in: modelContext) else {"),
                "\(path).\(name) does not guard on the refusal"
            )
            #expect(
                reportFollowsTheRefusal(
                    marker: "\(notice) = CadencePendingChangePersistence.editFailureNotice",
                    report: "\(notice) = nil",
                    in: body
                ),
                "\(path).\(name) clears its notice above the refusal branch"
            )
        }
    }

    /// **Source shape.** Each of the three notices is actually drawn. A notice that is set and never
    /// rendered is the same silence the ticket is about, one layer further in — the mistake
    /// `iOSCalendarEventEditSheet` made at regular width (T-497).
    @Test func everyRefusalNoticeTheseCreatorsSetIsDrawnSomewhere() throws {
        for (path, notice) in [
            ("Cadence/macOS/Sheets/CreateTaskSheet.swift", "CadenceInlineFailureNotice(text: actionError)"),
            ("Cadence/macOS/Views/SchedulePanelComponents.swift", "CadenceInlineFailureNotice(text: tagFailureNotice)"),
            ("Cadence/macOS/Views/NoteEditorPane.swift", "CadenceInlineFailureNotice(text: tagFailureNotice)"),
            ("Cadence/iOS/iOSTaskDetailComponents.swift", "CadenceInlineFailureNotice(text: tagFailureNotice)")
        ] {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            #expect(view.contains(notice), "\(path) sets a notice it never draws")
        }

        // The composer's hint line is a plain `Text(actionError)` rather than the shared component,
        // which is the row it already used for a refused task creation (T-364). Same sentence,
        // same place, so the tag failure reads as one more thing that did not happen.
        let composer = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/InlineTaskComposerView.swift")
        #expect(composer.contains("Text(actionError)"))

        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSCreateTaskSheet.swift")
        #expect(sheet.contains("Text(actionError)"))
    }

    /// **Source shape.** No picker selects, appends or clears over a refused creation.
    ///
    /// This is the half that makes the `nil` mean something. `onCreateTag` answers `Tag?` on all
    /// four macOS declarations now, and the two places that consume it guard rather than force —
    /// so a refused tag leaves the query in the field and no chip on the row.
    @Test func neitherTagPickerSelectsATagItsCreatorRefusedToMake() throws {
        for path in [
            "Cadence/macOS/Views/TagPickerSupportViews.swift",
            "Cadence/macOS/Views/TagPickerPopoverViews.swift",
            "Cadence/macOS/Views/SchedulePanelPopoverSupportViews.swift"
        ] {
            let view = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                view.contains("let onCreateTag: (String) -> Tag?"),
                "\(path) still promises a Tag for every name"
            )
        }

        let field = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/TaskTitleEntryField.swift")
        #expect(field.contains("let onCreateTag: ((String) -> Tag?)?"))
        let inline = try CadenceCommitSurfaceScan.declarationBody(named: "createInlineTag", in: field)
        #expect(
            inline.contains("guard let onCreateTag, let tag = onCreateTag(tagSearchQuery) else { return }"),
            "the # panel still selects whatever its creator handed back"
        )

        let popover = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/TagPickerPopoverViews.swift")
        let create = try CadenceCommitSurfaceScan.declarationBody(named: "createQueriedTagIfNeeded", in: popover)
        #expect(create.contains("guard canCreate, let tag = onCreateTag(query) else { return }"))
        #expect(
            reportFollowsTheRefusal(marker: "guard canCreate, let tag", report: #"query = """#, in: create),
            "the picker clears the query above its refusal guard"
        )
    }

    /// **Source shape.** The iOS popover clears its field and runs `onCommit()` — its entire report
    /// that the tag was made — only past the guard that returns on a refusal.
    @Test func theTouchTagPopoverClearsItsFieldOnlyOnACommittedInsert() throws {
        let components = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSTaskDetailComponents.swift")
        let add = try CadenceCommitSurfaceScan.declarationBody(named: "addTag", in: components)

        #expect(add.contains("guard let tag = TagSupport.committedTag(named: name, in: modelContext) else {"))
        for report in [#"newTagName = """#, "onCommit()"] {
            #expect(
                reportFollowsTheRefusal(
                    marker: "tagFailureNotice = CadencePendingChangePersistence.editFailureNotice",
                    report: report,
                    in: add
                ),
                "addTag runs `\(report)` above its refusal branch"
            )
        }
    }

    /// **Source shape.** The `#` suggestion row on iOS routes through the same creator rather than
    /// resolving inline, so the sheet has one answer to "what happens when the store refuses".
    @Test func theTouchComposerShortcutRoutesThroughTheCommittingCreator() throws {
        let sheet = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSCreateTaskSheet.swift")
        let suggestions = try CadenceCommitSurfaceScan.declarationBody(named: "markerSuggestions", in: sheet)

        #expect(suggestions.contains("createTag(name)"))
        #expect(
            CadenceSourceScan.matchCount(#"TagSupport\.resolveTags\("#, in: suggestions) == 0,
            "markerSuggestions still resolves the tag inline"
        )
    }

    // MARK: - The readers

    /// The scans above are only worth their assertions if the reader can still tell the two orders
    /// apart and the stripper still blanks comments. Both pinned on literals rather than on repo
    /// files, so the same edit cannot retune the rule and its witness together.
    @Test func theReadersUsedAboveStillDiscriminate() throws {
        #expect(reportFollowsTheRefusal(marker: "notice =", report: "clear()", in: "notice =\nclear()"))
        #expect(!reportFollowsTheRefusal(marker: "notice =", report: "clear()", in: "clear()\nnotice ="))
        #expect(!reportFollowsTheRefusal(marker: "absent", report: "clear()", in: "clear()"))
        #expect(!reportFollowsTheRefusal(marker: "notice =", report: "absent", in: "notice ="))
        // The forwards/backwards difference, as a fixture: a report that appears **both** above and
        // below the refusal is a failure. Written out because a backwards search passes it, and a
        // surviving mutation is how that was found rather than reasoned about.
        #expect(!reportFollowsTheRefusal(marker: "notice =", report: "clear()", in: "clear()\nnotice =\nclear()"))

        let stripped = CadenceSourceScan.strippingComments("let a = 1 // tag\n")
        #expect(!stripped.contains("tag"), "the comment stripper left the comment in place")
        #expect(stripped.count == "let a = 1 // tag\n".count, "the stripper changed the length")

        #expect(CadenceSourceScan.matchCount(#"\?\?\s*Tag\(name:"#, in: "x ?? Tag(name: name)") == 1)
        #expect(CadenceSourceScan.matchCount(#"\?\?\s*Tag\(name:"#, in: "TagSupport.committedTag(named: name)") == 0)
        #expect(CadenceSourceScan.matchCount(#"TagSupport\.resolveTags\("#, in: "TagSupport.resolveTags(named: x)") == 1)
        #expect(
            CadenceSourceScan.matchCount(
                #"TagSupport\.resolveTags\("#,
                in: "TagSupport.resolveTagsCommittingInsertions(named: x)"
            ) == 0,
            "the needle for the old resolver also matches the committing one"
        )
    }

    // MARK: - Helpers

    /// Whether **every** occurrence of `report` in `body` sits after `marker` — the question
    /// `CadenceCommitSurfaceScan.reportFollowsTheCatch` asks, with the one difference a mutation
    /// found.
    ///
    /// Four of these six creators guard on an Optional rather than catching a throw, because
    /// `onCreateTag` is a non-throwing closure and `TagSupport.committedTag` is where the throw
    /// became a value. The question is the same: is the success report below the refusal or above
    /// it.
    ///
    /// **It searches forwards, and so does `reportFollowsTheCatch` now.** It did not when this
    /// helper was written, and that difference is why this one existed: a backwards search asks "is
    /// *some* occurrence below the refusal", which a defect can satisfy while still reporting above
    /// it. The mutation that put a second `newTagName = ""` at the top of `addTag` — clearing the
    /// field before the guard, the exact defect this test exists for — left the original below the
    /// guard and **survived** the shared reader. T-659 anchored that reader on the first occurrence
    /// too, so the two now ask the same question; what still separates them is the *marker*, which
    /// here is a refusal **guard** rather than a `catch`.
    ///
    /// `false` when either string is absent, so a renamed notice fails rather than passes.
    private func reportFollowsTheRefusal(marker: String, report: String, in body: String) -> Bool {
        guard let refusal = body.range(of: marker),
              let reported = body.range(of: report) else { return false }
        return reported.lowerBound > refusal.lowerBound
    }
}
