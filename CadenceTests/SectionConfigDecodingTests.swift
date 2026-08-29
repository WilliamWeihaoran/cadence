import Foundation
import Testing
@testable import Cadence

/// Reading a list's stored kanban columns back off disk (T-475).
///
/// A list's whole column array is one JSON string — `Area.sectionConfigsRaw` /
/// `Project.sectionConfigsRaw` — and the only other record of those columns is
/// `sectionNamesRaw`, which keeps **names and nothing else**. So the `sectionConfigs` getter's
/// fallback is destructive by construction: anything that stops the blob decoding drops every
/// column's `uuid`, `colorHex`, `dueDate`, `isCompleted` and `isArchived`, and because the setter
/// rewrites the blob from whatever it is handed, the next save makes that loss permanent.
///
/// Two things guard it, and this suite pins both. `TaskSectionConfig.init(from:)` applies
/// `decodeIfPresent(…) ?? <default>` per field, so a field added later cannot invalidate a stored
/// blob. And `TaskSectionConfig.storedList` reads the array **element by element**, so an element
/// the decoder is still entitled to reject — no `name`, a `null`, a value of the wrong JSON type,
/// whatever a future build writes — costs one column instead of all of them.
@Suite("Stored section config decoding")
@MainActor
struct SectionConfigDecodingTests {
    private static let defaultUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D0")!
    private static let researchUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
    private static let shippedUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!

    private func seededConfigs() -> [TaskSectionConfig] {
        [
            TaskSectionConfig(uuid: Self.defaultUUID, name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(
                uuid: Self.researchUUID,
                name: "Research",
                colorHex: "#a78bfa",
                dueDate: "2026-09-01"
            ),
            TaskSectionConfig(
                uuid: Self.shippedUUID,
                name: "Shipped",
                colorHex: "#4ecb71",
                isCompleted: true,
                isArchived: true
            )
        ]
    }

    private func legacyMirror() -> String {
        [TaskSectionDefaults.defaultName, "Research", "Shipped"].joined(separator: "\n")
    }

    private func rawBlob(_ configs: [TaskSectionConfig]) throws -> String {
        String(decoding: try JSONEncoder().encode(configs), as: UTF8.self)
    }

    /// The stored blob with one element made unreadable, by removing the single key
    /// `TaskSectionConfig.init(from:)` still requires. That is the *cheapest* way to produce an
    /// element the decoder rejects; it stands in for every other one, because `Array`'s synthesized
    /// decoding treats them all the same way — the first throw ends the whole array.
    private func blobWithOneUnreadableColumn(_ configs: [TaskSectionConfig], at index: Int) throws -> String {
        var objects = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(configs)) as? [[String: Any]]
        )
        try #require(objects.indices.contains(index))
        objects[index].removeValue(forKey: "name")
        let raw = String(
            decoding: try JSONSerialization.data(withJSONObject: objects),
            as: UTF8.self
        )

        // Non-vacuity: the fixture is only a fixture if the strict decode this getter used to do
        // really does fail on it. Otherwise every expectation below passes for the wrong reason.
        #expect(
            (try? JSONDecoder().decode([TaskSectionConfig].self, from: Data(raw.utf8))) == nil,
            "the corrupted blob still decodes whole, so this suite no longer reproduces T-475"
        )
        return raw
    }

    private func column(_ configs: [TaskSectionConfig], named name: String) -> TaskSectionConfig? {
        configs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: - The decoder itself

    @Test func everyStoredFieldSurvivesAnEncodeDecodeRoundTrip() throws {
        let original = seededConfigs()
        let decoded = try JSONDecoder().decode(
            [TaskSectionConfig].self,
            from: JSONEncoder().encode(original)
        )

        #expect(decoded == original)
        // `==` is synthesized over every stored property, so it already covers a field added
        // later — but spell the payload out once, because a round trip comparing two *defaults*
        // would also pass.
        #expect(column(decoded, named: "Research")?.uuid == Self.researchUUID)
        #expect(column(decoded, named: "Research")?.colorHex == "#a78bfa")
        #expect(column(decoded, named: "Research")?.dueDate == "2026-09-01")
        #expect(column(decoded, named: "Shipped")?.isCompleted == true)
        #expect(column(decoded, named: "Shipped")?.isArchived == true)
    }

    /// **The T-475 ticket, before anyone adds the sixth property.** Every key but `name` is
    /// removed in turn and the column still has to decode, with the removed field falling back to
    /// its declared default and every other field untouched.
    ///
    /// The key list is re-derived from an encoded config rather than restated, so a property added
    /// to this struct without a matching `decodeIfPresent` line fails *here* instead of quietly
    /// invalidating every section list already on disk.
    @Test func aStoredColumnSurvivesEveryOptionalKeyGoingMissing() throws {
        let original = TaskSectionConfig(
            uuid: Self.researchUUID,
            name: "Research",
            colorHex: "#a78bfa",
            dueDate: "2026-09-01",
            isCompleted: true,
            isArchived: true
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )

        let keys = Set(object.keys)
        #expect(
            keys.isSuperset(of: ["uuid", "name", "colorHex", "dueDate", "isCompleted", "isArchived"]),
            "TaskSectionConfig stopped encoding a field this test was written to cover"
        )

        for key in keys.subtracting(["name"]).sorted() {
            var stripped = object
            stripped.removeValue(forKey: key)
            let config = try #require(
                try? JSONDecoder().decode(
                    TaskSectionConfig.self,
                    from: try JSONSerialization.data(withJSONObject: stripped)
                ),
                "TaskSectionConfig stops decoding when \(key) is missing, so every section list stored before that key existed loses its colours, dates and lifecycle flags"
            )

            #expect(config.name == "Research")
            if key != "uuid" { #expect(config.uuid == Self.researchUUID) }
            if key != "colorHex" { #expect(config.colorHex == "#a78bfa") }
            if key != "dueDate" { #expect(config.dueDate == "2026-09-01") }
            if key != "isCompleted" { #expect(config.isCompleted) }
            if key != "isArchived" { #expect(config.isArchived) }
        }

        // The one head field: a column with no name is not an older column, it is not a column.
        var nameless = object
        nameless.removeValue(forKey: "name")
        #expect(
            (try? JSONDecoder().decode(
                TaskSectionConfig.self,
                from: try JSONSerialization.data(withJSONObject: nameless)
            )) == nil
        )
    }

    // MARK: - One bad column must not cost the others

    /// Hand-setting `sectionConfigsRaw` is exactly what the model guide tells feature code never to
    /// do, and exactly what a test standing in for a blob already on disk has to do.
    @Test func oneUnreadableColumnDoesNotCostTheOthersTheirStoredFields() throws {
        let area = Area(name: "Ops")
        area.sectionConfigsRaw = try blobWithOneUnreadableColumn(seededConfigs(), at: 1)
        area.sectionNamesRaw = legacyMirror()

        let read = area.sectionConfigs

        let shipped = try #require(column(read, named: "Shipped"))
        #expect(shipped.uuid == Self.shippedUUID, "a readable column lost its identity to an unreadable neighbour")
        #expect(shipped.colorHex == "#4ecb71", "a readable column lost its colour to an unreadable neighbour")
        #expect(shipped.isCompleted, "a readable column lost its completion flag to an unreadable neighbour")
        #expect(shipped.isArchived, "a readable column lost its archive flag to an unreadable neighbour")

        let fallbackDefault = try #require(column(read, named: TaskSectionDefaults.defaultName))
        #expect(fallbackDefault.uuid == Self.defaultUUID)
    }

    /// The unreadable column is not *deleted* either: `sectionNamesRaw` is the only surviving
    /// record of it, so its name is recovered from there and the column — and the tasks pointing at
    /// it by name — still have somewhere to be.
    @Test func theNameOfAnUnreadableColumnIsRecoveredFromTheLegacyMirror() throws {
        let area = Area(name: "Ops")
        area.sectionConfigsRaw = try blobWithOneUnreadableColumn(seededConfigs(), at: 1)
        area.sectionNamesRaw = legacyMirror()

        let read = area.sectionConfigs
        #expect(Set(read.map(\.name)) == [TaskSectionDefaults.defaultName, "Research", "Shipped"])

        let recovered = try #require(column(read, named: "Research"))
        #expect(recovered.colorHex == TaskSectionDefaults.defaultColorHex)
        #expect(recovered.dueDate == "")
    }

    /// **The half of T-475 that is not about the throw.** A degraded read is survivable; a degraded
    /// read written back over the good blob is not. The next ordinary save has to leave the
    /// readable columns exactly as they were on disk.
    @Test func aDegradedReadIsNotWrittenBackOverTheReadableColumns() throws {
        let area = Area(name: "Ops")
        area.sectionConfigsRaw = try blobWithOneUnreadableColumn(seededConfigs(), at: 1)
        area.sectionNamesRaw = legacyMirror()

        // An ordinary edit, through the ordinary write path.
        area.addSectionConfig(TaskSectionConfig(name: "Backlog", colorHex: "#4a9eff"))

        // The blob on disk is readable again...
        let stored = try #require(
            try? JSONDecoder().decode([TaskSectionConfig].self, from: Data(area.sectionConfigsRaw.utf8))
        )
        // ...and it still carries what the readable columns carried.
        let shipped = try #require(column(stored, named: "Shipped"))
        #expect(shipped.uuid == Self.shippedUUID, "the degraded read overwrote a good column's identity")
        #expect(shipped.colorHex == "#4ecb71", "the degraded read overwrote a good column's colour")
        #expect(shipped.isArchived, "the degraded read overwrote a good column's archive flag")

        #expect(column(stored, named: "Backlog")?.colorHex == "#4a9eff")
        #expect(Set(stored.map(\.name)).contains("Research"), "the unreadable column was dropped by the write")
    }

    /// `Project` carries the same blob, the same mirror and the same getter as `Area`. A fix that
    /// reached one of them would be half a fix.
    @Test func aProjectSalvagesItsColumnsThroughTheSamePath() throws {
        let project = Project(name: "Launch")
        project.sectionConfigsRaw = try blobWithOneUnreadableColumn(seededConfigs(), at: 1)
        project.sectionNamesRaw = legacyMirror()

        let shipped = try #require(column(project.sectionConfigs, named: "Shipped"))
        #expect(shipped.uuid == Self.shippedUUID)
        #expect(shipped.colorHex == "#4ecb71")
        #expect(shipped.isArchived)
    }

    // MARK: - The three outcomes are distinguished, not collapsed

    /// Nothing to salvage is still nothing to salvage: a blob that is not a JSON array at all
    /// leaves the legacy name list as the whole answer, which is what a pre-config list has always
    /// done.
    @Test func aBlobThatIsNotAnArrayStillFallsBackToTheLegacyNameList() {
        let area = Area(name: "Ops")
        area.sectionConfigsRaw = "{\"not\": \"an array\""
        area.sectionNamesRaw = [TaskSectionDefaults.defaultName, "Research"].joined(separator: "\n")

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Research"])
    }

    /// A list whose columns were all deleted is not a list that never had any. Reading a stored
    /// `[]` as "no blob" would re-import the legacy mirror and bring every deleted column back.
    @Test func anEmptyStoredArrayIsNotReadAsALegacyNameList() {
        let area = Area(name: "Ops")
        area.sectionConfigsRaw = "[]"
        area.sectionNamesRaw = legacyMirror()

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName])
    }

    /// And a blob that decoded whole ignores the mirror entirely. The mirror is rewritten by the
    /// setter on every save, so it can add nothing to a clean read — but a stale one, which is what
    /// a CloudKit merge of two devices leaves, would resurrect a column the user deleted.
    @Test func aCleanBlobIgnoresTheLegacyMirrorEntirely() throws {
        let area = Area(name: "Ops")
        area.sectionConfigsRaw = try rawBlob(Array(seededConfigs().prefix(2)))
        area.sectionNamesRaw = [TaskSectionDefaults.defaultName, "Research", "Ghost"].joined(separator: "\n")

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Research"])
    }
}
