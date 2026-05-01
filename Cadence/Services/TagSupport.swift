import Foundation
import SwiftData

struct TagSeedDefinition {
    let name: String
    let desc: String
    let colorHex: String
}

enum TagSupport {
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

    static func seedDefaultTags(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        var existingBySlug = tagsBySlug(existing)
        for (index, definition) in defaultTags.enumerated() {
            let slug = slug(for: definition.name)
            if let tag = existingBySlug[slug] {
                if tag.order == 0 && index != 0 {
                    tag.order = index
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
        }
        if context.hasChanges {
            try? context.save()
        }
    }

    static func resolveTags(named names: [String], in context: ModelContext) -> [Tag] {
        let normalizedNames = normalizedTagNames(names)
        guard !normalizedNames.isEmpty else { return [] }

        let existing = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
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
        task.tags = resolveTags(named: names, in: context)
    }

    static func setTags(named names: [String], on note: Note, in context: ModelContext, writeFrontmatter: Bool) {
        let resolvedNames = writeFrontmatter ? names + MarkdownMetadataParser.inlineTagNames(in: note.content) : names
        let resolved = resolveTags(named: resolvedNames, in: context)
        note.tags = resolved
        if writeFrontmatter {
            note.content = MarkdownMetadataParser.content(note.content, replacingFrontmatterTags: names)
        }
        note.updatedAt = Date()
    }

    static func syncNoteTagsFromMarkdown(_ note: Note, in context: ModelContext) {
        let tagNames = MarkdownMetadataParser.metadata(in: note.content).tags
        let resolved = resolveTags(named: tagNames, in: context)
        guard tagSlugs(note.tags ?? []) != tagSlugs(resolved) else { return }
        note.tags = resolved
        note.updatedAt = Date()
    }

    static func syncAllNoteTagsFromMarkdown(in context: ModelContext) {
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        for note in notes {
            syncNoteTagsFromMarkdown(note, in: context)
        }
        if context.hasChanges {
            try? context.save()
        }
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
}
