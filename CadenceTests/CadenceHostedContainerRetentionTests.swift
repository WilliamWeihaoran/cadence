#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

/// **Every `ModelContainer` a hosted test view reads stays alive until the test process exits
/// ([[T-3218]], generalising [[T-3279]]).**
///
/// A `@Query` inside a view hosted by `NSHostingView` subscribes to SwiftData's models-changed
/// notification, and that subscription outlives the window: closing it and dropping
/// `contentView` does not deterministically deallocate the hosting view. Traced under
/// [[T-3279]], every earlier round's observer still answers a later round's post and asks its
/// own context for its container. If that container has been freed, `ModelContext.container`'s
/// getter executes `brk #1` and the whole test host dies with `signal trap` — on CI's
/// macOS 26.6.2, never on this Mac's macOS 27, which does not free them. So the crash lands on
/// whichever later test happens to save, not on the test that left the observer behind
/// ([[T-3215]]).
///
/// There is no public API to unregister those observers or to ask whether any remain, so the
/// hazard is removed from the other side: the container an observer will ask for is never freed.
/// They are small in-memory stores. Route every hosted view through
/// `retainingModelContainerForProcessLifetime(_:)` instead of `.modelContainer(_:)`;
/// `noHostedTestViewReadsAContainerTheProcessMayFree` below fails on any test file that hosts a
/// view and spells the bare modifier.
@MainActor
enum CadenceHostedContainerRetention {
    private static var retained: [ModelContainer] = []

    static func retain(_ container: ModelContainer) {
        guard !retained.contains(where: { $0 === container }) else { return }
        retained.append(container)
    }

    static func isRetained(_ container: ModelContainer) -> Bool {
        retained.contains { $0 === container }
    }
}

extension View {
    /// `.modelContainer(container)`, plus holding `container` for the life of the test process.
    /// The only spelling a test that HOSTS a view may use — see `CadenceHostedContainerRetention`.
    @MainActor
    func retainingModelContainerForProcessLifetime(_ container: ModelContainer) -> some View {
        CadenceHostedContainerRetention.retain(container)
        return modelContainer(container)
    }
}

@Suite(.serialized)
@MainActor
struct CadenceHostedContainerRetentionTests {
    /// A test file hosts a view when its code (comments and literals blanked) constructs one of
    /// these. `ImageRenderer` is included because it hosts a view graph too.
    private static let hostingConstructors = [
        "NSHostingView(", "NSHostingController(", "UIHostingController(", "ImageRenderer("
    ]

    private static func hostsAViewOverABareContainer(_ code: String) -> Bool {
        hostingConstructors.contains { code.contains($0) } && code.contains(".modelContainer(")
    }

    @Test func noHostedTestViewReadsAContainerTheProcessMayFree() throws {
        let instrument = try CadenceScanInstrument(
            "hosted view over a container the process may free",
            fires: "let host = NSHostingView(rootView: TasksListView().modelContainer(container))",
            andNotOn: "let host = NSHostingView(rootView: TasksListView()"
                + ".retainingModelContainerForProcessLifetime(container))",
            by: Self.hostsAViewOverABareContainer
        )
        let files = try CadenceSourceScan.swiftFiles(under: "CadenceTests")
        let offenders = try instrument.sweep(
            files,
            atLeast: 400,
            including: "CadenceTests/CadenceCodexKanbanRenderingTests.swift",
            read: { CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile($0)) }
        )
        #expect(offenders.isEmpty, "these test files host a view over a container that can be freed under a live @Query observer: \(offenders)")
    }

    /// The positive half of the sweep above: the three files known to host views over in-memory
    /// containers really do route through the retaining modifier, so the sweep's silence is not
    /// just a renamed hosting constructor walking past it.
    @Test func theThreeHostingSuitesRouteEveryContainerThroughTheRetainingModifier() throws {
        let expected = [
            "CadenceTests/CadenceCodexTaskListVirtualizationTests.swift": 2,
            "CadenceTests/CadenceCodexKanbanRenderingTests.swift": 1,
            "CadenceTests/MacTaskRowInlineDetailTests.swift": 1
        ]
        for (path, count) in expected {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("NSHostingView("), "\(path) no longer hosts a view; update this list")
            #expect(
                CadenceSourceScan.matchCount("\\.retainingModelContainerForProcessLifetime\\(", in: code) >= count,
                "\(path) hosts \(count) view(s) over a container but retains fewer"
            )
        }
    }

    /// The modifier really holds the container: dropped by its only owner, it is still alive.
    /// The control beside it shows the same container shape IS freed when nothing retains it, so
    /// the first expectation is not just a container that never dies on this OS.
    @Test func theRetainingModifierKeepsAContainerAliveAfterItsOwnerDropsIt() throws {
        weak var unretained: ModelContainer?
        try autoreleasepool {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            unretained = container
        }
        #expect(unretained == nil, "control: an unretained in-memory container must be freed on drop")

        weak var retained: ModelContainer?
        try autoreleasepool {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            retained = container
            // Built, never hosted: exercises the retention without registering an observer.
            _ = Text(verbatim: "retained").retainingModelContainerForProcessLifetime(container)
        }
        let survivor = try #require(retained, "the retaining modifier let its container be freed")
        #expect(CadenceHostedContainerRetention.isRetained(survivor))
    }
}

#endif
