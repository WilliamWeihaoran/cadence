#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Records a real `NSScrollView`'s live-scroll cycle.
///
/// Selector-based rather than closure-based on purpose: the offsets have to be read off the clip
/// view *inside* the notification, which is what makes the transcript AppKit's answer rather than
/// the loop's.
@MainActor
private final class LiveScrollRecorder: NSObject {
    /// `contentView.bounds.origin.y`, once per `didLiveScroll`.
    private(set) var offsets: [CGFloat] = []
    private(set) var startCount = 0
    private(set) var endCount = 0

    func observe(_ scrollView: NSScrollView) {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(willStartLiveScroll(_:)),
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        center.addObserver(
            self,
            selector: #selector(didLiveScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )
        center.addObserver(
            self,
            selector: #selector(didEndLiveScroll(_:)),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
    }

    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func willStartLiveScroll(_ note: Notification) {
        startCount += 1
    }

    @objc private func didLiveScroll(_ note: Notification) {
        guard let scrollView = note.object as? NSScrollView else { return }
        offsets.append(scrollView.contentView.bounds.origin.y)
    }

    @objc private func didEndLiveScroll(_ note: Notification) {
        endCount += 1
    }
}

/// A document view with the same coordinate sense a SwiftUI `ScrollView` reports: `contentOffset.y`
/// grows downward.
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Counts how often a `UserDefaults` key actually notifies, which is the channel an `@AppStorage`
/// write travels on.
private final class DefaultsKeyObserver: NSObject {
    private(set) var notifications = 0
    private let store: UserDefaults
    private let key: String

    init(store: UserDefaults, key: String) {
        self.store = store
        self.key = key
        super.init()
        store.addObserver(self, forKeyPath: key, options: [], context: nil)
    }

    func stopObserving() {
        store.removeObserver(self, forKeyPath: key)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        notifications += 1
    }
}

/// **T-1498 — the owner's second lag report, as a count.**
///
/// The owner reported that Today's timeline scrolls badly **and that the Calendar's does not**. The
/// two draw the *same* component, `TimelineDayCanvas`, so the control was in the report: the cost
/// cannot be in the canvas, and the diff between the two hosts is the whole of the answer.
///
/// That diff, read off the two files:
///
/// - `CalendarPageSupportViews.swift` guards its scroll report — `guard visibleTimelineHour !=
///   clampedHour else { return }` — and then debounces the `@AppStorage` write through
///   `CalendarPageStateSupport.schedulePersistence`.
/// - `SchedulePanel.swift` did neither. Its gate was `didRestoreScroll, !isRestoringScroll` and
///   nothing else, so **every frame** of a live scroll wrote
///   `@AppStorage("scheduleRememberedScrollHour")` — and an `@AppStorage` write invalidates the
///   view that declares it whether or not its body reads it.
///
/// **What is asserted here is a COUNT, never a duration.** CI runs Xcode 26 and this Mac runs 27
/// ([[T-1279]]/[[T-1296]]); "it feels smooth" is not a bound a test can hold. *"One fling is one
/// report per hour it crosses, however many frames it spans"* is — the same shape
/// `EstimateRollerCommitRateTests` holds for [[T-1431]].
///
/// **The before and after come out of one transcript through one code path.** Passing
/// `lastReportedHour: nil` at every frame reproduces the old behaviour exactly, because the old
/// code had no memory of the last hour. Nothing here models the shipping decision; it *is* the
/// shipping decision, driven by offsets a real `NSScrollView` reported.
@MainActor
struct SchedulePanelScrollWorkRateTests {

    // MARK: - The transcript

    private static let viewportHeight: CGFloat = 600
    private static let zoomLevel = 1
    /// 600 / `TimelineZoom.targetHours(1)` = 50pt per hour.
    private static var hourHeight: CGFloat {
        TimelineZoom.hourHeight(viewportHeight: viewportHeight, level: zoomLevel)
    }

    /// Drive a real clip view to each offset and, when asked, announce the live-scroll cycle around
    /// it. `announcingLiveScroll: false` is the negative control: the identical offsets are applied
    /// to the identical scroll view, and nothing is transcribed.
    private func liveScroll(
        to offsets: [CGFloat],
        announcingLiveScroll: Bool = true
    ) -> LiveScrollRecorder {
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 320, height: Self.viewportHeight)
        )
        scrollView.documentView = FlippedDocumentView(
            frame: NSRect(x: 0, y: 0, width: 320, height: Self.hourHeight * 24)
        )

        let recorder = LiveScrollRecorder()
        recorder.observe(scrollView)
        defer { recorder.stopObserving() }

        let center = NotificationCenter.default
        if announcingLiveScroll {
            center.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        }
        for offset in offsets {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            if announcingLiveScroll {
                center.post(name: NSScrollView.didLiveScrollNotification, object: scrollView)
            }
        }
        if announcingLiveScroll {
            center.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }
        return recorder
    }

    /// One fling down the timeline: `frames` evenly spaced samples covering 300pt, which at 50pt an
    /// hour is six hour boundaries.
    private func flingOffsets(frames: Int) -> [CGFloat] {
        let distance: CGFloat = 300
        return (1...frames).map { CGFloat($0) * distance / CGFloat(frames) }
    }

    /// The Today host's decision, threaded the way `SchedulePanelScrollPersistence` threads it.
    /// `remembering: false` drops the memory, which is what the code did before T-1498.
    private func adoptedHours(
        from offsets: [CGFloat],
        remembering: Bool = true,
        didRestoreScroll: Bool = true,
        isRestoringScroll: Bool = false
    ) -> [Int] {
        var last: Int?
        var adopted: [Int] = []
        for offset in offsets {
            guard let hour = SchedulePanelInteractionSupport.rememberedHourToPersist(
                yOffset: offset,
                geoHeight: Self.viewportHeight,
                zoomLevel: Self.zoomLevel,
                didRestoreScroll: didRestoreScroll,
                isRestoringScroll: isRestoringScroll,
                lastReportedHour: remembering ? last : nil
            ) else { continue }
            if remembering { last = hour }
            adopted.append(hour)
        }
        return adopted
    }

    /// The **calendar** host's decision — the smooth one — over the same offsets. Its own rule,
    /// `CalendarTimelineScrollSupport.clampedHour`, behind its own guard.
    private func calendarAdoptedHours(from offsets: [CGFloat]) -> [Int] {
        var visibleTimelineHour: Int?
        var adopted: [Int] = []
        for offset in offsets {
            let clampedHour = CalendarTimelineScrollSupport.clampedHour(
                offsetY: offset,
                hourHeight: Self.hourHeight
            )
            guard visibleTimelineHour != clampedHour else { continue }
            visibleTimelineHour = clampedHour
            adopted.append(clampedHour)
        }
        return adopted
    }

    // MARK: - The negative control, first

    /// **What makes every number below mean anything.** The same 60 offsets are applied to the same
    /// real `NSScrollView` with the live-scroll cycle suppressed, and the transcript is empty — so
    /// the offsets the counts are computed from are AppKit's report of a live scroll, not the test
    /// loop counting itself. This is [[T-1431]]'s control, which produced 0 writes the same way.
    @Test("Without the live-scroll cycle the same offsets transcribe nothing")
    func theTranscriptComesFromTheLiveScrollCycle() {
        let offsets = flingOffsets(frames: 60)

        let silent = liveScroll(to: offsets, announcingLiveScroll: false)
        #expect(silent.offsets.isEmpty)
        #expect(silent.startCount == 0)
        #expect(silent.endCount == 0)

        let live = liveScroll(to: offsets)
        #expect(live.offsets.count == 60)
        #expect(live.startCount == 1)
        #expect(live.endCount == 1)
        // AppKit's own answer, not the loop's: the clip view reports back what it accepted.
        #expect(live.offsets.last == 300)
    }

    // MARK: - The measurement the fix is answering

    /// **The before number.** Without the memory of the last hour — which is exactly what the panel
    /// had — a 60-frame fling adopts the report 60 times, once per frame. Each of those was an
    /// `@AppStorage` write, so each was a full `SchedulePanel` render.
    @Test("Ungated, one fling reports once per frame")
    func theUngatedPanelReportedOncePerFrame() {
        let transcript = liveScroll(to: flingOffsets(frames: 60))
        #expect(transcript.offsets.count == 60)

        let adopted = adoptedHours(from: transcript.offsets, remembering: false)

        #expect(adopted.count == transcript.offsets.count)
        #expect(adopted.count == 60)
    }

    /// **The after number, and the bound.** The same 60 frames, gated: 7 reports — the hour the
    /// fling started in, and the six boundaries it crossed — and they are in order and distinct.
    @Test("One fling is one report per hour crossed, not per frame")
    func theGatedPanelReportsOncePerHourCrossed() {
        let transcript = liveScroll(to: flingOffsets(frames: 60))

        let adopted = adoptedHours(from: transcript.offsets)

        #expect(adopted == [0, 1, 2, 3, 4, 5, 6])
        #expect(adopted.count == 7)
        #expect(adopted.count < transcript.offsets.count)
    }

    /// The difference between a bound and a coincidence: doubling the frame rate doubles the old
    /// number and leaves the new one alone. Nothing about the fix is tuned to 60.
    @Test("Twice the frames is still one report per hour crossed")
    func theReportCountDoesNotFollowTheFrameCount() {
        let coarse = liveScroll(to: flingOffsets(frames: 60))
        let fine = liveScroll(to: flingOffsets(frames: 120))

        #expect(adoptedHours(from: coarse.offsets, remembering: false).count == 60)
        #expect(adoptedHours(from: fine.offsets, remembering: false).count == 120)

        #expect(adoptedHours(from: coarse.offsets) == adoptedHours(from: fine.offsets))
        #expect(adoptedHours(from: fine.offsets).count == 7)
    }

    /// **The owner's own control, run as one.** The calendar page's timeline — the host the owner
    /// reports as smooth — put through the identical transcript with its identical arithmetic and
    /// its own guard, and it adopts the report exactly as often as the panel now does. Today's
    /// timeline was not doing more work because it draws something else; it was doing more work
    /// because it had no guard.
    @Test("The smooth host adopts the same transcript the same number of times")
    func theCalendarHostAdoptsTheSameTranscriptTheSameNumberOfTimes() {
        let transcript = liveScroll(to: flingOffsets(frames: 60))

        #expect(calendarAdoptedHours(from: transcript.offsets) == adoptedHours(from: transcript.offsets))
        #expect(calendarAdoptedHours(from: transcript.offsets).count == 7)
    }

    // MARK: - What the guard must never swallow

    /// A scroll the user made, landing on a new hour, still reports. Otherwise the panel would open
    /// on the wrong hour next launch, which is the whole reason the write exists.
    @Test("A report that names a new hour is still adopted")
    func aNewHourIsStillReported() {
        #expect(adoptedHours(from: [0, 260]) == [0, 5])
    }

    /// The gate that was already there, kept: the restore scrolls the panel itself, and adopting
    /// that would overwrite the very position being restored. It is a second negative control —
    /// the memory is switched off and the count is still zero, so it is the gate refusing and not
    /// the guard.
    @Test("Nothing is reported until the opening restore has finished")
    func theRestoreScrollIsNeverAdopted() {
        let offsets = liveScroll(to: flingOffsets(frames: 60)).offsets

        #expect(adoptedHours(from: offsets, remembering: false, didRestoreScroll: false).isEmpty)
        #expect(adoptedHours(from: offsets, remembering: false, isRestoringScroll: true).isEmpty)
    }

    // MARK: - Why the report count is the number that matters

    /// **REFUTED, and it is this ticket's own first guess that is refuted.**
    ///
    /// The obvious reading of the 60 above is *"sixty `@AppStorage` writes, so sixty `SchedulePanel`
    /// renders per fling"*. That reading is **wrong**, and it is wrong for a reason worth measuring
    /// rather than arguing: 53 of those 60 reports named an hour the key already held, and a
    /// `UserDefaults` key does **not** notify when it is written the value it already has.
    ///
    /// Measured here: sixty writes of one value notify **once**; sixty writes of sixty values notify
    /// **sixty** times. The second number is the control, without which the first could equally mean
    /// the observer never worked.
    ///
    /// **So what actually moves, stated at the size it is.** `UserDefaults` writes per fling go
    /// **60 → 1**, because the debounce executes one work item per settled gesture. Notifications —
    /// and so `SchedulePanel` invalidations from this path — go **7 → 1**, and those are the
    /// expensive ones: each re-ran a body that makes a full pass over every task in the store *and*
    /// an uncached `EKEventStore.events(matching:)` fetch. The **guard's** own saving is narrower
    /// and worth naming honestly: 60 → 7 schedule-and-cancel cycles, not 60 renders.
    ///
    /// **What this is NOT.** It is a measurement of the store, not of SwiftUI. It asserts no number
    /// of body evaluations, because this seat cannot count one — it removes a *claim* about them
    /// that would otherwise have gone into the ledger unmeasured.
    @Test("A defaults write of a value the key already holds does not notify")
    func anUnchangedDefaultsWriteDoesNotNotify() throws {
        // `withTemporaryDefaults`, not a suite named after a fresh `UUID()`: the name is derived
        // from this test so the backing plist is reused rather than multiplied (T-480), and
        // `CadenceTestTargetHygieneTests` fails the target for rolling its own.
        try withTemporaryDefaults("cadence.tests.scrollcost") { store in
            let key = "scheduleRememberedScrollHour"
            let observer = DefaultsKeyObserver(store: store, key: key)
            defer { observer.stopObserving() }

            for _ in 0..<60 { store.set(7, forKey: key) }
            let repeatedWrites = observer.notifications

            for hour in 0..<60 { store.set(hour, forKey: key) }
            let changingWrites = observer.notifications - repeatedWrites

            #expect(changingWrites == 60,
                    "the control: sixty distinct writes must notify sixty times, not \(changingWrites)")
            #expect(repeatedWrites == 1,
                    """
                    sixty writes of one value notified \(repeatedWrites) times. At 60 the ledger's \
                    refutation is wrong and the old per-frame write really was a per-frame render.
                    """)
        }
    }

    // MARK: - Neither host may lose its guard again

    /// Both halves, because this defect is a *missing* line and a missing line leaves no trace. The
    /// panel's guard is pinned here, and so is the calendar's — the control is only a control for
    /// as long as it stays guarded.
    @Test("Both hosts of the timeline canvas still refuse an unchanged scroll report")
    func bothHostsStillGuardTheirScrollReport() throws {
        let read = CadenceSourceScan.strippedSourceReader()

        let panel = try read("Cadence/macOS/Views/SchedulePanelInteractionSupport.swift")
        #expect(panel.contains("hour != lastReportedHour"),
                "the panel adopts every frame again")
        #expect(panel.contains("CalendarPageStateSupport.schedulePersistence"),
                "the panel writes @AppStorage undebounced again, or grew a second spelling of the debounce")

        let calendar = try read("Cadence/macOS/Views/CalendarPageSupportViews.swift")
        #expect(calendar.contains("guard visibleTimelineHour != clampedHour"),
                "the control host lost its guard, so it is no longer a control")

        // Non-vacuity: the panel's call site must actually thread the box, or the guard above is
        // reading a `lastReportedHour` that is `nil` on every frame.
        let host = try read("Cadence/macOS/Views/SchedulePanel.swift")
        #expect(host.contains("state: scrollPersistence"))
        #expect(host.contains("SchedulePanelScrollPersistence()"))
    }
}

/// **T-1498's other half, and the surfaces it does NOT explain.**
///
/// The owner widened the report to four laggy surfaces — the sidebar's lists, Today's timeline, All
/// Tasks as a list and All Tasks as a kanban — against one smooth control, the Calendar. Three
/// candidates were named for the common cause. Two of them are refused here by census, with the
/// control in the same table rather than in a paragraph, so nobody re-opens them.
@MainActor
struct SchedulePanelScrollCandidateCensusTests {

    /// **REFUTED: "a `@Query` over `AppTask` is what the laggy surfaces share."** `CalendarPageView`
    /// — the owner's smooth control — declares the byte-identical `@Query private var allTasks:
    /// [AppTask]` that `SidebarView` and `SchedulePanel` declare. A property three laggy surfaces
    /// share *with the smooth one* separates nothing.
    @Test("The smooth control declares the same unfiltered task query the laggy surfaces do")
    func theTaskQueryIsNotWhatSeparatesTheSurfaces() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let declaration = "@Query private var allTasks: [AppTask]"

        for path in [
            "Cadence/macOS/Views/SidebarView.swift",
            "Cadence/macOS/Views/SchedulePanel.swift",
            "Cadence/macOS/Views/CalendarPageView.swift"
        ] {
            let source = try read(path)
            #expect(source.contains(declaration), "\(path) no longer declares it")
        }
    }

    /// **REFUTED: "the eager `VStack` in the sidebar is the common cause."** It cannot be: All Tasks
    /// is `ScrollView { LazyVStack }` and is reported laggy anyway, while the calendar's month grid
    /// is `LazyVStack` and is reported smooth. Laziness does not sort the surfaces either way.
    ///
    /// The sidebar's eager stack is left standing as a *separate*, unmeasured candidate — see
    /// T-1500 — rather than folded into this one.
    @Test("Laziness does not separate the laggy surfaces from the smooth one")
    func containerLazinessIsNotWhatSeparatesTheSurfaces() throws {
        let read = CadenceSourceScan.strippedSourceReader()

        let allTasks = try read("Cadence/macOS/Views/TasksListView.swift")
        let monthGrid = try read("Cadence/macOS/Views/CalendarPageComponents.swift")
        let sidebar = try read("Cadence/macOS/Views/SidebarView.swift")

        #expect(allTasks.contains("LazyVStack"),
                "All Tasks is lazy and laggy, which is what refutes the eager stack")
        #expect(monthGrid.contains("LazyVStack"),
                "the smooth month grid is lazy too")
        #expect(sidebar.contains("LazyVStack") == false,
                "the sidebar became lazy without this census being revisited")
    }

    /// **REFUTED for three of the four surfaces: "a scroll-position binding writing through."** It
    /// is true of Today's timeline and it is the fix above. It is true of *nothing else* in the
    /// laggy set: the sidebar, All Tasks and the kanban observe no scroll geometry at all, so there
    /// is no per-frame write on them to find. Whatever they cost, they do not cost it this way.
    @Test("Only Today's timeline writes anything from a scroll report")
    func onlyTheTimelineObservesItsOwnScroll() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let observers = ["onScrollGeometryChange", ".scrollPosition(", "onScrollPhaseChange"]

        for path in [
            "Cadence/macOS/Views/SidebarView.swift",
            "Cadence/macOS/Views/TasksListView.swift",
            "Cadence/macOS/Views/TasksPanel.swift",
            "Cadence/macOS/Views/KanbanListColumnView.swift",
            "Cadence/macOS/Views/KanbanSectionColumnView.swift"
        ] {
            let source = try read(path)
            for observer in observers {
                #expect(source.contains(observer) == false, "\(path) grew \(observer)")
            }
        }

        let timeline = try read("Cadence/macOS/Views/SchedulePanel.swift")
        #expect(timeline.contains("onScrollGeometryChange"),
                "the one surface this census says does observe its scroll no longer does")
    }
}
#endif
