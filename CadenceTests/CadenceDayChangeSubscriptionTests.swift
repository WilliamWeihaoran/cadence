import AppKit
import Combine
import Foundation
import os
import SwiftUI
import Testing
@testable import Cadence

#if os(macOS)
/// A `NotificationCenter` that counts how many observers are added to it. Combine's
/// `NotificationCenter.Publisher` adds exactly one per subscription, so this is a subscription
/// counter for any stream built over it.
nonisolated final class CadenceObserverCountingCenter: NotificationCenter, @unchecked Sendable {
    private let added = OSAllocatedUnfairLock(initialState: 0)

    var addedObserverCount: Int { added.withLock { $0 } }

    override func addObserver(
        forName name: NSNotification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> any NSObjectProtocol {
        added.withLock { $0 += 1 }
        return super.addObserver(forName: name, object: obj, queue: queue, using: block)
    }
}

/// Counts body passes, so a test can prove the host really re-ran its body.
@MainActor
final class CadenceDayChangeBodyCounter {
    var passes = 0
}

/// T-3124 measurement: the exact shape the `cadenceTracksDayChanges` modifier had — a fresh
/// `MergeMany` erased to a fresh `AnyPublisher` and `receive(on:)`'d, built inline in `body` —
/// over a counting centre.
private struct FreshPublisherPerPassProbe: View {
    let generation: Int
    let center: NotificationCenter
    let counter: CadenceDayChangeBodyCounter

    var body: some View {
        counter.passes += 1
        return Text("\(generation)")
            .onReceive(CadenceDayChangeSupport.dayMayHaveChanged(on: center).receive(on: RunLoop.main)) { _ in }
    }
}

/// The control: the same stream, built once and handed in.
private struct CachedPublisherProbe: View {
    let generation: Int
    let publisher: AnyPublisher<Void, Never>
    let counter: CadenceDayChangeBodyCounter

    var body: some View {
        counter.passes += 1
        return Text("\(generation)")
            .onReceive(publisher) { _ in }
    }
}

/// The product modifier, over a counting stream the test holds.
private struct ProductModifierProbe: View {
    let generation: Int
    let stream: CadenceDayChangeStream
    let counter: CadenceDayChangeBodyCounter
    @State private var observedDay = CadenceObservedDay()

    var body: some View {
        counter.passes += 1
        // `generation` only: drawing `observedDay.todayKey` here as well crashed the hosted
        // window in AppKit's constraint pass on every `rootView` swap (measured 2026-10-12) —
        // a harness artefact, since the T-3136 probe below draws the key without swapping.
        return Text("\(generation)")
            .cadenceTracksDayChanges($observedDay, from: stream)
    }
}

@MainActor
struct CadenceDayChangeSubscriptionTests {
    private static let updates = 5

    private func settle<V: View>(_ host: NSHostingView<V>) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
    }

    private func hosted<V: View>(_ view: V) -> (NSHostingView<V>, NSWindow) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return (host, window)
    }

    /// Positive control for the instrument: one plain subscription adds one observer per name.
    @Test func theCountingCenterSeesOneObserverPerNamePerSubscription() {
        let center = CadenceObserverCountingCenter()
        let names = CadenceDayChangeSupport.notificationNames.count
        #expect(names > 0)
        let subscription = CadenceDayChangeSupport.dayMayHaveChanged(on: center).sink { }
        #expect(center.addedObserverCount == names)
        subscription.cancel()
    }

    @Test func measuredAFreshPublisherPerBodyPassResubscribes() async throws {
        let center = CadenceObserverCountingCenter()
        let counter = CadenceDayChangeBodyCounter()
        let names = CadenceDayChangeSupport.notificationNames.count
        let (host, window) = hosted(FreshPublisherPerPassProbe(generation: 0, center: center, counter: counter))
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        let mountedPasses = counter.passes
        #expect(mountedPasses >= 1, "non-vacuity: SwiftUI must evaluate the probe")
        for generation in 1...Self.updates {
            host.rootView = FreshPublisherPerPassProbe(generation: generation, center: center, counter: counter)
            try await settle(host)
        }
        let passes = counter.passes
        #expect(passes >= mountedPasses + Self.updates, "non-vacuity: every update must re-run body")
        print("T-3124 MEASURE fresh: passes=\(passes) observers=\(center.addedObserverCount) names=\(names)")
        #expect(center.addedObserverCount == names * passes)
    }

    @Test func measuredACachedPublisherSubscribesOnce() async throws {
        let center = CadenceObserverCountingCenter()
        let counter = CadenceDayChangeBodyCounter()
        let names = CadenceDayChangeSupport.notificationNames.count
        let publisher = CadenceDayChangeSupport.dayMayHaveChanged(on: center)
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
        let (host, window) = hosted(CachedPublisherProbe(generation: 0, publisher: publisher, counter: counter))
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        for generation in 1...Self.updates {
            host.rootView = CachedPublisherProbe(generation: generation, publisher: publisher, counter: counter)
            try await settle(host)
        }
        let passes = counter.passes
        #expect(passes >= 1 + Self.updates, "non-vacuity: every update must re-run body")
        print("T-3124 MEASURE cached: passes=\(passes) observers=\(center.addedObserverCount) names=\(names)")
        #expect(center.addedObserverCount == names)
    }

    /// T-3124 fix: the product modifier holds one subscription across host updates.
    @Test func theDayObserverSubscribesOnceAcrossHostBodyPasses() async throws {
        let center = CadenceObserverCountingCenter()
        let counter = CadenceDayChangeBodyCounter()
        let names = CadenceDayChangeSupport.notificationNames.count
        let stream = CadenceDayChangeStream(center: center)
        let (host, window) = hosted(ProductModifierProbe(generation: 0, stream: stream, counter: counter))
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        for generation in 1...Self.updates {
            host.rootView = ProductModifierProbe(generation: generation, stream: stream, counter: counter)
            try await settle(host)
        }
        #expect(counter.passes >= 1 + Self.updates, "non-vacuity: every update must re-run body")
        #expect(center.addedObserverCount == names)
    }

    /// The default overload every adopter calls must reach the one cached stream, not build one.
    @Test func everyAdopterSharesTheOneCachedDayStream() throws {
        #expect(CadenceDayChangeStream.main === CadenceDayChangeStream.main)

        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceDayChangeSupport.swift")
        )
        // Built once, in the static; and the raw stream is built only inside the stream's init.
        #expect(source.components(separatedBy: "CadenceDayChangeStream(center:").count - 1 == 1)
        #expect(source.components(separatedBy: "static let main = CadenceDayChangeStream(center: .default)").count - 1 == 1)
        #expect(source.components(separatedBy: "dayMayHaveChanged(on: center)").count - 1 == 1)
        #expect(source.components(separatedBy: "cadenceTracksDayChanges(day, from: .main)").count - 1 == 1)
    }
}

// T-3136's timeline-block measurement is NOT kept here, deliberately: it moved the process-wide
// `NSTimeZone.default` by 25 hours across several `await`s, and in a parallel test target that
// shifts `todayKey` under every other suite running at the same moment. Its result is recorded in
// the ledger under T-3136 and T-3140.

#endif
