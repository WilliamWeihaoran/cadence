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

    static func sorted(_ tags: [Tag]) -> [Tag] {
        tags.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

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
    /// inline pickers fall back to an unsaved `Tag`, and the three overwriting callers refuse to
    /// write anything at all.
    static func resolveTags(named names: [String], in context: ModelContext) -> [Tag]? {
        let normalizedNames = normalizedTagNames(names)
        guard !normalizedNames.isEmpty else { return [] }

        guard let existing = try? context.fetch(FetchDescriptor<Tag>()) else { return nil }
        var bySlug = tagsBySlug(existing)
        let nextOrderBase = (existing.map(\.order).max() ?? -1) + 1

        return normalizedNames.enumerated().map { offset, name in
            let tagSlug = slug(for: name)
            if let tag = bySlug[tagSlug] {
                return tag
            }
            let tag = Tag(name: name, slug: tagSlug, order: nextOrderBase + offset)
            context.insert(tag)
            bySlug[tagSlug] = tag
            return tag
        }
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
    static func syncNoteTagsFromMarkdown(_ note: Note, in context: ModelContext) -> Bool {
        let tagNames = MarkdownMetadataParser.metadata(in: note.content).tags
        guard let resolved = resolveTags(named: tagNames, in: context) else { return false }
        guard tagSlugs(note.tags ?? []) != tagSlugs(resolved) else { return false }
        note.tags = resolved
        note.updatedAt = Date()
        return true
    }

    @discardableResult
    static func syncAllNoteTagsFromMarkdown(in context: ModelContext, saveChanges: Bool = true) -> Bool {
        var changed = false
        // `?? []` reported "nothing needed syncing" when the notes simply could not be read.
        guard let notes = try? context.fetch(FetchDescriptor<Note>()) else { return false }
        for note in notes {
            changed = syncNoteTagsFromMarkdown(note, in: context) || changed
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
        Array(tagsBySlug(tags).values).sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func tagsBySlug(_ tags: [Tag]) -> [String: Tag] {
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

    private static func mergeTagMetadata(from source: Tag, into target: Tag) {
        if target.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.desc = source.desc
        }
        if target.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.colorHex = source.colorHex
        }
        target.order = min(target.order, source.order)
        target.isArchived = target.isArchived && source.isArchived
        target.createdAt = min(target.createdAt, source.createdAt)
        target.updatedAt = max(target.updatedAt, source.updatedAt)
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
