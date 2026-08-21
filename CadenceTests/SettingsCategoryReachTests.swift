import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-197 and T-196: one settings category deleted, one added, and two habit figures that were
/// computed on the model and rendered on one platform.
///
/// **Both halves need call-site tests, not just symbol tests.** A deleted enum case proves the case
/// is gone; it proves nothing about the section that used to route to it, and "a category that
/// still routes somewhere empty" is exactly how the `subtitle` parameter survived three separate
/// deletions. Likewise `habit.bestStreak` existing proves nothing about macOS drawing it — that
/// figure has been on the model, with an iOS-only reader, the whole time.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The helpers follow `CadenceSharedTaskRowJobsTests` — exact per-file counts rather than
/// "contains", comment-stripping rather than allowlisting, and a non-vacuity test at the bottom so
/// a broken scan cannot make the absence assertions pass silently.
@MainActor
struct SettingsCoverageCategoryRemovalTests {

    /// The case is gone from the shared enum, and — the half that matters for a `String`-backed,
    /// `Identifiable` enum — a stored `"coverage"` cannot decode back into it. Nothing persists a
    /// settings category today (both platforms hold the selection in `@State`), so there is no
    /// `ListDetailPage.resolved(_:)`-style remap to write; this assertion is what keeps that true.
    @Test func thereIsNoCoverageCategoryAndAStoredRawValueCannotReviveOne() {
        #expect(CadenceSettingsCategoryKind(rawValue: "coverage") == nil)
        #expect(!CadenceSettingsCategoryKind.allCases.map(\.rawValue).contains("coverage"))
    }

    /// Mobile's own list, stated as a derived set rather than a number: whatever the shared enum
    /// holds, minus the two categories mobile deliberately excludes. A literal count here could
    /// only ever agree with the exclusion list by coincidence.
    @Test func mobileOffersEveryRemainingCategoryAndNothingCalledCoverage() {
        let offered = Set(CadenceMobileSettingsLayout.categories)
        #expect(offered == Set(CadenceSettingsCategoryKind.allCases).subtracting(CadenceMobileSettingsLayout.desktopOnly))
        #expect(!CadenceMobileSettingsLayout.categories.map(\.rawValue).contains("coverage"))
        #expect(!CadenceMobileSettingsLayout.groups.flatMap(\.kinds).map(\.rawValue).contains("coverage"))
    }

    /// The parity manifest itself, and everything that rendered it. `iOSMobileCapability.all` was
    /// the only stale claim a *user* could read — it advertised a Theme picker that went with
    /// `ThemeManager`, and filed shipped features under "Partial".
    @Test func theParityManifestAndItsChromeAreGone() throws {
        for name in [
            "iOSMobileCapability",
            "iOSMobileCapabilityStatus",
            "iOSSettingsCapabilityRow",
            "iOSMobileCoverageSettingsSection"
        ] {
            try expectNoLiveMention(of: name)
        }
    }

    /// The route, not just the destination. `iOSSettingsView.sectionContent(for:)` is an exhaustive
    /// switch, so a leftover `case .coverage` would not compile — but the mobile category enum and
    /// the shared kind are two separate lists, and only one of them is checked by the compiler.
    @Test func noSettingsSurfaceStillRoutesToCoverage() throws {
        for path in [
            "Cadence/Shared/CadenceSettingsPresentationSupport.swift",
            "Cadence/iOS/iOSSettingsView.swift",
            "Cadence/iOS/iOSSettingsComponents.swift",
            "Cadence/iOS/iOSSettingsOverviewSections.swift",
            "Cadence/macOS/Views/SettingsViewSupport.swift",
            "Cadence/macOS/Views/SettingsView.swift"
        ] {
            let code = try strippingComments(sourceFile(path))
            #expect(
                code.range(of: "(?i)coverage", options: .regularExpression) == nil,
                "\(path) still mentions coverage as live code"
            )
        }
    }
}

/// T-196: the two reverse gaps, macOS missing what iOS already had.
@MainActor
struct MacSettingsAboutAndHabitMetricsTests {

    // MARK: - The habit figures were a rendering gap, not missing logic

    /// Both figures come off `Habit` and always did — `bestStreak` routes through
    /// `Habit.bestStreak(asOf:calendar:)` so it cannot invent a second definition of a streak, and
    /// `last7DayStates` returns exactly seven states with today last. Asserted here so the claim
    /// "this is rendering only" is checked rather than believed.
    @Test func bothFiguresAreAlreadyComputedOnTheModel() {
        let habit = Habit(title: "Read")
        habit.frequencyType = .daily
        habit.completions = [HabitCompletion(date: DateFormatters.todayKey(), habit: habit)]

        #expect(habit.last7DayStates.count == 7)
        #expect(habit.last7DayStates.last == true)
        #expect(habit.bestStreak == habit.bestStreak())
        #expect(habit.bestStreak >= habit.currentStreak)
    }

    /// The call sites. `HabitQuietMetrics` showed Streak / rate / Total and no best streak, and the
    /// macOS Activity card was the year-long heatmap alone — the one range a habit is actually
    /// checked against was missing from the desktop entirely.
    @Test func theMacOSHabitDetailDrawsBestStreakAndTheSevenDayStrip() throws {
        try expectOccurrences(
            of: "habit.bestStreak",
            at: ["Cadence/macOS/Views/HabitsSupportViews.swift": 1]
        )
        try expectCallSites(
            of: "HabitLast7DayStrip",
            at: ["Cadence/macOS/Views/HabitsSupportViews.swift": 1]
        )
    }

    /// The strip reads the model's walk rather than doing its own. It lives in `Shared/Components`
    /// because a recent-week strip is not a platform decision — iOS's habit detail still carries a
    /// private copy of it (`iOSFeatureDetailViews.swift`), which is the near-copy this placement
    /// exists to let it collapse into.
    @Test func theSharedStripReadsTheModelsOwnSevenDayWalk() throws {
        try expectOccurrences(
            of: "habit.last7DayStates",
            at: ["Cadence/Shared/Components/HabitProgressViews.swift": 1]
        )
    }

    // MARK: - macOS Settings → About

    /// Defined *and* offered. `.about` existed on the shared kind for as long as iOS has had an
    /// About screen; macOS simply had no case to hang one on, which is the state `.reminders` was
    /// in on mobile for months — absence looks exactly like a deliberate omission.
    @Test func theAboutCategoryIsTheSharedKindAndNotANewOne() {
        #expect(SettingsCategory.about.sharedKind == .about)
        #expect(SettingsCategory.about.title == CadenceSettingsCategoryKind.about.title)
        #expect(SettingsCategory.about.icon == CadenceSettingsCategoryKind.about.icon)
        #expect(SettingsCategory.about.tint == CadenceSettingsCategoryKind.about.tint)
    }

    /// macOS's omissions, stated positively — which is now the empty set.
    ///
    /// Mobile gets this for free from `CadenceMobileSettingsLayout.desktopOnly`; macOS's rail has no
    /// analogue (T-210), so with `.sync` landed and `.coverage` deleted the cheapest true statement
    /// is that macOS offers *every* shared category. A new shared kind that macOS forgets to offer
    /// fails here, which is the whole job `desktopOnly` does on the other side.
    @Test func macOSNowOffersEverySharedCategory() {
        let kinds = SettingsCategory.allCases.map(\.sharedKind)
        #expect(Set(kinds).count == kinds.count)
        #expect(Set(kinds) == Set(CadenceSettingsCategoryKind.allCases))
    }

    /// Filed in a rail group and routed to a section. Either half alone gives you a category that
    /// exists and cannot be opened, or a rail row that opens nothing.
    @Test func theAboutCategoryIsFiledInTheRailAndRoutedToItsSection() throws {
        let support = try strippingComments(sourceFile("Cadence/macOS/Views/SettingsViewSupport.swift"))
        let groupsStart = try #require(support.range(of: "static let all: [SettingsCategoryGroup]"))
        let groups = support[groupsStart.upperBound...]
        let groupsEnd = groups.range(of: "\n}")?.lowerBound ?? groups.endIndex
        #expect(
            groups[..<groupsEnd].contains(".about"),
            "SettingsCategory.about is defined but not filed in any rail group"
        )

        try expectCallSites(
            of: "SettingsAboutSection",
            at: ["Cadence/macOS/Views/SettingsView.swift": 1]
        )
    }

    /// One About screen, not two. The three strings and the label/value row both come from
    /// `Shared/`, so the two platforms cannot come to disagree about which `Info.plist` key holds
    /// the build number — the reason `iOSSettingsInfoRow` is gone rather than copied.
    @Test func bothAboutScreensReadTheSharedIdentityAndTheSharedRow() throws {
        #expect(!CadenceAppBuildIdentity.version.isEmpty)
        #expect(!CadenceAppBuildIdentity.build.isEmpty)
        #expect(!CadenceAppBuildIdentity.bundleID.isEmpty)

        try expectCallSites(
            of: "CadenceSettingsInfoRow",
            at: [
                "Cadence/macOS/Views/SettingsAboutSection.swift": 3,
                "Cadence/iOS/iOSSettingsOverviewSections.swift": 3
            ]
        )
        try expectNoLiveMention(of: "iOSSettingsInfoRow")
    }

    // MARK: - T-220: the About screens own the Privacy Policy and Support links

    /// The pair itself, as one list rather than two hand-typed button call sites.
    ///
    /// `CadenceAppReferenceLink` sits outside every `#if` for the usual reason — `Cadence/iOS/` is
    /// invisible to this macOS-built target — so this is the one assertion here that can check the
    /// real values rather than the source text.
    @Test func thereIsOneSharedListOfTheTwoReferenceLinks() throws {
        #expect(CadenceAppReferenceLink.all == [.privacyPolicy, .support])
        #expect(CadenceAppReferenceLink.all.map(\.title) == ["Privacy Policy", "Support"])
        #expect(CadenceAppReferenceLink.all.map(\.id) == ["privacy-policy", "support"])
        #expect(Set(CadenceAppReferenceLink.all.map(\.systemImage)).count == 2)
        #expect(CadenceAppReferenceLink.sectionTitle == "Links")

        for link in CadenceAppReferenceLink.all {
            let url = try #require(link.url, "\(link.title) has no URL")
            #expect(url.scheme == "https")
            #expect(!link.missingMessage.isEmpty)
        }
        #expect(CadenceAppReferenceLink.privacyPolicy.url == AppStoreReviewReadiness.privacyPolicyURL)
        #expect(CadenceAppReferenceLink.support.url == AppStoreReviewReadiness.supportURL)
    }

    /// Both About screens read that list, and neither hand-types a title.
    ///
    /// The exact-count form matters here in the way `expectCallSites`' doc comment describes: an
    /// assertion that each About file merely *mentions* `CadenceAppReferenceLink` somewhere would
    /// stay green with one of the two screens reverted to literals.
    @Test func bothAboutScreensRenderTheTwoLinksFromTheSharedList() throws {
        try expectOccurrences(
            of: "CadenceAppReferenceLink.all",
            at: [
                "Cadence/macOS/Views/SettingsAboutSection.swift": 1,
                "Cadence/iOS/iOSSettingsOverviewSections.swift": 1
            ]
        )
        try expectOccurrences(
            of: "CadenceAppReferenceLink.sectionTitle",
            at: [
                "Cadence/macOS/Views/SettingsAboutSection.swift": 1,
                "Cadence/iOS/iOSSettingsOverviewSections.swift": 1
            ]
        )
        // The titles live in exactly one file. Asserting 0 in the two views alone would be the
        // substring trap in its other form — vacuous if the scan read nothing — so the shared
        // file's count is asserted in the same breath.
        try expectOccurrences(
            of: "\"Privacy Policy\"",
            at: [
                "Cadence/Shared/AppStoreReviewReadiness.swift": 1,
                "Cadence/macOS/Views/SettingsAboutSection.swift": 0,
                "Cadence/iOS/iOSSettingsOverviewSections.swift": 0,
                "Cadence/macOS/Views/SettingsDataSafetySection.swift": 0
            ]
        )
    }

    /// macOS's Data Safety pane no longer carries them, and its privacy paragraph still does.
    ///
    /// The links sat here because *the paragraph* did; a support page is not a data-safety control,
    /// and a harmless link one tab-stop from an irreversible delete reads as one more thing that
    /// might erase something. `SettingsReviewLinksSection` is renamed rather than kept, because a
    /// struct named for links it no longer has is exactly how the page-header `subtitle` parameter
    /// survived three deletions.
    @Test func macOSDataSafetyKeepsThePrivacyParagraphAndNotTheLinks() throws {
        try expectNoLiveMention(of: "SettingsReviewLinksSection")
        try expectOccurrences(
            of: "AppStoreReviewReadiness",
            at: [
                "Cadence/macOS/Views/SettingsDataSafetySection.swift": 0,
                "Cadence/iOS/iOSSettingsOverviewSections.swift": 0
            ]
        )
        try expectCallSites(
            of: "SettingsPrivacyStatementSection",
            at: ["Cadence/macOS/Views/SettingsDataSafetySection.swift": 1]
        )
        let dataSafety = try strippingComments(sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift"))
        #expect(dataSafety.contains("Cadence stores planning data locally and in your private iCloud database"))
    }

    /// The scan itself works. Without this, a wrong repository root or a broken enumerator makes
    /// every absence assertion above pass by reading nothing at all.
    @Test func theSourceScanIsNotVacuous() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 200)
        #expect(files.contains("Cadence/macOS/Views/SettingsAboutSection.swift"))

        try expectCallSites(
            of: "HabitHeatmap",
            at: ["Cadence/macOS/Views/HabitsSupportViews.swift": 1]
        )
        // A symbol that is definitely live must be *found* by the same scan the absence
        // assertions use, or those assertions mean nothing.
        var liveHits = 0
        for path in files {
            let code = try strippingComments(sourceFile(path))
            if code.range(of: "(?<![A-Za-z0-9_])CadenceSettingsInfoRow(?![A-Za-z0-9_])", options: .regularExpression) != nil {
                liveHits += 1
            }
        }
        #expect(liveHits >= 3)
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// Exact counts, not "contains": a mutation run against `CadenceSharedBoardChromeTests` caught a
/// version asserting only that each file mentioned the shared component somewhere, and reverting
/// one of four call sites left it green.
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

/// Fails unless `text` occurs exactly `count` times as live code in each listed file. Unlike
/// `expectCallSites` this does not append `(`, so it can see a property read.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails if `name` appears anywhere under `Cadence/` as live code rather than inside a comment.
///
/// Comments are exempt deliberately: the tombstones recording what was deleted and why are the
/// reason the next agent does not rebuild it, and a test that forbade the *word* would force them
/// out along with the code.
private func expectNoLiveMention(
    of name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let pattern = "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_])"
    for path in try swiftFiles(under: "Cadence") {
        let code = try strippingComments(sourceFile(path))
        #expect(
            code.range(of: pattern, options: .regularExpression) == nil,
            "\(path) still refers to the retired \(name)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
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

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks stricter about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
