import Foundation
import Testing
@testable import Cadence

/// `CadenceOrderAllocation` is where a newly created row's `order` comes from.
///
/// The bug these tests pin (T-329): macOS allocated `contexts.count` and `links.count`. Counting
/// and max-plus-one agree only while nothing has ever been deleted. Delete the middle of three and
/// the survivors hold `[0, 2]` — counting hands the new row `2`, an order that already exists.
///
/// A repeated `order` is not a harmless tie. These collections sort on `order` alone, and a sort
/// with equal keys is unstable, so the two rows sharing `2` are free to swap places between
/// launches with nothing edited. Every assertion below fails if the allocation goes back to
/// counting.
@MainActor
struct CadenceOrderAllocationTests {

    // MARK: - The audit's own case

    /// Three rows numbered `0, 1, 2`; delete the middle one. The next row must be `3`.
    @Test func deletingTheMiddleOfThreeAllocatesThreeNotTwo() {
        let survivors = [0, 2]

        let allocated = CadenceOrderAllocation.nextOrder(after: survivors)

        #expect(allocated == 3)
        #expect(allocated != survivors.count)
        #expect(!survivors.contains(allocated))
    }

    /// The same case through real `Context` rows, because the sheet allocates from models rather
    /// than from a bare `[Int]`.
    @Test func allocatingAfterADeletedContextDoesNotRepeatAnExistingOrder() {
        var contexts = (0..<3).map { index -> Context in
            let context = Context(name: "Context \(index)")
            context.order = index
            return context
        }
        contexts.remove(at: 1)

        #expect(contexts.map(\.order) == [0, 2])

        let allocated = CadenceOrderAllocation.nextOrder(after: contexts, order: \.order)

        #expect(allocated == 3)
        #expect(!contexts.map(\.order).contains(allocated))
    }

    /// And through real `SavedLink` rows, the second site that counted.
    @Test func allocatingAfterADeletedLinkDoesNotRepeatAnExistingOrder() {
        var links = (0..<3).map { index -> SavedLink in
            let link = SavedLink(title: "Link \(index)", url: "https://example.com/\(index)")
            link.order = index
            return link
        }
        links.remove(at: 1)

        #expect(links.map(\.order) == [0, 2])

        let allocated = CadenceOrderAllocation.nextOrder(after: links, order: \.order)

        #expect(allocated == 3)
        #expect(!links.map(\.order).contains(allocated))
    }

    // MARK: - The invariant, over shapes a real store reaches

    /// The allocated order is always free and always last. Counting fails every line below that
    /// holds a gap, which is every line a delete can produce.
    @Test func theAllocatedOrderIsAlwaysFreeAndAlwaysLast() {
        let shapes: [[Int]] = [
            [],
            [0],
            [0, 1, 2],
            [0, 2],
            [1, 2],
            [0, 5, 9],
            [7],
            [0, 0, 1],
            [-3],
            [-5, -2],
            [3, 1, 2]
        ]

        for shape in shapes {
            let allocated = CadenceOrderAllocation.nextOrder(after: shape)
            #expect(!shape.contains(allocated), "\(shape) allocated a taken order \(allocated)")
            for existing in shape {
                #expect(allocated > existing, "\(shape) allocated \(allocated), not past \(existing)")
            }
        }
    }

    /// Empty allocates `0`, so the first row of an empty collection is numbered from zero.
    @Test func anEmptyCollectionAllocatesZero() {
        #expect(CadenceOrderAllocation.nextOrder(after: [Int]()) == 0)
        #expect(CadenceOrderAllocation.nextOrder(after: [Context](), order: \.order) == 0)
    }

    /// Negative stored orders are honoured rather than clamped: a migrated or hand-reordered row
    /// that sorts ahead of zero must keep sorting ahead of the row allocated after it.
    @Test func negativeStoredOrdersAllocateFromTheMaximumNotFromZero() {
        #expect(CadenceOrderAllocation.nextOrder(after: [-3]) == -2)
        #expect(CadenceOrderAllocation.nextOrder(after: [-5, -2]) == -1)
    }

    /// Allocating repeatedly without ever deleting still produces a dense `0, 1, 2, …` run, so the
    /// fix does not leave gaps in the ordinary case.
    @Test func repeatedAllocationWithoutDeletesStaysDense() {
        var orders: [Int] = []
        for expected in 0..<5 {
            let allocated = CadenceOrderAllocation.nextOrder(after: orders)
            #expect(allocated == expected)
            orders.append(allocated)
        }
        #expect(orders == [0, 1, 2, 3, 4])
    }

    // MARK: - The two macOS call sites

    /// `CreateContextSheet.create()` and `LinksView.addLink()` are private methods on SwiftUI
    /// views, so no test can call them. This scan is scoped to those two **function bodies** — not
    /// to the enclosing struct, which would pass on an unrelated `.count` elsewhere in the file.
    @Test func bothMacOSSheetsAllocateThroughTheSharedHelper() throws {
        let sites = [
            ("Cadence/macOS/Sheets/CreateContextSheet.swift", "create", "ctx.order", "modelContext.insert("),
            // T-327 moved this one insert behind CadenceSavedLinkPersistence, which commits it.
            // The anchor moved with it; the allocation assertions below are unchanged.
            ("Cadence/macOS/Views/LinksView.swift", "addLink", "link.order", "CadenceSavedLinkPersistence.insert(")
        ]

        for (relativePath, function, assignment, insertion) in sites {
            let raw = try CadenceSourceScan.sourceFile(relativePath)
            #expect(raw.count > 400, "\(relativePath) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(relativePath): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(relativePath): the stripper changed the length")

            let body = try #require(
                CadenceSourceScan.functionBody(named: function, in: stripped),
                "\(relativePath): could not find \(function)()"
            )
            #expect(body.contains(insertion), "\(function)() body looks wrong")
            #expect(body.contains(assignment), "\(function)() no longer assigns \(assignment)")

            #expect(
                body.contains("CadenceOrderAllocation.nextOrder("),
                "\(function)() does not allocate through CadenceOrderAllocation"
            )
            #expect(
                CadenceSourceScan.matchCount(countingAllocationPattern, in: body) == 0,
                "\(function)() still allocates an order by counting"
            )
        }
    }

    /// The needle above is only worth trusting if it matches the spelling it is hunting and misses
    /// the spelling it is protecting.
    @Test func theCountingNeedleMatchesTheOldSpellingAndNotTheNew() {
        #expect(CadenceSourceScan.matchCount(countingAllocationPattern, in: "ctx.order = contexts.count") == 1)
        #expect(CadenceSourceScan.matchCount(countingAllocationPattern, in: "link.order = links.count") == 1)
        #expect(
            CadenceSourceScan.matchCount(
                countingAllocationPattern,
                in: "ctx.order = CadenceOrderAllocation.nextOrder(after: contexts, order: \\.order)"
            ) == 0
        )
        #expect(CadenceSourceScan.matchCount(countingAllocationPattern, in: "let shown = rows.count") == 0)
    }

    /// The body extractor must return the function it was asked for and stop at its closing brace.
    @Test func theFunctionBodyExtractorIsScopedToOneFunction() throws {
        let source = """
        struct Sample {
            private func create() {
                if !url.hasPrefix("http://") { url = "https://" + url }
                let inner = { things.count }
                value.order = 3
            }

            private func other() {
                value.order = things.count
            }
        }
        """

        let stripped = CadenceSourceScan.strippingComments(source)
        #expect(stripped == source, "a URL scheme's slashes are not a comment")

        let body = try #require(CadenceSourceScan.functionBody(named: "create", in: stripped))
        #expect(body.contains("value.order = 3"))
        #expect(!body.contains("other"))
        #expect(CadenceSourceScan.matchCount(countingAllocationPattern, in: body) == 0)
        #expect(CadenceSourceScan.matchCount(countingAllocationPattern, in: source) == 1)
        #expect(CadenceSourceScan.functionBody(named: "missing", in: source) == nil)
    }

    /// The stripper blanks a real comment while leaving the code beside it alone, and never
    /// shortens the string.
    @Test func theCommentStripperBlanksCommentsWithoutShortening() throws {
        let source = "let url = \"https://example.com\" // a trailing note\nlet n = 1\n"

        let stripped = CadenceSourceScan.strippingComments(source)

        #expect(stripped != source)
        #expect(stripped.count == source.count)
        #expect(stripped.contains("\"https://example.com\""))
        #expect(!stripped.contains("a trailing note"))
        #expect(stripped.contains("let n = 1"))
    }
}

// MARK: - The needle

/// `<something>.order = <something>.count` — the allocation-by-counting spelling, and not a bare
/// `.count` read used for a badge or a guard.
///
/// The source-reading helpers this file used to carry are now `CadenceSourceScan`, shared with the
/// other scans that have to read a private method on a SwiftUI view. Their comment stripper is
/// still spelled `(?<!:)//` for the reason documented there, which `LinksView.addLink()` — with
/// its `hasPrefix("http://")` — is the reason for.
private let countingAllocationPattern = #"\.order\s*=\s*[A-Za-z_][A-Za-z0-9_]*\.count\b"#
