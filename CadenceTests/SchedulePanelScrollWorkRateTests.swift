#if os(macOS)
import Foundation
import Testing
@testable import Cadence

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
    /// was true of Today's timeline, and T-1498 rationed that write to one per settled gesture. It is true of *nothing else* in the
    /// laggy set: the sidebar, All Tasks and the kanban observe no scroll geometry at all, so there
    /// is no per-frame write on them to find. Whatever they cost, they do not cost it this way.
    ///
    /// **[[T-18869]]: and now not Today's timeline either.** Its write, the remembered scroll hour,
    /// lost its only reader in [[T-18863]] and was removed, observer and all — so Today's timeline
    /// joins the set that observes no scroll geometry. The calendar page, the smooth control, still
    /// does, which is what keeps the absence checks below from passing over a needle nothing spells.
    @Test("No laggy surface writes anything from a scroll report")
    func noLaggySurfaceObservesItsOwnScroll() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let observers = ["onScrollGeometryChange", ".scrollPosition(", "onScrollPhaseChange"]

        for path in [
            "Cadence/macOS/Views/SidebarView.swift",
            "Cadence/macOS/Views/SchedulePanel.swift",
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

        let control = try read("Cadence/macOS/Views/CalendarPageSupportViews.swift")
        #expect(control.contains("onScrollGeometryChange"),
                "the smooth control no longer observes its scroll, so the absences above prove nothing")
    }

    /// [[T-1498]]'s guard on the calendar page's timeline, kept when Today's half of the old
    /// both-hosts census went with its write ([[T-18869]]): the calendar still persists
    /// `calendarRememberedTimelineHour` from its scroll, so a missing guard there is the same
    /// per-frame write this file was opened for.
    @Test("The calendar timeline still refuses an unchanged scroll report")
    func theCalendarTimelineStillGuardsItsScrollReport() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let calendar = try read("Cadence/macOS/Views/CalendarPageSupportViews.swift")
        #expect(calendar.contains("guard visibleTimelineHour != clampedHour"),
                "the calendar timeline adopts every frame of a scroll again")
    }
}
#endif
