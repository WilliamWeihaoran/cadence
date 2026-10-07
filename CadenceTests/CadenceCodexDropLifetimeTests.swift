import CoreGraphics
import Foundation
import AppKit
import SwiftUI
import Testing
@testable import Cadence

@MainActor
@Suite(.serialized)
struct CadenceCodexDropLifetimeTests {
    private let frame = CGRect(x: 12, y: 100, width: 320, height: 600)

    @Test func codexFinalDestructionRemovesEveryDropFactAndItsTieBreakPosition() {
        var store = CadenceNewTaskDropFrameStore()
        let id = UUID()
        register(id, in: &store)
        #expect(store.retainedFrameCount == 1)
        #expect(store.candidates().map(\.id) == [id])
        #expect(store.slotMinute(for: id, at: CGPoint(x: 20, y: 160)) != nil)
        store.destroy(id)
        #expect(store.retainedFrameCount == 0)
        #expect(store.candidates().isEmpty)
        #expect(store.placement(for: id) == nil)
        #expect(store.slotMinute(for: id, at: CGPoint(x: 20, y: 160)) == nil)
        // Reusing the fixture ID makes a stale order entry observable as a duplicate candidate.
        register(id, in: &store)
        #expect(store.candidates().map(\.id) == [id])
        store.destroy(id)
        store.destroy(id)
        #expect(store.retainedFrameCount == 0)
    }

    @Test func codexSharedStateOwnerSurvivesTheMeasuredPopOrderUntilFinalRelease() async throws {
        let box = CodexDropStoreBox()
        var outgoing: CadenceNewTaskDropRegistrationLifetime? = lifetime(in: box)
        let weakOwner = CodexWeakDropLifetime(outgoing)
        let id = try #require(outgoing).activate()
        register(id, in: &box.store)
        var restored = outgoing
        box.store.setFrame(frame, slotOriginY: frame.minY, for: id)
        box.store.retire(id)
        outgoing = nil
        #expect(weakOwner.value != nil, "the restored state's reference must retain the same owner")
        #expect(try #require(restored).activate() == id)
        box.store.setPlacement(dropKey: "list:a_lifetime", listName: "Lifetime", for: id)
        box.store.setLive(true, for: id)
        #expect(box.store.candidates().map(\.id) == [id], "T-3008: no new geometry publication on return")
        #expect(box.destructions == 0)
        restored = nil
        #expect(weakOwner.value == nil)
        await drainDestructions(in: box, expected: 1)
        #expect(box.store.retainedFrameCount == 0)
        #expect(box.store.candidates().isEmpty)
    }

    @Test func codexDestroyedTargetsDoNotAccumulateBehindAStillRetainedTarget() async throws {
        let box = CodexDropStoreBox()
        let retained = lifetime(in: box)
        let retainedID = retained.activate()
        register(retainedID, in: &box.store)
        box.store.retire(retainedID)
        var owners: [CadenceNewTaskDropRegistrationLifetime] = []
        for _ in 0..<200 {
            let owner = lifetime(in: box)
            let id = owner.activate()
            register(id, in: &box.store)
            box.store.retire(id)
            owners.append(owner)
        }
        #expect(box.store.retainedFrameCount == 201)
        #expect(box.store.candidates().isEmpty)
        owners.removeAll()
        await drainDestructions(in: box, expected: 200)
        #expect(box.store.retainedFrameCount == 1)
        box.store.setLive(true, for: retainedID)
        #expect(box.store.candidates().map(\.id) == [retainedID])
        #expect(retained.activate() == retainedID)
    }

    @Test func codexUnusedStateInitialValuesDoNotScheduleRegistrationDestruction() async {
        let box = CodexDropStoreBox()
        for _ in 0..<200 {
            var unused: CadenceNewTaskDropRegistrationLifetime? = lifetime(in: box)
            let weakOwner = CodexWeakDropLifetime(unused)
            #expect(weakOwner.value != nil)
            unused = nil
            #expect(weakOwner.value == nil)
        }
        await Task.yield()
        #expect(box.destructions == 0)
        #expect(box.store.retainedFrameCount == 0)
    }

    @Test func codexAnOldOwnersDeferredCleanupCannotRemoveANewIdentity() async throws {
        let box = CodexDropStoreBox()
        var old: CadenceNewTaskDropRegistrationLifetime? = lifetime(in: box)
        let oldID = try #require(old).activate()
        register(oldID, in: &box.store)
        let replacement = lifetime(in: box)
        let newID = replacement.activate()
        #expect(newID != oldID)
        register(newID, in: &box.store)
        old = nil
        await drainDestructions(in: box, expected: 1)
        #expect(box.store.candidates().map(\.id) == [newID])
        #expect(box.store.retainedFrameCount == 1)
        #expect(box.store.placement(for: newID) != nil)
        #expect(replacement.activate() == newID)
    }

    @Test func codexNativeStateKeepsItsOwnerAcrossReevaluationAndReleasesItOnRemoval() async throws {
        let box = CodexDropStoreBox()
        let host = NSHostingView(rootView: CodexDropLifetimeRoot(box: box, generation: 0, showsTarget: true))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host)
        let id = try #require(box.nativePublishedIDs.last, "positive control: SwiftUI must mount the probe")
        #expect(box.store.retainedFrameCount == 1)
        for generation in 1...5 {
            host.rootView = CodexDropLifetimeRoot(box: box, generation: generation, showsTarget: true)
            try await settle(host)
            #expect(box.nativePublishedIDs.last == id)
            #expect(box.store.retainedFrameCount == 1)
            #expect(box.destructions == 0, "discarded initial State values must not unregister the adopted owner")
        }
        #expect(Set(box.nativePublishedIDs) == [id])
        host.rootView = CodexDropLifetimeRoot(box: box, generation: 6, showsTarget: false)
        try await settle(host)
        await drainDestructions(in: box, expected: 1)
        #expect(box.store.retainedFrameCount == 0)
        #expect(box.store.candidates().isEmpty)
    }

    private func settle<V: View>(_ host: NSHostingView<V>) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
    }

    private func register(_ id: UUID, in store: inout CadenceNewTaskDropFrameStore) {
        store.setFrame(frame, slotOriginY: frame.minY, for: id)
        store.setPlacement(
            dropKey: "list:a_lifetime", listName: "Lifetime",
            slot: CadenceCaptureDropSlotRule(hourHeight: 60), for: id
        )
        store.setLive(true, for: id)
    }

    private func lifetime(in box: CodexDropStoreBox) -> CadenceNewTaskDropRegistrationLifetime {
        CadenceNewTaskDropRegistrationLifetime { [weak box] id in
            guard let box else { return }
            box.store.destroy(id)
            box.destructions += 1
        }
    }

    private func drainDestructions(in box: CodexDropStoreBox, expected: Int) async {
        for _ in 0..<100 where box.destructions < expected {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(box.destructions == expected, "the destruction callback must actually run")
    }
}

@MainActor
private final class CodexDropStoreBox {
    var store = CadenceNewTaskDropFrameStore()
    var destructions = 0
    var nativePublishedIDs: [UUID] = []
}

private struct CodexDropLifetimeRoot: View {
    let box: CodexDropStoreBox
    let generation: Int
    let showsTarget: Bool

    var body: some View {
        if showsTarget {
            CodexDropLifetimeProbe(box: box, generation: generation)
        }
    }
}

private struct CodexDropLifetimeProbe: View {
    let box: CodexDropStoreBox
    let generation: Int
    @State private var lifetime: CadenceNewTaskDropRegistrationLifetime

    init(box: CodexDropStoreBox, generation: Int) {
        self.box = box
        self.generation = generation
        _lifetime = State(initialValue: CadenceNewTaskDropRegistrationLifetime { [weak box] id in
            guard let box else { return }
            box.store.destroy(id)
            box.destructions += 1
        })
    }

    var body: some View {
        let id = lifetime.activate()
        Text("\(generation)")
            .onChange(of: generation, initial: true) { _, _ in
                box.nativePublishedIDs.append(id)
                box.store.setFrame(CGRect(x: 0, y: 0, width: 320, height: 200), slotOriginY: 0, for: id)
                box.store.setPlacement(dropKey: "list:a_native", listName: "Native", for: id)
                box.store.setLive(true, for: id)
            }
            .onDisappear { box.store.retire(id) }
    }
}

@MainActor
private final class CodexWeakDropLifetime {
    weak var value: CadenceNewTaskDropRegistrationLifetime?

    init(_ value: CadenceNewTaskDropRegistrationLifetime?) {
        self.value = value
    }
}
