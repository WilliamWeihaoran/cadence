#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Records a real `NSScrollView`'s live-scroll cycle on the **horizontal** axis.
///
/// Selector-based and reading the clip view *inside* the notification, for the same reason
/// `SchedulePanelScrollWorkRateTests` does it that way: the offsets counted below have to be
/// AppKit's report of a live scroll rather than this test's own loop counting itself.
@MainActor
private final class HorizontalLiveScrollRecorder: NSObject {
    /// `contentView.bounds.origin.x`, once per `didLiveScroll`.
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
        offsets.append(scrollView.contentView.bounds.origin.x)
    }

    @objc private func didEndLiveScroll(_ note: Notification) {
        endCount += 1
    }
}

/// Everything one horizontal fling costs the persistence path, counted rather than described.
///
/// Each field is one observable event of `CalendarPageView`'s real call site: `cancelPending` is
/// `pendingDayPersistence?.cancel()`, `storePending` is a write to that **`@State`** property, and
/// `persistedKeys` is what actually reached `@AppStorage("calendarRememberedTimelineDateKey")`.
private final class DayPersistenceTranscript {
    var reports = 0
    var cancels = 0
    /// Writes into the pending box *while the gesture is live*. The settled work item clears the
    /// box once more as it runs, and that one is not scroll-rate churn, so it is held apart.
    var storePendingWrites = 0
    var storePendingWritesDuringScroll = 0
    var persistedKeys: [String] = []
}

/// **T-1498's remaining half: the timeline's HORIZONTAL axis.**
///
/// The ticket landed a last-reported-value guard on Today's panel (vertical, hours) and left the
/// calendar timeline's *day* axis exactly as it was. That axis had a guard, but on the wrong
/// thing: `CalendarTimelineDayScroller` refused an unchanged `visibleTimelineDayIndex` **binding**
/// and then called persistence *below* that guard, so the call ran on every changed pixel of
/// `contentOffset.x`.
///
/// **What is asserted here is a COUNT, never a duration** — CI runs Xcode 26 and this Mac runs 27
/// ([[T-1279]]/[[T-1296]]). The counts are of events this seat can actually observe: calls into
/// `CalendarPageInteractionSupport.persistVisibleTimelineDay`, work-item cancellations, writes
/// into the page's `@State` pending box, and keys that reached the store. **No body evaluation is
/// counted anywhere**, because this seat cannot count one — the same refusal the first half of
/// this ticket recorded.
///
/// **The before and the after come out of one transcript through one code path.** Passing
/// `lastReportedDay: nil` at every report reproduces the old behaviour exactly, because the old
/// code had no memory of the last day.
@MainActor
struct CalendarTimelineHorizontalScrollWorkRateTests {

    // MARK: - The transcript

    private static let colWidth: CGFloat = 50
    private static let viewportWidth: CGFloat = 320
    private static let calendar = Calendar.current
    private static var bufferStart: Date { calendar.startOfDay(for: Date()) }
    private static let todayDayIdx = 0

    /// Drive a real clip view to each offset and, when asked, announce the live-scroll cycle
    /// around it. `announcingLiveScroll: false` is the negative control: identical offsets, the
    /// identical scroll view, and nothing transcribed.
    private func liveScroll(
        to offsets: [CGFloat],
        announcingLiveScroll: Bool = true
    ) -> HorizontalLiveScrollRecorder {
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: Self.viewportWidth, height: 400)
        )
        scrollView.documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: Self.colWidth * 40, height: 400)
        )

        let recorder = HorizontalLiveScrollRecorder()
        recorder.observe(scrollView)
        defer { recorder.stopObserving() }

        let center = NotificationCenter.default
        if announcingLiveScroll {
            center.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        }
        for offset in offsets {
            scrollView.contentView.scroll(to: NSPoint(x: offset, y: 0))
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

    /// One fling across the timeline: `frames` evenly spaced samples covering 300pt, which at a
    /// 50pt column is six day boundaries.
    private func flingOffsets(frames: Int) -> [CGFloat] {
        let distance: CGFloat = 300
        return (1...frames).map { CGFloat($0) * distance / CGFloat(frames) }
    }

    /// The shipping decision, threaded the way `CalendarTimelineScrollState` threads it.
    /// `remembering: false` drops the memory, which is what the code did before this change.
    private func adoptedDays(
        from offsets: [CGFloat],
        remembering: Bool = true,
        didRestoreTimelineScroll: Bool = true,
        startingFrom seed: Int? = nil
    ) -> [Int] {
        var last = seed
        var adopted: [Int] = []
        for offset in offsets {
            let clampedDay = CalendarTimelineScrollSupport.clampedDayIndex(
                offsetX: offset,
                colWidth: Self.colWidth
            )
            guard let day = CalendarTimelineScrollSupport.dayToPersist(
                clampedDay: clampedDay,
                didRestoreTimelineScroll: didRestoreTimelineScroll,
                lastReportedDay: remembering ? last : nil
            ) else { continue }
            if remembering { last = day }
            adopted.append(day)
        }
        return adopted
    }

    /// The whole call site, run for real: the shipping decision in front of the page's own
    /// `persistVisibleTimelineDay`, with every closure the page passes replaced by a counter that
    /// does what the page's closure does. The debounced work item is executed at the end, which
    /// is what a settled gesture does to it.
    private func drivePersistence(
        over offsets: [CGFloat],
        remembering: Bool
    ) -> DayPersistenceTranscript {
        let transcript = DayPersistenceTranscript()
        var pending: DispatchWorkItem?
        var last: Int?

        for offset in offsets {
            let clampedDay = CalendarTimelineScrollSupport.clampedDayIndex(
                offsetX: offset,
                colWidth: Self.colWidth
            )
            guard let day = CalendarTimelineScrollSupport.dayToPersist(
                clampedDay: clampedDay,
                didRestoreTimelineScroll: true,
                lastReportedDay: remembering ? last : nil
            ) else { continue }
            if remembering { last = day }

            transcript.reports += 1
            CalendarPageInteractionSupport.persistVisibleTimelineDay(
                dayIndex: day,
                calendar: Self.calendar,
                bufferStart: Self.bufferStart,
                cancelPending: {
                    transcript.cancels += 1
                    pending?.cancel()
                },
                storePending: { item in
                    transcript.storePendingWrites += 1
                    pending = item
                },
                persist: { key in
                    transcript.persistedKeys.append(key)
                }
            )
        }

        transcript.storePendingWritesDuringScroll = transcript.storePendingWrites
        // The settled gesture: the surviving work item is the one `asyncAfter` would have run.
        pending?.perform()
        return transcript
    }

    // MARK: - The negative control, first

    /// **What makes every number below mean anything.** The same 60 offsets applied to the same
    /// real `NSScrollView` with the live-scroll cycle suppressed transcribe nothing, so the
    /// offsets the counts are computed from are AppKit's report of a live scroll.
    @Test("Without the live-scroll cycle the same horizontal offsets transcribe nothing")
    func theTranscriptComesFromTheLiveHorizontalScrollCycle() {
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

    /// **The before number.** Without a memory of the last persisted day — which is exactly what
    /// the horizontal axis had — a 60-frame fling hands persistence the day 60 times, once per
    /// frame.
    @Test("Ungated, one horizontal fling reports once per frame")
    func theUngatedScrollerReportedOncePerFrame() {
        let transcript = liveScroll(to: flingOffsets(frames: 60))
        #expect(transcript.offsets.count == 60)

        let adopted = adoptedDays(from: transcript.offsets, remembering: false)

        #expect(adopted.count == transcript.offsets.count)
        #expect(adopted.count == 60)
    }

    /// **The after number, and the bound.** The same 60 frames, guarded: 7 reports — the day the
    /// fling started in and the six boundaries it crossed — in order and distinct.
    @Test("One horizontal fling is one report per day crossed, not per frame")
    func theGuardedScrollerReportsOncePerDayCrossed() {
        let transcript = liveScroll(to: flingOffsets(frames: 60))

        let adopted = adoptedDays(from: transcript.offsets)

        #expect(adopted == [0, 1, 2, 3, 4, 5, 6])
        #expect(adopted.count == 7)
        #expect(adopted.count < transcript.offsets.count)
    }

    /// The difference between a bound and a coincidence: doubling the frame rate doubles the old
    /// number and leaves the new one alone. Nothing about this guard is tuned to 60.
    @Test("Twice the frames is still one horizontal report per day crossed")
    func theHorizontalReportCountDoesNotFollowTheFrameCount() {
        let coarse = liveScroll(to: flingOffsets(frames: 60))
        let fine = liveScroll(to: flingOffsets(frames: 120))

        #expect(adoptedDays(from: coarse.offsets, remembering: false).count == 60)
        #expect(adoptedDays(from: fine.offsets, remembering: false).count == 120)

        #expect(adoptedDays(from: coarse.offsets) == adoptedDays(from: fine.offsets))
        #expect(adoptedDays(from: fine.offsets).count == 7)
    }

    /// **The vertical axis of the same timeline, run as the control.** It has always guarded its
    /// report, and over the same transcript with the same arithmetic it adopts exactly as often as
    /// the horizontal axis now does. The two axes of one scroll view were doing different amounts
    /// of work for the same gesture, and now they are not.
    @Test("The already-guarded vertical axis adopts the same transcript the same number of times")
    func theVerticalAxisAdoptsTheSameTranscriptTheSameNumberOfTimes() {
        let transcript = liveScroll(to: flingOffsets(frames: 60))

        // `CalendarPageSupportViews`' rule, transcribed: clamp, then refuse an unchanged value.
        var visibleTimelineHour: Int?
        var verticalAdopted: [Int] = []
        for offset in transcript.offsets {
            let clampedHour = CalendarTimelineScrollSupport.clampedHour(
                offsetY: offset,
                hourHeight: Self.colWidth
            )
            guard visibleTimelineHour != clampedHour else { continue }
            visibleTimelineHour = clampedHour
            verticalAdopted.append(clampedHour)
        }

        #expect(verticalAdopted.count == adoptedDays(from: transcript.offsets).count)
        #expect(verticalAdopted.count == 7)
    }

    // MARK: - What the guard actually buys, at the size it is

    /// **The honest accounting, and it REFUTES the obvious reading of the 60 above.**
    ///
    /// *"Sixty reports, so sixty remembered-day writes"* is wrong, and the control that says so is
    /// in this same test: the page's writer is already debounced through
    /// `CalendarPageStateSupport.schedulePersistence`, so **one** key reaches the store per
    /// settled gesture either way — before the fix and after it. The defaults traffic does not
    /// move at all.
    ///
    /// What moves is everything the debounce does *not* collapse, and the first half of this
    /// ticket named it exactly: repeated cancellation, allocation and scheduling. Per fling,
    /// **60 → 7** for each of: calls into `persistVisibleTimelineDay` (each one a
    /// `DateFormatters.dateKey` format), `pendingDayPersistence?.cancel()`, and writes into
    /// `pendingDayPersistence` — which is a **`@State` property of `CalendarPageView`**, the
    /// heaviest view on the page.
    ///
    /// **What this is NOT.** It is not a render count. This seat cannot evaluate a SwiftUI body,
    /// so the `@State` write is counted as a write and the sentence stops there.
    @Test("The guard removes scheduling churn, and the store traffic was already one either way")
    func theGuardRemovesSchedulingChurnRatherThanDefaultsWrites() {
        let offsets = liveScroll(to: flingOffsets(frames: 60)).offsets

        let before = drivePersistence(over: offsets, remembering: false)
        let after = drivePersistence(over: offsets, remembering: true)

        #expect(before.reports == 60)
        #expect(before.cancels == 60)
        #expect(before.storePendingWritesDuringScroll == 60)

        #expect(after.reports == 7)
        #expect(after.cancels == 7)
        #expect(after.storePendingWritesDuringScroll == 7)

        // The settled work item clears the box as it runs, on both sides. Counted so the number
        // above is the scroll-rate churn and nothing else.
        #expect(before.storePendingWrites == 61)
        #expect(after.storePendingWrites == 8)

        // The refutation, with both sides measured rather than one side argued: the debounce was
        // already collapsing the store traffic, so this fix does not touch it.
        #expect(before.persistedKeys.count == 1,
                """
                the debounce no longer collapses the gesture — it let \
                \(before.persistedKeys.count) keys through, and the paragraph above is wrong
                """)
        #expect(after.persistedKeys.count == 1)
    }

    // MARK: - What the guard must never swallow

    /// **The restore behaviour, pinned to the value and not to the count.** The remembered day
    /// exists so the timeline reopens where the user left it. The guarded path must persist the
    /// *same* day the ungated path did — the one the fling settled on — and that day must survive
    /// the round trip back through `CalendarPageStateSupport.rememberedTimelineDayIndex`.
    @Test("The guarded path remembers the same day the ungated path did")
    func theRememberedDaySurvivesTheGuard() throws {
        let offsets = liveScroll(to: flingOffsets(frames: 60)).offsets

        let before = drivePersistence(over: offsets, remembering: false)
        let after = drivePersistence(over: offsets, remembering: true)

        #expect(after.persistedKeys == before.persistedKeys)

        let restored = CalendarPageStateSupport.rememberedTimelineDayIndex(
            rememberedDateKey: try #require(after.persistedKeys.last),
            bufferStart: Self.bufferStart,
            todayDayIdx: Self.todayDayIdx,
            calendar: Self.calendar
        )
        #expect(restored == 6, "the fling settled on day 6 and the page must reopen there")
    }

    /// **Why the memory is its own box and not the `visibleTimelineDayIndex` binding.**
    ///
    /// Folding the persist into the binding's existing `if` reads like the same fix and loses a
    /// day. The binding is written by the jump paths — `applyTodayHorizontalJump`,
    /// `applyExternalHorizontalJump`, `setTimelineMode`, `handleViewModeChange` — so after any of
    /// them every scroll report already matches the binding and the naive guard persists nothing.
    ///
    /// Both variants are run over the same offsets here, so the difference is the guard and not
    /// the transcript.
    @Test("A day the binding has already seen but persistence has not is still persisted")
    func aDayTheBindingAlreadyHoldsIsStillPersisted() {
        // A jump parked the view on day 6; persistence last saw day 0. Ten frames of settling
        // inside day 6 follow.
        let offsets: [CGFloat] = (0..<10).map { 300 + CGFloat($0) }
        let jumpedTo = 6

        // The naive variant: guard the persist on the binding.
        var binding: Int? = jumpedTo
        var naive: [Int] = []
        for offset in offsets {
            let clampedDay = CalendarTimelineScrollSupport.clampedDayIndex(
                offsetX: offset,
                colWidth: Self.colWidth
            )
            guard binding != clampedDay else { continue }
            binding = clampedDay
            naive.append(clampedDay)
        }

        #expect(naive.isEmpty,
                "the naive guard must be shown losing the day, or this test proves nothing")

        // The shipped variant: guard on what persistence last saw.
        #expect(adoptedDays(from: offsets, startingFrom: 0) == [6])
    }

    /// **The hazard this guard creates, closed and then pinned.** A jump writes `anchorDateKey`
    /// itself, so after one the box's memory is of a day persistence no longer agrees with. Land
    /// the jump one column away from that remembered day, scroll back onto it, and a guard that
    /// kept its memory would refuse the only report that could correct the anchor — the timeline
    /// would reopen on the jump's day instead of where the user left it.
    ///
    /// Both halves are here: the stale memory is shown swallowing the report, and the two places
    /// that move the scroll without a report — `jumpHorizontally` and the scroller's `onAppear`
    /// restore — are pinned as dropping it. `jumpHorizontally` needs a live `ScrollViewProxy`,
    /// which this seat cannot build, so its half is a source pin rather than a call.
    @Test("A horizontal jump drops the remembered day so a scroll back onto it still persists")
    func aJumpDropsTheRememberedDay() throws {
        // Persistence last saw day 6; a jump parks the view on day 7; the user scrolls one
        // column back onto day 6.
        let backOntoDaySix: [CGFloat] = [300]

        // Had the jump kept the memory, the one report that matters would be refused.
        #expect(adoptedDays(from: backOntoDaySix, startingFrom: 6).isEmpty,
                "a kept memory must be shown swallowing the report, or this test proves nothing")

        // Dropped, it gets through — and the state's own default is the dropped one.
        #expect(CalendarTimelineScrollState().lastReportedDay == nil)
        #expect(adoptedDays(from: backOntoDaySix, startingFrom: nil) == [6])

        let read = CadenceSourceScan.strippedSourceReader()
        let support = try read("Cadence/macOS/Views/CalendarTimelineScrollSupport.swift")
        #expect(support.contains("scrollState.lastReportedDay = nil"),
                "jumpHorizontally keeps a memory the jump just invalidated")

        let scroller = try read("Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift")
        #expect(scroller.contains("timelineScrollState.lastReportedDay = nil"),
                "the opening restore keeps a memory from the previous appearance")
    }

    /// The gate that was already there, kept: nothing is persisted until the opening restore has
    /// finished, or the restore would overwrite the very position it is restoring. A second
    /// negative control — the memory is switched off and the count is still zero, so it is the
    /// gate refusing and not the guard.
    @Test("Nothing is persisted until the opening timeline restore has finished")
    func theRestoreScrollIsNeverPersisted() {
        let offsets = liveScroll(to: flingOffsets(frames: 60)).offsets

        #expect(adoptedDays(
            from: offsets,
            remembering: false,
            didRestoreTimelineScroll: false
        ).isEmpty)
    }

    // MARK: - Neither axis may lose its guard again

    /// This defect is a *missing* line, and a missing line leaves no trace. Both axes of the
    /// timeline are pinned, and so is the call site threading the box — without the box the guard
    /// reads a `lastReportedDay` that is `nil` on every frame, which is the old behaviour wearing
    /// the new code's shape.
    @Test("Both axes of the calendar timeline still refuse an unchanged scroll report")
    func bothAxesStillGuardTheirScrollReport() throws {
        let read = CadenceSourceScan.strippedSourceReader()

        let support = try read("Cadence/macOS/Views/CalendarTimelineScrollSupport.swift")
        #expect(support.contains("clampedDay != lastReportedDay"),
                "the horizontal axis persists on every changed pixel again")

        let scroller = try read("Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift")
        #expect(scroller.contains("CalendarTimelineScrollSupport.persistVisibleDay"),
                "the day scroller calls persistence directly again")
        #expect(scroller.contains("state: timelineScrollState"),
                "the guard is reading a lastReportedDay that is nil on every frame")

        let state = try read("Cadence/macOS/Views/CalendarTimelineSupport.swift")
        #expect(state.contains("var lastReportedDay: Int?"),
                "the memory the guard reads is gone")

        let vertical = try read("Cadence/macOS/Views/CalendarPageSupportViews.swift")
        #expect(vertical.contains("guard visibleTimelineHour != clampedHour"),
                "the vertical axis lost its guard, so it is no longer a control")
    }
}
#endif
