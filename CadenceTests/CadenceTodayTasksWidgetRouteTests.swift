import Foundation
import Testing
@testable import Cadence

/// T-5801. The Today Tasks widget's background tap route.
///
/// WidgetKit does not deliver `Link` on a small widget, so without `.widgetURL` a tap on the small
/// Today Tasks widget opened Cadence on whatever page it was last on. The widget extension is not
/// linked into `CadenceTests`, so this is a source pin beside the Calendar widget's
/// (`CadenceCodexWidgetFollowupTests.codexCalendarReadyContentHasItsDatedBackgroundRoute`); it is
/// not a sighting of a tap, which no test here can drive (T-1461).
struct CadenceTodayTasksWidgetRouteTests {
    @Test func todayTasksWidgetRoutesItsBackgroundTapToTheShownTaskOrToday() throws {
        let route = try CadenceScanInstrument(
            "today tasks widget background route",
            fires: """
            .widgetURL(backgroundURL)
            if widgetFamily == .systemSmall, let task = entry.snapshot.tasks.first { return task.deepLinkURL }
            return entry.snapshot.todayURL
            """,
            andNotOn: """
            // .widgetURL(backgroundURL)
            if widgetFamily == .systemSmall, let task = entry.snapshot.tasks.first { return task.deepLinkURL }
            return entry.snapshot.todayURL
            """,
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                return code.contains(".widgetURL(backgroundURL)")
                    && code.contains("widgetFamily == .systemSmall")
                    && code.contains("return task.deepLinkURL")
                    && code.contains("return entry.snapshot.todayURL")
            }
        )
        let paths = ["CadenceWidgets/TodayTasksWidgetView.swift"]
        #expect(try route.sweep(paths, atLeast: 1, including: paths[0], read: CadenceSourceScan.strippedSourceReader()) == paths)
    }

    /// **[[T-12335].]** The family-aware sentence is chosen in the provider's catch, which the
    /// test target cannot link, so this pins the call: a bare `unavailableSnapshot()` there would
    /// put the full sentence back on the `systemSmall` tile, where it stopped mid-word.
    @Test func theUnavailableTileAsksItsFamilyForItsSentence() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("CadenceWidgets/TodayTasksWidget.swift"))
        #expect(CadenceSourceScan.matchCount(#"unavailableSnapshot\(\s*message:\s*CadenceTodayWidgetSupport\.unavailableMessage\(for:\s*family\.cadenceLayout\)"#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"unavailableSnapshot\(\s*\)"#, in: code) == 0)
    }
}

/// **[[T-12334]], seen on an 11" iPad home screen.** The Today Tasks widget was an
/// `AppIntentConfiguration` over a `WidgetConfigurationIntent` with no `@Parameter`, so iOS offered
/// `Edit Widget` and opened an empty editor. A configuration intent is only worth declaring for
/// the parameters it carries, so this sweeps every widget-reachable source for one that carries
/// none, and pins the Today widget to the `StaticConfiguration` the Calendar widget already uses.
/// A source pin, not a sighting: the editor itself is iOS's, and no test here can open it.
struct CadenceWidgetConfigurationIntentTests {
    @Test func noWidgetDeclaresAConfigurationIntentWithNothingToConfigure() throws {
        let emptyIntent = try CadenceScanInstrument(
            "parameterless widget configuration intent",
            fires: """
            struct TodayIntent: WidgetConfigurationIntent {
                static var title: LocalizedStringResource { "Today" }
            }
            """,
            andNotOn: """
            struct TodayIntent: WidgetConfigurationIntent {
                static var title: LocalizedStringResource { "Today" }
                @Parameter(title: "List") var list: String?
            }
            """,
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                let pattern = #"(?:struct|class|enum)\s+\w+\s*:[^{]*\bWidgetConfigurationIntent\b[^{]*"#
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
                let range = NSRange(code.startIndex..., in: code)
                return regex.matches(in: code, range: range).contains { match in
                    guard let declared = Range(match.range, in: code) else { return true }
                    guard let body = CadenceSourceScan.declarationBody(String(code[declared]), in: code) else { return true }
                    return !body.contains("@Parameter")
                }
            }
        )
        let paths = try CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
            + CadenceSourceScan.swiftFiles(under: "Cadence/Services")
        let witness = "Cadence/Services/CadenceWidgetIntents.swift"
        #expect(try emptyIntent.sweep(paths, atLeast: 5, including: witness, read: CadenceSourceScan.strippedSourceReader()) == [])
    }

    @Test func theTodayTasksWidgetIsAStaticConfiguration() throws {
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("CadenceWidgets/TodayTasksWidget.swift"))
        #expect(code.contains("StaticConfiguration("))
        #expect(!code.contains("AppIntentConfiguration("))
        #expect(!code.contains("AppIntentTimelineProvider"))
    }
}
