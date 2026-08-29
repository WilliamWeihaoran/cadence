import Foundation
import SwiftData

/// Every stored field in `CadenceSchema` that can hold markdown, enumerated in one place.
///
/// **Why this is a type and not a `map(\.content)` at the call site.** The image sweep in
/// `ModelContext.deleteUnreferencedMarkdownImageAssets` asks one question — *does anything in this
/// store still reference this asset?* — and it used to answer it from `Note.content` alone. But the
/// markdown editor is one component bound to more than one field: `MarkdownEditor` on macOS
/// (`ListNotesSupportViews`, `NoteEditorPane`, `NotePanel`, `FocusNotesPanel`,
/// `TaskInspectorContentSupportViews`) and `iOSMarkdownEditingSurface` on iOS both create
/// `MarkdownImageAsset` rows from a paste or a photo pick *regardless of which field the binding
/// writes to*, and two of those macOS sites plus `iOSTaskDetailSheetSections` write
/// `AppTask.notes`. So an image pasted into a task's notes was referenced by nothing the sweep
/// looked at, and the next note delete or list cascade collected its `.externalStorage` bytes out
/// from under a live task. Paste is the ordinary path; the loss is permanent.
///
/// The fix is not "add `AppTask.notes` too" — that is the same mistake one field later. The
/// inventory is a `CaseIterable` enum switched over exhaustively, so a *new* markdown-bearing model
/// cannot be read without adding a case, and adding a case is a compile error until the reader
/// handles it. `CadenceMarkdownSourceInventoryTests` closes the other half: it scans
/// `Cadence/Models/` for stored `String` properties and fails on any that is neither in this
/// inventory nor explicitly declared plain, so a new markdown field on an *existing* model is a red
/// test rather than a silent deletion.
///
/// **Bias: keep, not collect.** Over-counting a reference defers garbage to the next delete;
/// under-counting one destroys a picture. That is why the legacy note models are in here at all
/// (`NoteMigrationService` copies them into `Note` and never deletes the originals, so their bodies
/// are still live text in the store), and why any failed fetch aborts the whole answer.
///
/// **Not covered, and out of reach from a `ModelContext`:** note templates live in `UserDefaults`
/// under `NoteTemplateLibrary.storageKey`, and the calendar sheets' notes editors write
/// `EKEvent.notes` in EventKit. Both are markdown surfaces that can hold an image reference and
/// neither is a row in this store.
///
/// **Neither was closed by widening this scan.** For the template body it could have been —
/// `UserDefaults` is one synchronous read — but the sweep's failure mode decided it: an asset this
/// inventory cannot see is *deleted*, so the door that must shut is the one that lets the asset in.
/// `EKEvent.notes` had no second option at all: EventKit has no unbounded "every event" query, so
/// reading the calendar store to answer a synchronous delete was never available.
///
/// Both are closed by `iOSMarkdownEditingSurface.allowsImageInsertion`, which is `false` at the
/// three hosts whose text is not a row here — the note-template editor (T-421), and the two
/// calendar sheets' Apple Calendar note (T-422). So this list is not "the fields we manage to
/// read"; it is every field an image reference can reach. `CadenceMarkdownImageInsertionScopeTests`
/// pins that relation from the other side.
///
/// **The asymmetry that picked the door over the scan.** Over-counting a reference leaves garbage
/// for the next delete; under-counting one destroys `.externalStorage` bytes. A `UserDefaults` read
/// bolted into a type whose contract is "every stored field in `CadenceSchema`" would have bought
/// a rarely-wanted capability with a second way to get that answer wrong.
nonisolated enum CadenceMarkdownSourceInventory {

    /// One markdown-bearing stored property.
    ///
    /// The case list *is* the contract: `liveTexts(for:...)` switches over it exhaustively, so a
    /// case added here does not compile until it is read, and `allCases` is what the tests compare
    /// against the schema and against the model sources.
    enum Source: CaseIterable, Sendable {
        /// The unified note body — every `NoteKind`, list notes included.
        case noteContent
        /// A task's notes. Bound to the same editor as the above; this is the T-411 loss.
        case taskNotes
        /// Legacy list document. Migrated into `Note`, original row retained.
        case documentContent
        /// Legacy daily note. Migrated into `Note`, original row retained.
        case dailyNoteContent
        /// Legacy weekly note. Migrated into `Note`, original row retained.
        case weeklyNoteContent
        /// Legacy notepad. Migrated into `Note`, original row retained.
        case permNoteContent
        /// Legacy meeting note. Migrated into `Note`, original row retained.
        case eventNoteContent

        /// The `@Model` type's name as `CadenceSchema` spells it.
        var entityName: String {
            switch self {
            case .noteContent: "Note"
            case .taskNotes: "AppTask"
            case .documentContent: "Document"
            case .dailyNoteContent: "DailyNote"
            case .weeklyNoteContent: "WeeklyNote"
            case .permNoteContent: "PermNote"
            case .eventNoteContent: "EventNote"
            }
        }

        /// The stored property as the model source spells it.
        var propertyName: String {
            switch self {
            case .taskNotes: "notes"
            case .noteContent, .documentContent, .dailyNoteContent,
                 .weeklyNoteContent, .permNoteContent, .eventNoteContent: "content"
            }
        }
    }

    /// Every markdown text still live in the store, or `nil` when any part could not be read.
    ///
    /// **`nil` is load-bearing.** This is the set that decides which images are *referenced*, so
    /// coercing a failed fetch to `[]` does not mean "that model holds no references" — it means
    /// "nothing in this store references any image", and the caller then deletes the user's entire
    /// image library. One unreadable table must abort the collection, not shrink it; the garbage
    /// waits for the next delete and costs nothing. `deleteUnreferencedMarkdownImageAssets` has
    /// carried that guard for `Note` since it was written — widening the scan widens the number of
    /// fetches that can fail, so the guard has to move with it rather than be applied once.
    ///
    /// - Parameter excludingNoteIDs: notes the caller has already decided are going. Belt and
    ///   braces beside the `isDeleted` filter below: a `ModelContext` fetch returns rows that are
    ///   deleted-but-unsaved, and the exclusion set is the whole reason the images go.
    static func liveMarkdownTexts(in context: ModelContext, excludingNoteIDs: Set<UUID> = []) -> [String]? {
        var texts: [String] = []
        for source in Source.allCases {
            guard let values = liveTexts(for: source, in: context, excludingNoteIDs: excludingNoteIDs) else {
                return nil
            }
            texts.append(contentsOf: values)
        }
        return texts
    }

    private static func liveTexts(
        for source: Source,
        in context: ModelContext,
        excludingNoteIDs: Set<UUID>
    ) -> [String]? {
        switch source {
        case .noteContent:
            texts(of: Note.self, in: context, at: \.content) { !excludingNoteIDs.contains($0.id) }
        case .taskNotes:
            texts(of: AppTask.self, in: context, at: \.notes)
        case .documentContent:
            texts(of: Document.self, in: context, at: \.content)
        case .dailyNoteContent:
            texts(of: DailyNote.self, in: context, at: \.content)
        case .weeklyNoteContent:
            texts(of: WeeklyNote.self, in: context, at: \.content)
        case .permNoteContent:
            texts(of: PermNote.self, in: context, at: \.content)
        case .eventNoteContent:
            texts(of: EventNote.self, in: context, at: \.content)
        }
    }

    /// Reads one field off every live row of one model, or `nil` if the fetch failed.
    ///
    /// **The `isDeleted` filter is insurance, and deliberately unpinned — measured, not assumed.**
    /// Every cascade calls the sweep *before* the save (`cascadeDeleteTasks` passes
    /// `commitsImmediately: false`), so the rows it has just deleted are still pending when this
    /// fetch runs. In this store they do not come back from `fetch`: removing the guard leaves the
    /// whole suite green, `anImageOnlyADeletedListsTaskReferencedIsStillReclaimed` included, and
    /// that test was written to catch exactly this. It stays because the guarantee is undocumented,
    /// because `deleteUnreferencedMarkdownImageAssets` already carries `excludingNoteIDs` against
    /// the same window, and because what it would prevent — a deleted row's body keeping an asset
    /// alive forever — is a leak rather than a loss, which is the direction this file errs in
    /// anyway. Checked before the key path, so a deleted row's body is never read.
    private static func texts<Model: PersistentModel>(
        of type: Model.Type,
        in context: ModelContext,
        at keyPath: KeyPath<Model, String>,
        keeping include: (Model) -> Bool = { _ in true }
    ) -> [String]? {
        guard let models = try? context.fetch(FetchDescriptor<Model>()) else { return nil }
        return models.compactMap { model in
            guard !model.isDeleted, include(model) else { return nil }
            return model[keyPath: keyPath]
        }
    }
}
