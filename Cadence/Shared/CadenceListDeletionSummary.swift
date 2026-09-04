import Foundation
import SwiftData

/// Which cascade a delete confirmation is about to run.
///
/// The three sentences are the ones macOS's `confirmationDialog`s already showed, lifted here so
/// the two platforms cannot come to describe the same cascade differently. They are deliberately
/// *categorical* ("its tasks, projects, documents, and links") — `CadenceListDeletionSummary`
/// supplies the counts, and the two are shown together.
enum CadenceListDeletionKind: String, CaseIterable, Sendable {
    case area
    case project
    case context

    /// Title-cased, because every use is a button title or a sheet title.
    var noun: String {
        switch self {
        case .area: return "Area"
        case .project: return "Project"
        case .context: return "Context"
        }
    }

    /// The placeholder label for a list of this kind with a blank name.
    ///
    /// **T-512.** This used to be `"Untitled \(kind.noun)"`, built at the call site — which is the
    /// one shape `CadenceSharedConstantReuseSweepTests` cannot see: its harvest excludes
    /// interpolated literals *by construction*, so a label assembled from a prefix and a noun is
    /// invisible to a sweep that compares whole strings. The label it produced was
    /// character-for-character `CadenceTitleNormalization.defaultAreaName` and friends, so renaming
    /// one of those constants left the interpolated copy behind with nothing going red.
    ///
    /// Reading the constants is the fix; `noSourceFileBuildsAPlaceholderLabelByInterpolation` is
    /// what stops the shape coming back.
    var untitledName: String {
        switch self {
        case .area: return CadenceTitleNormalization.defaultAreaName
        case .project: return CadenceTitleNormalization.defaultProjectName
        case .context: return CadenceTitleNormalization.defaultContextName
        }
    }

    /// Shown **inside** the still-open confirmation when the delete could not be completed
    /// (T-320). It names the kind for the same reason `cascadeSentence` does: the sheet is one
    /// view used for three deletes, and "Couldn't delete this list" is not a thing the app calls
    /// anything.
    ///
    /// **It says "Nothing was removed", and it is the same promise the note delete makes.** It did
    /// not always: `CadenceTaskMutationSupport.deleteTasks` used to commit with
    /// `try? modelContext.save()` part-way through the cascade, so a refused delete left the
    /// list's tasks gone from the store while the list itself came back, and this sentence had to
    /// hedge — "Couldn't finish… some of it may already be gone." T-291 made the cascade defer
    /// that commit (`commitsImmediately: false`), so the whole tree is now one pending change and
    /// one `rollback()` undoes all of it, whether the cascade aborted half-way or the commit was
    /// refused. `CadenceDeleteConfirmationCommitTests` measures the restored tree; if a commit
    /// ever creeps back inside the cascade, that test goes red *before* this sentence starts
    /// lying.
    ///
    /// The one thing rollback does not restore is a cancelled local notification, which the next
    /// reconcile re-schedules. "Nothing was removed" is about the user's data, and none of it is.
    var deleteFailureNotice: String {
        "Couldn't delete this \(noun.lowercased()). Nothing was removed."
    }

    var cascadeSentence: String {
        switch self {
        case .area:
            return "This permanently deletes the area and its tasks, projects, documents, and links."
        case .project:
            return "This permanently deletes the project and its tasks, documents, and links."
        case .context:
            return "This permanently deletes the context and all its areas, projects, tasks, milestones, and habits."
        }
    }
}

/// What a list delete is about to take with it, counted before the fact.
///
/// **Why counts at all.** Deleting an area is recursive — it takes its tasks, its list notes, its
/// links, its legacy documents *and its nested projects*, and a context takes every area and
/// project under it plus their goals and habits. macOS's confirmation names those *categories*;
/// it cannot tell you that this particular area is holding 140 tasks. The iOS confirmation shows
/// both, which is the one respect in which it is deliberately stronger than the desktop dialog.
///
/// **The counts mirror `ModelContext.deleteArea/deleteProject/deleteContext`**, including the two
/// things a naive count would get wrong:
/// - notes are filtered to `.list` kind, because the cascade only deletes list notes; a daily or
///   permanent note attached to the list survives it.
/// - tasks are deduped by id, because an area's task set and its projects' task sets can name the
///   same row (and under a context, so can a goal's).
///
/// **Every count but `images` is exact; `images` is the one that can be wrong, and only upward**
/// (T-433). It used to say "mirror … exactly" and have no `images` field at all, while all three
/// cascades end in `deleteUnreferencedMarkdownImageAssets` — so deleting an area holding twenty
/// image-bearing notes destroyed those `.externalStorage` bytes with the confirmation saying
/// nothing about them, next to a note confirmation that has reported "N embedded images" since
/// T-298. Two summaries of the same store disagreeing about whether images are worth mentioning is
/// the defect; the missing number is how it showed.
///
/// A summary that over-promised would be worse than no summary: the user would authorise the
/// deletion of work that is not actually going anywhere, or fail to authorise work that is. That
/// rule is one-directional, and it is what decides `images`' failure behaviour — see
/// `hasUnknownImpact` and `applyImageSweep`.
struct CadenceListDeletionSummary: Equatable, Sendable {
    var tasks = 0
    var notes = 0
    var links = 0
    var projects = 0
    var areas = 0
    var goals = 0
    var habits = 0
    /// Image assets this cascade will reclaim — the same collection
    /// `deleteUnreferencedMarkdownImageAssets` is about to make, restricted to this delete.
    ///
    /// Not a reference count: an image the cascade's notes share with a *surviving* note or task is
    /// not going anywhere, so it is not counted. That is the same definition
    /// `CadenceNoteDeletionSummary.images` uses, which is why the two confirmations can print the
    /// same phrase and mean the same thing.
    var images = 0

    /// True when a store read behind `images` failed, so that count is not a total.
    ///
    /// **Ported from `CadenceNoteDeletionSummary`, not re-argued** — see the long note there. The
    /// short version: a failed fetch is not an empty store, and the two fetches behind `images`
    /// move it in opposite directions — a missing survivor set moves the *loss* upward, a missing
    /// asset table moves it to zero and over-promises survival instead (see `applyImageSweep`
    /// below). `images` is the only field that reads the store at all; the other seven are walked
    /// off the model objects and stay exact, which is why this is a flag beside the counts rather
    /// than eight optional `Int`s.
    var hasUnknownImpact = false

    /// The unknown-impact sentence, or `nil` when the counts are complete.
    ///
    /// It reads `CadenceNoteDeletionSummary`'s copy rather than spelling its own. One store, two
    /// delete confirmations, one thing to say when a read failed — a second wording would be a
    /// second promise, and this file already exists because the cascade sentences were spelled per
    /// platform.
    var unknownImpactLine: String? {
        hasUnknownImpact ? CadenceNoteDeletionSummary.unknownImpactNotice : nil
    }

    /// **Never true while the impact is unknown**, for the reason `CadenceNoteDeletionSummary`
    /// gives: "nothing else is filed under this area" is the strongest claim on the screen, and an
    /// unread image table is exactly the case where it would be false and reassuring at once.
    var isEmpty: Bool {
        tasks == 0 && notes == 0 && links == 0 && projects == 0 && areas == 0 && goals == 0
            && habits == 0 && images == 0 && !hasUnknownImpact
    }

    /// One line per non-zero kind, in cascade order: the containers first, then the work inside
    /// them. Zero-count kinds are omitted rather than shown as "0 notes" — a list of zeroes reads
    /// as a form, and the thing the user needs to see is what is actually at stake.
    ///
    /// Images sit directly after notes, and are worded exactly as the note confirmation words
    /// them, because they are the same bytes: they live *inside* the notes and task notes above,
    /// and a user who has seen "3 embedded images" on a single note delete should not have to work
    /// out whether the list version means something else.
    var lostItemLines: [String] {
        [
            Self.line(areas, "area", "areas"),
            Self.line(projects, "project", "projects"),
            Self.line(goals, "goal", "goals"),
            Self.line(habits, "habit", "habits"),
            Self.line(tasks, "task", "tasks"),
            Self.line(notes, "note", "notes"),
            Self.line(images, "embedded image", "embedded images"),
            Self.line(links, "saved link", "saved links")
        ].compactMap { $0 }
    }

    private static func line(_ count: Int, _ singular: String, _ plural: String) -> String? {
        guard count > 0 else { return nil }
        return CadencePluralization.phrase(count, singular: singular, plural: plural)
    }

    /// **The `ModelContext` is what `images` costs.** The other seven counts are walked off the
    /// model object; the image sweep asks a question about the whole store — *does anything that
    /// survives this delete still reference these assets?* — and there is no answering it from an
    /// `Area`. `CadenceNoteDeletionSummary.forNote` took the same parameter for the same reason.
    static func forProject(_ project: Project, in modelContext: ModelContext) -> Self {
        let tasks = dedupe(project.tasks ?? [], by: \.id)
        let notes = listNotes(project.notes ?? [])
        let documents = dedupe(project.documents ?? [], by: \.id)

        var summary = Self()
        summary.tasks = tasks.count
        summary.notes = notes.count
        summary.links = uniqueCount(project.links ?? [], by: \.id)
        summary.applyImageSweep(in: modelContext, notes: notes, documents: documents, tasks: tasks)
        return summary
    }

    static func forArea(_ area: Area, in modelContext: ModelContext) -> Self {
        let projects = dedupe(area.projects ?? [], by: \.id)
        let tasks = dedupe((area.tasks ?? []) + projects.flatMap { $0.tasks ?? [] }, by: \.id)
        let notes = listNotes((area.notes ?? []) + projects.flatMap { $0.notes ?? [] })
        let documents = dedupe((area.documents ?? []) + projects.flatMap { $0.documents ?? [] }, by: \.id)

        var summary = Self()
        summary.projects = projects.count
        summary.tasks = tasks.count
        summary.notes = notes.count
        summary.links = uniqueCount((area.links ?? []) + projects.flatMap { $0.links ?? [] }, by: \.id)
        summary.applyImageSweep(in: modelContext, notes: notes, documents: documents, tasks: tasks)
        return summary
    }

    static func forContext(_ context: Context, in modelContext: ModelContext) -> Self {
        let areas = context.areas ?? []
        let goals = context.goals ?? []
        let habits = context.habits ?? []
        // An area's projects and the context's own projects overlap in practice — a project has
        // both an `area` and a `context` — so this is one deduped set, exactly as the cascade
        // builds it.
        let projects = dedupe(areas.flatMap { $0.projects ?? [] } + (context.projects ?? []), by: \.id)
        let tasks = dedupe(
            areas.flatMap { $0.tasks ?? [] }
                + projects.flatMap { $0.tasks ?? [] }
                + (context.tasks ?? [])
                + goals.flatMap { $0.tasks ?? [] },
            by: \.id
        )
        let notes = listNotes(areas.flatMap { $0.notes ?? [] } + projects.flatMap { $0.notes ?? [] })
        let documents = dedupe(
            areas.flatMap { $0.documents ?? [] } + projects.flatMap { $0.documents ?? [] },
            by: \.id
        )

        var summary = Self()
        summary.areas = areas.count
        summary.projects = projects.count
        summary.goals = goals.count
        summary.habits = habits.count
        summary.tasks = tasks.count
        summary.notes = notes.count
        summary.links = uniqueCount(
            areas.flatMap { $0.links ?? [] } + projects.flatMap { $0.links ?? [] },
            by: \.id
        )
        summary.applyImageSweep(in: modelContext, notes: notes, documents: documents, tasks: tasks)
        return summary
    }

    /// The sweep's own arithmetic, restricted to what this cascade takes.
    ///
    /// **Three kinds of doomed markdown, not one.** `forNote` had a single note to exclude and the
    /// inventory's `excludingNoteIDs` said it in one word. A list cascade also deletes the tasks
    /// (`cascadeDeleteTasks`) and the legacy documents, and both of those fields are in
    /// `CadenceMarkdownSourceInventory` — so an image pasted into a doomed task's notes is exactly
    /// the T-411 loss, and reporting it as surviving would be this summary breaking its own rule
    /// on the screen where the user says yes. `excludingNoteIDs` cannot express those two, so they
    /// are removed from the live set by text instead; see `survivingMarkdownTexts`.
    private mutating func applyImageSweep(
        in modelContext: ModelContext,
        notes: [Note],
        documents: [Document],
        tasks: [AppTask]
    ) {
        // No `?? []` on either read: `try?` already erases *why* a fetch failed, and coercing the
        // `nil` erases *that* it failed, which is the whole of T-298 one summary over.
        let existingImageAssetIDs = (try? modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()))
            .map { Set($0.map(\.id)) }
        let doomedTaskAndDocumentTexts = documents.map(\.content) + tasks.map(\.notes)
        let surviving = Self.survivingMarkdownTexts(
            in: modelContext,
            excludingNoteIDs: Set(notes.map(\.id)),
            alsoDoomed: doomedTaskAndDocumentTexts
        )

        applyImageSweep(
            doomedTexts: notes.map(\.content) + doomedTaskAndDocumentTexts,
            survivingMarkdownTexts: surviving,
            existingImageAssetIDs: existingImageAssetIDs
        )
    }

    /// The same arithmetic with the store reads hoisted out, so it can be exercised directly.
    ///
    /// **`nil` means the fetch failed; `[]` means the store is empty.** Same signature shape and
    /// same reason as `CadenceNoteDeletionSummary.forNote(_:allNotes:survivingMarkdownTexts:
    /// existingImageAssetIDs:)`: an in-memory container cannot be made to fail a fetch, so without
    /// this seam `hasUnknownImpact` is unreachable from a test and the branch that sets it is
    /// exactly the kind of unmeasured failure path T-291 was found on.
    ///
    /// A missing survivor set leaves `stillReferenced` empty and moves `images` *up*; a missing
    /// asset table empties the intersection and moves it to zero. Only the second can over-promise
    /// survival, and it is why the flag is reported rather than the count quietly published.
    mutating func applyImageSweep(
        doomedTexts: [String],
        survivingMarkdownTexts: [String]?,
        existingImageAssetIDs: Set<UUID>?
    ) {
        hasUnknownImpact = existingImageAssetIDs == nil || survivingMarkdownTexts == nil
        images = Self.referencedIDs(in: doomedTexts)
            .intersection(existingImageAssetIDs ?? [])
            .subtracting(Self.referencedIDs(in: survivingMarkdownTexts ?? []))
            .count
    }

    /// Every markdown text that outlives this cascade, or `nil` when any part could not be read.
    ///
    /// **Why the doomed tasks and documents are removed by text.**
    /// `CadenceMarkdownSourceInventory.liveMarkdownTexts` takes an exclusion set of *note* ids and
    /// nothing else, and it is the single owner of the field list — widening its signature per
    /// caller is how that list stops being one list. Every row this cascade is about to delete is
    /// still live when the confirmation is drawn, so its body is in the returned array; removing
    /// one occurrence per doomed body leaves precisely the survivors, and two rows holding the
    /// same text remove one each.
    ///
    /// The failure direction if that ever stops holding — a body that is not found, because the
    /// inventory started deduping or dropping empties — is that the text stays in the survivor set
    /// and `images` comes back *lower*, which is the direction this file forbids. It is pinned by
    /// `anAreaSummaryCountsAnImageOnlyItsDoomedTaskReferenced`.
    private static func survivingMarkdownTexts(
        in modelContext: ModelContext,
        excludingNoteIDs: Set<UUID>,
        alsoDoomed: [String]
    ) -> [String]? {
        guard let live = CadenceMarkdownSourceInventory.liveMarkdownTexts(
            in: modelContext,
            excludingNoteIDs: excludingNoteIDs
        ) else { return nil }
        guard !alsoDoomed.isEmpty else { return live }

        var pending: [String: Int] = [:]
        for text in alsoDoomed { pending[text, default: 0] += 1 }
        return live.filter { text in
            guard let remaining = pending[text], remaining > 0 else { return true }
            pending[text] = remaining - 1
            return false
        }
    }

    private static func referencedIDs(in texts: [String]) -> Set<UUID> {
        texts.reduce(into: Set<UUID>()) { result, text in
            result.formUnion(MarkdownImageAssetService.referencedIDs(in: text))
        }
    }

    private static func listNotes(_ notes: [Note]) -> [Note] {
        dedupe(notes, by: \.id).filter { $0.kind == .list }
    }

    private static func uniqueCount<T>(_ models: [T], by id: KeyPath<T, UUID>) -> Int {
        dedupe(models, by: id).count
    }

    private static func dedupe<T>(_ models: [T], by id: KeyPath<T, UUID>) -> [T] {
        var seen = Set<UUID>()
        return models.filter { seen.insert($0[keyPath: id]).inserted }
    }
}
