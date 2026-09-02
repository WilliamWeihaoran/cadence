import Foundation
import Testing
@testable import Cadence

/// **T-560.** Every in-memory store in this repository disables CloudKit mirroring.
///
/// A `ModelConfiguration(isStoredInMemoryOnly: true)` that leaves `cloudKitDatabase` at its
/// default attaches a mirroring delegate to a throwaway store. In a unit test that is network I/O
/// and nondeterminism nobody asked for, and it is the only mechanism that fits T-560's residue:
/// 3,652 empty `<app container>/tmp/<UUID>/inMemory_store_ckAssets` directories in the user's real
/// container, `inMemory_store` being the name SwiftData gives an in-memory store.
///
/// The rule is stated over the whole repository rather than over the test target, because the two
/// shipped in-memory configurations already followed it and the ledger is more useful when it
/// covers them too. `CadenceTestStore` is now the test target's only one.
struct CadenceInMemoryStoreHygieneTests {

    private static let roots = ["Cadence", "CadenceTests", "CadenceWidgets", "CadenceMCPServer"]

    /// Every in-memory `ModelConfiguration(…)` call in `source` that does **not** disable
    /// mirroring, returned as its own flattened source text.
    ///
    /// Walks with bounds-checked indices and `continue`s past anything malformed: this helper is
    /// read by a sweep over every Swift file in three shipped targets, and a trap in a scan helper
    /// is a dead test host rather than a test failure.
    static func mirroringEnabledInMemorySites(in source: String) -> [String] {
        let characters = Array(source)
        var sites: [String] = []
        var searchStart = source.startIndex

        while let needle = source.range(
            of: "isStoredInMemoryOnly",
            range: searchStart..<source.endIndex
        ) {
            searchStart = needle.upperBound
            guard let opening = source.range(
                of: "ModelConfiguration(",
                options: .backwards,
                range: source.startIndex..<needle.lowerBound
            ) else { continue }

            let openIndex = source.distance(from: source.startIndex, to: opening.upperBound) - 1
            guard openIndex >= 0, openIndex < characters.count else { continue }

            var depth = 0
            var closeIndex: Int?
            var cursor = openIndex
            while cursor < characters.count {
                if characters[cursor] == "(" {
                    depth += 1
                } else if characters[cursor] == ")" {
                    depth -= 1
                    if depth == 0 {
                        closeIndex = cursor
                        break
                    }
                }
                cursor += 1
            }

            guard let close = closeIndex, close > openIndex else { continue }
            let call = String(characters[openIndex...close])
            guard !call.contains("cloudKitDatabase: .none") else { continue }
            sites.append(call.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " "))
        }
        return sites
    }

    @Test func noInMemoryStoreInTheRepositoryLeavesCloudKitMirroringOn() throws {
        let instrument = try CadenceScanInstrument(
            "mirroringEnabledInMemoryStore",
            fires: "let configuration = ModelConfiguration(isStoredInMemoryOnly: true)",
            andNotOn: "let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)",
            by: { !Self.mirroringEnabledInMemorySites(in: CadenceSourceScan.codeOnly($0)).isEmpty }
        )

        let paths = try Self.roots.flatMap { try CadenceSourceScan.swiftFiles(under: $0) }
        let offenders = try instrument.sweep(
            paths,
            atLeast: 800,
            including: "CadenceTests/CadenceTestStoreSupport.swift",
            read: { try CadenceSourceScan.sourceFile($0) }
        )

        #expect(
            offenders.isEmpty,
            """
            These files build an in-memory store with CloudKit mirroring left on. Mirroring stages \
            assets into the host app's real container and never cleans them up (T-560). Pass \
            `cloudKitDatabase: .none`, or in the test target call `CadenceTestStore.container()`:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// The exact ledger, not a floor: a floor over a population the repository is shrinking cannot
    /// tell you the survivors are still where you left them.
    @Test func theRepositoryDeclaresExactlyThreeInMemoryStores() throws {
        let paths = try Self.roots.flatMap { try CadenceSourceScan.swiftFiles(under: $0) }
        #expect(paths.count >= 800, "the walk read \(paths.count) files, so it did not cover the repository")

        var declaring: [String] = []
        var occurrences = 0
        for path in paths {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            let count = CadenceSourceScan.matchCount("isStoredInMemoryOnly", in: code)
            guard count > 0 else { continue }
            declaring.append(path)
            occurrences += count
        }

        #expect(
            declaring.sorted() == [
                "Cadence/Services/MCPReadOnly/CadenceModelContainerFactory.swift",
                "Cadence/Services/PersistenceController.swift",
                "CadenceTests/CadenceTestStoreSupport.swift"
            ],
            "in-memory stores are declared in \(declaring.sorted())"
        )
        #expect(occurrences == 3, "expected one in-memory configuration per declaring file, found \(occurrences)")
    }
}
