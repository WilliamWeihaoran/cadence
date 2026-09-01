import Foundation
import SwiftData

/// **Creating a tag from an inline picker, committed** (T-631).
///
/// Separate from `TagSupport.swift` for one reason, and it is a target boundary rather than a
/// taste: that file compiles into `CadenceWidgets` too, and `CadencePendingChangePersistence` does
/// not. A widget draws tags and never makes one, so the commit belongs on the app side of the line
/// and this is where the line is.
extension TagSupport {

    /// `resolveTags`, **plus the commit for the rows it had to mint** (T-631).
    ///
    /// Every inline "create tag" affordance in the app called `resolveTags` from a view's ambient
    /// `@Environment(\.modelContext)` and committed nothing. The new `Tag` therefore sat *pending*
    /// in the app's single `ModelContext`: cancelling the sheet did not undo it, because no
    /// composer rolls back and `TaskCreationService.createTask` un-inserts `[task] + subtasks` and
    /// not the tag. It landed later, from whatever unrelated screen saved next — which is how a
    /// tag typed into a sheet the user then dismissed turned up in Settings › Tags minutes
    /// afterwards, from another window.
    ///
    /// So the moment the tag exists is now the moment the user asked for it, which is what
    /// `SettingsTagsSection.createTag` and `iOSSettingsTagsSection.createTag` already did for the
    /// same act on the same model.
    ///
    /// **Only the rows this call minted are handed to `commitInsert`.** A refused commit un-inserts
    /// exactly those and leaves the tags that already existed — and any unrelated pending work in
    /// the shared context — alone. `rollback()` is not available here for the reason
    /// `CadencePendingChangePersistence.commitEdit` documents at length.
    ///
    /// **`nil` and `throws` are different answers on purpose.** `nil` is `resolveTags`' own
    /// "the tag table could not be read, so nothing was created"; a throw is "the tag was made and
    /// the store refused it, and it has been taken back out". Both leave the caller with no tag,
    /// and the caller says so rather than selecting a chip for a row that does not exist.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`; it is
    ///   forwarded so the undo path stays reachable from a test.
    static func resolveTagsCommittingInsertions(
        named names: [String],
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> [Tag]? {
        guard let resolution = resolution(named: names, in: context) else { return nil }
        guard !resolution.inserted.isEmpty else { return resolution.tags }
        try CadencePendingChangePersistence.commitInsert(
            of: resolution.inserted,
            in: context,
            commit: commit
        )
        return resolution.tags
    }

    /// The inline pickers' spelling of `resolveTagsCommittingInsertions(named:in:commit:)`: one
    /// name in, one committed `Tag` or `nil` out.
    ///
    /// **Why the throw is turned into a value here and not six times over.** `onCreateTag` is a
    /// non-throwing closure stored on a `View`, so every one of the six surfaces that offers
    /// "create tag" would otherwise write the same `do`/`catch` around the same call — and six
    /// copies of one sentence is how a repo ends up with six answers to one question, which is
    /// what T-631 found when it counted them.
    ///
    /// The two failures it merges are one event to a caller: the tag table could not be read, or
    /// the store refused the insert and it has been taken back out. Either way there is no tag,
    /// nothing is left pending, and the surface must say so rather than draw a chip for a row that
    /// does not exist. What it must *not* do is fall back to `Tag(name:)` — an object the store was
    /// never asked about — which is what four of the six did.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`; it is
    ///   forwarded so a test can reach the `nil` a refused commit produces.
    static func committedTag(
        named name: String,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Tag? {
        do {
            return try resolveTagsCommittingInsertions(named: [name], in: context, commit: commit)?.first
        } catch {
            return nil
        }
    }
}
