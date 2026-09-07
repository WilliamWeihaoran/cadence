import Foundation
import Observation
import SwiftData
import SwiftUI

/// Every user-facing word the archive **import** shows, on both platforms, in one place — and the
/// small state machine that drives it, for the same reason.
///
/// `CadenceDataExportPresentation` already works this way and the argument is T-19's: a data-safety
/// control has to say plainly what it does, and copy written twice is copy that comes to say two
/// things. The import needs that more than the export did, because the sentence a user most needs
/// is one the *engine* is responsible for and the screen is the only place it can be read.
///
/// ## The word this file will not use
///
/// `CadenceArchiveImportService` never deletes. Both `CadenceArchiveImportMode` cases add the rows
/// the destination is missing; they differ only in who wins on a row that already exists. So a row
/// created after the archive was written survives an import under either mode, and **an import
/// cannot roll a store back to the archive's exact state**.
///
/// A control labelled *Restore* promises exactly the thing this cannot do. So nothing here is
/// called a restore: the card is *Import an Archive*, the modes are *Add what's missing* and
/// *Overwrite what matches*, and `neverDeletesNote` — shown in the preview, before the first write,
/// not buried in a ledger — says what survives and names the two-step route that does produce a
/// store equal to the archive: delete Cadence's data first, then import into the empty store.
nonisolated enum CadenceArchiveImportPresentation {
    static let title = "Import an Archive"

    static let description = """
        Read a Cadence archive back in, from this device or from iCloud Drive. Cadence shows you \
        exactly what the file would add and what it already has before anything is written.
        """

    static let buttonTitle = "Choose Archive…"

    /// The preview's own heading. Deliberately a question about the file rather than a label for
    /// the sheet the reader is already looking at.
    static let previewTitle = "This archive holds"

    static let confirmButtonTitle = "Import"

    static let cancelButtonTitle = "Cancel"

    /// The correction. An import is not an undo, and this is the one place a user reads that
    /// *before* choosing.
    static let neverDeletesNote = """
        An import never deletes anything. Everything on this device that the archive does not \
        contain survives it, so importing cannot roll Cadence back to the day the archive was \
        written. To make this device match an archive exactly, delete Cadence's data first and \
        then import into the empty store — two deliberate steps, each of which says what it does.
        """

    // MARK: - The mode choice

    static func modeTitle(_ mode: CadenceArchiveImportMode) -> String {
        switch mode {
        case .mergeKeepingExistingRows: return "Add what's missing"
        case .restoreOverwritingExistingRows: return "Overwrite what matches"
        }
    }

    /// The label beside the chooser. A question about the archive's collisions, because the two
    /// answers only differ on a record the destination already has — a reader who has none is
    /// choosing between two identical imports and should be able to see that from the label.
    static let modeQuestion = "If a record is already here"

    /// The chooser's rows, here rather than at the two call sites, for this file's whole reason:
    /// a mode whose consequence is spelled twice is a mode that comes to mean two things.
    ///
    /// **Not `Picker(.segmented)`, which is what this was.** A segmented control is AppKit's on the
    /// Mac — its own bezel, its own accent, no palette colour — and `SettingsSharedVocabularyTests`
    /// sweeps macOS Settings for exactly that. The app already had the replacement:
    /// `CadenceChoiceValueButton` over a `CadenceChoicePopoverList`, the same swap T-20 made for the
    /// work-hours window. It is the better control here for a second reason — a segmented control
    /// has room for a title and nothing else, so `modeExplanation` could only be shown for the mode
    /// *already* chosen, and the cost of the other one was invisible until you picked it. As rows,
    /// both consequences are on screen at the moment of choosing.
    /// `@MainActor` because `CadenceChoiceRow` is: the rows are the only members of this
    /// otherwise `nonisolated` enum that build a UI value rather than a `String`.
    @MainActor
    static func modeRows() -> [CadenceChoiceRow<CadenceArchiveImportMode>] {
        CadenceArchiveImportMode.allCases.map { mode in
            CadenceChoiceRow(
                value: mode,
                title: modeTitle(mode),
                subtitle: modeExplanation(mode),
                systemImage: mode == .mergeKeepingExistingRows ? "plus.circle" : "arrow.triangle.2.circlepath",
                color: Theme.blue
            )
        }
    }

    static func modeExplanation(_ mode: CadenceArchiveImportMode) -> String {
        switch mode {
        case .mergeKeepingExistingRows:
            return """
                Records the archive has and this device does not are added. Records you already \
                have are left exactly as they are, including every change made since the archive \
                was written.
                """
        case .restoreOverwritingExistingRows:
            return """
                Records the archive has and this device does not are added, and records you \
                already have are replaced by the archive's copy — changes made to them since the \
                archive was written are lost. Records the archive never had are still kept.
                """
        }
    }

    // MARK: - The plan, as sentences

    /// What applying this plan would do, in one line, naming the mode's consequence rather than
    /// only a total. `CadenceArchiveImportPlan.changesAnything` is the case worth calling out: a
    /// second import of the same file in `.mergeKeepingExistingRows` is a no-op, and a preview that
    /// said "0 added, 4,182 already here" without saying so reads like a failure.
    static func planSummary(_ plan: CadenceArchiveImportPlan) -> String {
        let added = plan.totalInsertCount
        let matched = plan.totalMatchedCount

        if added == 0 && matched == 0 {
            return "This archive contains no records, so importing it would change nothing."
        }
        if !plan.changesAnything {
            return """
                This device already has all \(records(matched)) in this archive, so importing it \
                would change nothing.
                """
        }

        var sentence = added == 0
            ? "Nothing new would be added."
            : "\(records(added)) would be added."
        if matched > 0 {
            switch plan.mode {
            case .mergeKeepingExistingRows:
                sentence += " \(records(matched)) already here would be left untouched."
            case .restoreOverwritingExistingRows:
                sentence += " \(records(matched)) already here would be replaced by this archive's copy."
            }
        }
        return sentence
    }

    /// Named once so "4,182 records" and "1 record" cannot disagree between the summary, the
    /// per-kind rows and the outcome sentence.
    static func records(_ count: Int) -> String {
        "\(count) record\(count == 1 ? "" : "s")"
    }

    /// The rows the preview lists: one per kind of record the import would actually touch, biggest
    /// first, so a screen names the tables that change rather than quoting one total.
    ///
    /// A kind the plan counts at zero on both sides is dropped. `CadenceArchiveImportPlan`'s keys
    /// are every entity in `CadenceSchema`, and a preview that listed all of them would bury the
    /// four that matter under seventeen zeroes.
    static func planLines(_ plan: CadenceArchiveImportPlan) -> [CadenceArchiveImportPlanLine] {
        var names = Set(plan.insertCountsByEntityName.keys)
        names.formUnion(plan.matchedCountsByEntityName.keys)

        var lines: [CadenceArchiveImportPlanLine] = []
        for name in names {
            let added = plan.insertCountsByEntityName[name] ?? 0
            let matched = plan.matchedCountsByEntityName[name] ?? 0
            guard added > 0 || matched > 0 else { continue }
            lines.append(
                CadenceArchiveImportPlanLine(
                    entityName: name,
                    addedCount: added,
                    matchedCount: matched,
                    mode: plan.mode
                )
            )
        }

        return lines.sorted { first, second in
            let left = first.addedCount + first.matchedCount
            let right = second.addedCount + second.matchedCount
            if left == right { return first.title < second.title }
            return left > right
        }
    }

    /// Reported, never thrown — the archive's other tables are still importable, and refusing the
    /// file would strand the user's only copy of everything else. See
    /// `CadenceArchiveImportPlan.entityNamesOnlyInTheArchive`.
    static func unreadableKindsNote(_ plan: CadenceArchiveImportPlan) -> String? {
        let names = plan.entityNamesOnlyInTheArchive.map(entityTitle(_:)).sorted()
        guard !names.isEmpty else { return nil }
        return """
            This archive also contains \(names.joined(separator: ", ")), which this version of \
            Cadence cannot store. Everything else above still imports.
            """
    }

    // MARK: - Outcomes

    /// The sentence for an import that **committed** — which is every `CadenceArchiveImportOutcome`,
    /// since a refused one throws and lands on `failureMessage` instead.
    ///
    /// Named for the outcome rather than for success because it has two moods ([[T-1111]]): the
    /// archive is on disk either way, but its legacy-note fold may still be outstanding, and that
    /// difference decides whether the user should do anything next. Collapsing the two — either by
    /// dropping the warning or by routing the fold failure to `failureMessage` — is the bug this
    /// replaced, where a restore whose rows were already durable said "Import failed".
    static func outcomeMessage(_ outcome: CadenceArchiveImportOutcome) -> String {
        var sentence: String
        switch (outcome.insertedRecordCount, outcome.overwrittenRecordCount) {
        case (0, 0):
            sentence = "Imported. Nothing changed — this device already had every record in that archive."
        case (let inserted, 0):
            sentence = "Imported \(records(inserted))."
        case (0, let overwritten):
            sentence = "Imported. \(records(overwritten)) replaced by the archive's copy."
        case (let inserted, let overwritten):
            sentence = "Imported \(records(inserted)) and replaced \(records(overwritten))."
        }
        if outcome.notesFoldedFromLegacyRows > 0 {
            let folded = outcome.notesFoldedFromLegacyRows
            sentence += " \(folded) older note\(folded == 1 ? "" : "s") \(folded == 1 ? "was" : "were") brought forward into Notes."
        }
        if let failure = outcome.legacyNoteFoldFailure {
            // Says what is saved before it says what is not, and does not ask for a retry: the
            // import itself must not be run again, and the fold is retried at the next launch by
            // `PersistenceController` without the user doing anything.
            sentence += """
                 Your data is saved, but older notes could not be brought forward yet — \
                Cadence will try again next time it opens. (\(failure))
                """
        }
        return sentence
    }

    /// The sentence for an import that wrote **nothing**. Every reason that reaches this one left
    /// the store untouched; see `CadenceArchiveImportService`'s three failure classes.
    static func failureMessage(_ reason: String) -> String {
        "Import failed: \(reason)"
    }

    // MARK: - Reading the chosen file

    /// A file chosen through `.fileImporter` arrives security-scoped on both platforms — it is
    /// outside the app's container by definition, which is the whole point of an archive — so
    /// reading it without opening that scope fails with a permission error rather than a missing
    /// file. `stopAccessing…` is paired only when the start succeeded, because balancing a call
    /// that returned `false` decrements a count this process never took.
    static func readArchiveData(at url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    // MARK: - Naming a table for a reader

    /// `CadenceSchema`'s entity names are Swift type names, and a preview that says
    /// "HabitCompletion: 240" is telling the user about the schema rather than about their data.
    ///
    /// Mechanical rather than a twenty-one-entry table, because such a table is the next thing to
    /// go stale: a model added next year gets a readable name here without anyone remembering to
    /// come back. Exactly one override, for the one name where the mechanical answer is wrong
    /// rather than merely plain — `AppTask` is the type; "tasks" is the word the whole app uses.
    static func entityTitle(_ entityName: String) -> String {
        if let override = entityTitleOverrides[entityName] { return override }
        let words = splitCamelCase(entityName)
        guard let last = words.last else { return entityName }
        let pluralised = words.dropLast() + [pluralise(last)]
        return pluralised.enumerated()
            .map { $0.offset == 0 ? capitalizingFirstWord($0.element) : $0.element.lowercased() }
            .joined(separator: " ")
    }

    private static let entityTitleOverrides = ["AppTask": "Tasks"]

    /// Upper-cases the first character and leaves the rest alone, unlike `capitalized`, which would
    /// turn "Habit completions" into "Habit Completions".
    private static func capitalizingFirstWord(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    private static func splitCamelCase(_ name: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase && !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func pluralise(_ word: String) -> String {
        let lower = word.lowercased()
        if lower.hasSuffix("s") || lower.hasSuffix("x") || lower.hasSuffix("ch") || lower.hasSuffix("sh") {
            return word + "es"
        }
        if lower.hasSuffix("y"), let penultimate = lower.dropLast().last, !"aeiou".contains(penultimate) {
            return String(word.dropLast()) + "ies"
        }
        return word + "s"
    }
}

// MARK: - One row of the preview

/// One kind of record the import would touch, already worded. The view draws it; it does not do
/// arithmetic on a plan of its own.
nonisolated struct CadenceArchiveImportPlanLine: Identifiable, Equatable, Sendable {
    let entityName: String
    let addedCount: Int
    let matchedCount: Int
    let mode: CadenceArchiveImportMode

    var id: String { entityName }

    var title: String { CadenceArchiveImportPresentation.entityTitle(entityName) }

    /// The right-hand side of the row. It names what happens to the matched rows rather than
    /// counting them neutrally, because "3 already here" reads identically under a mode that keeps
    /// them and a mode that overwrites them.
    var detail: String {
        var parts: [String] = []
        if addedCount > 0 { parts.append("\(addedCount) added") }
        if matchedCount > 0 {
            switch mode {
            case .mergeKeepingExistingRows: parts.append("\(matchedCount) kept")
            case .restoreOverwritingExistingRows: parts.append("\(matchedCount) replaced")
            }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The flow both platforms drive

/// Choose a file, preview what it would do, change your mind about the mode, then write — held in
/// one place so iPhone and Mac cannot come to disagree about when the store is touched.
///
/// The two screens differ in chrome and in nothing else. Every decision that could drift — that the
/// plan is recomputed when the mode changes rather than shown stale, that a failed read leaves no
/// pending archive behind, that the write goes through `importArchive(_:mode:into:)` and therefore
/// through a `ModelContext` of its own — lives here, where a test can reach it without a view.
///
/// **Why a private context and not the app's.** `CadenceArchiveImportService.apply` rolls its
/// context back if the commit throws. Handing it the app's shared context would put every other
/// pending edit in that blast radius, and this app has exactly one shared context. `importArchive`
/// makes a private one for precisely this reason, so the flow calls that rather than `apply`.
/// The preview is planned against a private context too — a plan read through a context holding
/// uncommitted inserts would count a row as already-here that the import will not find.
@Observable
final class CadenceArchiveImportFlow {

    /// Non-`nil` exactly while the preview is up: a file has been read and validated and nothing
    /// has been written.
    private(set) var plan: CadenceArchiveImportPlan?

    /// The last thing that happened, shown on the card. Not on the preview: a sheet that reports
    /// the outcome of the import that dismissed it has nowhere to put it.
    private(set) var statusMessage: String?

    /// True while `confirm()` is writing. The confirm button reads it so a second tap cannot start
    /// a second import of the same file.
    private(set) var isWriting = false

    var mode: CadenceArchiveImportMode = .mergeKeepingExistingRows {
        didSet {
            guard mode != oldValue else { return }
            replan()
        }
    }

    var isPreviewing: Bool { plan != nil }

    private var pendingData: Data?
    private var container: ModelContainer?

    /// What runs once, after an import has committed, to bring the OS's pending reminders back in
    /// line with the rows the archive just changed ([[T-1112]]).
    ///
    /// **Injectable because the live one is unobservable from a test host.**
    /// `HabitNotificationReconcileSupport.scheduleReconcile` bottoms out in `NotificationManager`,
    /// which early-returns under `XCTestConfigurationFilePath` — so a reconcile that ran and one
    /// that never happened look identical from outside, which is exactly the shape in which a
    /// dropped call stays green forever. Same reasoning as
    /// `CadenceNotificationsEnabledEffects`, and it takes the container rather than a context for
    /// the reason below.
    private let reconcileNotifications: ((ModelContainer) -> Void)?

    /// `? = nil` rather than `= liveReconcile`, for the compiler reason
    /// `HabitNotificationReconcileSupport.applyNotificationsEnabledChange` already records: a
    /// default argument expression is evaluated in a *nonisolated* context, and the live reconcile
    /// is main-actor isolated. The live one is therefore named at the call site in `confirm()`,
    /// which is isolated, and `nil` means "use it".
    init(reconcileNotifications: ((ModelContainer) -> Void)? = nil) {
        self.reconcileNotifications = reconcileNotifications
    }

    /// A **fresh** context over the same container, never the app's.
    ///
    /// The import wrote through a private context of its own, so the app's shared context has not
    /// seen those rows: reconciling from it would diff the OS's pending requests against the
    /// pre-import store and could cancel a reminder the archive just restored, or leave one
    /// pending for a task the archive just completed. A context made here reads the committed
    /// state. `scheduleReconcile` skips the pass entirely if either fetch fails, so a store that
    /// cannot be read does not become "nothing should be pending".
    @MainActor
    private static func liveReconcileNotifications(_ container: ModelContainer) {
        HabitNotificationReconcileSupport.scheduleReconcile(in: ModelContext(container))
    }

    /// The `.fileImporter` result, on both platforms. Reads, decodes and fully validates the
    /// archive before showing anything, so the preview cannot promise an import that then fails —
    /// `CadenceArchiveImportService.plan` runs the same validation `apply` does.
    func preview(_ result: Result<URL, Error>, in container: ModelContainer) {
        statusMessage = nil
        switch result {
        case .failure(let error):
            clear()
            statusMessage = CadenceArchiveImportPresentation.failureMessage(error.localizedDescription)
        case .success(let url):
            do {
                let data = try CadenceArchiveImportPresentation.readArchiveData(at: url)
                let planned = try CadenceArchiveImportService.plan(
                    data,
                    mode: mode,
                    in: ModelContext(container)
                )
                pendingData = data
                self.container = container
                plan = planned
            } catch {
                clear()
                statusMessage = CadenceArchiveImportPresentation.failureMessage(error.localizedDescription)
            }
        }
    }

    /// Dismissing the preview. Drops the archive as well as the plan: a sheet that is gone must not
    /// leave a file this flow would still import.
    func cancel() {
        clear()
    }

    /// Write. Nothing before this point has touched the store.
    ///
    /// **The reconcile hangs off the returned outcome, not off a fully clean one.** A committed
    /// import whose legacy-note fold failed ([[T-1111]]) has still changed the tasks and habits the
    /// OS holds reminders for, so it needs the same follow-up as a spotless one. The `catch` is the
    /// only branch that wrote nothing, and it is the only branch that does not reconcile.
    func confirm() {
        guard !isWriting, let pendingData, let container else { return }
        isWriting = true
        defer {
            isWriting = false
            clear()
        }
        do {
            let outcome = try CadenceArchiveImportService.importArchive(
                pendingData,
                mode: mode,
                into: container
            )
            statusMessage = CadenceArchiveImportPresentation.outcomeMessage(outcome)
            (reconcileNotifications ?? Self.liveReconcileNotifications)(container)
        } catch {
            statusMessage = CadenceArchiveImportPresentation.failureMessage(error.localizedDescription)
        }
    }

    /// The mode changed while the preview is up. The counts move — `changesAnything` alone flips
    /// between the two modes on a re-import — so the plan is recomputed rather than relabelled.
    private func replan() {
        guard let pendingData, let container else { return }
        do {
            plan = try CadenceArchiveImportService.plan(pendingData, mode: mode, in: ModelContext(container))
        } catch {
            clear()
            statusMessage = CadenceArchiveImportPresentation.failureMessage(error.localizedDescription)
        }
    }

    private func clear() {
        pendingData = nil
        container = nil
        plan = nil
    }
}
