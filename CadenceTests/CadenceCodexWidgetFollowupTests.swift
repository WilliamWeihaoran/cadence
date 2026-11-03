import Foundation
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexWidgetFollowupTests {
    @Test func codexWidgetFamilyBudgetsMatchTheSelectedContent() {
        let families = CadenceWidgetFamilyLayout.allCases
        // `.medium` was 3 until T-7121: a header plus three rows overflowed the 158pt tile at both
        // ends on `Cadence-iPhone15` and `Cadence-iPadPro11`, seen on screen in both galleries.
        #expect(families.map(\.todayTaskLimit) == [1, 2, 2, 8])
        #expect(families.map(\.habitLimit) == [2, 3, 8, 8])
        #expect(families.map(\.habitColumns) == [2, 3, 3, 3])
        #expect(families.map(\.calendarDayLimit) == [3, 6, 14, 14])
        #expect(families.map(\.milestoneGoalLimit) == [1, 3, 5, 5])
        for family in families.prefix(2) {
            #expect(family.habitLimit <= family.habitColumns, "small/medium must stay one row")
        }
        #expect((CadenceWidgetFamilyLayout.large.habitLimit + 2) / 3 == 3)
    }

    @Test(arguments: [true, false])
    func codexHabitOverrideExpiresAtMidnightBeforeItsTTL(isDone: Bool) throws {
        try withTemporaryDefaults("cadence.codex.widget.followups") { defaults in
            let day = try #require(DateFormatters.date(from: "2026-10-04"))
            let before = try #require(Calendar.current.date(bySettingHour: 23, minute: 59, second: 45, of: day))
            let id = UUID()
            CadenceWidgetRefreshCenter.markHabitCompletion(id, isDoneToday: isDone, now: before, userDefaults: defaults)
            let sameDay = CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: before.addingTimeInterval(10), userDefaults: defaults)
            #expect(sameDay[id] == isDone)
            let afterMidnight = CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: before.addingTimeInterval(30), userDefaults: defaults)
            #expect(afterMidnight[id] == nil)
            #expect(defaults.dictionary(forKey: "cadence.widgets.habits.recentlyChangedHabits") == nil)
        }
    }

    @Test func codexHabitOverrideStillHonorsTTLAndSnapshotDate() throws {
        try withTemporaryDefaults("cadence.codex.widget.followups") { defaults in
            let now = try #require(DateFormatters.date(from: "2026-10-04"))
            let id = UUID()
            CadenceWidgetRefreshCenter.markHabitCompletion(id, isDoneToday: true, now: now, userDefaults: defaults)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now.addingTimeInterval(90), userDefaults: defaults)[id] == true)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now.addingTimeInterval(91), userDefaults: defaults)[id] == nil)
            CadenceWidgetRefreshCenter.markHabitCompletion(id, isDoneToday: false, now: now, userDefaults: defaults)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now, dateKey: "2026-10-05", userDefaults: defaults)[id] == nil)
        }
    }

    @Test func codexLegacyHabitOverridesAreDatedFromTheirTimestamp() throws {
        try withTemporaryDefaults("cadence.codex.widget.followups") { defaults in
            let day = try #require(DateFormatters.date(from: "2026-10-04"))
            let before = try #require(Calendar.current.date(bySettingHour: 23, minute: 59, second: 45, of: day))
            let id = UUID()
            let payload: [String: Any] = ["timestamp": before.timeIntervalSince1970, "isDoneToday": true]
            defaults.set([id.uuidString: payload], forKey: "cadence.widgets.habits.recentlyChangedHabits")
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: before, userDefaults: defaults)[id] == true)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: before.addingTimeInterval(30), userDefaults: defaults)[id] == nil)
        }
    }

    @Test func codexCalendarReadyContentHasItsDatedBackgroundRoute() throws {
        let route = try CadenceScanInstrument(
            "calendar widget background route",
            fires: "content.widgetURL(entry.snapshot.calendarURL)",
            andNotOn: "// .widgetURL(entry.snapshot.calendarURL)\ncontent.widgetURL(otherURL)",
            by: { CadenceSourceScan.codeOnly($0).contains(".widgetURL(entry.snapshot.calendarURL)") }
        )
        let paths = ["CadenceWidgets/CalendarSnapshotWidget.swift"]
        #expect(try route.sweep(paths, atLeast: 1, including: paths[0], read: CadenceSourceScan.strippedSourceReader()) == paths)
    }

    /// **Re-pointed for [[T-2078]], not weakened, and not deleted.** This guard used to walk five
    /// widget sources. `7b686a76` deleted two of them with the Habit Check-In and Milestone
    /// Momentum widgets, and `sweep` *reads* every path it is handed — so the stale list did not
    /// fail an assertion, it threw `NSCocoaErrorDomain 260` and `main` was red on an I/O error
    /// rather than on the thing this test is for. The three survivors are walked, `atLeast:` is
    /// re-derived 5 -> 3 rather than relaxed to a floor, and the witness is **named rather than
    /// indexed**: `including: paths[2]` used to be `HabitCheckInWidget.swift`, so deleting array
    /// entries alone would have silently re-pointed the non-vacuity claim at a different file.
    ///
    /// **Which assertions died with which widget, and where the equivalent went.**
    /// - `HabitCheckInWidget.swift`: `limit: family.cadenceLayout.habitLimit` and
    ///   `paddedHabits(count: layout.habitLimit)` were the provider-side and the view-side halves
    ///   of one claim — the family budget reaches the drawn content. **Both halves survive and are
    ///   asserted below**: the provider half on `TodayTasksWidget` and `CalendarSnapshotWidget`,
    ///   and the view half as the new `TodayTasksWidgetView` block, which this test walked in its
    ///   sweep but never actually read. That gap is the reason the view block is added here rather
    ///   than the habit block merely being dropped.
    /// - `count: layout.habitColumns` and `.contentMarginsDisabled()` have **no equivalent** and
    ///   are gone. No surviving widget lays content out in a family-sized grid, and
    ///   `.contentMarginsDisabled()` now appears nowhere under `CadenceWidgets/`.
    /// - `!habit.contains("summaryRail")` is gone and **was already vacuous before T-2078**:
    ///   `summaryRail` occurs nowhere in this repository and did not occur in
    ///   `HabitCheckInWidget.swift` either, so it was true of any file including an empty one. It
    ///   is replaced by a negative control that can actually fire — the Today view must not
    ///   hardcode a row count equal to any family's `todayTaskLimit`.
    /// - `MilestoneMomentumWidget.swift`'s two `milestoneGoalLimit` reads were the clamp-then-
    ///   prefix pair. The identical pair on `calendarDayLimit` is asserted below and is untouched,
    ///   so the shape those two lines guarded is still guarded.
    ///
    /// `habitLimit`, `habitColumns` and `milestoneGoalLimit` still exist on
    /// `CadenceWidgetFamilyLayout` and are deliberately **not** removed here. After T-2078 their
    /// only readers anywhere in the tree are the model assertions in
    /// `codexWidgetFamilyBudgetsMatchTheSelectedContent` above; retiring the properties is a
    /// separate decision and a separate ticket, not a side effect of fixing a red run.
    @Test func codexWidgetProvidersAndViewsShareFamilyBudgets() throws {
        let rule = try CadenceScanInstrument(
            "widget family content budget",
            fires: "family.cadenceLayout.todayTaskLimit",
            andNotOn: "// family.cadenceLayout.todayTaskLimit\nlet limit = 8",
            by: { CadenceSourceScan.codeOnly($0).contains(".cadenceLayout.") }
        )
        // Named, not indexed: the witness must survive an edit to this list, not follow its order.
        let todayProviderPath = "CadenceWidgets/TodayTasksWidget.swift"
        let todayViewPath = "CadenceWidgets/TodayTasksWidgetView.swift"
        let calendarPath = "CadenceWidgets/CalendarSnapshotWidget.swift"
        let paths = [todayProviderPath, todayViewPath, calendarPath]
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try rule.sweep(paths, atLeast: 3, including: calendarPath, read: read) == paths.sorted())
        let calendar = CadenceSourceScan.codeOnly(try read(calendarPath))
        #expect(calendar.contains("renderedCount: snapshot.state == .ready"))
        #expect(calendar.contains("min(snapshot.days.count, family.cadenceLayout.calendarDayLimit)"))
        #expect(calendar.contains("family.cadenceLayout.calendarDayLimit) : 0"))
        #expect(calendar.contains("entry.snapshot.days.prefix(widgetFamily.cadenceLayout.calendarDayLimit)"))
        let today = CadenceSourceScan.codeOnly(try read(todayProviderPath))
        #expect(today.contains("family.cadenceLayout.todayTaskLimit"))
        #expect(today.contains("limit: snapshotLimit(for: family)"))
        #expect(today.contains("renderedCount: snapshot.tasks.count"))
        let todayView = CadenceSourceScan.codeOnly(try read(todayViewPath))
        #expect(todayView.contains("entry.snapshot.tasks.prefix(widgetFamily.cadenceLayout.todayTaskLimit)"))
        #expect(todayView.contains("prefix(widgetFamily.cadenceLayout.todayTaskLimit - 1)"))
        let hardcodedBudgets = CadenceWidgetFamilyLayout.allCases
            .map { "prefix(\($0.todayTaskLimit))" }
            .filter { todayView.contains($0) }
        #expect(hardcodedBudgets.isEmpty, "the Today view's row budget must come from cadenceLayout, not a literal")
    }

    /// [[T-7120]], [[T-7121]], [[T-7122]] — the shared half of all three defects, pinned where a
    /// later edit to either configuration would drop it silently.
    ///
    /// WidgetKit insets widget content by about 16pt a side unless a configuration opts out, and
    /// both widget views draw their own `scale.outerPadding` inside that. Together they spent 56pt
    /// of a 158pt `systemSmall` tile and 32pt of a 158pt `systemMedium` tile's height on chrome
    /// before any content was laid out — which is what made a small day cell ~31pt wide (every
    /// two-digit day number truncated to a bare ellipsis, seen on both standing simulators) and
    /// what pushed the medium header off the top edge of both widgets.
    ///
    /// This is a source assertion rather than a layout one on purpose: no test host here can ask
    /// SwiftUI what a widget's content margins resolved to, which is the same limit
    /// `CadenceCalendarCaptureClearanceTests` records for `contentMargins`. What CAN be held is
    /// that the opt-out is still written, on both configurations.
    @Test func codexWidgetConfigurationsOptOutOfWidgetKitContentMargins() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        for path in [
            "CadenceWidgets/TodayTasksWidget.swift",
            "CadenceWidgets/CalendarSnapshotWidget.swift",
        ] {
            let source = CadenceSourceScan.codeOnly(try read(path))
            #expect(
                source.contains(".contentMarginsDisabled()"),
                "\(path) must opt out of WidgetKit's default content margins (T-7120/T-7121/T-7122)"
            )
        }
    }

    /// T-7125: the widget gallery takes `snapshot`/`getSnapshot` with `isPreview` set, so a
    /// provider that answers it from the live store advertises an empty widget on a new install.
    /// What is held is the branch itself, in both providers; a WidgetKit host is what would show
    /// the picture, and this test has none.
    @Test func widgetGalleryPreviewsDrawThePlaceholderNotTheLiveStore() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let today = CadenceSourceScan.codeOnly(try read("CadenceWidgets/TodayTasksWidget.swift"))
        let calendar = CadenceSourceScan.codeOnly(try read("CadenceWidgets/CalendarSnapshotWidget.swift"))
        #expect(CadenceSourceScan.matchCount("context\\.isPreview\\s*\\?\\s*placeholderSnapshot\\(for: context\\.family\\)", in: today) == 1)
        #expect(calendar.contains("context.isPreview ? placeholderSnapshot() : currentSnapshot(for: context.family)"))
        // Non-vacuity: the live path is still what the timeline draws.
        #expect(CadenceSourceScan.matchCount("currentSnapshot\\(for: context\\.family\\)", in: today) == 2)
        #expect(CadenceSourceScan.matchCount("currentSnapshot\\(for: context\\.family\\)", in: calendar) == 2)
    }

    /// T-7123 / T-7124: the state card's title wraps and is laid out before its message, and the
    /// Calendar widget centers its state card beyond `systemSmall` exactly as Today does.
    @Test func widgetStateCardsKeepTheirTitleAndCenterBeyondSmall() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let chrome = CadenceSourceScan.codeOnly(try read("CadenceWidgets/WidgetChrome.swift"))
        let calendar = CadenceSourceScan.codeOnly(try read("CadenceWidgets/CalendarSnapshotWidget.swift"))
        let title = try #require(chrome.range(of: ".font(.system(size: scale.stateTitleSize, weight: .semibold))"))
        let message = try #require(chrome.range(of: "if let message, !message.isEmpty"))
        let titleBlock = String(chrome[title.upperBound..<message.lowerBound])
        #expect(titleBlock.contains(".lineLimit(2)"))
        #expect(titleBlock.contains(".layoutPriority(1)"))
        #expect(calendar.contains("widgetFamily == .systemSmall ? .leading : .center"))
        #expect(CadenceSourceScan.matchCount("alignment: stateCardAlignment", in: calendar) == 2)
    }

    /// T-7211 (b): T-7126's whole-or-nothing container name was meant for the iPad extra-large
    /// columns only. The same `taskRow` draws the medium rows and the large queue card, where a
    /// long list name used to truncate and, unscoped, vanished. The decision is the model's; the
    /// view is held to reading it, and to truncating (no `fixedSize`) everywhere else.
    @Test func todayRowDropsAnUnfittedContainerNameOnlyAtExtraLarge() throws {
        let families = CadenceWidgetFamilyLayout.allCases
        #expect(families.map(\.todayRowDropsContainerNameThatDoesNotFit) == [false, false, false, true])
        let read = CadenceSourceScan.strippedSourceReader()
        let view = CadenceSourceScan.codeOnly(try read("CadenceWidgets/TodayTasksWidgetView.swift"))
        // Two in the file: this row's, and `primaryTaskCard`'s (T-7315, held by its own test).
        #expect(CadenceSourceScan.matchCount("ViewThatFits\\(in: \\.horizontal\\)", in: view) == 2)
        let gate = try #require(view.range(of: "if widgetFamily.cadenceLayout.todayRowDropsContainerNameThatDoesNotFit {"))
        let fits = try #require(view.range(of: "ViewThatFits(in: .horizontal)", range: gate.upperBound..<view.endIndex))
        let otherwise = try #require(view.range(of: "statusLine(status, containerName: task.containerName, truncates: true)"))
        #expect(gate.upperBound <= fits.lowerBound && fits.upperBound <= otherwise.lowerBound)
        #expect(view.contains("statusLine(status, containerName: task.containerName, truncates: false)"))
        #expect(view.contains(".fixedSize(horizontal: !truncates, vertical: false)"))
    }

    /// T-7421 (3), owner-decided 2026-11-02: the extra-large row no longer drops every container
    /// name that does not fit whole. Its `ViewThatFits` offers, in order, the whole name, the name
    /// truncating above a minimum width, and the pill alone -- so a name that would only be the
    /// `[S` stub (T-7126) is still dropped, and every other overflow truncates as the medium and
    /// large rows do. The truncating candidate pins its ideal width to the floor, or
    /// `ViewThatFits` would measure it as the whole name and never pick it. Not parameterised.
    @Test func extraLargeTodayRowTruncatesAContainerNameAboveAFloorBeforeDroppingIt() throws {
        #expect(CadenceWidgetFamilyLayout.todayRowTruncatedContainerNameMinimumEms >= 3,
                "a floor under three caption ems lets the two-character stub back")
        let read = CadenceSourceScan.strippedSourceReader()
        let view = CadenceSourceScan.codeOnly(try read("CadenceWidgets/TodayTasksWidgetView.swift"))
        let gate = try #require(view.range(of: "if widgetFamily.cadenceLayout.todayRowDropsContainerNameThatDoesNotFit {"))
        let otherwise = try #require(view.range(of: "statusLine(status, containerName: task.containerName, truncates: true)", range: gate.upperBound..<view.endIndex))
        let choice = String(view[gate.upperBound..<otherwise.lowerBound])
        let whole = try #require(choice.range(of: "statusLine(status, containerName: task.containerName, truncates: false)"))
        let truncated = try #require(choice.range(of: #"truncates: true,\n\s*truncatedNameMinimumWidth: scale\.captionFontSize\n\s*\* CadenceWidgetFamilyLayout\.todayRowTruncatedContainerNameMinimumEms"#, options: .regularExpression))
        let pillAlone = try #require(choice.range(of: #"statusPill\(status\)\n\s*\}"#, options: .regularExpression))
        #expect(whole.upperBound <= truncated.lowerBound && truncated.upperBound <= pillAlone.lowerBound)
        let line = try #require(view.range(of: "private func statusLine("))
        let body = String(view[line.upperBound...].prefix(1400))
        #expect(body.contains("idealWidth: truncatedNameMinimumWidth"), "the truncating candidate must measure at its floor")
        #expect(body.contains("minWidth: truncatedNameMinimumWidth"))
    }

    /// T-7211 (a): the small Calendar tile draws its `d`/`p` chips side by side in ~30pt, so a
    /// two-digit count needs a lower shrink floor there than the stacked families need. The floor
    /// is the model's; the chip is held to reading it rather than a literal.
    @Test func calendarCountChipsShrinkFurtherOnlyOnTheSmallTile() throws {
        let floors = CadenceWidgetFamilyLayout.allCases.map(\.calendarCountChipMinimumScaleFactor)
        let small = try #require(floors.first)
        #expect(floors.dropFirst().allSatisfy { $0 == 0.9 })
        #expect(small < 0.9)
        #expect(small <= 0.75)
        let read = CadenceSourceScan.strippedSourceReader()
        let calendar = CadenceSourceScan.codeOnly(try read("CadenceWidgets/CalendarSnapshotWidget.swift"))
        let chip = try #require(calendar.range(of: "private func countChip("))
        let chipBody = String(calendar[chip.upperBound..<calendar.endIndex])
        #expect(chipBody.contains(".minimumScaleFactor(widgetFamily.cadenceLayout.calendarCountChipMinimumScaleFactor)"))
        #expect(CadenceSourceScan.matchCount("\\.minimumScaleFactor\\(0\\.", in: chipBody) == 0)
    }

    /// T-7211 (c): since T-7125 the widget gallery draws the Today placeholder for every user,
    /// and its first task is the one the small and large tiles headline. The sample copy is user
    /// copy: no task or list in it names the app or the widget work it was written during.
    @Test func todayPlaceholderSampleTasksReadAsUserCopy() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let today = try read("CadenceWidgets/TodayTasksWidget.swift")
        let start = try #require(today.range(of: "private func placeholderSnapshot(for family: WidgetFamily)"))
        let end = try #require(today.range(of: "return CadenceTodayWidgetSnapshot(", range: start.upperBound..<today.endIndex))
        let block = String(today[start.upperBound..<end.lowerBound])
        func values(_ key: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: key + ": \"([^\"]*)\"")
            let range = NSRange(block.startIndex..., in: block)
            return regex.matches(in: block, range: range).compactMap { match in
                Range(match.range(at: 1), in: block).map { String(block[$0]) }
            }
        }
        let titles = values("title")
        let lists = values("containerName")
        #expect(titles.count >= 2)
        #expect(lists.count == titles.count)
        for text in titles + lists {
            let lowered = text.lowercased()
            #expect(!lowered.contains("cadence") && !lowered.contains("widget"), "\(text)")
        }
    }

    /// T-7195: the populated Today `systemLarge` layout wanted ~387pt of the 354pt an iPhone 15
    /// gives that family. Its middle row is as tall as the summary panel, so the panel's spacing
    /// and the queue card's subtitle are the budget; measured offscreen, they now sum to ~348pt.
    /// What is held is each saving in its own block, since no WidgetKit host runs in this test.
    @Test func todayLargeSummaryPanelAndQueueSubtitleStayInsideTheIPhoneTile() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let view = CadenceSourceScan.codeOnly(try read("CadenceWidgets/TodayTasksWidgetView.swift"))
        func block(from start: String, to end: String) throws -> String {
            let lower = try #require(view.range(of: start))
            let upper = try #require(view.range(of: end, range: lower.upperBound..<view.endIndex))
            return String(view[lower.upperBound..<upper.lowerBound])
        }
        let panel = try block(from: "private var summaryPanel: some View {", to: "private var focusStrip: some View {")
        #expect(panel.contains("VStack(alignment: .leading, spacing: 4) {"))
        #expect(CadenceSourceScan.matchCount("metricTile\\(", in: panel) == 3)
        let tile = try block(from: "private func metricTile(", to: "private func focusTile(")
        #expect(tile.contains("VStack(alignment: .leading, spacing: 2) {"))
        #expect(!tile.contains(".padding(.vertical"))
        let card = try block(from: "private func taskStackCard(", to: "private func taskColumnCard(")
        let subtitle = try block(from: "Text(subtitle)", to: "ForEach(tasks)")
        #expect(card.contains("Text(subtitle)"))
        #expect(subtitle.contains(".lineLimit(1)"))
    }

    /// T-7285: the large layout's `VStack` proposed the `Priority now` row an even split of the
    /// tile, less than a two-line title needs, so the title drew one truncated line even though
    /// the summary panel made the row taller anyway. The row asks for its own height instead.
    /// Held here: exactly one vertical `fixedSize` in `largeLayout`, on the row (after the panel,
    /// before the queue), and none in `extraLargeLayout`, which draws the same card in a tile
    /// that has no height for a third title line.
    @Test func todayLargePriorityRowTakesItsOwnHeightSoTheTitleWraps() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let view = CadenceSourceScan.codeOnly(try read("CadenceWidgets/TodayTasksWidgetView.swift"))
        func block(from start: String, to end: String) throws -> String {
            let lower = try #require(view.range(of: start))
            let upper = try #require(view.range(of: end, range: lower.upperBound..<view.endIndex))
            return String(view[lower.upperBound..<upper.lowerBound])
        }
        let verticalFit = "\\.fixedSize\\(horizontal: false, vertical: true\\)"
        let large = try block(from: "private var largeLayout: some View {", to: "private var extraLargeLayout: some View {")
        #expect(CadenceSourceScan.matchCount(verticalFit, in: large) == 1)
        let panel = try #require(large.range(of: ".frame(width: 132)"))
        let fit = try #require(large.range(of: ".fixedSize(horizontal: false, vertical: true)"))
        let queue = try #require(large.range(of: "let queueTasks"))
        #expect(panel.upperBound <= fit.lowerBound && fit.upperBound <= queue.lowerBound)
        let extraLarge = try block(from: "private var extraLargeLayout: some View {", to: "private var summaryPanel: some View {")
        #expect(CadenceSourceScan.matchCount(verticalFit, in: extraLarge) == 0)
        let card = try block(from: "private func primaryTaskCard(", to: "private func taskStackCard(")
        #expect(CadenceSourceScan.matchCount(verticalFit, in: card) == 0)
    }

    /// T-7315: on the iPhone's large tile the `Priority now` card's container pill was left
    /// ~40pt beside a `fixedSize` dated status pill and drew `[Sa...`. Beyond the compact card it
    /// now rides only when it fits WHOLE, the choice T-7126 made for the extra-large rows: a
    /// `ViewThatFits` whose first child is both pills, the name unsqueezable, and whose fallback
    /// is the status pill alone. The compact card (small, medium) keeps truncating as before.
    /// The row has no `Spacer`, which would make its `HStack` offer the choice only part of the
    /// width. No WidgetKit host runs here; the harness renders are in the ledger entry.
    @Test func todayPriorityCardDropsAContainerNameThatDoesNotFitWhole() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let view = CadenceSourceScan.codeOnly(try read("CadenceWidgets/TodayTasksWidgetView.swift"))
        let start = try #require(view.range(of: "private func primaryTaskCard("))
        let end = try #require(view.range(of: "private func taskStackCard(", range: start.upperBound..<view.endIndex))
        let card = String(view[start.upperBound..<end.lowerBound])
        #expect(CadenceSourceScan.matchCount("ViewThatFits\\(in: \\.horizontal\\)", in: card) == 1)
        let compactBranch = try #require(card.range(of: "if compact {\n                HStack(spacing: 6) {"))
        let fits = try #require(card.range(of: "ViewThatFits(in: .horizontal)"))
        #expect(compactBranch.upperBound <= fits.lowerBound)
        let choice = String(card[fits.upperBound...])
        let whole = try #require(choice.range(of: "containerPill(task.containerName)\n                                .fixedSize()"))
        let fallback = try #require(choice.range(of: "statusPill(status)\n                }\n                .frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(whole.upperBound <= fallback.lowerBound)
        #expect(!String(choice[..<fallback.upperBound]).contains("Spacer("))
    }

    /// T-10000: the Calendar widget's metric cards drew Overdue, Scheduled and Due all in the body
    /// colour, Scheduled before Due, while the tile's own medium badge line and the Today
    /// widget's summary panel read overdue red, due amber, scheduled blue in that order. Held
    /// here: both card sites draw one shared `metricCards`, which names each tint in that order,
    /// and the Today panel still says the same three.
    @Test func calendarMetricCardsTintAndOrderTheirCountsLikeTheTodayPanel() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        // Not `codeOnly`: it blanks the string literals that name each card.
        let calendar = try read("CadenceWidgets/CalendarSnapshotWidget.swift")
        let today = CadenceSourceScan.codeOnly(try read("CadenceWidgets/TodayTasksWidgetView.swift"))
        #expect(CadenceSourceScan.matchCount("CadenceWidgetMetricCard\\(", in: calendar) == 3)
        #expect(CadenceSourceScan.matchCount("(?m)^\\s*metricCards$", in: calendar) == 2)
        let start = try #require(calendar.range(of: "private var metricCards: some View {"))
        let cards = String(calendar[start.upperBound...])
        let overdue = try #require(cards.range(of: "title: \"Overdue\", value: \"\\(entry.snapshot.overdueCount)\", valueTint: Theme.red)"))
        let due = try #require(cards.range(of: "title: CadenceWidgetCountWords.dueTitle, value: \"\\(dueCount)\", valueTint: Theme.amber)"))
        let scheduled = try #require(cards.range(of: "title: CadenceWidgetCountWords.plannedTitle, value: \"\\(scheduledCount)\", valueTint: Theme.blueLight)"))
        #expect(overdue.upperBound <= due.lowerBound && due.upperBound <= scheduled.lowerBound)
        let panelStart = try #require(today.range(of: "private var summaryPanel: some View {"))
        let panel = String(today[panelStart.upperBound...])
        let red = try #require(panel.range(of: "tint: Theme.red"))
        let amber = try #require(panel.range(of: "tint: Theme.amber"))
        let blue = try #require(panel.range(of: "tint: Theme.blueLight"))
        #expect(red.upperBound <= amber.lowerBound && amber.upperBound <= blue.lowerBound)
    }

    /// T-10002: the two widgets named the due-today count "due now" / "due" / "Due today" / "Due"
    /// and the do-date count "planned" / "scheduled" / "Scheduled" by family. One word each now,
    /// read from `CadenceWidgetCountWords` at every site: "due now" claimed a task due today was
    /// due this minute, and "scheduled" reads as a scheduled start time.
    @Test func bothWidgetsNameEachCountWithOneSharedWord() throws {
        #expect(CadenceWidgetCountWords.due == "due")
        #expect(CadenceWidgetCountWords.planned == "planned")
        #expect(CadenceWidgetCountWords.dueTitle == "Due")
        #expect(CadenceWidgetCountWords.plannedTitle == "Planned")
        #expect(CadenceWidgetCountWords.badge(3, CadenceWidgetCountWords.due) == "3 due")
        #expect(CadenceWidgetCountWords.badge(1, CadenceWidgetCountWords.planned) == "1 planned")

        let read = CadenceSourceScan.strippedSourceReader()
        // Not `codeOnly`: the retired words live in string literals.
        let today = try read("CadenceWidgets/TodayTasksWidgetView.swift")
        let calendar = try read("CadenceWidgets/CalendarSnapshotWidget.swift")
        for (path, code, badges, titles) in [
            ("TodayTasksWidgetView", today, 5, 4),
            ("CalendarSnapshotWidget", calendar, 2, 2),
        ] {
            #expect(CadenceSourceScan.matchCount("CadenceWidgetCountWords\\.badge\\(", in: code) == badges, "\(path) badge sites")
            #expect(CadenceSourceScan.matchCount("CadenceWidgetCountWords\\.(due|planned)Title", in: code) == titles, "\(path) title sites")
            #expect(CadenceSourceScan.matchCount("\\) (due|due now|planned|scheduled)\"", in: code) == 0, "\(path) types a count word again")
            for retired in ["\"Due today\"", "\"Scheduled\"", "\"Due\"", "\"Planned\""] {
                #expect(!code.contains(retired), "\(path) types \(retired) instead of the shared word")
            }
        }
    }

    /// T-10001: two cards lay flat among lifted siblings -- the Today extra-large focus strip's
    /// tiles, under a shadowed priority card and beside shadowed column panels, and the Calendar
    /// extra-large agenda's next-up card, under three shadowed metric cards. Held here: the focus
    /// tile carries the shared elevation, and the next-up card is drawn by `CadenceWidgetPanel`,
    /// whose chrome carries it, rather than by a hand copy of that chrome without the shadow.
    @Test func widgetExtraLargeCardsLiftLikeTheirSiblings() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let calendar = CadenceSourceScan.codeOnly(try read("CadenceWidgets/CalendarSnapshotWidget.swift"))
        let today = CadenceSourceScan.codeOnly(try read("CadenceWidgets/TodayTasksWidgetView.swift"))
        let chrome = CadenceSourceScan.codeOnly(try read("CadenceWidgets/WidgetChrome.swift"))
        let tileStart = try #require(today.range(of: "private func focusTile("))
        let tileEnd = try #require(today.range(of: "private func emptyState(", range: tileStart.upperBound..<today.endIndex))
        #expect(today[tileStart.upperBound..<tileEnd.lowerBound].contains(".cadenceWidgetElevation(scale)"))
        let agendaStart = try #require(calendar.range(of: "private var agendaPanel: some View {"))
        let agendaEnd = try #require(calendar.range(of: "private var metricCards: some View {", range: agendaStart.upperBound..<calendar.endIndex))
        let agenda = String(calendar[agendaStart.upperBound..<agendaEnd.lowerBound])
        let panel = try #require(agenda.range(of: "CadenceWidgetPanel {"))
        let nextUp = try #require(agenda.range(of: "nextUpSection(titleLineLimit: 2)"))
        #expect(panel.upperBound <= nextUp.lowerBound)
        #expect(!agenda.contains(".background("))
        let panelChromeStart = try #require(chrome.range(of: "struct CadenceWidgetPanel<Content: View>: View {"))
        #expect(chrome[panelChromeStart.upperBound...].contains(".cadenceWidgetElevation(scale)"))
    }

    @Test func codexHabitSnapshotRequestsOverridesForItsOwnDate() throws {
        let rule = try CadenceScanInstrument(
            "habit snapshot dated override",
            fires: "CadenceWidgetRefreshCenter.recentHabitCompletionStates(dateKey: todayKey)",
            andNotOn: "// recentHabitCompletionStates(dateKey: todayKey)\nCadenceWidgetRefreshCenter.recentHabitCompletionStates()",
            by: { CadenceSourceScan.codeOnly($0).contains("recentHabitCompletionStates(dateKey: todayKey)") }
        )
        let paths = ["Cadence/Services/CadenceHabitWidgetSupport.swift"]
        #expect(try rule.sweep(paths, atLeast: 1, including: paths[0], read: CadenceSourceScan.strippedSourceReader()) == paths)
    }

}
