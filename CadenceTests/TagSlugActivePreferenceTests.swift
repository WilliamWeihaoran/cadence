import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-17013]]: when an active and an archived row share a slug -- a second device seeding the
/// defaults while the archived `bug` is still in flight -- the active row is the tag for that slug.
@MainActor
struct TagSlugActivePreferenceTests {
    @Test func theActiveTwinIsTheOneTagForItsSlug() {
        let archived = Cadence.Tag(name: "work", slug: "work", order: 0, isArchived: true)
        let active = Cadence.Tag(name: "Work", slug: "work", order: 5)

        #expect(TagSupport.uniqueBySlug([archived, active]).map(\.id) == [active.id])
        #expect(TagSupport.uniqueBySlug([active, archived]).map(\.id) == [active.id])
    }

    @Test func aNoteNamingTheSlugIsSyncedOntoTheActiveTwin() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let archived = Cadence.Tag(name: "work", slug: "work", order: 0, isArchived: true)
        let active = Cadence.Tag(name: "Work", slug: "work", order: 5)
        context.insert(archived)
        context.insert(active)
        let note = Note(kind: .daily, title: "Today", content: "---\ntags: [\"work\"]\n---\n\nBody #work")
        context.insert(note)

        TagSupport.syncNoteTagsFromMarkdown(note, in: context)

        #expect(note.sortedTags.map(\.id) == [active.id])
        #expect(try #require(TagSupport.resolveTags(named: ["work"], in: context)).map(\.id) == [active.id])
    }

    /// With only archived rows, the sorted-first one still wins, as before.
    @Test func allArchivedTwinsKeepTheSortedFirst() {
        let first = Cadence.Tag(name: "work", slug: "work", order: 0, isArchived: true)
        let second = Cadence.Tag(name: "Work", slug: "work", order: 5, isArchived: true)

        #expect(TagSupport.uniqueBySlug([second, first]).map(\.id) == [first.id])
    }
}
