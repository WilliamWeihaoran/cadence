import CloudKit
import Foundation
import Testing
@testable import Cadence

/// T-188 and T-189: two tickets of the same shape, and the tests that make them stay closed.
///
/// Both were "the logic is already shared and correct, and one platform has no surface for it".
/// T-188: `CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd` existed, was pinned by
/// `TaskRecurrenceEndConditionTests`, and had exactly one caller — macOS's inspector — so a
/// recurring task created on iPhone repeated forever while correctly honouring a bound set on a
/// Mac. T-189 is the same defect pointing the other way: `CadenceSyncHealth.resolve` existed, was
/// pinned by `CadenceSyncHealthTests`, and had exactly one reader — `iOSSyncSettingsSection`.
///
/// **Why these are source-text assertions.** Both helpers were already fully covered, and both
/// stayed green through the entire period in which one platform could not reach them: a pure
/// function is true about nobody in particular. That is T-161 exactly — a committed fix that was
/// revertible with the whole suite green, because the tests pinned a helper while nothing observed
/// the call site. So the counts below are exact per file, comments are stripped rather than
/// allowlisted, and the last test in each struct is the one that stops the scan going vacuous.
///
/// It is also the only tool available for the iOS half: `Cadence/iOS/` is inside `#if os(iOS)` and
/// this target builds for macOS, so there is no iOS symbol to reference. Everything that *can* be
/// referenced — `CadenceTaskRecurrenceEndPresentation`, `SettingsCategory`,
/// `CadenceSyncHealthLevel` — is asserted against directly.
@MainActor
struct CadenceRecurrenceEndSurfaceTests {

    // MARK: - The call site, on both platforms

    /// **The T-161 test for T-188.** Delete the iOS Ends rows and this fails. Nothing else in the
    /// suite would: `applyRecurrenceEnd` keeps all of its own coverage from the macOS caller alone.
    ///
    /// Two calls per platform, not one. Each sheet writes the end condition from its own control
    /// *and* clears it when the rule drops to `.none` — an end condition left behind on a task that
    /// no longer repeats silently re-arms the moment repeating is switched back on.
    @Test func bothPlatformsWriteTheEndConditionThroughTheSharedWorkflow() throws {
        try expectCallSites(
            of: "CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd",
            at: [
                "Cadence/iOS/iOSTaskDetailSheet.swift": 2,
                "Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift": 2,
            ]
        )
    }

    /// Nowhere else, and in particular nowhere that writes the three stored properties by hand.
    /// They are plain SwiftData properties: assigning `task.recurrenceEndMode` compiles, bypasses
    /// the series propagation and the off-mode normalization, and looks right in review.
    @Test func nothingOutsideTheWorkflowAndTheModelWritesTheEndFieldsDirectly() throws {
        let endCountReaders = try filesMentioning("recurrenceEndCount")
        #expect(
            endCountReaders == [
                "Cadence/Models/AppTask.swift",
                "Cadence/Shared/CadenceTaskMutationSupport.swift",
                "Cadence/Shared/CadenceTaskRecurrenceWorkflowSupport.swift",
                "Cadence/iOS/iOSTaskDetailSheet.swift",
                "Cadence/iOS/iOSTaskDetailSheetSections.swift",
                "Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift",
            ].sorted(),
            "recurrenceEndCount is read or written from \(endCountReaders)"
        )

        // The two view files may *read* the stored count to seed a control; neither may assign it.
        for path in [
            "Cadence/iOS/iOSTaskDetailSheetSections.swift",
            "Cadence/iOS/iOSTaskDetailSheet.swift",
            "Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift",
        ] {
            let source = try strippingComments(sourceFile(path))
            for field in ["recurrenceEndMode", "recurrenceEndDate", "recurrenceEndCount"] {
                #expect(
                    source.range(of: "\\.\(field)\\s*=[^=]", options: .regularExpression) == nil,
                    "\(path) assigns \(field) directly instead of going through applyRecurrenceEnd"
                )
            }
        }
    }

    /// All three modes, reachable. The iOS picker is built from `allCases` rather than a typed-out
    /// list, so a fourth mode cannot be added to the model and quietly go unofferred on one
    /// platform — which is how the first three came to be macOS-only.
    @Test func theIOSPickerOffersEveryEndModeAndAnEditorForEachOne() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSTaskDetailSheetSections.swift"))

        #expect(
            source.contains("TaskRecurrenceEndMode.allCases"),
            "the iOS end-mode picker no longer enumerates every mode"
        )
        // `.never` needs no editor; the other two each need theirs, or selecting the mode stores a
        // value that `effectiveRecurrenceEndMode` degrades straight back to `.never`.
        #expect(source.contains("endDateRow"), "the iOS sheet lost its end-date editor")
        #expect(source.contains("endCountRow"), "the iOS sheet lost its occurrence-count editor")
        #expect(
            source.contains("CadenceTaskRecurrenceEndPresentation.detail"),
            "the iOS sheet decides which editor a mode needs itself instead of asking the shared map"
        )
    }

    /// Neither platform keeps its own wording for the bound. macOS's inspector had "Until Jan 5"
    /// and "3 of 5" inline; iOS's Ends row says the same two things, and a second spelling of them
    /// is how the same series comes to read differently on a phone and a Mac.
    @Test func neitherPlatformSpellsTheEndSummaryItself() throws {
        for path in [
            "Cadence/iOS/iOSTaskDetailSheetSections.swift",
            "Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift",
        ] {
            let source = try strippingComments(sourceFile(path))
            #expect(
                source.contains("CadenceTaskRecurrenceEndPresentation"),
                "\(path) stopped reading the shared end-condition presentation"
            )
            #expect(
                !source.contains("\"Until "),
                "\(path) has its own \"Until <date>\" wording again"
            )
        }
    }

    // MARK: - The shared presentation type

    /// Total, and one editor per mode. A mode that maps to no detail is a mode whose value can
    /// never be set, which is precisely what an iOS user had for all three.
    @Test func everyEndModeMapsToExactlyOneDetailControl() {
        let details = TaskRecurrenceEndMode.allCases.map(CadenceTaskRecurrenceEndPresentation.detail(for:))

        #expect(details.count == 3)
        #expect(CadenceTaskRecurrenceEndPresentation.detail(for: .never) == .none)
        #expect(CadenceTaskRecurrenceEndPresentation.detail(for: .onDate) == .date)
        #expect(CadenceTaskRecurrenceEndPresentation.detail(for: .afterCount) == .count)
        // Every detail case is actually used by some mode — a dead case here would mean a control
        // nothing can open.
        #expect(Set(details) == Set(CadenceRecurrenceEndDetail.allCases))
    }

    @Test func onlyARepeatingTaskShowsEndControls() {
        #expect(!CadenceTaskRecurrenceEndPresentation.showsEndControls(rule: .none))
        for rule in TaskRecurrenceRule.allCases where rule != .none {
            #expect(CadenceTaskRecurrenceEndPresentation.showsEndControls(rule: rule))
        }
    }

    /// `.never` says nothing rather than "repeats forever": the row above already states the rule,
    /// and there is no honest next-occurrence date to add from outside the spawn path.
    @Test func theSummaryIsSilentOnlyForAnUnboundedSeries() {
        #expect(
            CadenceTaskRecurrenceEndPresentation.summary(
                mode: .never, endDateKey: "2026-09-01", occurrenceNumber: 2, endCount: 5
            ) == nil
        )

        #expect(
            CadenceTaskRecurrenceEndPresentation.summary(
                mode: .onDate, endDateKey: "2026-09-01", occurrenceNumber: 2, endCount: 0
            ) == "Until Sep 1"
        )

        // "N of M", not "M left": where you are in the series cannot be reconstructed from a
        // remaining count, and it is the fact no other row on either platform states.
        #expect(
            CadenceTaskRecurrenceEndPresentation.summary(
                mode: .afterCount, endDateKey: "", occurrenceNumber: 3, endCount: 5
            ) == "3 of 5"
        )
    }

    /// A trigger button cannot render `nil`, and it must not invent a second wording either.
    @Test func theTriggerLabelIsTheSummaryPlusANameForSilence() {
        #expect(
            CadenceTaskRecurrenceEndPresentation.valueLabel(
                mode: .never, endDateKey: "", occurrenceNumber: 1, endCount: 0
            ) == TaskRecurrenceEndMode.never.label
        )

        for mode in [TaskRecurrenceEndMode.onDate, .afterCount] {
            let summary = CadenceTaskRecurrenceEndPresentation.summary(
                mode: mode, endDateKey: "2026-09-01", occurrenceNumber: 3, endCount: 5
            )
            let label = CadenceTaskRecurrenceEndPresentation.valueLabel(
                mode: mode, endDateKey: "2026-09-01", occurrenceNumber: 3, endCount: 5
            )
            #expect(label == summary, "\(mode) reads differently in the row and in the trigger")
        }
    }

    /// The seeds, and why they are not the clamp. A control that opens on `1` would be offering
    /// "end this series on its very first occurrence" as the default; a control that opens on `0`
    /// would be offering a value the model discards.
    @Test func theSeededCountIsUsableAndTheClampIsNot() {
        #expect(CadenceTaskRecurrenceEndPresentation.resolvedEndCount(0) == 10)
        #expect(CadenceTaskRecurrenceEndPresentation.resolvedEndCount(-4) == 10)
        #expect(CadenceTaskRecurrenceEndPresentation.resolvedEndCount(3) == 3)

        #expect(CadenceTaskRecurrenceEndPresentation.normalizedEndCount(0) == 1)
        #expect(CadenceTaskRecurrenceEndPresentation.normalizedEndCount(-9) == 1)
        #expect(CadenceTaskRecurrenceEndPresentation.normalizedEndCount(7) == 7)

        // The offered list has to contain both ends of that story: the honest minimum and the seed.
        #expect(CadenceTaskRecurrenceEndPresentation.endCountChoices.first == 1)
        #expect(CadenceTaskRecurrenceEndPresentation.endCountChoices.contains(10))
        #expect(CadenceTaskRecurrenceEndPresentation.endCountChoices == Array(1...60))
    }

    @Test func theSeededEndDateIsAMonthOutAndParses() throws {
        let reference = try #require(DateFormatters.date(from: "2026-01-31"))
        let key = CadenceTaskRecurrenceEndPresentation.defaultEndDateKey(from: reference)

        #expect(!key.isEmpty)
        #expect(key > "2026-01-31", "the seeded end date is not in the future")
        #expect(DateFormatters.date(from: key) != nil, "the seeded end date is not a storable key")
        #expect(CadenceTaskRecurrenceEndPresentation.resolvedEndDate("", reference: reference)
                == DateFormatters.date(from: key))
        #expect(CadenceTaskRecurrenceEndPresentation.resolvedEndDate("2026-03-04")
                == DateFormatters.date(from: "2026-03-04"))
    }

    // MARK: - The seed is what makes the mode stick

    /// The trap the seed exists for, asserted against the model rather than the wording.
    ///
    /// `effectiveRecurrenceEndMode` degrades an `.onDate` with no date and an `.afterCount` with a
    /// non-positive count back to `.never`. A picker that writes the bare mode therefore appears to
    /// refuse the tap: the row snaps back to "Never" and nothing says why.
    @Test func selectingAModeWithoutItsValueWouldSilentlyMeanNever() {
        let bare = AppTask(title: "Water the plants")
        bare.recurrenceRule = .weekly
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
            mode: .onDate, endDateKey: "", to: bare, allTasks: [bare], scope: .thisTask
        )
        #expect(bare.effectiveRecurrenceEndMode == .never)

        let seeded = AppTask(title: "Water the plants")
        seeded.recurrenceRule = .weekly
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
            mode: .onDate,
            endDateKey: CadenceTaskRecurrenceEndPresentation.defaultEndDateKey(),
            to: seeded,
            allTasks: [seeded],
            scope: .thisTask
        )
        #expect(seeded.effectiveRecurrenceEndMode == .onDate)

        let counted = AppTask(title: "Water the plants")
        counted.recurrenceRule = .weekly
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd(
            mode: .afterCount,
            endCount: CadenceTaskRecurrenceEndPresentation.resolvedEndCount(0),
            to: counted,
            allTasks: [counted],
            scope: .thisTask
        )
        #expect(counted.effectiveRecurrenceEndMode == .afterCount)
        #expect(counted.recurrenceEndCount == 10)
        #expect(!counted.recurrenceHasEnded, "a freshly seeded count already ends the series")
    }

    // MARK: - The scan itself

    /// The absence assertions above are worth nothing if the scan reads no files, and a scan that
    /// silently returns nothing passes every one of them. A `/tmp` against `/private/tmp` mismatch
    /// once made a scan that read nothing at all look like four clean results.
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/iOS/iOSTaskDetailSheet.swift"))
        #expect(files.contains("Cadence/iOS/iOSTaskDetailSheetSections.swift"))
        #expect(files.contains("Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift"))
        #expect(files.contains("Cadence/Shared/CadenceTaskRecurrenceEndPresentation.swift"))

        // Reading *content*, not just listing names: a positive control on a string that is
        // unmistakably in one of the files above, and a negative control on one that is not.
        #expect(try strippingComments(sourceFile("Cadence/Shared/CadenceTaskRecurrenceWorkflowSupport.swift"))
            .contains("func applyRecurrenceEnd"))
        #expect(try !filesMentioning("applyRecurrenceEnd").isEmpty)
        #expect(try filesMentioning("thisStringIsInNoSourceFile").isEmpty)
    }
}

/// T-189: the macOS half of the sync surface.
@MainActor
struct CadenceSyncSurfaceTests {

    // MARK: - The call site, on both platforms

    /// **The T-161 test for T-189.** `CadenceSyncHealth.resolve` had one reader for as long as the
    /// macOS app had no sync surface, and `CadenceSyncHealthTests` was green throughout.
    ///
    /// One call per platform: macOS's is `static` on the section precisely so the settings rail's
    /// status badge can read the verdict the card draws instead of resolving a second time — two
    /// resolves on one screen are two chances for the badge and the card to disagree.
    @Test func bothPlatformsResolveTheOneSyncVerdict() throws {
        try expectCallSites(
            of: "CadenceSyncHealth.resolve",
            at: [
                "Cadence/macOS/Views/SettingsSyncSection.swift": 1,
                "Cadence/iOS/iOSSettingsOverviewSections.swift": 1,
            ]
        )

        let resolvers = try filesMentioning("CadenceSyncHealth.resolve")
        #expect(
            resolvers == [
                "Cadence/iOS/iOSSettingsOverviewSections.swift",
                "Cadence/macOS/Views/SettingsSyncSection.swift",
            ],
            "the sync verdict is resolved in \(resolvers)"
        )
    }

    /// The account state is asked for in exactly one place on either platform. macOS gaining a
    /// sync surface meant either sharing iOS's `CKContainer` call or writing a second one, and a
    /// second one is how `CKAccountStatus`'s three not-a-status cases came to be re-derived from a
    /// pair of optionals at every call site in the first place.
    @Test func onlyOneFileInTheAppTalksToCloudKitDirectly() throws {
        let cloudKitCallers = try filesMentioning("CKContainer")
        #expect(
            cloudKitCallers == ["Cadence/Shared/CadenceCloudAccountProbe.swift"],
            "CKContainer is called from \(cloudKitCallers)"
        )

        for path in [
            "Cadence/macOS/Views/SettingsSyncSection.swift",
            "Cadence/iOS/iOSSettingsOverviewSections.swift",
        ] {
            let source = try strippingComments(sourceFile(path))
            #expect(
                !source.contains("CKAccountStatus"),
                "\(path) reads the raw account status instead of the shared verdict"
            )
        }
    }

    // MARK: - macOS offers a case that already existed

    /// The finding, as an assertion: nothing new had to be defined. `CadenceSettingsCategoryKind`
    /// already had `.sync` — mobile files it under "System" — and macOS's own `SettingsCategory`
    /// simply did not offer it. So the title, glyph and tint come across unchanged, and macOS
    /// cannot drift into a second name for the same screen.
    @Test func theMacOSSyncCategoryIsTheSharedKindAndNotANewOne() {
        #expect(SettingsCategory.sync.sharedKind == .sync)
        #expect(SettingsCategory.sync.title == CadenceSettingsCategoryKind.sync.title)
        #expect(SettingsCategory.sync.icon == CadenceSettingsCategoryKind.sync.icon)
        #expect(SettingsCategory.sync.tint == CadenceSettingsCategoryKind.sync.tint)
    }

    /// Every macOS category maps onto a distinct shared kind, so a new case cannot be bolted on
    /// with a borrowed identity — which would give two rail rows the same name and glyph.
    @Test func everyMacOSCategoryHasItsOwnSharedKind() {
        let kinds = SettingsCategory.allCases.map(\.sharedKind)
        #expect(Set(kinds).count == kinds.count)
        #expect(SettingsCategory.allCases.count == 13)
        #expect(Set(kinds).isSubset(of: Set(CadenceSettingsCategoryKind.allCases)))
    }

    /// Defined is not offered. `.sync` has to be filed in one of the rail's groups or the category
    /// exists and is unreachable — the state `.reminders` was in on mobile for months, where
    /// absence looked exactly like a deliberate omission.
    @Test func theSyncCategoryIsFiledInTheMacOSRail() throws {
        let source = try strippingComments(sourceFile("Cadence/macOS/Views/SettingsViewSupport.swift"))
        let groupsStart = try #require(source.range(of: "static let all: [SettingsCategoryGroup]"))
        let groups = source[groupsStart.upperBound...]
        let groupsEnd = groups.range(of: "\n}")?.lowerBound ?? groups.endIndex

        #expect(
            groups[..<groupsEnd].contains(".sync"),
            "Settings > Account & Sync is defined but filed in no rail group, so nothing can open it"
        )
    }

    /// And the selected category actually draws the section. A rail row that routes nowhere lands
    /// on the `switch`'s other branches and shows a neighbouring screen.
    @Test func selectingTheSyncCategoryDrawsTheSyncSection() throws {
        try expectCallSites(
            of: "SettingsSyncSection",
            at: ["Cadence/macOS/Views/SettingsView.swift": 1]
        )

        let source = try strippingComments(sourceFile("Cadence/macOS/Views/SettingsView.swift"))
        _ = try #require(
            source.range(of: "case\\s*\\.sync:\\s*SettingsSyncSection\\(", options: .regularExpression),
            "Settings > Account & Sync no longer routes to the section that draws it"
        )
    }

    // MARK: - The badge

    /// One state is good news. "The account check has not come back yet" is not — it is no news,
    /// and a green pill over it would be the same lie the iOS row used to tell with
    /// `checkmark.icloud`.
    @Test func onlyASyncingStoreReadsAsHealthy() {
        for level in CadenceSyncHealthLevel.allCases {
            #expect(level.isHealthy == (level == .syncing), "\(level) reports isHealthy \(level.isHealthy)")
            #expect(!level.badgeTitle.isEmpty)
        }

        // Distinct, so the pill cannot say the same thing about two different situations.
        #expect(Set(CadenceSyncHealthLevel.allCases.map(\.badgeTitle)).count == CadenceSyncHealthLevel.allCases.count)
    }

    /// The rule the whole type exists for, read through the *macOS* entry point this ticket added.
    /// `CadenceSyncHealthTests` pins `resolve`; this pins that macOS's screen goes through it and
    /// therefore inherits the precedence, rather than reporting a healthy account over a store that
    /// cannot sync.
    @Test func theMacOSSectionInheritsTheStoreOverAccountPrecedence() {
        let healthy = SettingsSyncSection.health(for: .available)
        #expect(healthy.level == (PersistenceController.startupIssue?.kind.disablesCloudSync == true ? .notSyncing : .syncing))

        let signedOut = SettingsSyncSection.health(for: .noAccount)
        #expect(signedOut.level != .syncing)
        #expect(signedOut.iconName != "checkmark.icloud")
    }

    // MARK: - The probe

    @Test func aFreshProbeHasNotCheckedAndSaysSo() {
        let probe = CadenceCloudAccountProbe()

        #expect(probe.state == .notChecked)
        #expect(probe.lastChecked == nil)
        #expect(!probe.isChecking)
        // Which resolves to the neutral "go and check" verdict, not to a failure and not to health.
        #expect(SettingsSyncSection.health(for: probe.state).level != .syncing)
    }

    /// The precedence the probe delegates rather than re-deriving: a check in flight wins over an
    /// error, and an error wins over a stale status.
    @Test func theAccountStateKeepsItsOnePrecedenceOrder() {
        #expect(CadenceCloudAccountState(accountStatus: .available, accountError: "boom", isChecking: true) == .checking)
        #expect(CadenceCloudAccountState(accountStatus: .available, accountError: "boom", isChecking: false) == .failed("boom"))
        #expect(CadenceCloudAccountState(accountStatus: .available, accountError: nil, isChecking: false) == .available)
        #expect(CadenceCloudAccountState(accountStatus: nil, accountError: nil, isChecking: false) == .notChecked)
    }

    // MARK: - The scan itself

    @Test func theSourceScanActuallyReachesBothSettingsSurfaces() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/macOS/Views/SettingsSyncSection.swift"))
        #expect(files.contains("Cadence/macOS/Views/SettingsView.swift"))
        #expect(files.contains("Cadence/macOS/Views/SettingsViewSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSSettingsOverviewSections.swift"))
        #expect(files.contains("Cadence/Shared/CadenceCloudAccountProbe.swift"))

        #expect(try strippingComments(sourceFile("Cadence/Shared/CadenceCloudAccountProbe.swift"))
            .contains("func refreshIfNeeded"))
        #expect(try !filesMentioning("CadenceCloudAccountProbe").isEmpty)
        #expect(try filesMentioning("thisStringIsInNoSourceFile").isEmpty)
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// Exact counts rather than "contains", for the reason `CadenceSharedBoardChromeTests` records: a
/// mutation that reverted *one* of several call sites left a "contains" assertion green.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Every file under `Cadence/` whose **live code** mentions `name`, sorted. Comments are stripped
/// so the tombstones and design notes this repo keeps do not count as callers.
private func filesMentioning(_ name: String) throws -> [String] {
    let pattern = "(?<![A-Za-z0-9_])\(NSRegularExpression.escapedPattern(for: name))(?![A-Za-z0-9_])"
    return try swiftFiles(under: "Cadence")
        .filter { try strippingComments(sourceFile($0)).range(of: pattern, options: .regularExpression) != nil }
        .sorted()
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
