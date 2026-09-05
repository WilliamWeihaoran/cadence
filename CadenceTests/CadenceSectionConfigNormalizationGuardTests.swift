import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-915: both section-blob write guards compared the pre-normalisation array.**
///
/// `applySectionConfigEdits` guards on "did the merge change anything" ([[T-738]]) and
/// `mutateSectionConfigs` has guarded the same way for longer. Both asked the question of the array
/// they were about to *hand* the setter, against the array the **getter** returned — and the
/// getter's array has already been through `normalizedSectionConfigs` while the setter's argument
/// has not. `Area`/`Project` force `isCompleted` and `isArchived` false on the Default column
/// there, drop names that trim to empty, dedupe case-insensitively and pull Default back to index
/// 0. A write differing from the store only in something that list discards therefore passed both
/// guards, re-serialised `sectionConfigsRaw` to a byte-identical string, dirtied the object and
/// pushed a CloudKit record — every time it was attempted.
///
/// **This was unreachable in the shipping app when it was filed, and that is the point.** All four
/// routes to a column's lifecycle are gated on `TaskSectionConfig.supportsLifecycle` ([[T-268]]),
/// which is the only field the normaliser touches on a column the user can reach. The guards read
/// as "an identical write costs nothing", and that sentence is true only while that gate holds. The
/// tests below reach past the gate deliberately, by calling the container's own write methods,
/// which is exactly what a future caller would do.
///
/// **Why `modelContext.hasChanges` and not a write counter.**
/// `CadenceKanbanColumnLifecycleSurfaceTests` counts assignments through a spy container, and that
/// is the right instrument for the merge — but the spy deliberately does not normalise, and the gap
/// between what a container is handed and what it stores *is* this defect, so the spy cannot see
/// it. The cost the ticket names is a dirtied object and the record it pushes, which is what
/// `hasChanges` reports on a real `Area` in a real store.
@MainActor
struct CadenceSectionConfigNormalizationGuardTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    private func seededArea(in modelContext: ModelContext) throws -> Area {
        let area = Area(name: "Work")
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing")
        ]
        modelContext.insert(area)
        try modelContext.save()
        return area
    }

    /// **Behavioural, and red before T-915.** `updateSectionConfig` reaches `mutateSectionConfigs`.
    /// Setting `isCompleted` on the Default column is a write the container's normaliser discards
    /// outright, so the stored string cannot change — and the object must not be dirtied for it.
    @Test func amutationTheNormaliserDiscardsDoesNotDirtyTheContainer() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = try seededArea(in: modelContext)
        let defaultUUID = try #require(area.sectionConfigs.first(where: \.isDefault)?.uuid)

        #expect(!modelContext.hasChanges, "the seed is not settled, so this measures nothing")
        #expect(area.updateSectionConfig(uuid: defaultUUID) { $0.isCompleted = true })

        #expect(
            !modelContext.hasChanges,
            "a write the normaliser discards still re-serialised the blob and dirtied the object"
        )
    }

    /// **Behavioural, and red before T-915.** The stale-snapshot sibling of the guard above.
    @Test func aneditTheNormaliserDiscardsDoesNotDirtyTheContainer() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = try seededArea(in: modelContext)
        let base = area.sectionConfigs

        #expect(!modelContext.hasChanges, "the seed is not settled, so this measures nothing")
        area.applySectionConfigEdits(
            base: base,
            edited: base.map { config in
                guard config.isDefault else { return config }
                var archived = config
                archived.isArchived = true
                return archived
            }
        )

        #expect(
            !modelContext.hasChanges,
            "a stale-snapshot write the normaliser discards still dirtied the object"
        )
    }

    /// **Non-vacuity for the pair above.** The same two entry points, on a field the normaliser
    /// keeps, still write. A guard that refused everything would satisfy both tests above.
    @Test func awriteTheNormaliserKeepsStillReachesTheBlob() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = try seededArea(in: modelContext)
        let doingUUID = try #require(area.sectionConfigs.first(where: { $0.name == "Doing" })?.uuid)

        #expect(area.updateSectionConfig(uuid: doingUUID) { $0.isCompleted = true })
        #expect(modelContext.hasChanges, "a real column write no longer reaches the blob")
        #expect(area.sectionConfigs.first(where: { $0.uuid == doingUUID })?.isCompleted == true)

        try modelContext.save()
        area.applySectionConfigEdits(
            base: area.sectionConfigs,
            edited: area.sectionConfigs.map { config in
                guard config.uuid == doingUUID else { return config }
                var renamed = config
                renamed.name = "Shipping"
                return renamed
            }
        )
        #expect(modelContext.hasChanges, "a real stale-snapshot write no longer reaches the blob")
        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Shipping"])
    }

    /// **The third write guard already asked the right question, and this pins that it keeps
    /// asking it.** `reorderSectionConfigs` compares `sectionConfigs` *read back* against the
    /// previous read, so both sides of its comparison are post-normalisation and it was never
    /// blind the way the other two were. Its answer for a declined transform is `true` — nothing
    /// is pending and the board is drawing what the store holds.
    @Test func thereorderGuardComparesWhatTheContainerStored() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = try seededArea(in: modelContext)

        #expect(
            area.reorderSectionConfigs(in: modelContext, commit: { _ in throw CommitRefused() }) { configs in
                // A transform the normaliser undoes: Default is forced back to index 0 on write,
                // so the read-back equals the previous read and there is nothing to commit.
                Array(configs.reversed())
            },
            "a reorder the normaliser undid was reported as refused"
        )
        #expect(!modelContext.hasChanges, "a reorder the normaliser undid still dirtied the object")
        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Doing"])
    }

    /// **Behavioural, and red before T-915 in its `hasChanges` half.** Padding a name with
    /// whitespace is a second kind of write with no stored effect: the normaliser trims it back to
    /// exactly what is already there. Reached through `Project`, so both containers are exercised.
    ///
    /// Deliberately padding rather than *clearing*: a name that trims to **empty** is discarded by
    /// the normaliser along with its column, so a rename to whitespace really does change the store
    /// — it deletes the column. That is a separate finding, filed as [[T-1053]], and it is why this
    /// test does not use it.
    @Test func apaddedRenameThatTrimsToTheSameNameDoesNotDirtyTheContainer() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let project = Project(name: "Launch")
        project.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing")
        ]
        modelContext.insert(project)
        try modelContext.save()
        let doingUUID = try #require(project.sectionConfigs.first(where: { $0.name == "Doing" })?.uuid)

        #expect(!modelContext.hasChanges, "the seed is not settled, so this measures nothing")
        #expect(project.updateSectionConfig(uuid: doingUUID) { $0.name = "  Doing  " })

        #expect(
            project.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Doing"],
            "non-vacuity: the normaliser did not trim the padded name after all"
        )
        #expect(
            !modelContext.hasChanges,
            "a rename the normaliser trims away still re-serialised the blob and dirtied the object"
        )
    }

    /// **The guard's soundness condition, stated as a test.** The comparison only means "this write
    /// changes what a later read returns" while `normalizedSectionConfigs` is idempotent — otherwise
    /// every write would look like a change, and the guards would be back where they started.
    @Test func thecontainersNormalisationIsIdempotent() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = try seededArea(in: modelContext)

        let messy = [
            TaskSectionConfig(name: "  Doing  "),
            TaskSectionConfig(name: "DOING"),
            TaskSectionConfig(name: "   "),
            TaskSectionConfig(name: TaskSectionDefaults.defaultName, colorHex: "", isCompleted: true, isArchived: true)
        ]
        let once = area.normalizedSectionConfigs(messy)
        #expect(once != messy, "non-vacuity: the normaliser changed nothing about this array")
        #expect(area.normalizedSectionConfigs(once) == once, "the guards' comparison is not sound")
        #expect(area.normalizedSectionConfigs(area.sectionConfigs) == area.sectionConfigs)
    }
}
