import Foundation
import Testing
@testable import Cadence

#if os(macOS)
/// T-3120 part (1): every Today surface that reads "today" in its own `body`, and whose host does
/// not hand it the day, observes the day changing itself — the way [[T-3104]] wired `TasksPanel`
/// and `iOSTodayView` (pinned by `CadenceDayChangeSupportTests`).
///
/// A child built with constant arguments, or with inputs that can be equal on both sides of
/// midnight, is not re-evaluated just because its host's body re-ran, so being *under* an
/// observing view is not enough: the timeline panes take no day at all, and the macOS Today header
/// takes only the day's counts.
@MainActor
struct CadenceDayChangeAdoptionTests {
    /// The adopting views, by file and by the declaration whose body installs the observer.
    private static let adopters: [(path: String, declaration: String)] = [
        ("Cadence/macOS/Views/TasksPanel.swift", "struct TasksPanel: View"),
        ("Cadence/iOS/iOSTodayView.swift", "struct iOSTodayView: View"),
        ("Cadence/macOS/Views/SchedulePanel.swift", "struct SchedulePanel: View"),
        ("Cadence/macOS/Views/TasksPanelSupportViews.swift", "struct TasksPanelHeader<Trailing: View>: View"),
        ("Cadence/iOS/iOSTodaySchedulePanel.swift", "struct iOSSchedulePanel: View"),
        ("Cadence/macOS/Views/CalendarPageView.swift", "struct CalendarPageView: View"),
        // T-5011: the always-visible sidebars' Today badge, and the macOS list rows' due flag
        // (their host `ContextSection` holds no day, so each row observes its own).
        ("Cadence/macOS/Views/SidebarView.swift", "struct SidebarView: View"),
        ("Cadence/macOS/Views/SidebarSupportViews.swift", "struct SidebarListRow: View"),
        ("Cadence/iOS/iOSRootSidebar.swift", "struct iOSSidebar: View"),
        ("Cadence/iOS/iOSTasksTabView.swift", "struct iOSTasksTabView: View"),
    ]

    private static let install = ".cadenceTracksDayChanges($observedDay)"

    /// Equality, not containment: a new adopter is a decision to add here, and a lost one is the
    /// bug this ticket fixed.
    @Test func theProductTreeInstallsTheDayObserverInExactlyTheExpectedFiles() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(files.count > 100, "the sweep read \(files.count) files")

        var installing: Set<String> = []
        for path in files where try read(path).contains(".cadenceTracksDayChanges(") {
            installing.insert(path)
        }
        // The modifier's own declaration is the one non-call site.
        installing.remove("Cadence/Shared/CadenceDayChangeSupport.swift")

        #expect(installing == Set(Self.adopters.map(\.path)))
    }

    /// Each adopter holds its own observed day, reads today through it (so the body depends on the
    /// state the observer writes), never reads the clock's key beside it, and installs the
    /// observer once, in its own body.
    @Test func everyAdopterReadsItsDayThroughTheObserverItInstalls() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        for (path, declaration) in Self.adopters {
            let source = try read(path)
            let view = try #require(CadenceSourceScan.declarationBody(declaration, in: source), "\(path)")
            #expect(view.contains("@State private var observedDay = CadenceObservedDay()"), "\(path)")
            #expect(view.contains("observedDay.todayKey"), "\(path)")
            #expect(view.contains("DateFormatters.todayKey()") == false, "\(path)")

            let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: view), "\(path)")
            #expect(body.components(separatedBy: Self.install).count - 1 == 1, "\(path)")
        }
    }
}
#endif
