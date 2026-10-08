import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// The timed calendar grid's zoom: a real multiplier, not a label.
///
/// The control this replaces was `− 1x +` over `base + (zoom − 1) × 16`, so its "3x" produced 90pt
/// against a 58pt base — about 1.55×. Three discrete steps hid that; a continuous pinch would not
/// have. These pin the decision that the number and the behaviour now agree.
struct CadenceCalendarZoomTests {
    /// The two bases `iOSCalendarTimelineGrid` uses.
    private static let compactBase: CGFloat = 58
    private static let regularBase: CGFloat = 64

    @Test
    func zoomIsAMultiplierOfTheBaseHourHeight() {
        #expect(CadenceCalendarZoom.hourHeight(base: Self.compactBase, zoom: 1) == 58)
        #expect(CadenceCalendarZoom.hourHeight(base: Self.compactBase, zoom: 3) == 174)
        #expect(CadenceCalendarZoom.hourHeight(base: Self.regularBase, zoom: 1) == 64)
        #expect(CadenceCalendarZoom.hourHeight(base: Self.regularBase, zoom: 3) == 192)
    }

    /// The specific thing the old control got wrong, stated as a test so it cannot come back: the
    /// top of the range is three times the bottom, not the bottom plus a constant.
    @Test
    func theTopOfTheRangeIsThreeTimesTheBottom() {
        for base in [Self.compactBase, Self.regularBase] {
            let low = CadenceCalendarZoom.hourHeight(base: base, zoom: CadenceCalendarZoom.minimum)
            let high = CadenceCalendarZoom.hourHeight(base: base, zoom: CadenceCalendarZoom.maximum)
            #expect(high == low * 3)
            // And the old formula's "3x" is well inside the new range, not at its top.
            #expect(base + 32 < high)
        }
    }

    @Test
    func zoomClampsAtBothEnds() {
        #expect(CadenceCalendarZoom.clamp(0.2) == 1)
        #expect(CadenceCalendarZoom.clamp(9) == 3)
        #expect(CadenceCalendarZoom.clamp(2.4) == 2.4)
        #expect(CadenceCalendarZoom.clamp(.nan) == CadenceCalendarZoom.defaultZoom)
    }

    /// A pinch past a stop and back returns where it was. The clamp is on the *result*, so the
    /// excess is never accumulated into the stored zoom and the grid does not drift.
    @Test
    func pinchingPastAStopAndBackReturnsToWhereItWas() {
        #expect(CadenceCalendarZoom.zoom(startingFrom: 2, magnification: 4) == 3)
        #expect(CadenceCalendarZoom.zoom(startingFrom: 2, magnification: 0.1) == 1)
        #expect(CadenceCalendarZoom.zoom(startingFrom: 2, magnification: 1) == 2)
        #expect(CadenceCalendarZoom.zoom(startingFrom: 2, magnification: 1.25) == 2.5)
        // A degenerate magnification cannot move the zoom.
        #expect(CadenceCalendarZoom.zoom(startingFrom: 1.5, magnification: 0) == 1.5)
    }

    /// The point held between the fingers stays between the fingers.
    ///
    /// Stated as the property rather than as a number: whatever content point was at `focusY` on
    /// screen is at `focusY` on screen afterwards.
    @Test
    func theHourUnderTheFingersStaysUnderTheFingers() {
        let focusY: CGFloat = 240
        let offset: CGFloat = 600
        let scale: CGFloat = 1.75
        let newOffset = CadenceCalendarZoom.anchoredVerticalOffset(
            currentOffset: offset,
            focusY: focusY,
            scale: scale,
            contentHeight: 24 * 58 * scale,
            viewportHeight: 500
        )
        let heldBefore = offset + focusY
        let heldAfterOnScreen = heldBefore * scale - newOffset
        #expect(abs(heldAfterOnScreen - focusY) < 0.01)
    }

    /// And it never asks the scroll view for an offset it cannot have — a clamp the scroll view
    /// would otherwise apply silently, leaving the anchoring maths describing a position the grid
    /// is not in.
    @Test
    func theAnchoredOffsetStaysInsideTheScrollableRange() {
        let zoomedOut = CadenceCalendarZoom.anchoredVerticalOffset(
            currentOffset: 40,
            focusY: 10,
            scale: 0.2,
            contentHeight: 400,
            viewportHeight: 500
        )
        #expect(zoomedOut == 0)

        let zoomedIn = CadenceCalendarZoom.anchoredVerticalOffset(
            currentOffset: 5_000,
            focusY: 300,
            scale: 3,
            contentHeight: 1_392,
            viewportHeight: 500
        )
        let maximumOffset: CGFloat = 1_392 - 500
        #expect(zoomedIn == maximumOffset, "got \(zoomedIn), wanted \(maximumOffset)")
    }

    /// Settings and the pinch are two ends of **one** preference, and they drifted because
    /// Settings re-spelled the key as a literal and declared it `Int`. A stored `1.5` read back
    /// there as `1`: the wrong density shown, and a coarse integer written over a continuous zoom
    /// the moment the row was touched. So the literal may appear exactly once in shipping
    /// source — on `CadenceCalendarZoom.storageKey` — and both readers go through it. T-392.
    @Test
    func theZoomKeyIsSpelledOnceInShippingSource() throws {
        let sourceRoot = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence")
        let enumerator = try #require(
            FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        )

        // `matchCount` answers -1 for a pattern that does not compile, which a `== 0` assertion
        // would sail straight past. Prove the pattern finds the literal before trusting a miss.
        let pattern = "\"ios\\.calendar\\.zoomLevel\""
        #expect(CadenceSourceScan.matchCount(pattern, in: "\"ios.calendar.zoomLevel\"") == 1)
        #expect(CadenceSourceScan.matchCount(pattern, in: "CadenceCalendarZoom.storageKey") == 0)

        var scannedFiles = 0
        var strippedSomething = false
        var keptItsLength = true
        var spellings: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scannedFiles += 1
            let raw = try String(contentsOf: url, encoding: .utf8)
            let code = CadenceSourceScan.strippingComments(raw)
            if code != raw { strippedSomething = true }
            if code.count != raw.count { keptItsLength = false }
            for _ in 0..<max(0, CadenceSourceScan.matchCount(pattern, in: code)) {
                spellings.append(url.lastPathComponent)
            }
        }

        // Non-vacuity: a scan that read nothing, or stripped nothing, proves nothing. The
        // stripper blanks comments to spaces of equal length, so the pair is `!=` and `count ==`.
        #expect(scannedFiles > 400, "the scan read only \(scannedFiles) Swift files")
        #expect(strippedSomething, "the comment stripper never fired, so it read prose as code")
        #expect(keptItsLength, "the comment stripper changed a file's length, so it is not blanking")
        #expect(spellings == ["CadenceCalendarTimedGridSupport.swift"], "got \(spellings)")
    }

    /// The other half of the drift: the type. Settings' picker binding is a SwiftUI `@Binding`
    /// inside an iOS-only view, which the macOS test target cannot reach, so this reads it.
    @Test
    func theSettingsDensityPickerIsBoundAsADouble() throws {
        // Needle self-check: it must match the spelling being banned and must not match the one
        // being required, or a `== 0` result says nothing about the file.
        #expect(CadenceSourceScan.matchCount("calendarZoomLevel: Int\\b", in: "var calendarZoomLevel: Int") == 1)
        #expect(CadenceSourceScan.matchCount("calendarZoomLevel: Int\\b", in: "var calendarZoomLevel: Double") == 0)
        #expect(CadenceSourceScan.matchCount("calendarZoomLevel = 1\\b", in: "var calendarZoomLevel = 1") == 1)
        #expect(
            CadenceSourceScan.matchCount(
                "calendarZoomLevel = 1\\b",
                in: "var calendarZoomLevel = CadenceCalendarZoom.defaultZoom"
            ) == 0
        )

        for path in [
            "Cadence/iOS/iOSSettingsView.swift",
            "Cadence/iOS/iOSSettingsOverviewSections.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let source = CadenceSourceScan.strippingComments(raw)
            #expect(source != raw, "the comment stripper never fired on \(path)")
            #expect(source.count == raw.count, "the comment stripper changed \(path)'s length")
            #expect(source.contains("calendarZoomLevel"), "\(path) no longer mentions the zoom binding")
            #expect(
                CadenceSourceScan.matchCount("calendarZoomLevel: Int\\b", in: source) == 0,
                "\(path) still types the shared zoom preference as an Int"
            )
            #expect(
                CadenceSourceScan.matchCount("calendarZoomLevel = 1\\b", in: source) == 0,
                "\(path) still defaults the shared zoom preference to an Int literal"
            )
        }
    }

    /// **The decision, pinned:** the picker does not snap. A pinch writes a continuous multiplier,
    /// and a value between two presets is preserved and reported as Custom — with no density row
    /// checked — until the user picks one. Rounding it into the nearest density would be the same
    /// lie the `Int` binding told, one step quieter.
    @Test
    func aPinchedZoomIsPreservedAndReadsAsCustomRatherThanSnapping() {
        #expect(CadenceCalendarZoom.densityTitle(for: 1) == "Compact")
        #expect(CadenceCalendarZoom.densityTitle(for: 2) == "Comfort")
        #expect(CadenceCalendarZoom.densityTitle(for: 3) == "Spacious")

        for pinched in [1.2, 1.5, 2.4, 2.99] {
            #expect(
                CadenceCalendarZoom.densityPreset(matching: pinched) == nil,
                "\(pinched) was matched to a preset it is not at"
            )
            #expect(CadenceCalendarZoom.densityTitle(for: pinched) == CadenceCalendarZoom.customDensityTitle)
            // Preserved, not snapped: nothing about naming it rewrites it.
            #expect(CadenceCalendarZoom.clamp(pinched) == pinched)
        }
    }

    /// Every preset the picker offers is a zoom the grid can actually be at, and picking one
    /// writes a value that reads back as that same preset.
    @Test
    func everyDensityPresetIsALegalZoomThatRoundTrips() {
        #expect(CadenceCalendarZoom.densityPresets.count == 3)
        #expect(Set(CadenceCalendarZoom.densityPresets.map(\.title)).count == 3)
        for preset in CadenceCalendarZoom.densityPresets {
            #expect(CadenceCalendarZoom.clamp(preset.zoom) == preset.zoom)
            #expect(CadenceCalendarZoom.densityPreset(matching: preset.zoom)?.title == preset.title)
        }
        #expect(CadenceCalendarZoom.densityPresets.first?.zoom == CadenceCalendarZoom.defaultZoom)
        #expect(CadenceCalendarZoom.densityPresets.last?.zoom == CadenceCalendarZoom.maximum)
    }

    /// The migration, **observed rather than assumed**.
    ///
    /// `ios.calendar.zoomLevel` held an `Int` written by the `− 1x +` control, and the property that
    /// reads it is now a `Double`. If an `Int`-backed key did not read back as a `Double`, every
    /// upgrading user would land on the default instead of the zoom they set. It does, and 1/2/3 are
    /// all inside the new 1…3 range, which is why the key did not have to be versioned.
    @MainActor
    @Test
    func zoomStoredByTheOldIntegerControlStillReads() throws {
        try withTemporaryDefaults("CadenceTests.calendarZoomMigration") { defaults in
            for stored in [1, 2, 3] {
                defaults.set(stored, forKey: CadenceCalendarZoom.storageKey)
                let storage = AppStorage(
                    wrappedValue: CadenceCalendarZoom.defaultZoom,
                    CadenceCalendarZoom.storageKey,
                    store: defaults
                )
                #expect(storage.wrappedValue == Double(stored), "Int \(stored) did not read back as a Double")
                #expect(CadenceCalendarZoom.clamp(storage.wrappedValue) == Double(stored))
            }

            // And an unset key still falls back to the default rather than to zero.
            defaults.removeObject(forKey: CadenceCalendarZoom.storageKey)
            let fresh = AppStorage(
                wrappedValue: CadenceCalendarZoom.defaultZoom,
                CadenceCalendarZoom.storageKey,
                store: defaults
            )
            #expect(fresh.wrappedValue == CadenceCalendarZoom.defaultZoom)
        }
    }
}

/// The window of day columns the timed grid scrolls through.
///
/// The grid used to render exactly the days `CadenceScheduleSupport.dates(containing:mode:)` built,
/// so scrolling sideways reached nothing. These pin the replacement: a wide run of columns with the
/// anchor near its middle, recentred as a scroll approaches either end.
struct CadenceCalendarTimelineWindowTests {
    private let calendar = Calendar.current

    private func date(_ key: String) throws -> Date {
        try #require(DateFormatters.date(from: key))
    }

    /// The snap that makes Week open on a week. Without it the leading column would be whatever
    /// day the anchor happened to be, and "Week" would mean seven days starting on a Thursday.
    @Test
    func theWindowStartsOnAWeekBoundary() throws {
        for key in ["2026-08-17", "2026-08-19", "2026-01-01", "2026-12-31"] {
            let start = CadenceCalendarTimelineWindow.windowStart(for: try date(key), calendar: calendar)
            #expect(
                calendar.isDate(
                    start,
                    inSameDayAs: CadenceScheduleSupport.startOfWeek(containing: start, calendar: calendar)
                ),
                "window start for \(key) was not a week start"
            )
        }
    }

    /// A date maps to a column and back to the same date. This is the arithmetic the toolbar's date
    /// button and the scroll offset both go through, so a drift here is a title naming the wrong day.
    @Test
    func aDateRoundTripsThroughItsColumnIndex() throws {
        let anchor = try date("2026-08-19")
        let start = CadenceCalendarTimelineWindow.windowStart(for: anchor, calendar: calendar)
        for offset in [-30, -7, -1, 0, 1, 7, 30, 120] {
            let subject = try #require(calendar.date(byAdding: .day, value: offset, to: anchor))
            let index = CadenceCalendarTimelineWindow.index(for: subject, windowStart: start, calendar: calendar)
            let resolved = CadenceCalendarTimelineWindow.date(at: index, windowStart: start, calendar: calendar)
            #expect(calendar.isDate(resolved, inSameDayAs: subject), "offset \(offset) did not round trip")
        }
    }

    // MARK: - Keeping the selected day on screen (T-439)

    /// The rule this used to state inside `iOSCalendarView.keepSelectedDateInView()`, where no test
    /// could reach it: the selection moves **only** when it has left the visible span, and it lands
    /// on the leading day.
    @Test
    func theSelectionMovesOnlyOnceItHasLeftTheVisibleSpan() throws {
        let leading = try date("2026-08-16")

        // Inside a seven-column week: left alone, and said so as `nil` rather than as the same date
        // handed back — a caller that wrote the answer into `@State` on every column is the write
        // storm `CadenceCalendarDateMemory` records.
        for key in ["2026-08-16", "2026-08-19", "2026-08-22"] {
            let selected = try date(key)
            let answer = CadenceCalendarTimelineWindow.selectionKeptInView(
                selectedDate: selected,
                leadingDate: leading,
                visibleDayCount: 7,
                calendar: calendar
            )
            #expect(answer == nil, "\(key) is on screen and was moved anyway")
        }

        // Off either end: snapped to the leading column.
        for key in ["2026-08-15", "2026-08-01", "2026-08-23", "2026-09-30"] {
            let selected = try date(key)
            let moved = try #require(
                CadenceCalendarTimelineWindow.selectionKeptInView(
                    selectedDate: selected,
                    leadingDate: leading,
                    visibleDayCount: 7,
                    calendar: calendar
                ),
                "\(key) is off screen and was left there"
            )
            #expect(calendar.isDate(moved, inSameDayAs: leading))
        }
    }

    /// Both edges are *visible*, so neither is dragged to the leading column. `2026-08-22` is the
    /// seventh day of a window starting on the sixteenth; an off-by-one either way shows up here
    /// and nowhere else.
    @Test
    func aSelectionOnEitherEdgeOfTheSpanIsLeftWhereItIs() throws {
        let leading = try date("2026-08-16")
        #expect(CadenceCalendarTimelineWindow.selectionKeptInView(
            selectedDate: leading, leadingDate: leading, visibleDayCount: 7, calendar: calendar
        ) == nil)
        let trailingEdge = try date("2026-08-22")
        #expect(CadenceCalendarTimelineWindow.selectionKeptInView(
            selectedDate: trailingEdge, leadingDate: leading, visibleDayCount: 7, calendar: calendar
        ) == nil)
        // One day past the trailing edge is not.
        let pastTrailingEdge = try date("2026-08-23")
        #expect(CadenceCalendarTimelineWindow.selectionKeptInView(
            selectedDate: pastTrailingEdge, leadingDate: leading, visibleDayCount: 7, calendar: calendar
        ) != nil)
    }

    /// 2 Weeks is fourteen columns, so a day that Week would have pulled back stays put. The span is
    /// read from the count rather than assumed.
    @Test
    func theSpanIsAsWideAsTheGridSays() throws {
        let leading = try date("2026-08-16")
        let dayTen = try date("2026-08-25")
        #expect(CadenceCalendarTimelineWindow.selectionKeptInView(
            selectedDate: dayTen, leadingDate: leading, visibleDayCount: 7, calendar: calendar
        ) != nil)
        #expect(CadenceCalendarTimelineWindow.selectionKeptInView(
            selectedDate: dayTen,
            leadingDate: leading,
            visibleDayCount: CadenceCalendarWeekGridLayout.visibleDayCount(for: .twoWeeks),
            calendar: calendar
        ) == nil)
    }

    /// Times of day are not part of the decision: both ends are snapped to the start of their day,
    /// so an anchor carrying 23:59 does not push the last visible column back by one.
    @Test
    func theDecisionIsMadeOnDaysRatherThanOnInstants() throws {
        let leadingDay = try date("2026-08-16")
        let lastDay = try date("2026-08-22")
        let leading = try #require(calendar.date(byAdding: .hour, value: 23, to: leadingDay))
        let lastColumnLateAtNight = try #require(calendar.date(byAdding: .hour, value: 22, to: lastDay))
        #expect(CadenceCalendarTimelineWindow.selectionKeptInView(
            selectedDate: lastColumnLateAtNight,
            leadingDate: leading,
            visibleDayCount: 7,
            calendar: calendar
        ) == nil)
    }

    /// A **source scan**, because `iOSCalendarView` is under `Cadence/iOS/` and this target builds
    /// for macOS. The behaviour above is pinned by the tests; this pins that the view reaches it,
    /// which is the whole of what moving the rule bought.
    @Test
    func theCalendarPageNoLongerSpellsTheSpanArithmeticItself() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarView.swift")
        #expect(raw.count > 400, "the calendar page read as \(raw.count) characters")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper removed nothing")
        #expect(source.count == raw.count, "the stripper changed the length")
        #expect(source.contains("struct iOSCalendarView: View"), "the calendar page moved")

        let body = try #require(
            CadenceSourceScan.functionBody(named: "keepSelectedDateInView", in: source),
            "iOSCalendarView has no keepSelectedDateInView()"
        )
        #expect(body.contains("CadenceCalendarTimelineWindow.selectionKeptInView("),
                "the view still decides the span itself")
        // The gate stays: only the timed grids scroll their own days, and that is page state.
        #expect(body.contains("guard isTimedGrid else { return }"))
        #expect(body.contains("selectedDate = moved"))
        #expect(CadenceSourceScan.matchCount(#"byAdding:\s*\.day"#, in: body) == 0,
                "the view still does the day arithmetic")
        #expect(CadenceSourceScan.matchCount(#"startOfDay"#, in: body) == 0,
                "the view still snaps the dates itself")
    }

    /// Without this the two `== 0` assertions above are true of any text at all.
    @Test
    func theCalendarPageScanNeedlesAreNotVacuous() {
        #expect(CadenceSourceScan.matchCount(#"byAdding:\s*\.day"#,
                                             in: "calendar.date(byAdding: .day, value: 6, to: leading)") == 1)
        #expect(CadenceSourceScan.matchCount(#"byAdding:\s*\.day"#,
                                             in: "calendar.date(byAdding: .hour, value: 6, to: leading)") == 0)
        #expect(CadenceSourceScan.matchCount(#"startOfDay"#, in: "calendar.startOfDay(for: anchorDate)") == 1)
        #expect(CadenceSourceScan.matchCount(#"startOfDay"#, in: "calendar.isDate(a, inSameDayAs: b)") == 0)
    }

    /// The anchor sits far enough inside the run that a user can scroll a long way in either
    /// direction before anything has to be rebuilt. Half of it, less the week snap.
    @Test
    func thereIsRoomToScrollBackwardsAsWellAsForwards() throws {
        let anchor = try date("2026-08-19")
        let start = CadenceCalendarTimelineWindow.windowStart(for: anchor, calendar: calendar)
        let index = CadenceCalendarTimelineWindow.index(for: anchor, windowStart: start, calendar: calendar)
        #expect(index > 180)
        #expect(index < CadenceCalendarTimelineWindow.renderDayCount - 180)
    }

    @Test
    func aScrollOffsetResolvesToTheColumnAtTheLeadingEdge() {
        let width: CGFloat = 112
        #expect(CadenceCalendarTimelineWindow.leadingIndex(scrollOffsetX: 0, columnWidth: width) == 0)
        #expect(CadenceCalendarTimelineWindow.leadingIndex(scrollOffsetX: 112, columnWidth: width) == 1)
        // Rounded, not floored: a column dragged four fifths of the way off the leading edge is not
        // the one you are looking at.
        #expect(CadenceCalendarTimelineWindow.leadingIndex(scrollOffsetX: 200, columnWidth: width) == 2)
        // A negative offset is a rubber band, not a column before the first one.
        #expect(CadenceCalendarTimelineWindow.leadingIndex(scrollOffsetX: -60, columnWidth: width) == 0)
        #expect(CadenceCalendarTimelineWindow.leadingIndex(scrollOffsetX: 400, columnWidth: 0) == 0)
    }

    @Test
    func anIndexResolvesBackToTheOffsetThatPutsItAtTheLeadingEdge() {
        for index in [0, 1, 17, 209] {
            let offset = CadenceCalendarTimelineWindow.scrollOffsetX(forIndex: index, columnWidth: 112)
            #expect(CadenceCalendarTimelineWindow.leadingIndex(scrollOffsetX: offset, columnWidth: 112) == index)
        }
    }

    /// The built columns always cover what is on screen, with margin, and never run off either end
    /// of the window.
    @Test
    func theRenderedRunAlwaysCoversTheVisibleColumns() {
        let last = CadenceCalendarTimelineWindow.renderDayCount - 1
        for leading in [0, 1, 6, 210, last - 3, last] {
            for visible in [7, 14] {
                let range = CadenceCalendarTimelineWindow.renderedIndexRange(
                    leadingIndex: leading,
                    visibleDayCount: visible
                )
                #expect(range.lowerBound >= 0)
                #expect(range.upperBound <= CadenceCalendarTimelineWindow.renderDayCount)
                #expect(range.contains(leading), "leading column \(leading) was not built")
                let lastVisible = min(leading + visible - 1, last)
                #expect(range.contains(lastVisible), "column \(lastVisible) was not built")
            }
        }
    }

    /// Recentring is what makes "infinite" true rather than merely large — and it must not fire in
    /// the middle, where it would re-scroll the grid under a moving finger. That is the shape
    /// `ecaf80f` shipped.
    @Test
    func theWindowSlidesOnlyWhenAScrollNearsAnEndOfIt() throws {
        let anchor = try date("2026-08-19")
        let start = CadenceCalendarTimelineWindow.windowStart(for: anchor, calendar: calendar)
        let middle = CadenceCalendarTimelineWindow.index(for: anchor, windowStart: start, calendar: calendar)

        #expect(
            CadenceCalendarTimelineWindow.recenteredWindowStart(
                leadingIndex: middle,
                leadingDate: anchor,
                currentWindowStart: start,
                calendar: calendar
            ) == nil
        )

        let nearEndDate = CadenceCalendarTimelineWindow.date(at: 3, windowStart: start, calendar: calendar)
        let slid = CadenceCalendarTimelineWindow.recenteredWindowStart(
            leadingIndex: 3,
            leadingDate: nearEndDate,
            currentWindowStart: start,
            calendar: calendar
        )
        let rebuilt = try #require(slid)
        #expect(rebuilt < start)
        // And the day the user was looking at is still the day they are looking at.
        let reindexed = CadenceCalendarTimelineWindow.index(for: nearEndDate, windowStart: rebuilt, calendar: calendar)
        #expect(
            calendar.isDate(
                CadenceCalendarTimelineWindow.date(at: reindexed, windowStart: rebuilt, calendar: calendar),
                inSameDayAs: nearEndDate
            )
        )
    }

    /// The event fetch window covers every column that can be on screen, in both timed modes.
    @Test
    func theEventWindowCoversEveryVisibleColumn() throws {
        for key in ["2026-08-16", "2026-08-19", "2026-08-22"] {
            let leading = try date(key)
            let window = Set(
                CadenceCalendarTimelineWindow.eventWindowDates(leadingDate: leading, calendar: calendar)
                    .map { DateFormatters.dateKey(from: $0) }
            )
            for visible in [7, 14] {
                for offset in 0..<visible {
                    let day = try #require(calendar.date(byAdding: .day, value: offset, to: leading))
                    #expect(
                        window.contains(DateFormatters.dateKey(from: day)),
                        "leading \(key), \(visible) columns: day \(offset) was outside the fetch window"
                    )
                }
            }
        }
    }

    /// **T-570.** The inspected day is always inside the fetch window on a timed grid, whatever the
    /// selection started as.
    ///
    /// `iOSCalendarView.selectedEvents` reads the window cache and only falls back to a live query
    /// for a day the window does not hold. This is why the timed grids never take that fallback:
    /// the selection is held inside the visible span by `selectionKeptInView`, and the visible span
    /// is inside the window. Month has no such rule, which is what the fallback exists for —
    /// `CalendarMonthScrollWindowTests.aDayCarriedByTheSelectionCanLeaveTheMonthsEventWindow`.
    @Test
    func theKeptInViewSelectionIsAlwaysInsideTheFetchWindow() throws {
        let leading = try date("2026-08-19")
        let window = Set(
            CadenceCalendarTimelineWindow.eventWindowDates(leadingDate: leading, calendar: calendar)
                .map { DateFormatters.dateKey(from: $0) }
        )

        var everMoved = false
        for visible in [7, 14] {
            // A year either side, so the selection starts well outside the span far more often
            // than inside it.
            for offset in stride(from: -365, through: 365, by: 13) {
                let started = try #require(calendar.date(byAdding: .day, value: offset, to: leading))
                let settled = CadenceCalendarTimelineWindow.selectionKeptInView(
                    selectedDate: started,
                    leadingDate: leading,
                    visibleDayCount: visible,
                    calendar: calendar
                ) ?? started
                if !calendar.isDate(settled, inSameDayAs: started) { everMoved = true }
                #expect(
                    window.contains(DateFormatters.dateKey(from: settled)),
                    "\(visible) columns, offset \(offset): the inspected day is outside the fetch window"
                )
            }
        }
        // Non-vacuity: the rule actually fired, so this is not a walk over days that were already
        // in the span.
        #expect(everMoved)
    }

    /// And it only changes identity once a week, which is the whole reason it is coarse: the grid
    /// writes its leading column back on every column scrolled past, and a fetch window that moved
    /// with it would re-query EventKit several times a second, mid-gesture.
    @Test
    func theEventWindowDoesNotMoveWhileScrollingWithinAWeek() throws {
        let weekStart = CadenceScheduleSupport.startOfWeek(containing: try date("2026-08-19"), calendar: calendar)
        let first = CadenceCalendarTimelineWindow.eventWindowStart(leadingDate: weekStart, calendar: calendar)
        for offset in 0..<7 {
            let day = try #require(calendar.date(byAdding: .day, value: offset, to: weekStart))
            #expect(
                calendar.isDate(
                    CadenceCalendarTimelineWindow.eventWindowStart(leadingDate: day, calendar: calendar),
                    inSameDayAs: first
                )
            )
        }
        let nextWeek = try #require(calendar.date(byAdding: .day, value: 7, to: weekStart))
        #expect(
            !calendar.isDate(
                CadenceCalendarTimelineWindow.eventWindowStart(leadingDate: nextWeek, calendar: calendar),
                inSameDayAs: first
            )
        )
    }
}

/// `545f429`'s guarantee, restated for a grid that scrolls.
///
/// That commit fixed Week showing four and a half of its seven days behind a horizontal scroller.
/// The way it stated the fix — "the content is no wider than the pane" — cannot survive infinite
/// scrolling, because the content is now always wider than the pane. The property that survives is
/// the one the user actually cared about: **seven columns are on screen**, and the rest are a scroll
/// away rather than lost.
///
/// `CadenceCalendarWeekGridLayoutTests` keeps the original form against the same pane widths; this
/// is the same chain run to a column *count*.
struct CadenceCalendarWeekVisibleColumnTests {
    /// Every pane the app runs a week in on the devices it targets — the same list `545f429` pinned.
    private static let realPaneWidths: [CGFloat] = [646, 737, 834, 1022, 1210]

    private static let weekClaim = CadenceCalendarWeekGridLayout.fullSizeWidth(isRegularWidth: true)

    private func gridWidth(paneWidth: CGFloat) -> CGFloat {
        guard CadenceCalendarPaneLayout.showsInspector(
            paneWidth: paneWidth,
            calendarMinimumWidth: Self.weekClaim
        ) else { return paneWidth }
        return CadenceCalendarPaneLayout.calendarWidth(
            forPaneWidth: paneWidth,
            calendarMinimumWidth: Self.weekClaim
        )
    }

    private func availableWidth(paneWidth: CGFloat) -> CGFloat {
        gridWidth(paneWidth: paneWidth) - CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: true)
    }

    private func columnWidth(paneWidth: CGFloat) -> CGFloat {
        CadenceCalendarWeekGridLayout.dayColumnWidth(
            availableWidth: availableWidth(paneWidth: paneWidth),
            dayCount: CadenceCalendarWeekGridLayout.visibleDayCount(for: .week),
            isRegularWidth: true
        )
    }

    @Test
    func weekShowsSevenColumnsAtEveryRealPaneWidth() {
        for paneWidth in Self.realPaneWidths {
            let visible = CadenceCalendarWeekGridLayout.visibleColumnCount(
                availableWidth: availableWidth(paneWidth: paneWidth),
                columnWidth: columnWidth(paneWidth: paneWidth)
            )
            #expect(
                visible >= CadenceCalendarWeekGridLayout.daysInWeek,
                "pane \(paneWidth) showed \(visible) of seven columns"
            )
        }
    }

    /// Seven that are still tappable — "it fits" must not be bought by shaving the columns away.
    @Test
    func thoseSevenColumnsStayLegalTouchTargets() {
        for paneWidth in Self.realPaneWidths {
            #expect(
                columnWidth(paneWidth: paneWidth) >= CadenceCalendarWeekGridLayout.minimumDayColumnWidth,
                "pane \(paneWidth) column \(columnWidth(paneWidth: paneWidth))"
            )
        }
    }

    /// The column width is **fixed**, which is what lets the grid scroll past the visible seven. It
    /// used to be `availableWidth / dates.count`, so a window of four hundred columns would have
    /// divided the pane four hundred ways.
    @Test
    func theColumnWidthDoesNotDependOnHowManyColumnsExist() {
        let available = availableWidth(paneWidth: 1022)
        let sevenVisible = CadenceCalendarWeekGridLayout.dayColumnWidth(
            availableWidth: available,
            dayCount: CadenceCalendarWeekGridLayout.visibleDayCount(for: .week),
            isRegularWidth: true
        )
        #expect(sevenVisible == columnWidth(paneWidth: 1022))
        // The count that matters is the visible one, and Week's is seven at every pane.
        #expect(CadenceCalendarWeekGridLayout.visibleDayCount(for: .week) == 7)
        #expect(CadenceCalendarWeekGridLayout.visibleDayCount(for: .twoWeeks) == 14)
    }

    /// The phone is deliberately not in the list above, and this is **the arithmetic that used to
    /// decide what a phone showed**. Ask for seven on a 393pt iPhone and you get 49pt a column,
    /// under the touch floor, so `dayColumnWidth` abandons the fitted branch for the 104pt
    /// preference and the grid scrolls.
    ///
    /// The assertion to read is the last one: that fallback put **exactly three** columns on the
    /// phone, and three was never a figure anyone picked — it is `345 / 104`, an emergent remainder.
    /// It is pinned here so that the number the owner was looking at when they asked for two has a
    /// name and a derivation, rather than being hunted for as a literal that does not exist.
    @Test
    func aSevenColumnWeekOnAPhoneFallsBackToThreeNobodyChose() {
        let available = 393 - CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: false)
        let column = CadenceCalendarWeekGridLayout.dayColumnWidth(
            availableWidth: available,
            dayCount: CadenceCalendarWeekGridLayout.visibleDayCount(for: .week, isCompact: false),
            isRegularWidth: false
        )
        #expect(column == CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: false))
        let visible = CadenceCalendarWeekGridLayout.visibleColumnCount(
            availableWidth: available, columnWidth: column
        )
        #expect(visible < 7)
        #expect(visible == 3, "the cramped phone week was three columns of 104pt, not a chosen count")
    }

    /// Two columns, and they **fill** the phone — the same guarantee the iPad's seven carry, stated
    /// at the width a phone actually has.
    ///
    /// The point is not that two is smaller. It is that two is back on the *fitted* branch: 345
    /// divided two ways is 172.5, over `minimumDayColumnWidth`, so the width is derived from the
    /// pane again instead of from a preference the pane cannot afford. Three was the remainder of a
    /// fallback; two is a division.
    @Test
    func aPhonesWeekIsTwoColumnsThatDivideTheCanvasExactly() {
        let available: CGFloat = 393 - CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: false)
        let count = CadenceCalendarWeekGridLayout.visibleDayCount(for: .week, isCompact: true)
        #expect(count == 2)

        let column = CadenceCalendarWeekGridLayout.dayColumnWidth(
            availableWidth: available,
            dayCount: count,
            isRegularWidth: false
        )
        // The fitted branch, not the preference — this is the whole difference from the test above.
        #expect(column == available / 2)
        #expect(column != CadenceCalendarWeekGridLayout.preferredDayColumnWidth(isRegularWidth: false))
        #expect(column >= CadenceCalendarWeekGridLayout.minimumDayColumnWidth)
        #expect(
            CadenceCalendarWeekGridLayout.visibleColumnCount(availableWidth: available, columnWidth: column) == 2
        )
    }

    /// The control, and the half that matters most: **narrowing the phone must not reach the iPad.**
    ///
    /// Written as a sweep over the real pane widths rather than one reading, so it cannot pass for
    /// the one-candidate reason the standing verification bar warns about. `isCompact` defaults to
    /// `false`, so a caller that forgets to ask is answered at regular width — this is what pins
    /// that default, and it is what reddens if the narrowing is ever moved into the `.week` case
    /// unconditionally.
    @Test
    func narrowingTheCompactWeekLeavesTheRegularWeekAtSeven() {
        #expect(CadenceCalendarWeekGridLayout.visibleDayCount(for: .week) == 7)
        #expect(CadenceCalendarWeekGridLayout.visibleDayCount(for: .week, isCompact: false) == 7)

        for paneWidth in Self.realPaneWidths {
            let visible = CadenceCalendarWeekGridLayout.visibleColumnCount(
                availableWidth: availableWidth(paneWidth: paneWidth),
                columnWidth: columnWidth(paneWidth: paneWidth)
            )
            #expect(visible >= 7, "the iPad pane \(paneWidth) lost a day to the phone's narrowing")
        }

        // The other two modes answer the same at both widths. `.twoWeeks` is unreachable from the
        // picker and `.month` does not use this grid at all; neither is the phone's problem.
        for mode in [CadenceCalendarViewMode.twoWeeks, .month] {
            #expect(
                CadenceCalendarWeekGridLayout.visibleDayCount(for: mode, isCompact: true)
                    == CadenceCalendarWeekGridLayout.visibleDayCount(for: mode, isCompact: false),
                "\(mode) changed with the size class and nothing asked it to"
            )
        }
    }

    /// The two consumers of the count that are not the column width, at two columns.
    ///
    /// `selectionKeptInView`'s doc used to say the count was "never below a week", which the
    /// arithmetic never actually needed — `visibleDayCount - 1` is a valid offset at two, and one
    /// is the only value that would have made the span empty. `renderedIndexRange` still builds a
    /// margin either side, so a fling has somewhere to land.
    @Test
    func theOtherConsumersOfTheCountSurviveATwoColumnWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let leading = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let secondColumn = calendar.date(byAdding: .day, value: 1, to: leading)!
        let thirdColumn = calendar.date(byAdding: .day, value: 2, to: leading)!

        // Both visible columns are left alone; the first one off the edge is pulled back.
        for onScreen in [leading, secondColumn] {
            #expect(CadenceCalendarTimelineWindow.selectionKeptInView(
                selectedDate: onScreen, leadingDate: leading, visibleDayCount: 2, calendar: calendar
            ) == nil)
        }
        #expect(CadenceCalendarTimelineWindow.selectionKeptInView(
            selectedDate: thirdColumn, leadingDate: leading, visibleDayCount: 2, calendar: calendar
        ) == leading)

        #expect(CadenceCalendarTimelineWindow.visibleDates(
            leadingDate: leading, visibleDayCount: 2, calendar: calendar
        ) == [leading, secondColumn])

        // Still a margin either side of the two, so the window is not the visible span.
        let range = CadenceCalendarTimelineWindow.renderedIndexRange(leadingIndex: 40, visibleDayCount: 2)
        #expect(range.contains(40) && range.contains(41))
        #expect(range.count > 2)
    }
}

/// Where a sideways scroll of a timed grid comes to rest.
///
/// **The defect, in the owner's words: "the ios calendar pages do not snap to the boundaries of the
/// day, but it works fine on macos" (T-3075).** The Mac's Calendar page has attached
/// `DayBoundaryScrollTargetBehavior` since it was written; the iOS timed grid's horizontal
/// `ScrollView` carried no scroll target behaviour at all, so it settled wherever deceleration
/// stopped it and parked the user across two columns. Not a mis-sized snap — an absent one.
///
/// The arithmetic is one shared function now (`CadenceCalendarDaySnap.settledOffsetX`) and both
/// platforms reach it through the one behaviour, which is what this suite is really for: the rule
/// cannot drift apart again without something here going red. `ScrollTarget` and `TargetContext`
/// cannot be constructed in a test, so the behaviour's two call sites are pinned by reading source
/// and everything it *decides* is pinned as arithmetic.
struct CadenceCalendarDayBoundarySnapTests {
    /// An iPad week at 1022pt of pane: seven columns of the canvas less its rail.
    private static let columnWidth: CGFloat = CadenceCalendarWeekGridLayout.dayColumnWidth(
        availableWidth: 1022 - CadenceCalendarWeekGridLayout.timeRailWidth(isRegularWidth: true),
        dayCount: CadenceCalendarWeekGridLayout.visibleDayCount(for: .week),
        isRegularWidth: true
    )

    /// A range long enough that nothing below is clamped by accident.
    private static let farMaximum: CGFloat = columnWidth * 1000

    private func settled(
        _ proposed: CGFloat,
        velocity: CGFloat = 0,
        width: CGFloat = columnWidth,
        maximum: CGFloat = farMaximum
    ) -> CGFloat {
        CadenceCalendarDaySnap.settledOffsetX(
            proposedOffsetX: proposed,
            dayWidth: width,
            velocityX: velocity,
            maximumOffsetX: maximum
        )
    }

    /// The whole of the rule, as a property rather than as a list of cases: wherever a scroll is
    /// proposed and at whatever velocity, what it settles on is a **whole number of columns**.
    ///
    /// This is the assertion the defect fails. Every other test here says *which* column.
    @Test func everySettledOffsetIsAWholeNumberOfColumns() {
        let width = Self.columnWidth
        for step in stride(from: 0.0 as CGFloat, through: 40.0, by: 0.37) {
            for velocity in [-900.0, -120.0, -80.0, 0.0, 40.0, 80.0, 120.0, 900.0] as [CGFloat] {
                let offset = settled(step * width, velocity: velocity)
                let columns = offset / width
                #expect(
                    abs(columns - columns.rounded()) < 0.0001,
                    "offset \(offset) at velocity \(velocity) is \(columns) columns, not a whole one"
                )
            }
        }
    }

    /// A drag released mid-column with no fling behind it goes to the nearer edge — in both
    /// directions, which is the half a `floor`-shaped fix would get wrong.
    @Test func aDragReleasedMidColumnGoesToTheNearerEdge() {
        let width = Self.columnWidth

        // Just past the middle of column 5: forward to 6.
        #expect(settled(width * 5.51) == width * 6)
        // Just short of it: back to 5.
        #expect(settled(width * 5.49) == width * 5)

        // A slow release is a drag, not a fling: the threshold is exclusive on both sides, so a
        // velocity exactly at it still rounds.
        #expect(settled(width * 5.9, velocity: CadenceCalendarDaySnap.flingVelocity) == width * 6)
        #expect(settled(width * 5.1, velocity: -CadenceCalendarDaySnap.flingVelocity) == width * 5)
    }

    /// A fling states a direction, so it commits to the next column on far less than half of one —
    /// and refuses to be dragged back by the rounding that a slow release would apply.
    @Test func aFlingCommitsToTheColumnItIsHeadedFor() {
        let width = Self.columnWidth
        let fling = CadenceCalendarDaySnap.flingVelocity + 1
        let past = CadenceCalendarDaySnap.flungPastProgress

        // Forward, barely into column 5: a drag would round back to 5, a fling takes 6.
        #expect(settled(width * (5 + past + 0.01), velocity: fling) == width * 6)
        #expect(settled(width * (5 + past + 0.01)) == width * 5)
        // Forward but not yet committed: stays on 5.
        #expect(settled(width * (5 + past - 0.01), velocity: fling) == width * 5)

        // Backward, barely out of column 5: a drag would round forward to 6, a fling keeps 5.
        #expect(settled(width * (6 - past - 0.01), velocity: -fling) == width * 5)
        #expect(settled(width * (6 - past - 0.01)) == width * 6)
        // Backward and all but gone from 5: it has reached 6's edge and stays there.
        #expect(settled(width * (6 - past + 0.01), velocity: -fling) == width * 6)
    }

    /// A fling that crosses several columns lands on the column deceleration proposed, not on the
    /// one it started from: the behaviour settles the *proposed* offset, so the distance a fling
    /// carries is the scroll view's to decide and the edge it stops on is this rule's.
    @Test func aFlingAcrossSeveralColumnsSettlesOnTheColumnItReaches() {
        let width = Self.columnWidth
        let fling = CadenceCalendarDaySnap.flingVelocity * 12

        #expect(settled(width * 12.6, velocity: fling) == width * 13)
        #expect(settled(width * 12.05, velocity: fling) == width * 12)
        #expect(settled(width * 2.4, velocity: -fling) == width * 2)
        #expect(settled(width * 2.95, velocity: -fling) == width * 3)
    }

    /// The first column of the loaded range. A backward fling, a backward drag and the rubber-band
    /// offsets past the leading edge all rest at 0 rather than at a negative column.
    @Test func theFirstColumnIsTheFloor() {
        let width = Self.columnWidth
        let fling = CadenceCalendarDaySnap.flingVelocity * 6

        #expect(settled(width * 0.4, velocity: -fling) == 0)
        #expect(settled(width * 0.4) == 0)
        #expect(settled(0) == 0)
        // Rubber-banded past the leading edge: `floor` of a negative raw column is -1, so a fix
        // that trusted `floor` alone would settle one column *behind* the content.
        #expect(settled(-width * 0.3) == 0)
        #expect(settled(-width * 0.3, velocity: -fling) == 0)
        #expect(settled(-width * 2) == 0)
    }

    /// The last column. The clamp is the final step, so when the scrollable extent is **not** a
    /// whole number of columns — which is what a trailing partial column means — the end of the
    /// range is the resting place rather than a column edge past the content.
    @Test func theLastColumnIsTheCeilingEvenWhenTheRangeEndsMidColumn() {
        let width = Self.columnWidth
        let fling = CadenceCalendarDaySnap.flingVelocity * 6

        // A range ending exactly on a column edge rests on that edge.
        let wholeMaximum = width * 20
        #expect(settled(width * 19.8, velocity: fling, maximum: wholeMaximum) == wholeMaximum)
        #expect(settled(width * 25, velocity: fling, maximum: wholeMaximum) == wholeMaximum)

        // A range ending mid-column cannot rest on the next edge, because the content stops first.
        let partialMaximum = width * 20.4
        #expect(settled(width * 20.3, velocity: fling, maximum: partialMaximum) == partialMaximum)
        // A drag released in that trailing stub still prefers the clean edge behind it — the clamp
        // is a ceiling, not a magnet.
        #expect(settled(width * 20.3, maximum: partialMaximum) == width * 20)
        #expect(settled(width * 19.6, maximum: partialMaximum) == width * 20)
    }

    /// A programmatic jump is already on an edge, so the behaviour must leave it exactly where it
    /// was put. `CadenceCalendarTimelineWindow.scrollOffsetX(forIndex:columnWidth:)` is what every
    /// jump on the iOS grid goes through — the initial placement, the toolbar's date jump and the
    /// rotation re-align — and a settle that moved any of them by a column would rename the day the
    /// user asked for.
    @Test func aProgrammaticJumpToAColumnIsLeftWhereItWasPut() {
        let width = Self.columnWidth
        for index in [0, 1, 7, 210, 211, 419] {
            let offset = CadenceCalendarTimelineWindow.scrollOffsetX(forIndex: index, columnWidth: width)
            #expect(settled(offset) == offset, "jump to column \(index) was moved")
            #expect(settled(offset, velocity: 400) == offset)
            #expect(settled(offset, velocity: -400) == offset)
        }
    }

    /// A column width of zero is the first layout pass, before the grid has a width. The rule must
    /// answer a number rather than a `NaN` the scroll view then settles on.
    @Test func aGridWithNoWidthYetSettlesAtZeroRatherThanNaN() {
        let offset = settled(240, width: 0, maximum: 0)
        #expect(offset.isFinite)
        #expect(offset == 0)
    }

    /// **The cross-platform half, and the point of the ticket.** One behaviour, declared once in
    /// `Shared/`, attached by both timed grids — so the Mac's day edge and the phone's are the same
    /// edge by construction rather than by two files agreeing.
    @Test func bothTimedGridsAttachTheOneSharedDayBoundaryBehaviour() throws {
        let shared = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarTimedGridSupport.swift")
        )
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift")
        )
        let ios = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        let macSupport = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarTimelineSupport.swift")
        )

        // Non-vacuity: the right files, past the stripper, still holding the views this is about.
        #expect(ios.contains("struct iOSCalendarTimelineGrid: View"))
        #expect(mac.contains("ScrollView(.horizontal"))

        // Declared once, in Shared, and nowhere else.
        #expect(shared.contains("struct DayBoundaryScrollTargetBehavior: ScrollTargetBehavior"))
        #expect(!macSupport.contains("struct DayBoundaryScrollTargetBehavior"))
        #expect(!ios.contains("struct DayBoundaryScrollTargetBehavior"))

        // Attached by both grids, each over its own column width.
        for (name, source) in [("macOS", mac), ("iOS", ios)] {
            #expect(
                CadenceSourceScan.matchCount(
                    "\\.scrollTargetBehavior\\(DayBoundaryScrollTargetBehavior\\(dayWidth: colWidth\\)\\)",
                    in: source
                ) == 1,
                "\(name) does not attach the shared day-boundary behaviour exactly once"
            )
        }

        // And neither grid re-spells the arithmetic the behaviour already owns.
        for (name, source) in [("macOS", mac), ("iOS", ios), ("macOS support", macSupport)] {
            #expect(
                CadenceSourceScan.matchCount("rounded\\(\\.toNearestOrAwayFromZero\\)", in: source) == 0,
                "\(name) carries a second copy of the settle rule"
            )
        }
        #expect(
            CadenceSourceScan.matchCount("rounded\\(\\.toNearestOrAwayFromZero\\)", in: shared) == 1
        )
    }

    /// The Board is **not** covered, and that is a decision rather than an omission.
    ///
    /// `iOSCalendarBoardView` already pages at compact width through `.viewAligned`, and
    /// deliberately does not at regular width — "paging a multi-column board would snap away days
    /// that are fully readable where they are". A board column is not sized to a fraction of the
    /// pane either: `CalendarBoardPlannerSupport.compactColumnWidth` sizes it so the *next* day
    /// peeks in, which is the one place in the calendar where a partial column is the point. So the
    /// board keeps its own behaviour, and this pins that it still has one.
    @Test func theBoardKeepsItsOwnPagingAndItsDeliberatePeek() throws {
        let board = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBoardView.swift")
        )
        #expect(board.contains("struct iOSCalendarBoardPlanner: View"))
        #expect(board.contains("content.scrollTargetBehavior(.viewAligned)"))
        #expect(!board.contains("DayBoundaryScrollTargetBehavior"))

        // The peek is real arithmetic, not a stopping accident: a compact column plus its inset and
        // spacing is narrower than the container by the peek fraction.
        let container: CGFloat = 393
        let width = CalendarBoardPlannerSupport.compactColumnWidth(
            containerWidth: container,
            leadingInset: iOSCalendarBoardMetrics.horizontalPadding(isRegularWidth: false),
            columnSpacing: iOSCalendarBoardMetrics.columnSpacing
        )
        #expect(width < container)
        #expect(width > container * 0.5)
    }
}
