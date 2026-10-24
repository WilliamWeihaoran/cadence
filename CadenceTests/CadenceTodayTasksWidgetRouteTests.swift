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
}
