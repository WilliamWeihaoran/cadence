import Foundation
import SwiftData

nonisolated struct TagSeedDefinition {
    let name: String
    let desc: String
    let colorHex: String
}

nonisolated enum TagSupport {
    static let colorOptions = [
        "#ff6b6b", "#ff8a4c", "#ffb84d", "#4ecb71",
        "#5aa2ff", "#9e8cff", "#e671b8", "#7b8492",
    ]

    static let defaultTags: [TagSeedDefinition] = [
        .init(name: "bug", desc: "Something broken or incorrect.", colorHex: "#ff6b6b"),
        .init(name: "enhancement", desc: "Improvement to an existing flow.", colorHex: "#4ecb71"),
        .init(name: "feature", desc: "New user-facing capability.", colorHex: "#5aa2ff"),
        .init(name: "docs", desc: "Documentation, notes, or writing work.", colorHex: "#9e8cff"),
        .init(name: "question", desc: "Needs clarification or a decision.", colorHex: "#ffb84d"),
        .init(name: "blocked", desc: "Waiting on something external.", colorHex: "#ff8a4c"),
        .init(name: "polish", desc: "Fit, finish, and small refinements.", colorHex: "#7b8492"),
    ]

    nonisolated static func slug(for value: String) -> String {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let collapsed = folded
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "tag" : collapsed
    }

    nonisolated static func displayName(for value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    nonisolated static func normalizedTagNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let display = displayName(for: value)
            let key = slug(for: display)
            guard !display.isEmpty, seen.insert(key).inserted else { continue }
            result.append(display)
        }
        return result
    }

    nonisolated static func normalizedColorHex(_ value: String, fallback: String = "#7b8492") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixed = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        guard prefixed.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil else {
            return fallback
        }
        return prefixed.lowercased()
    }

    /// The one tag ordering, and the reason it ends on `id`.
    ///
    /// `order` then `name` is not a total order: `order` defaults to 0 on every hand-made tag, and
    /// CloudKit can land case-variant duplicates of the same name. Two tags that compare equal
    /// under a partial comparator come out of `sorted` in whatever order the input happened to be
    /// in — and both callers here feed it a collection with no defined order. `uniqueBySlug` sorts
    /// `Array(tagsBySlug(tags).values)` and `DataIntegrityRepairService` sorts
    /// `Array(tagsByID.values)`; Swift `Dictionary` value order is unspecified and seeded per
    /// process, so the same store can order the `#` picker's eight offered tags differently on
    /// every launch. Worse, `sorted` runs *inside* `tagsBySlug`, so a tie there decides which
    /// duplicate becomes canonical for a slug.
    ///
    /// `id` closes it, the same way `TaskOrdering.fallbackPrecedes` closes the task comparator:
    /// unique, stable across launches, and never displayed.
    nonisolated static func precedes(_ lhs: Tag, _ rhs: Tag) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }

        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func sorted(_ tags: [Tag]) -> [Tag] {
        tags.sorted(by: precedes)
    }

    /// Adds any default tag whose slug is not already in the store. **User-initiated only.**
    ///
    /// Its whole signal is "no tag carries this slug", and that sentence is only readable when a
    /// person has just asked for the defaults. Unprompted — at launch, or when a tag screen
    /// appears — it says the same thing about a user who has never had tags and a user whose tags
    /// have not synced yet, and it resolves that ambiguity by *inserting*: an active `bug` beside
    /// the archived, recoloured `bug` still in flight, which `deduplicateTags` then merges into
    /// one active row and CloudKit propagates everywhere. On a single device with no CloudKit at
    /// all, the same missing signal re-seeded `bug` next to a `bug` the user had renamed to
    /// `Defect`, because renaming rewrites the slug.
    ///
    /// So T-528 removed every automatic caller rather than trying to guard the insert, and
    /// `CadenceFirstLaunchEmptyStoreTests.noUnpromptedCodePathSeedsTheDefaultTags` keeps it that
    /// way. The legitimate callers are the "Add Defaults" controls on both platforms and the tag
    /// pickers' own empty states — iOS's `iOSTaskTagPickerPopover` and, since T-532, the macOS
    /// pickers' shared `TagPickerPlaceholderRow`. Pressing one after a rename *is* meant to bring
    /// the original back.
    @discardableResult
    static func seedDefaultTags(in context: ModelContext, saveChanges: Bool = true) -> Bool {
        var changed = deduplicateTags(in: context, save: false)
        // `?? []` here re-seeded all seven default tags as duplicates on a failed read, because
        // "no tags exist" is exactly what an unreadable table looks like.
        guard let existing = try? context.fetch(FetchDescriptor<Tag>()) else { return changed }
        var existingBySlug = tagsBySlug(existing)
        for (index, definition) in defaultTags.enumerated() {
            let slug = slug(for: definition.name)
            if let tag = existingBySlug[slug] {
                if tag.order == 0 && index != 0 {
                    tag.order = index
                    changed = true
                }
                continue
            }
            let tag = Tag(
                name: definition.name,
                slug: slug,
                desc: definition.desc,
                colorHex: definition.colorHex,
                order: index
            )
            context.insert(tag)
            existingBySlug[slug] = tag
            changed = true
        }
        if saveChanges && context.hasChanges {
            try? context.save()
        }
        return changed
    }

    @discardableResult
    static func deduplicateTags(in context: ModelContext, save: Bool = true) -> Bool {
        var changed = false
        // A failed read produced no groups, so the repair no-oped while reporting the store clean.
        guard let existing = try? context.fetch(FetchDescriptor<Tag>()) else { return false }
        let grouped = Dictionary(grouping: existing) { stableSlug(for: $0) }

        for (_, duplicates) in grouped where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredDuplicateTagSort)
            guard let canonical = ordered.first else { continue }
            canonical.slug = stableSlug(for: canonical)

            for duplicate in ordered.dropFirst() {
                mergeTagMetadata(from: duplicate, into: canonical)
                moveTagRelationships(from: duplicate, into: canonical)
                context.delete(duplicate)
                changed = true
            }
        }

        if save && context.hasChanges {
            try? context.save()
        }
        return changed
    }

    /// Matches each name to an existing tag or creates one. Returns `nil` — having created
    /// nothing — when the tag table could not be read.
    ///
    /// This used to coerce a failed fetch to `[]`, which meant *no existing tag could ever
    /// match*, so every name minted a brand-new duplicate `Tag`. The callers that overwrite a
    /// model's tag set with the result then re-pointed the task or note at the duplicates,
    /// severing it from the canonical tag. Run unattended by `syncAllNoteTagsFromMarkdown` at
    /// launch, one failed read was enough to re-point every note in the store at a parallel set
    /// of duplicate tags while the originals silently dropped to zero usage. `nextOrderBase` also
    /// collapsed to 0, scrambling tag order.
    ///
    /// Optional rather than empty so the compiler makes each caller say what it wants: the
    /// overwriting callers refuse to write anything at all, and the pickers that offer "create
    /// tag" go through `resolveTagsCommittingInsertions(named:in:commit:)` in
    /// `Cadence/Shared/CadenceInlineTagCreation.swift` and show a notice.
    ///
    /// **It is handed its `ModelContext`, so the caller owns the unit of work** — that signature is
    /// the statement, and it is why half 3 of the `try? save()` rule exempts this declaration and
    /// charges its callers instead. T-631 is what happens when every caller takes that exemption
    /// and none of them commits.
    static func resolveTags(named names: [String], in context: ModelContext, index: TagSlugIndex? = nil) -> [Tag]? {
        resolution(named: names, in: context, index: index)?.tags
    }

    /// The resolved tags **and the subset this call inserted**, which is what an undo needs to know.
    ///
    /// Split out rather than having `resolveTagsCommittingInsertions` re-derive the new rows from
    /// the returned array: "which of these did I just mint" is only knowable here, and a second
    /// reading of it — by id, by `isInserted`, by comparing against a fetch — is a second chance to
    /// hand `commitInsert` a row it must not delete.
    ///
    /// **Internal rather than private, and that is a target boundary rather than a preference.**
    /// This file compiles into `CadenceWidgets` as well as the app, and
    /// `CadencePendingChangePersistence` does not — so the two committing spellings live in
    /// `Cadence/Shared/CadenceInlineTagCreation.swift`, which the widget never sees, and reach this
    /// through the module rather than through `private`.
    /// **`index:` is the whole of T-1314.** Left `nil` — every picker, every inline "create tag",
    /// every single-shot caller — this reads the tag table itself and behaves exactly as it always
    /// did. Handed an index, it reads nothing: the caller has already read the table once for the
    /// whole pass and this call resolves against that snapshot. `syncAllNoteTagsFromMarkdown` is
    /// the pass that needed it, because it is on the launch path and calls this once per note.
    static func resolution(
        named names: [String],
        in context: ModelContext,
        index: TagSlugIndex? = nil
    ) -> (tags: [Tag], inserted: [Tag])? {
        let normalizedNames = normalizedTagNames(names)
        guard !normalizedNames.isEmpty else { return ([], []) }

        guard let index = index ?? makeTagIndex(in: context) else { return nil }
        let nextOrderBase = index.nextOrderBase

        var inserted: [Tag] = []
        let tags = normalizedNames.enumerated().map { offset, name -> Tag in
            let tagSlug = slug(for: name)
            if let tag = index.tag(forSlug: tagSlug) {
                return tag
            }
            let tag = Tag(name: name, slug: tagSlug, order: nextOrderBase + offset)
            context.insert(tag)
            index.register(tag)
            inserted.append(tag)
            return tag
        }
        return (tags, inserted)
    }

    /// The one read of the whole `Tag` table behind a resolution, and the only place in this file
    /// that fetches it for one.
    ///
    /// `nil` — never an empty index — when the table could not be read, because that failure is
    /// the distinction `resolution`'s optional return exists to keep: "no tag carries this slug"
    /// and "the tags could not be read" mint a duplicate and refuse, respectively, and coercing
    /// the second into the first is what T-631's predecessor did to every note in the store.
    static func makeTagIndex(in context: ModelContext) -> TagSlugIndex? {
        guard let existing = try? context.fetch(FetchDescriptor<Tag>()) else { return nil }
        return TagSlugIndex(tags: existing)
    }

    static func setTags(named names: [String], on task: AppTask, in context: ModelContext) {
        guard let resolved = resolveTags(named: names, in: context) else { return }
        task.tags = resolved
    }

    static func setTags(named names: [String], on note: Note, in context: ModelContext, writeFrontmatter: Bool) {
        let resolvedNames = writeFrontmatter ? names + MarkdownMetadataParser.inlineTagNames(in: note.content) : names
        guard let resolved = resolveTags(named: resolvedNames, in: context) else { return }
        note.tags = resolved
        if writeFrontmatter {
            note.content = MarkdownMetadataParser.content(note.content, replacingFrontmatterTags: names)
        }
        note.updatedAt = Date()
    }

    @discardableResult
    static func syncNoteTagsFromMarkdown(
        _ note: Note,
        in context: ModelContext,
        index: TagSlugIndex? = nil
    ) -> Bool {
        let tagNames = MarkdownMetadataParser.metadata(in: note.content).tags
        guard let resolved = resolveTags(named: tagNames, in: context, index: index) else { return false }
        guard tagSlugs(note.tags ?? []) != tagSlugs(resolved) else { return false }
        note.tags = resolved
        note.updatedAt = Date()
        return true
    }

    /// The launch-path sweep: every note's frontmatter tags reconciled against the tag table.
    ///
    /// **It reads that table once, not once per note (T-1314).** This is the first real work a
    /// cold launch does, and it used to be quadratic in the owner's own data: `resolution` opened
    /// with a fetch of the whole `Tag` table and re-sorted it into a slug index, and this loop
    /// called `resolution` for every note. K tagged notes over T tags meant K full table reads
    /// plus K · O(T log T) of index work, recomputed identically each time. Now the index is built
    /// here, once, and handed down.
    ///
    /// `makingTagIndex` is a seam, not a convenience, and it has one job: a test counts the calls
    /// and fails if the number is not 1 for a store of any size
    /// (`TagSupportTests.theStartupSweepReadsTheWholeTagTableExactlyOnce`). The cheapest way to
    /// undo this fix is to move the index construction back inside the loop, which would keep
    /// every other assertion in that suite green.
    @discardableResult
    static func syncAllNoteTagsFromMarkdown(
        in context: ModelContext,
        saveChanges: Bool = true,
        makingTagIndex: (ModelContext) -> TagSlugIndex? = TagSupport.makeTagIndex(in:)
    ) -> Bool {
        var changed = false
        // `?? []` reported "nothing needed syncing" when the notes simply could not be read.
        guard let notes = try? context.fetch(FetchDescriptor<Note>()) else { return false }
        // No notes, no tag read — the empty store this runs against on a first launch keeps
        // costing exactly one fetch, as it did when the tag fetch lived one frame down.
        guard !notes.isEmpty else { return false }
        // A tag table that cannot be read is the same refusal it was per note: resolution answered
        // `nil` for every note and nothing was written. It is answered once now instead of K times.
        guard let index = makingTagIndex(context) else { return false }
        for note in notes {
            changed = syncNoteTagsFromMarkdown(note, in: context, index: index) || changed
        }
        if saveChanges && context.hasChanges {
            try? context.save()
        }
        return changed
    }

    nonisolated static func tagSlugs(_ tags: [Tag]) -> [String] {
        tags.map(\.slug).sorted()
    }

    static func uniqueBySlug(_ tags: [Tag]) -> [Tag] {
        Array(tagsBySlug(tags).values).sorted(by: precedes)
    }

    fileprivate static func tagsBySlug(_ tags: [Tag]) -> [String: Tag] {
        var result: [String: Tag] = [:]
        for tag in sorted(tags) where result[tag.slug] == nil {
            result[tag.slug] = tag
        }
        return result
    }

    private static func stableSlug(for tag: Tag) -> String {
        let normalized = slug(for: tag.slug)
        if normalized != "tag" || tag.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalized
        }
        return slug(for: tag.name)
    }

    nonisolated private static func preferredDuplicateTagSort(_ lhs: Tag, _ rhs: Tag) -> Bool {
        if lhs.isArchived != rhs.isArchived {
            return !lhs.isArchived && rhs.isArchived
        }

        let lhsUsage = (lhs.tasks?.count ?? 0) + (lhs.notes?.count ?? 0)
        let rhsUsage = (rhs.tasks?.count ?? 0) + (rhs.notes?.count ?? 0)
        if lhsUsage != rhsUsage {
            return lhsUsage > rhsUsage
        }

        if lhs.desc.isEmpty != rhs.desc.isEmpty {
            return !lhs.desc.isEmpty
        }

        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }

        return lhs.createdAt < rhs.createdAt
    }

    /// The duplicate-merge policy, stated once: **the canonical tag's metadata wins, and
    /// `updatedAt` never claims more freshness than the surviving values carry.**
    ///
    /// Which record is canonical is `preferredDuplicateTagSort`'s call — active over archived,
    /// most used, described, lowest `order`, oldest — and that is deliberately *not* "whichever
    /// row was written last". The commonest way this store grows duplicate slugs is a second
    /// device seeding `defaultTags`: those rows are newer than everything while carrying no user
    /// intent at all, so letting `updatedAt` pick the winner would revert a recoloured tag to its
    /// seed colour. A duplicate therefore never overwrites a value the canonical already has.
    ///
    /// What a duplicate may do is *fill a value the canonical does not have*. When it does, the
    /// survivor is showing the duplicate's edit, so the stamp moves with it; when it does not, the
    /// stamp stays the canonical's own. An unconditional `max(target.updatedAt, source.updatedAt)`
    /// is what T-360 was: the survivor advertised the newer row's freshness while displaying the
    /// older row's colour, so nothing downstream could tell the colour had been dropped — and
    /// `CadenceReadService.tagDetail` publishes that stamp over MCP.
    ///
    /// `order` and `createdAt` still merge conservatively and deliberately do **not** move
    /// `updatedAt`: no writer in the app stamps `updatedAt` when it assigns either
    /// (`seedDefaultTags` backfills `order` without one), so they are not part of what the stamp
    /// describes. `isArchived` cannot make the survivor reflect the source at all — an active
    /// duplicate always sorts ahead of an archived one, so the canonical is archived only when
    /// every duplicate is, and this line then re-confirms the value it already had.
    private static func mergeTagMetadata(from source: Tag, into target: Tag) {
        var adoptedSourceMetadata = false

        // Live branch: `desc` really can be empty, and empty means unset rather than cleared —
        // the same reading `preferredDuplicateTagSort` takes when it ranks a described tag first.
        if target.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !source.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.desc = source.desc
            adoptedSourceMetadata = true
        }

        // This branch reads like the one above but was not: it asked `target.colorHex.isEmpty`,
        // and `Tag.colorHex` defaults to a non-empty hex, so for anything the app created it was
        // structurally unreachable. "The canonical has no colour" for a row that arrived from
        // CloudKit, an import, or a legacy store means no *usable* colour, which is the judgement
        // `normalizedColorHex` already makes everywhere else in this module.
        if usableColorHex(target) == nil, let sourceColorHex = usableColorHex(source) {
            target.colorHex = sourceColorHex
            adoptedSourceMetadata = true
        }

        target.order = min(target.order, source.order)
        target.isArchived = target.isArchived && source.isArchived
        target.createdAt = min(target.createdAt, source.createdAt)
        if adoptedSourceMetadata {
            target.updatedAt = max(target.updatedAt, source.updatedAt)
        }
    }

    /// The tag's colour if it is one, otherwise `nil`. `normalizedColorHex` returns its fallback
    /// for anything that is not `#rrggbb`, so an empty fallback turns "invalid" into "absent".
    private static func usableColorHex(_ tag: Tag) -> String? {
        let normalized = normalizedColorHex(tag.colorHex, fallback: "")
        return normalized.isEmpty ? nil : normalized
    }

    private static func moveTagRelationships(from source: Tag, into target: Tag) {
        for task in source.tasks ?? [] {
            task.tags = replacing(source, with: target, in: task.tags ?? [])
        }

        for note in source.notes ?? [] {
            note.tags = replacing(source, with: target, in: note.tags ?? [])
        }
    }

    private static func replacing(_ source: Tag, with target: Tag, in tags: [Tag]) -> [Tag] {
        var seen = Set<String>()
        var result: [Tag] = []

        for tag in tags {
            let candidate = tag === source ? target : tag
            let key = stableSlug(for: candidate)
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }

        return sorted(result)
    }
}

/// The `Tag` table read once, carried through a pass that resolves many names (T-1314).
///
/// One call to `TagSupport.resolution` is one read of the table plus one slug index built over it,
/// and for a picker resolving the name someone just typed that is the right shape. It is the wrong
/// shape for `syncAllNoteTagsFromMarkdown`, which calls `resolution` once per note on the launch
/// path: the table was re-read and re-sorted for every note in the store, identically each time.
/// This type is that read, made once and handed down.
///
/// **A class, because the pass mints rows.** A note introducing `#alpha` has to leave that tag
/// visible to the next note, which the per-note version got for free — a SwiftData fetch sees the
/// context's pending inserts. Reference semantics are how that survives the fetch going away.
///
/// **`maxOrder`, not a running counter**, so a minted tag receives the same `order` the per-note
/// fetch would have given it: `(highest order in the table) + 1 + its offset within the call`,
/// where the "table" includes the rows this pass has already minted. That equivalence is not
/// decorative — `order` is the first key of `TagSupport.precedes`, so a different number here is a
/// different tag order on screen. `TagSupportTests.theSweptStoreMatchesTheOldPerNoteResolution`
/// holds the two paths to the same answer by running both.
nonisolated final class TagSlugIndex {
    private var bySlug: [String: Tag]
    private var maxOrder: Int

    /// **Internal rather than `fileprivate`, so a test can hand the sweep a snapshot the store
    /// disagrees with.** That disagreement is the only way to observe, from outside, that every
    /// note in a pass really went through the handed index: an index built from no tags at all,
    /// over a store that has them, mints duplicates if it is honoured and mints nothing if
    /// anything underneath refetched the table
    /// (`TagSupportTests.everyNoteInTheSweepResolvesThroughTheOneIndexItWasGiven`).
    init(tags: [Tag]) {
        bySlug = TagSupport.tagsBySlug(tags)
        maxOrder = tags.map(\.order).max() ?? -1
    }

    fileprivate var nextOrderBase: Int { maxOrder + 1 }

    fileprivate func tag(forSlug slug: String) -> Tag? {
        bySlug[slug]
    }

    /// Records a tag this pass just minted. First writer wins, matching `tagsBySlug`, which keeps
    /// the first tag per slug in `TagSupport.precedes` order rather than the last.
    fileprivate func register(_ tag: Tag) {
        if bySlug[tag.slug] == nil {
            bySlug[tag.slug] = tag
        }
        maxOrder = max(maxOrder, tag.order)
    }
}
