import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The Notes sidebar — month headings with dated rows under them — became one implementation for
/// macOS, iPad and iPhone, and grew a fold.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning
/// `CadenceNotesListMetrics.desktop.dayNumberWidth == 20` proves the shared thing is correct; it
/// proves nothing about anybody *using* it. T-161 is the standing example: a committed fix was
/// reverted and every test stayed green, because the tests pinned a helper while nothing observed
/// the call sites. So the fold arithmetic and the figures are pinned below **and** the call sites
/// are read out of the real source files, so a platform quietly going back to its own list fails
/// here.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The precedent is `CadenceSharedBoardChromeTests` and `NoteEditorPerformanceRegressionTests`,
/// which guard their call sites the same way.
@MainActor
struct CadenceNotesListSupportTests {

    // MARK: - Figures: what is shared

    /// Everything the two surfaces could agree on, they agree on. These are the figures that would
    /// otherwise be typed twice and drift — the day-number gap is the one macOS had to widen from
    /// 9pt because a number and the first word of a title read as one run, and a phone typing its
    /// own 9 would rediscover that.
    @Test func theFiguresThatCouldBeSharedAreShared() {
        for surface in CadencePageHeaderSurface.allCases {
            let metrics = CadenceNotesListMetrics.metrics(for: surface)
            #expect(metrics.dayNumberSpacing == 14, "\(surface) day-number spacing")
            #expect(metrics.rowHorizontalPadding == 10, "\(surface) row padding")
            #expect(metrics.columnVerticalPadding == 10, "\(surface) column padding")
        }
    }

    /// iPhone and iPad are one style. They differ in *layout* — the column is the whole screen on
    /// the phone and one of two panes on iPad — and must not differ in how a row looks. There is one
    /// touch tier, spelled twice only because the size class has two names.
    @Test func iPhoneAndIPadDrawTheIdenticalRow() {
        #expect(CadenceNotesListMetrics.metrics(for: .compact) == CadenceNotesListMetrics.metrics(for: .regular))
        #expect(CadenceNotesListMetrics.metrics(isRegularWidth: false) == CadenceNotesListMetrics.metrics(for: .compact))
        #expect(CadenceNotesListMetrics.metrics(isRegularWidth: true) == CadenceNotesListMetrics.metrics(for: .regular))
    }

    // MARK: - Figures: what could not be shared, and why

    /// The clearest figure that could not be shared. A 24pt-tall macOS row is a pointer target; a
    /// touch row has a 44pt floor. `.desktop` is a third tier for the same reason
    /// `CadencePageHeaderSurface` has one — folding it into `.regular` would put a 44pt minimum on
    /// every row of a Mac window's index column.
    @Test func onlyTheTouchTiersTakeTheFortyFourPointFloor() {
        #expect(CadenceNotesListMetrics.desktop.rowMinHeight == 0)
        #expect(CadenceNotesListMetrics.desktop.headerMinHeight == 0)
        #expect(CadenceNotesListMetrics.metrics(for: .compact).rowMinHeight == 44)
        #expect(CadenceNotesListMetrics.metrics(for: .compact).headerMinHeight == 44)
    }

    /// The macOS column is unchanged by the move: these are the literals
    /// `macOS/Views/NotesListRows.swift` held before it became shared. A "unify the platforms"
    /// change that quietly restyles the one surface that already worked is not a unification.
    @Test func theDesktopColumnIsExactlyWhatMacOSAlreadyDrew() {
        let desktop = CadenceNotesListMetrics.desktop
        #expect(desktop.dayNumberWidth == 20)
        #expect(desktop.rowVerticalPadding == 6)
        #expect(desktop.dayNumberSize == 12)
        #expect(desktop.titleSize == 12)
        #expect(desktop.detailSize == 11)
        #expect(desktop.headerLabelSize == 11)
        #expect(desktop.groupSpacing == 10)
        #expect(desktop.rowSpacing == 3)
        #expect(desktop.columnHorizontalPadding == 8)
        #expect(CadenceNotesListMetrics.columnMinWidth == 180)
        #expect(CadenceNotesListMetrics.columnIdealWidth == 224)
        #expect(CadenceNotesListMetrics.columnMaxWidth == 300)
    }

    /// Every heading sets type one point over the day number beside it. That relationship is what
    /// makes a heading out-read its own rows, and it is what survives the tier difference — not the
    /// absolute 11 or 12.
    @Test func theHeadingOutSetsItsOwnRowsOnEveryTier() {
        for surface in CadencePageHeaderSurface.allCases {
            let metrics = CadenceNotesListMetrics.metrics(for: surface)
            #expect(metrics.headerLabelSize == metrics.dayNumberSize - 1, "\(surface)")
        }
    }

    /// Adding a fold chevron must not move the text the user already knows the position of: the
    /// chevron's slot plus the gap after it exactly consume the heading's leading padding, so the
    /// title still starts on the day-number column's left edge.
    @Test func theChevronIsAbsorbedByTheHeadingsLeadingPadding() {
        for surface in CadencePageHeaderSurface.allCases {
            let metrics = CadenceNotesListMetrics.metrics(for: surface)
            #expect(metrics.headerHorizontalPadding == metrics.rowHorizontalPadding, "\(surface)")
            #expect(metrics.headerLeadingPadding == 0, "\(surface)")
            let titleX = metrics.headerLeadingPadding
                + CadenceNotesListMetrics.headerChevronSlot
                + CadenceNotesListMetrics.headerChevronSpacing
            #expect(titleX == metrics.rowHorizontalPadding, "\(surface) title x")
        }
    }

    // MARK: - Fold state: the arithmetic

    @Test func nothingIsFoldedOnAFreshInstall() {
        let state = CadenceNotesFoldState()
        #expect(state.isCollapsed(month: "2026-08", kind: .daily) == false)
        #expect(state.collapsedMonths(kind: .daily).isEmpty)
        #expect(state.encoded().isEmpty)
    }

    @Test func togglingFoldsAndUnfoldsTheSameMonth() {
        var state = CadenceNotesFoldState()
        state.toggle(month: "2026-08", kind: .daily)
        #expect(state.isCollapsed(month: "2026-08", kind: .daily))
        state.toggle(month: "2026-08", kind: .daily)
        #expect(state.isCollapsed(month: "2026-08", kind: .daily) == false)
    }

    /// The whole reason the state is keyed by kind. `2026-08` names a different group in each of the
    /// four lists, so a global set would fold four columns from one tap — and Notepad, which groups
    /// by creation month only because a notepad note has no date, would follow a decision the user
    /// made about their Daily archive.
    @Test func foldingOneKindLeavesTheOtherThreeAlone() {
        var state = CadenceNotesFoldState()
        state.toggle(month: "2026-08", kind: .daily)

        #expect(state.isCollapsed(month: "2026-08", kind: .daily))
        #expect(state.isCollapsed(month: "2026-08", kind: .weekly) == false)
        #expect(state.isCollapsed(month: "2026-08", kind: .permanent) == false)
        #expect(state.isCollapsed(month: "2026-08", kind: .meeting) == false)
    }

    @Test func collapseAllFoldsEveryListedSectionAndOnlyThose() throws {
        let context = try makeContext()
        let sections = NotesListGrouping.sections(
            for: [daily("2026-08-09", "a", in: context), daily("2026-07-20", "b", in: context)],
            kind: .daily,
            foldState: CadenceNotesFoldState(),
            dateKey: { $0.dateKey }
        )

        var state = CadenceNotesFoldState()
        state.collapseAll(sections, kind: .daily)

        #expect(state.collapsedMonths(kind: .daily) == ["2026-08", "2026-07"])
        // A month the user has never seen gets no entry: only what is listed can be folded.
        #expect(state.isCollapsed(month: "2026-06", kind: .daily) == false)
    }

    /// `expandAll` is the escape hatch, so it must clear months that are no longer listed too —
    /// otherwise a fold could survive with nothing on screen able to undo it.
    @Test func expandAllClearsEvenMonthsThatAreNoLongerListed() {
        var state = CadenceNotesFoldState()
        state.setCollapsed(true, month: "2026-08", kind: .daily)
        state.setCollapsed(true, month: "2019-01", kind: .daily)
        state.setCollapsed(true, month: "2026-08", kind: .weekly)

        state.expandAll(kind: .daily)

        #expect(state.collapsedMonths(kind: .daily).isEmpty)
        #expect(state.isCollapsed(month: "2026-08", kind: .weekly))
    }

    /// An empty list has nothing folded, so it must not report "everything is folded" — that would
    /// light up an unfold control with nothing to unfold.
    @Test func anEmptyListIsNotEverythingCollapsed() {
        #expect(CadenceNotesFoldState().isEverythingCollapsed(in: []) == false)
    }

    @Test func everythingCollapsedIsTrueOnlyWhenNoSectionIsOpen() throws {
        let context = try makeContext()
        let notes = [daily("2026-08-09", "a", in: context), daily("2026-07-20", "b", in: context)]

        var state = CadenceNotesFoldState()
        state.setCollapsed(true, month: "2026-08", kind: .daily)
        let half = NotesListGrouping.sections(for: notes, kind: .daily, foldState: state, dateKey: { $0.dateKey })
        #expect(state.isEverythingCollapsed(in: half) == false)

        state.setCollapsed(true, month: "2026-07", kind: .daily)
        let all = NotesListGrouping.sections(for: notes, kind: .daily, foldState: state, dateKey: { $0.dateKey })
        #expect(state.isEverythingCollapsed(in: all))
    }

    // MARK: - Fold state: storage

    @Test func theStateSurvivesAnEncodeDecodeRoundTrip() {
        var state = CadenceNotesFoldState()
        state.setCollapsed(true, month: "2026-08", kind: .daily)
        state.setCollapsed(true, month: "2026-07", kind: .daily)
        state.setCollapsed(true, month: "2025-12", kind: .meeting)

        #expect(CadenceNotesFoldState.decoded(state.encoded()) == state)
    }

    /// `Set` and `Dictionary` iteration order are not stable, and this blob is re-encoded on every
    /// toggle from a view that a live `@Query` rebuilds. An unstable encoding would rewrite
    /// `UserDefaults` — and wake every `@AppStorage` observer — for no change at all.
    @Test func theEncodingIsStableAcrossRuns() {
        var state = CadenceNotesFoldState()
        for month in ["2026-08", "2024-02", "2025-11", "2026-01"] {
            state.setCollapsed(true, month: month, kind: .daily)
        }
        state.setCollapsed(true, month: "2026-03", kind: .weekly)

        let encoded = state.encoded()
        for _ in 0..<8 {
            #expect(CadenceNotesFoldState.decoded(encoded).encoded() == encoded)
        }
    }

    /// Unfolding the last month leaves the blob a fresh install has, rather than `{"daily":[]}`
    /// that the next reader has to squint at to see is not state.
    @Test func unfoldingEverythingLeavesNoStoredState() {
        var state = CadenceNotesFoldState()
        state.setCollapsed(true, month: "2026-08", kind: .daily)
        state.setCollapsed(false, month: "2026-08", kind: .daily)

        #expect(state.encoded().isEmpty)
        #expect(state == CadenceNotesFoldState())
    }

    /// The write-only-key hazard, handled at the only place it can bite this key: a stored entry
    /// for a note kind that no longer exists is dropped on read, and the next write persists the
    /// pruned form. (`CadenceNotesEditorPreferences.purgeRetiredKeys()` is the handling for a key
    /// with no readers at all; this one is read by five call sites, asserted below.)
    @Test func anEntryForAKindThatNoLongerExistsIsDropped() {
        let raw = #"{"daily":["2026-08"],"seance":["2026-08"]}"#
        let decoded = CadenceNotesFoldState.decoded(raw)

        #expect(decoded.isCollapsed(month: "2026-08", kind: .daily))
        #expect(decoded.encoded() == #"{"daily":["2026-08"]}"#)
    }

    /// Anything unreadable decodes to "nothing is folded" — the only failure mode that cannot hide
    /// a note behind a heading the user did not close.
    @Test func garbageDecodesToNothingFolded() {
        for raw in ["", "not json", "[]", "{\"daily\":42}", "{\"daily\":[]}"] {
            #expect(CadenceNotesFoldState.decoded(raw) == CadenceNotesFoldState(), "\(raw)")
        }
    }

    // MARK: - Sections: grouping plus the fold

    @Test func aCollapsedSectionKeepsItsCountAndDropsItsRows() throws {
        let context = try makeContext()
        let notes = [
            daily("2026-08-09", "a", in: context),
            daily("2026-08-02", "b", in: context),
            daily("2026-07-20", "c", in: context)
        ]

        var state = CadenceNotesFoldState()
        state.setCollapsed(true, month: "2026-08", kind: .daily)
        let sections = NotesListGrouping.sections(for: notes, kind: .daily, foldState: state, dateKey: { $0.dateKey })

        #expect(sections.map(\.id) == ["2026-08", "2026-07"])
        #expect(sections[0].isCollapsed)
        #expect(sections[0].notes.isEmpty)
        // The count is what lets a folded heading say how much it is hiding without the column
        // keeping a second copy of the grouping to ask.
        #expect(sections[0].noteCount == 2)
        #expect(sections[1].isCollapsed == false)
        #expect(sections[1].notes.map(\.id) == [notes[2].id])
    }

    /// A heading standing over nothing reads as a loading failure. Folding must not be able to
    /// produce one, and neither must filtering: `sections` cannot invent a group, and a collapsed
    /// section is not this case — it carries `noteCount > 0` and says so.
    @Test func aMonthWithNothingInItNeverBecomesASection() throws {
        let context = try makeContext()
        // July's only note is blank, so the filter removes it entirely.
        let listed = NotesListVisibility.dailyNotes(
            [daily("2026-08-09", "a", in: context), daily("2026-07-20", "", in: context)],
            todayKey: "2026-08-10"
        )

        var state = CadenceNotesFoldState()
        // Folded or not, July has no heading to fold.
        state.setCollapsed(true, month: "2026-07", kind: .daily)
        let sections = NotesListGrouping.sections(for: listed, kind: .daily, foldState: state, dateKey: { $0.dateKey })

        #expect(sections.map(\.id) == ["2026-08"])
        #expect(sections.allSatisfy { $0.noteCount > 0 })
        #expect(NotesListGrouping.sections(for: [], kind: .daily, foldState: state, dateKey: { $0.dateKey }).isEmpty)
    }

    /// Month keys are deliberately **not** pruned when their group stops being listed. Writing in
    /// that month again must find it exactly as it was left — a fold that forgot itself because the
    /// last note was deleted would flicker back open the moment a note returned.
    @Test func aFoldSurvivesItsMonthBeingFilteredAwayAndComingBack() throws {
        let context = try makeContext()
        var state = CadenceNotesFoldState()
        state.setCollapsed(true, month: "2026-07", kind: .daily)

        let blankJuly = daily("2026-07-20", "", in: context)
        let listedWhileBlank = NotesListVisibility.dailyNotes([blankJuly], todayKey: "2026-08-10")
        #expect(NotesListGrouping.sections(for: listedWhileBlank, kind: .daily, foldState: state, dateKey: { $0.dateKey }).isEmpty)

        blankJuly.content = "written again"
        let listedAfter = NotesListVisibility.dailyNotes([blankJuly], todayKey: "2026-08-10")
        let sections = NotesListGrouping.sections(for: listedAfter, kind: .daily, foldState: state, dateKey: { $0.dateKey })

        #expect(sections.map(\.id) == ["2026-07"])
        #expect(sections[0].isCollapsed)
        #expect(sections[0].noteCount == 1)
    }

    /// The fallback the grouping has always carried, kept as a test because it is the reason a note
    /// with a malformed key does not silently disappear from the column.
    @Test func aNoteWithAnUnparseableKeyFilesUnderItsLastEdit() throws {
        let context = try makeContext()
        let note = Note(kind: .daily, title: "broken", content: "a", dateKey: "not-a-date")
        note.updatedAt = DateFormatters.date(from: "2026-05-04")!
        context.insert(note)

        let sections = NotesListGrouping.sections(
            for: [note],
            kind: .daily,
            foldState: CadenceNotesFoldState(),
            dateKey: { $0.dateKey }
        )

        #expect(sections.map(\.id) == ["2026-05"])
        #expect(sections[0].title == "MAY 2026")
    }

    /// Event Notes file under the event's day, and fall back to the last edit — the same
    /// "nothing silently disappears" rule, now shared with iOS instead of spelled privately inside
    /// the macOS page.
    @Test func eventNotesFileUnderTheEventsOwnDay() throws {
        let context = try makeContext()
        let dated = Note(kind: .meeting, title: "Standup", content: "a")
        dated.eventDateKey = "2026-08-11"
        let undated = Note(kind: .meeting, title: "Ad hoc", content: "b")
        undated.updatedAt = DateFormatters.date(from: "2026-06-02")!
        context.insert(dated)
        context.insert(undated)

        #expect(NotesListVisibility.meetingDayKey(for: dated) == "2026-08-11")
        #expect(NotesListVisibility.meetingDayKey(for: undated) == "2026-06-02")
        #expect(NotesListVisibility.meetingNotes([undated, dated]).map(\.id) == [dated.id, undated.id])
    }

    /// `NoteKind.meeting`'s raw value is persisted in `Note.kindRaw`; only the label reads "Event
    /// Notes". The tab the fold is filed under has to be that same case, or a folded Event Notes
    /// month would be filed under a kind nothing reads.
    @Test func theEventsTabIsFiledUnderTheMeetingKind() {
        #expect(CadenceMobileNotesTab.events.noteKind == .meeting)
        #expect(NoteKind.meeting.rawValue == "meeting")
        #expect(CadenceMobileNotesTab.today.noteKind == .daily)
        #expect(CadenceMobileNotesTab.week.noteKind == .weekly)
        #expect(CadenceMobileNotesTab.notepad.noteKind == .permanent)
    }

    // MARK: - The call sites

    /// **The T-161 test.** Every Notes list on both platforms must reach the shared column. Revert
    /// any one of these five call sites to a local list and this fails; pinning the metrics and the
    /// fold arithmetic above would not have noticed.
    ///
    /// macOS has four because it has four pages; iOS has one because one view switches between the
    /// four tabs. A legitimate new Notes list is a line in this table.
    @Test func everyNotesListOnBothPlatformsDrawsTheSharedFoldableColumn() throws {
        try expectNotesCallSites(
            of: "NotesFoldableListColumn",
            at: [
                "Cadence/macOS/Views/NotesView.swift": 4,
                "Cadence/iOS/iOSNotesView.swift": 1
            ]
        )
    }

    /// The fold cannot be half-adopted. `NotesGroupedListColumn` renders sections it is handed and
    /// knows nothing about storage; `NotesFoldableListColumn` is the only thing that owns the
    /// `@AppStorage` and the only caller of `NotesListGrouping.sections`. A surface that reached
    /// past it would render a column whose headings did not fold — which is exactly how the four
    /// macOS pages and the one iOS view would drift apart again.
    @Test func theFoldHasExactlyOneOwner() throws {
        let shared = try notesSource("Cadence/Shared/CadenceNotesListSupport.swift")
        #expect(shared.components(separatedBy: "NotesListGrouping.sections(").count - 1 == 1)
        #expect(shared.components(separatedBy: "NotesGroupedListColumn(").count - 1 == 1)
        #expect(shared.components(separatedBy: "@AppStorage(CadenceNotesFoldState.storageKey)").count - 1 == 1)

        for path in try notesSwiftFiles(under: "Cadence") where path != "Cadence/Shared/CadenceNotesListSupport.swift" {
            let code = try notesStrippingComments(notesSource(path))
            #expect(code.contains("NotesListGrouping.sections(") == false, "\(path) bypasses the fold")
            #expect(code.contains("NotesGroupedListColumn(") == false, "\(path) renders the column without the fold")
            #expect(code.contains(CadenceNotesFoldState.storageKey) == false, "\(path) reads the fold key directly")
        }
    }

    /// The two macOS files this moved out of are gone, not emptied — and nothing may declare their
    /// contents again under any platform guard. A second `NotesListGrouping` behind `#if os(iOS)`
    /// would compile, pass every test above, and be the fork this change exists to remove.
    @Test func neitherPlatformDeclaresItsOwnCopy() throws {
        for retired in ["Cadence/macOS/Views/NotesListRows.swift", "Cadence/macOS/Views/NotesListVisibilitySupport.swift"] {
            #expect(FileManager.default.fileExists(atPath: notesRepositoryRoot().appendingPathComponent(retired).path) == false, "\(retired) still exists")
        }

        let declarations = [
            "NoteMonthGroup", "CadenceNotesListSection", "NotesListGrouping", "NotesListVisibility",
            "NotesListMetrics", "CadenceNotesListMetrics", "CadenceNotesFoldState", "CadenceNotesLayout",
            "NotesMonthHeader", "NotesGroupedListColumn", "NotesFoldableListColumn", "NoteListDayRow",
            "DailyNoteListRow", "WeeklyNoteListRow", "MeetingNoteListRow", "NotepadNoteListRow",
            // The two iOS spellings this replaced. Neither may come back.
            "iOSMeetingNotesList", "iOSNoteListRowMetrics"
        ]
        let allowed = "Cadence/Shared/CadenceNotesListSupport.swift"

        for path in try notesSwiftFiles(under: "Cadence") where path != allowed {
            let code = try notesStrippingComments(notesSource(path))
            for name in declarations {
                #expect(
                    code.range(of: "(struct|class|enum|typealias)\\s+\(name)\\b", options: .regularExpression) == nil,
                    "\(path) declares \(name)"
                )
            }
        }
    }

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    @discardableResult
    private func daily(_ dateKey: String, _ content: String, in context: ModelContext) -> Note {
        let note = Note(kind: .daily, title: dateKey, content: content, dateKey: dateKey)
        context.insert(note)
        return note
    }
}

// MARK: - Source-reading helpers
//
// Deliberately private to this file rather than shared with `CadenceSharedBoardChromeTests`, which
// carries its own set: a test that reads source is only as trustworthy as its own reader, and one
// file's helpers changing under another file's assertions is the failure mode these exist to catch.

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** Asserting only that a file still mentions the shared component
/// somewhere lets one of several call sites revert unnoticed — which is T-161 reproduced inside the
/// test written to prevent it. A count that has to be edited on purpose is the point.
private func expectNotesCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try notesStrippingComments(notesSource(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func notesRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
private func notesSwiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = notesRepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func notesSource(_ relativePath: String) throws -> String {
    try String(contentsOf: notesRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make these
/// checks stricter about what counts as a comment, never looser about live code.
private func notesStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}

// MARK: - T-177: two columns or one

/// **The notes split had no floor.** It branched on the horizontal size class alone — no width input
/// at all — so every regular-width host got two columns however little room it had, and the list
/// took `regularColumnWidth` off the top of it as a fixed frame. On an iPad Air 13" in portrait with
/// the shell sidebar out, Today's inspector is 320pt wide, which left the markdown editor
/// **320 − 280 − 1 = 39pt**: one character per line.
///
/// Two kinds of test again, and the second kind is again the point. The arithmetic below proves the
/// floor is derived rather than picked; `theNotesSplitReadsTheFloorRatherThanTheSizeClass` proves
/// the view *asks*. T-161 is the standing example of why the first without the second is not enough.
@MainActor
struct CadenceNotesTwoColumnFloorTests {
    /// The shell sidebar, spelled out because `iOSSidebarMetrics` lives under `Cadence/iOS/` inside
    /// `#if os(iOS)` and this target builds for macOS.
    private static let sidebarWidth: CGFloat = 188

    private func layout(hostWidth: CGFloat) -> CadenceNotesLayout {
        CadenceNotesListMetrics.layout(isRegularWidth: true, hostWidth: hostWidth)
    }

    /// **The derivation, not the number.** Stated in terms of the parts on both sides, so raising
    /// `regularColumnWidth` moves the boundary with it and a hand-typed `601` fails here the moment
    /// any part changes.
    @Test func theFloorIsTheSumOfItsPartsAndTheBoundaryFollowsThem() {
        let sum = CadenceNotesListMetrics.regularColumnWidth
            + CadenceNotesListMetrics.columnDividerWidth
            + CadenceNotesListMetrics.minimumEditorWidth
        #expect(CadenceNotesListMetrics.twoColumnMinimumWidth == sum)
        #expect(layout(hostWidth: sum) == .twoColumn)
        #expect(layout(hostWidth: sum - 1) == .oneColumn)
        #expect(CadenceNotesListMetrics.supportsTwoColumns(hostWidth: sum))
        #expect(CadenceNotesListMetrics.supportsTwoColumns(hostWidth: sum - 1) == false)
    }

    /// The minimum editor width is the one figure that had to be chosen, and it is chosen by
    /// reference: `CadenceTodayLayoutSupport.inspectorPaneMinWidth`, which that file already
    /// describes as the least the notes/timeline inspector will accept before its own content
    /// clips. Requiring the editor *half* to clear the whole pane's stated floor is the stronger
    /// reading of it, on purpose.
    @Test func theMinimumEditorWidthIsBorrowedRatherThanInvented() {
        #expect(CadenceNotesListMetrics.minimumEditorWidth == CadenceTodayLayoutSupport.inspectorPaneMinWidth)
        #expect(CadenceNotesListMetrics.columnDividerWidth == CadenceTodayLayoutSupport.paneDividerWidth)
    }

    /// The reported bug width. 320pt is the inspector at its floor, and it is the width that used to
    /// draw a 39pt editor.
    @Test func theWidthThatDrewAFortyPointEditorNowFallsBack() {
        let inspector = CadenceTodayLayoutSupport.inspectorPaneMinWidth
        #expect(layout(hostWidth: inspector) == .oneColumn)
        // What the two-column form would have left the editor there, kept as the record of the bug.
        #expect(
            inspector
                - CadenceNotesListMetrics.regularColumnWidth
                - CadenceNotesListMetrics.columnDividerWidth == 39
        )
        // And the widest the Today inspector ever gets — a 13" iPad in landscape with the sidebar
        // folded — is still under the floor, so that host is one-column at every size.
        #expect(layout(hostWidth: 545) == .oneColumn)
    }

    /// **The hosts that must not change.** Every pane the Notes *tab* is handed on a target iPad,
    /// sidebar out and folded, in both orientations. The narrowest is an 11" in portrait at
    /// 834 − 188 = 646, which clears the floor by 45pt and keeps a 365pt editor — that margin is
    /// exactly why the floor is 601 and not the 656 an iPhone-width anchor would have given.
    @Test func everyNotesTabPaneOnATargetIPadKeepsItsTwoColumns() {
        for window in [CGFloat(834), 1_210, 1_024, 1_366] {
            for pane in [window - Self.sidebarWidth, window] {
                #expect(layout(hostWidth: pane) == .twoColumn, "pane \(pane)")
            }
        }
    }

    /// Compact is compact however much room is behind it — the phone's form is not a fallback there,
    /// it is the form. Same guarantee `CadenceTodayLayoutSupport` gives.
    @Test func compactWidthIsAlwaysOneColumnHoweverWideTheHost() {
        for hostWidth in [CGFloat(0), 375, 393, 1_024, 4_000] {
            #expect(CadenceNotesListMetrics.layout(isRegularWidth: false, hostWidth: hostWidth) == .oneColumn)
        }
    }

    /// An unmeasured host answers with the size class rather than with `.oneColumn`. `onGeometryChange`
    /// lands after the first layout pass, so a regular host reads 0 for one frame; resolving that to
    /// the phone's form would flash it on every appearance of the iPad Notes tab.
    @Test func anUnmeasuredHostAssumesTheAnswerItAlmostAlwaysResolvesTo() {
        #expect(layout(hostWidth: 0) == .twoColumn)
        #expect(layout(hostWidth: -1) == .twoColumn)
    }

    @Test func theRangeIsExactlyTwoCases() {
        for hostWidth in stride(from: CGFloat(0), through: 4_000, by: 13) {
            for isRegularWidth in [true, false] {
                let resolved = CadenceNotesListMetrics.layout(isRegularWidth: isRegularWidth, hostWidth: hostWidth)
                #expect(resolved == .oneColumn || resolved == .twoColumn)
            }
        }
    }

    // MARK: - The call site

    /// **The half that T-161 says has to exist.** A floor nothing reads is revertible with the whole
    /// suite green: the arithmetic above would pass unchanged if `iOSNotesView` went back to
    /// `if isCompactWidth { sidebar } else { HStack … }`. `Cadence/iOS/` is inside `#if os(iOS)` and
    /// invisible to this macOS-built target, so the call site is read out of the source text — the
    /// same tool `everyNotesListOnBothPlatformsDrawsTheSharedFoldableColumn` uses.
    ///
    /// The counts are exact on purpose, and the split between the two symbols is the assertion:
    /// `notesLayout` is every decision about *how many columns*, and `isCompactWidth` is only the
    /// two things that are genuinely about the size class — the back control on a pushed compact
    /// screen, and the row metrics' touch tier. Move a layout branch back onto the size class and
    /// both counts move.
    @Test func theNotesSplitReadsTheFloorRatherThanTheSizeClass() throws {
        try expectNotesCallSites(
            of: "CadenceNotesListMetrics.layout",
            at: ["Cadence/iOS/iOSNotesView.swift": 1]
        )

        let code = try notesStrippingComments(notesSource("Cadence/iOS/iOSNotesView.swift"))

        // Declaration, plus the three decisions: the column split, whether a tapped row presents the
        // editor over the list, and where the template control lives.
        #expect(code.components(separatedBy: "notesLayout").count - 1 == 4)
        // Declaration, the `!isCompactWidth` inside `notesLayout`, the back control, the row metrics.
        #expect(code.components(separatedBy: "isCompactWidth").count - 1 == 4)
        // Measured rather than wrapped in a `GeometryReader`, and measured exactly once.
        #expect(code.components(separatedBy: "onGeometryChange").count - 1 == 1)
        // The one-column form is reused, not rebuilt: the editor is still presented over the list by
        // the same `fullScreenCover` the phone has always used.
        #expect(code.contains("fullScreenCover(item: $presentedNote)"))
    }
}
