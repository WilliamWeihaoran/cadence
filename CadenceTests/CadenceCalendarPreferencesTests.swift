import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-8737]]: the Calendar page's view, style and timeline density are app-wide defaults.**
///
/// iOS remembered them under `ios.calendar.*` and Settings set them; the Mac held view and style in
/// `@State` (so it opened on Week / Timeline at every launch) and its zoom under an `Int`
/// `calendarZoomLevel`. Both platforms now read one key per choice, the old values are copied in at
/// launch, and the Mac's Settings has the phone's rows.
@MainActor
struct CadenceCalendarPreferencesTests {
    private static let scope = "CadenceTests.calendarPreferences"

    /// The Mac toolbar's zoom steps. `TimelineZoom` is Mac-only and this suite also compiles into the
    /// iOS test target ([[T-10860]]), so the phone pins the same three steps; the Mac leg reads the
    /// real range and catches a change to it.
    #if os(macOS)
    private static let macTimelineLevels = TimelineZoom.levels
    #else
    private static let macTimelineLevels = 1...3
    #endif

    // MARK: - The migration

    /// The phone's three stored choices reach the shared keys, once, and stay on disk.
    @Test func thePhonesCalendarChoicesAreCopiedOnceAndLeftInPlace() throws {
        try withTemporaryDefaults(Self.scope) { defaults in
            defaults.set(CadenceCalendarViewMode.month.rawValue, forKey: CadenceCalendarPreferences.legacyIOSViewModeKey)
            defaults.set(CadenceCalendarPresentation.board.rawValue, forKey: CadenceCalendarPreferences.legacyIOSPresentationKey)
            defaults.set(1.75, forKey: CadenceCalendarZoom.legacyIOSStorageKey)

            let first = CadenceCalendarPreferences.migrateLegacyKeys(in: defaults)
            #expect(Set(first) == [
                CadenceCalendarPreferences.viewModeKey,
                CadenceCalendarPreferences.presentationKey,
                CadenceCalendarZoom.storageKey
            ])
            #expect(defaults.string(forKey: CadenceCalendarPreferences.viewModeKey) == "Month")
            #expect(defaults.string(forKey: CadenceCalendarPreferences.presentationKey) == "Board")
            // Copied as stored: a pinched zoom is not snapped to a preset on the way through.
            #expect(defaults.double(forKey: CadenceCalendarZoom.storageKey) == 1.75)

            // Idempotent.
            #expect(CadenceCalendarPreferences.migrateLegacyKeys(in: defaults).isEmpty)

            // Non-destructive: every legacy value is still there.
            #expect(defaults.string(forKey: CadenceCalendarPreferences.legacyIOSViewModeKey) == "Month")
            #expect(defaults.string(forKey: CadenceCalendarPreferences.legacyIOSPresentationKey) == "Board")
            #expect(defaults.double(forKey: CadenceCalendarZoom.legacyIOSStorageKey) == 1.75)
        }
    }

    /// The Mac's `Int` zoom reaches the shared `Double`, and every step it could hold survives.
    @Test func theMacsIntegerZoomIsCopiedIntoTheSharedDouble() throws {
        try withTemporaryDefaults(Self.scope) { defaults in
            for level in Self.macTimelineLevels {
                defaults.removeObject(forKey: CadenceCalendarZoom.storageKey)
                defaults.set(level, forKey: CadenceCalendarZoom.legacyMacStorageKey)

                #expect(CadenceCalendarPreferences.migrateLegacyKeys(in: defaults) == [CadenceCalendarZoom.storageKey])
                #expect(defaults.double(forKey: CadenceCalendarZoom.storageKey) == Double(level))
                // And the Mac grid reads back the very step it stored.
                #expect(CadenceCalendarZoom.timelineLevel(for: defaults.double(forKey: CadenceCalendarZoom.storageKey)) == level)
                #expect(defaults.integer(forKey: CadenceCalendarZoom.legacyMacStorageKey) == level, "left on disk")
            }
        }
    }

    /// Only one legacy zoom exists on a real device; a domain holding both takes the phone's,
    /// the more precise of the two, and still clears neither.
    @Test func aDomainHoldingBothLegacyZoomsTakesTheContinuousOne() throws {
        try withTemporaryDefaults(Self.scope) { defaults in
            defaults.set(3, forKey: CadenceCalendarZoom.legacyMacStorageKey)
            defaults.set(1.25, forKey: CadenceCalendarZoom.legacyIOSStorageKey)
            CadenceCalendarPreferences.migrateLegacyKeys(in: defaults)
            #expect(defaults.double(forKey: CadenceCalendarZoom.storageKey) == 1.25)
            #expect(defaults.integer(forKey: CadenceCalendarZoom.legacyMacStorageKey) == 3)
        }
    }

    /// **[[T-10712]]: the Mac Today panel's old `Int` zoom seeds the calendar density only while it
    /// is unset**, after the Calendar's own legacy choice, and stays on disk.
    @Test func theMacTodayPanelsOldZoomSeedsTheSharedDensityOnlyWhileUnset() throws {
        try withTemporaryDefaults(Self.scope) { defaults in
            defaults.set(3, forKey: CadenceCalendarZoom.legacyMacSchedulePanelStorageKey)
            #expect(CadenceCalendarPreferences.migrateLegacyKeys(in: defaults) == [CadenceCalendarZoom.storageKey])
            #expect(defaults.double(forKey: CadenceCalendarZoom.storageKey) == 3)
            #expect(defaults.integer(forKey: CadenceCalendarZoom.legacyMacSchedulePanelStorageKey) == 3, "left on disk")

            // A density already chosen is never overwritten by the panel's old value.
            defaults.set(1.5, forKey: CadenceCalendarZoom.storageKey)
            #expect(CadenceCalendarPreferences.migrateLegacyKeys(in: defaults).isEmpty)
            #expect(defaults.double(forKey: CadenceCalendarZoom.storageKey) == 1.5)

            // The Calendar's own legacy choice wins over the panel's: Today follows the calendar.
            defaults.removeObject(forKey: CadenceCalendarZoom.storageKey)
            defaults.set(2, forKey: CadenceCalendarZoom.legacyMacStorageKey)
            CadenceCalendarPreferences.migrateLegacyKeys(in: defaults)
            #expect(defaults.double(forKey: CadenceCalendarZoom.storageKey) == 2)
        }
    }

    /// The Mac panels' `−/+` reads the nearest step of the shared zoom and writes the step it moved to.
    @Test func aMacTimelineStepperReadsAndWritesTheSharedZoom() {
        var stored = 2.4
        let zoom = Binding(get: { stored }, set: { stored = $0 })
        let level = CadenceCalendarZoom.timelineLevelBinding(zoom)
        #expect(level.wrappedValue == 2)
        level.wrappedValue = 3
        #expect(stored == 3)
        stored = 0.2
        #expect(level.wrappedValue == 1, "a stored zoom is clamped before it is stepped")
    }

    /// A choice already on a shared key is never overwritten, and a device with nothing stored —
    /// or with an unparseable legacy value — gets nothing written.
    @Test func theCalendarMigrationNeverOverwritesAChoiceOrSeedsGarbage() throws {
        try withTemporaryDefaults(Self.scope) { defaults in
            #expect(CadenceCalendarPreferences.migrateLegacyKeys(in: defaults).isEmpty)
            #expect(defaults.object(forKey: CadenceCalendarPreferences.viewModeKey) == nil)
            #expect(defaults.object(forKey: CadenceCalendarZoom.storageKey) == nil)

            defaults.set("Fortnight", forKey: CadenceCalendarPreferences.legacyIOSViewModeKey)
            defaults.set("Carousel", forKey: CadenceCalendarPreferences.legacyIOSPresentationKey)
            defaults.set("big", forKey: CadenceCalendarZoom.legacyIOSStorageKey)
            #expect(CadenceCalendarPreferences.migrateLegacyKeys(in: defaults).isEmpty)

            defaults.set(CadenceCalendarViewMode.week.rawValue, forKey: CadenceCalendarPreferences.viewModeKey)
            defaults.set(CadenceCalendarPresentation.timeline.rawValue, forKey: CadenceCalendarPreferences.presentationKey)
            defaults.set(2.0, forKey: CadenceCalendarZoom.storageKey)
            defaults.set(CadenceCalendarViewMode.month.rawValue, forKey: CadenceCalendarPreferences.legacyIOSViewModeKey)
            defaults.set(CadenceCalendarPresentation.board.rawValue, forKey: CadenceCalendarPreferences.legacyIOSPresentationKey)
            defaults.set(1, forKey: CadenceCalendarZoom.legacyMacStorageKey)
            #expect(CadenceCalendarPreferences.migrateLegacyKeys(in: defaults).isEmpty)
            #expect(defaults.string(forKey: CadenceCalendarPreferences.viewModeKey) == "Week")
            #expect(defaults.string(forKey: CadenceCalendarPreferences.presentationKey) == "Timeline")
            #expect(defaults.double(forKey: CadenceCalendarZoom.storageKey) == 2.0)
        }
    }

    /// A migration nothing calls is the defect, not the mapping.
    @Test func theCalendarMigrationRunsAtLaunch() throws {
        let app = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/CadenceApp.swift"))
        #expect(app.contains("CadenceCalendarPreferences.migrateLegacyKeys()"))
    }

    // MARK: - The Mac grid's reading of the shared zoom

    @Test func theMacTimelineReadsTheNearestStepAndNeverLeavesItsRange() {
        #expect(CadenceCalendarZoom.densityPresets.map { CadenceCalendarZoom.timelineLevel(for: $0.zoom) } == [1, 2, 3])
        #expect(CadenceCalendarZoom.timelineLevel(for: 1.4) == 1)
        #expect(CadenceCalendarZoom.timelineLevel(for: 1.6) == 2)
        #expect(CadenceCalendarZoom.timelineLevel(for: 2.6) == 3)
        for wild in [0, -4, 9, .infinity, .nan] as [Double] {
            #expect(Self.macTimelineLevels.contains(CadenceCalendarZoom.timelineLevel(for: wild)), "\(wild)")
        }
    }

    // MARK: - One key per choice, on both platforms

    /// Every reader and writer of the three choices goes through the shared constants: the two
    /// Calendar pages, the two Settings panes, and iOS Today's schedule panel for the zoom.
    @Test func bothPlatformsReadOneKeyPerCalendarChoice() throws {
        let viewMode = "@AppStorage(CadenceCalendarPreferences.viewModeKey)"
        let presentation = "@AppStorage(CadenceCalendarPreferences.presentationKey)"
        let zoom = "@AppStorage(CadenceCalendarZoom.storageKey)"
        let readers: [(path: String, needles: [String])] = [
            ("Cadence/macOS/Views/CalendarPageView.swift", [viewMode, presentation, zoom]),
            ("Cadence/macOS/Views/SettingsCalendarDefaultsSection.swift", [viewMode, presentation, zoom]),
            ("Cadence/iOS/iOSCalendarView.swift", [viewMode, presentation, zoom]),
            ("Cadence/iOS/iOSSettingsView.swift", [viewMode, presentation, zoom]),
            ("Cadence/iOS/iOSTodaySchedulePanel.swift", [zoom])
        ]
        for reader in readers {
            let raw = try CadenceSourceScan.sourceFile(reader.path)
            let code = CadenceSourceScan.strippingComments(raw)
            #expect(code.count == raw.count, "\(reader.path): the stripper changed the length")
            for needle in reader.needles {
                #expect(code.contains(needle), "\(reader.path) does not read \(needle)")
            }
        }
    }

    /// **The Mac page remembers.** Its view and style were `@State`, which is the whole defect:
    /// nothing outlived the window. They are computed over the stored raw values now, and the
    /// zoom over the shared `Double` rather than the retired `Int` key.
    @Test func theMacCalendarPageStoresItsViewAndStyleRatherThanHoldingThem() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageView.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code != raw, "the comment stripper never fired")

        let heldInState = #"@State\s+private\s+var\s+(viewMode|presentation)\b"#
        #expect(CadenceSourceScan.matchCount(heldInState, in: "@State private var viewMode: CadenceCalendarViewMode = .week") == 1)
        #expect(CadenceSourceScan.matchCount(heldInState, in: "@State private var viewModeRaw = \"\"") == 0)
        #expect(CadenceSourceScan.matchCount(heldInState, in: code) == 0)

        let viewModeGetter = try #require(CadenceSourceScan.declarationBody(
            "private var viewMode: CadenceCalendarViewMode", in: code)).filter { !$0.isWhitespace }
        #expect(viewModeGetter.contains("CadenceCalendarViewMode(rawValue:viewModeRaw)"))
        #expect(viewModeGetter.contains("viewModeRaw=newValue.rawValue"))
        let presentationGetter = try #require(CadenceSourceScan.declarationBody(
            "private var presentation: CadenceCalendarPresentation", in: code)).filter { !$0.isWhitespace }
        #expect(presentationGetter.contains("CadenceCalendarPresentation(rawValue:presentationRaw)"))
        #expect(presentationGetter.contains("presentationRaw=newValue.rawValue"))

        #expect(!code.contains("\"calendarZoomLevel\""), "the page still reads the retired Int key")
    }

    /// The stored raw values round-trip through `@AppStorage` against a suite of the test's own,
    /// which is the persistence the page now relies on: a value written in one launch is the value
    /// the next launch's property reads.
    @Test func aStoredCalendarChoiceIsWhatTheNextReaderSees() throws {
        try withTemporaryDefaults(Self.scope) { defaults in
            let writer = AppStorage(
                wrappedValue: CadenceCalendarPresentation.timeline.rawValue,
                CadenceCalendarPreferences.presentationKey,
                store: defaults
            )
            writer.wrappedValue = CadenceCalendarPresentation.board.rawValue
            let nextLaunch = AppStorage(
                wrappedValue: CadenceCalendarPresentation.timeline.rawValue,
                CadenceCalendarPreferences.presentationKey,
                store: defaults
            )
            #expect(nextLaunch.wrappedValue == CadenceCalendarPresentation.board.rawValue)
        }
    }

    // MARK: - The Mac's Settings rows

    /// The Mac's Navigation pane draws the phone's two calendar rows over the shared choice, and
    /// the two platforms name the stored pair with one function.
    @Test func theMacSettingsPaneDrawsThePhonesCalendarRows() throws {
        let section = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsCalendarDefaultsSection.swift"))
        #expect(section.contains("label: \"Calendar view\""))
        #expect(section.contains("label: \"Timeline density\""))
        #expect(section.contains("rows: CadenceCalendarPageView.allCases.map"))
        #expect(section.contains("rows: CadenceCalendarZoom.densityPresets.map"))
        #expect(section.contains("selection: $zoom,"))
        let selection = try #require(CadenceSourceScan.declarationBody(
            "private var calendarViewSelection: Binding<CadenceCalendarPageView>", in: section))
            .filter { !$0.isWhitespace }
        #expect(selection.contains("choice.apply(presentation:&newPresentation,viewMode:&newViewMode)"))
        #expect(selection.contains("viewModeRaw=newViewMode.rawValue"))
        #expect(selection.contains("presentationRaw=newPresentation.rawValue"))

        let pane = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsSectionViews.swift"))
        #expect(pane.contains("SettingsCalendarDefaultsSection()"), "the pane does not draw the rows")

        for path in ["Cadence/macOS/Views/SettingsCalendarDefaultsSection.swift",
                     "Cadence/iOS/iOSSettingsOverviewSections.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("CadenceCalendarPageView.settingsTitle("), "\(path) names the pair itself")
            #expect(code.contains("choice.settingsSubtitle"), "\(path) words Board itself")
        }
    }

    @Test func theSettingsTitleNamesTheStoredPair() {
        #expect(CadenceCalendarPageView.settingsTitle(presentation: .board, viewMode: .month) == "Board")
        #expect(CadenceCalendarPageView.settingsTitle(presentation: .timeline, viewMode: .month) == "Month")
        #expect(CadenceCalendarPageView.settingsTitle(presentation: .timeline, viewMode: .twoWeeks) == "2 Weeks")
        #expect(CadenceCalendarPageView.allCases.compactMap(\.settingsSubtitle).count == 1)
        #expect(CadenceCalendarPageView.board.settingsSubtitle != nil)
    }
}
