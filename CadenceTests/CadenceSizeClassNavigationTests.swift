import Foundation
import Testing
@testable import Cadence

/// T-334 and T-335: what a size-class change is allowed to forget.
///
/// One cause, two surfaces. Both kept a single piece of *user* navigation state in two
/// presentation-shaped stores — sidebar item versus tab-plus-segment at the root, rail category
/// versus drilled category in Settings — and let `horizontalSizeClass` pick which copy got read.
/// Split View and Stage Manager make that switch an ordinary gesture, so the copy nobody was
/// writing went stale and then got shown. The rule both fixes encode is the one Month's detail
/// toggle already followed: **the selection is user state, compact-versus-regular is presentation.**
///
/// The projections are pinned behaviourally here because they live in `Shared/`. The wiring cannot
/// be: `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for macOS, so the
/// two suites at the bottom read source text and say so.
@MainActor
struct CadenceShellNavigationBridgeTests {
    // MARK: - The round trip

    /// The whole point of the bridge: whatever the sidebar is pointing at, routing it into the
    /// compact shell and reading it back must name the same screen. A destination that comes back
    /// as something else is precisely "resizing lands you on the wrong screen".
    @Test func everyDestinationSurvivesTheRoundTripThroughTheCompactShell() {
        for destination in CadenceFeatureDestination.allCases {
            let route = destination.compactRoute
            #expect(
                CadenceShellNavigationBridge.visibleDestination(for: route) == destination,
                "\(destination.title) narrows into the compact shell and widens back as something else"
            )
        }
    }

    /// The tab roots answer from the tab, and the Tasks tab answers from its segment rather than
    /// from a fixed guess — the exact case the ticket names, where compact Calendar widened back
    /// into a stale Today.
    @Test func aTabRootIsReadBackFromTheTabAndItsSegment() {
        #expect(
            CadenceShellNavigationBridge.visibleDestination(tab: .calendar, tasksSection: .today)
                == .calendar
        )
        #expect(
            CadenceShellNavigationBridge.visibleDestination(tab: .notes, tasksSection: .all)
                == .notes
        )

        for section in CadenceTasksSection.allCases {
            #expect(
                CadenceShellNavigationBridge.visibleDestination(tab: .tasks, tasksSection: section)
                    == section.destination,
                "the Tasks tab widened into a slice the segment control was not on"
            )
        }
    }

    /// More has no sidebar row, so its bare menu answers nothing and the sidebar is left where the
    /// user put it. Inventing a destination here would be the same defect wearing the fix's clothes.
    @Test func theMoreMenuNamesNoDestinationOfItsOwn() {
        for section in CadenceTasksSection.allCases {
            #expect(CadenceCompactTab.more.rootDestination(tasksSection: section) == nil)
            #expect(
                CadenceShellNavigationBridge.visibleDestination(tab: .more, tasksSection: section)
                    == nil
            )
        }
    }

    /// A push answers only for the tab that owns it. The root mirrors one pushed screen per tab, so
    /// the value recorded against a tab the user is not on must not out-vote the tab they are.
    @Test func aPushFromAnotherTabCannotAnswerForThisOne() {
        #expect(
            CadenceShellNavigationBridge.visibleDestination(
                tab: .more,
                tasksSection: .today,
                pushedDestination: .goals
            ) == .goals
        )

        #expect(
            CadenceShellNavigationBridge.visibleDestination(
                tab: .calendar,
                tasksSection: .today,
                pushedDestination: .goals
            ) == .calendar,
            "a stale More push answered for the Calendar tab"
        )

        #expect(
            CadenceShellNavigationBridge.visibleDestination(
                tab: .tasks,
                tasksSection: .inbox,
                pushedDestination: .settings
            ) == .inbox,
            "a stale More push answered for the Tasks tab"
        )
    }

    /// Every More row must widen into its own sidebar row; that is the half of T-334 the tab-level
    /// projection alone cannot reach.
    @Test func everyMoreRowWidensIntoItself() {
        for destination in CadenceCompactTab.more.destinations {
            #expect(
                CadenceShellNavigationBridge.visibleDestination(
                    tab: .more,
                    tasksSection: .today,
                    pushedDestination: destination
                ) == destination,
                "\(destination.title) is reachable in More but widens into something else"
            )
        }
    }
}

/// T-335's half: one stored category, two readings.
@MainActor
struct CadenceMobileSettingsNavigationTests {
    @Test func everyMobileCategorySurvivesBeingStoredAndReadBackByBothLayouts() {
        for kind in CadenceMobileSettingsLayout.categories {
            let raw = CadenceMobileSettingsNavigation.storedRawValue(for: kind)

            #expect(
                CadenceMobileSettingsNavigation.railCategory(storedRawValue: raw) == kind,
                "\(kind.title) narrows and widens back as a different category"
            )
            #expect(
                CadenceMobileSettingsNavigation.drilledCategory(storedRawValue: raw) == kind,
                "\(kind.title) is forgotten by the phone layout"
            )
        }
    }

    /// The one asymmetry, stated deliberately: the phone's category list is a place the user can
    /// be and regular width has no way to show it, so it widens into the default and nothing else.
    @Test func theCategoryListIsTheEmptyStringAndWidensIntoTheDefault() {
        let raw = CadenceMobileSettingsNavigation.storedRawValue(for: nil)

        #expect(raw == CadenceMobileSettingsNavigation.categoryListRawValue)
        #expect(raw.isEmpty, "an unset AppStorage string has to already mean the category list")
        #expect(CadenceMobileSettingsNavigation.drilledCategory(storedRawValue: raw) == nil)
        #expect(
            CadenceMobileSettingsNavigation.railCategory(storedRawValue: raw)
                == CadenceMobileSettingsNavigation.defaultCategory
        )
    }

    /// A stored value mobile has no screen for must not select one. `sidebar` and `account` parse
    /// perfectly well as `CadenceSettingsCategoryKind` and are exactly the two mobile omits, so
    /// parsing alone would put the rail on a category the detail cannot render.
    @Test func aCategoryMobileDoesNotOfferIsRefusedRatherThanSelected() {
        for kind in CadenceMobileSettingsLayout.desktopOnly {
            #expect(
                CadenceMobileSettingsNavigation.drilledCategory(storedRawValue: kind.rawValue) == nil,
                "\(kind.title) has no mobile screen but was accepted as a selection"
            )
            #expect(
                CadenceMobileSettingsNavigation.railCategory(storedRawValue: kind.rawValue)
                    == CadenceMobileSettingsNavigation.defaultCategory
            )
        }

        #expect(CadenceMobileSettingsNavigation.drilledCategory(storedRawValue: "coverage") == nil)
        #expect(
            CadenceMobileSettingsNavigation.railCategory(storedRawValue: "coverage")
                == CadenceMobileSettingsNavigation.defaultCategory
        )
    }

    @Test func theDefaultIsTheOneMacOSSettingsAlsoOpensOn() {
        #expect(CadenceMobileSettingsNavigation.defaultCategory == .navigation)
        #expect(CadenceMobileSettingsLayout.categories.contains(.navigation))
    }
}

/// The iOS wiring. **Source-text assertions, not behaviour** — `Cadence/iOS/` is inside
/// `#if os(iOS)` and this target builds for macOS, so there is no symbol here to call. A correct
/// projection read by a root that never consults it is the whole bug, so the call site is what
/// these check.
@MainActor
struct CadenceSizeClassNavigationWiringTests {
    @Test func theRootBridgesOnTheSizeClassTransition() throws {
        let source = try strippingSwiftComments(swiftSource("Cadence/iOS/iOSRootView.swift"))

        #expect(
            source.contains(".onChange(of: horizontalSizeClass)"),
            "the root still does not notice the transition T-334 is about"
        )
        #expect(
            source.contains("bridgeNavigation(to: sizeClass)"),
            "the root notices the transition and does not carry the selection across it"
        )
        #expect(
            source.contains("CadenceShellNavigationBridge.visibleDestination("),
            "the root reads the compact shell back by some means other than the shared projection"
        )
        #expect(
            source.contains("compactPushedFeature[tab] = destination"),
            "nothing records which feature the compact stack is showing, so More cannot widen"
        )
        // The bridge must not run on `nil -> something`. That transition is the shell learning its
        // width, not a resize: the sidebar still holds its `@State` default while the tab has
        // already been restored from `ios.compact.selectedTab`, so bridging there writes Today over
        // the tab the user actually left the app on.
        #expect(
            source.contains("guard previous != nil else { return }"),
            "the bridge runs on first appearance and can overwrite the restored compact tab"
        )
    }

    @Test func settingsKeepsOneCategoryRatherThanOnePerLayout() throws {
        let source = try strippingSwiftComments(swiftSource("Cadence/iOS/iOSSettingsView.swift"))

        #expect(
            source.contains("@AppStorage(\"ios.settings.category\")"),
            "the settings category is not stored anywhere the size class cannot destroy"
        )
        #expect(
            source.contains("CadenceMobileSettingsNavigation.railCategory(storedRawValue:"),
            "the iPad rail reads its category from somewhere other than the shared store"
        )
        #expect(
            source.contains("CadenceMobileSettingsNavigation.drilledCategory(storedRawValue:"),
            "the phone layout reads its category from somewhere other than the shared store"
        )
        #expect(
            !source.contains("@State private var selectedCategory"),
            "the rail's category is view state again, which the size class resets"
        )
        #expect(
            !source.contains("@State private var drilledCategory"),
            "the phone's category is view state again, which the size class resets"
        )
    }

    /// Stops every assertion above from passing vacuously against an unread file, which is what a
    /// `contains` on the empty string does.
    @Test func theWiringScanReadsRealSourceAndReallyStripsComments() throws {
        for path in ["Cadence/iOS/iOSRootView.swift", "Cadence/iOS/iOSSettingsView.swift"] {
            let raw = try swiftSource(path)
            let stripped = try strippingSwiftComments(raw)

            #expect(raw.count > 1_000, "\(path) read as nothing")
            #expect(raw.contains("/// "), "\(path) has no doc comments, so stripping proves nothing")
            #expect(!stripped.contains("/// "), "strippingSwiftComments did not strip \(path)")
        }

        #expect(
            try strippingSwiftComments(swiftSource("Cadence/iOS/iOSRootView.swift"))
                .contains("struct iOSRootView"),
            "the root scan is reading some other file"
        )
        #expect(
            try strippingSwiftComments(swiftSource("Cadence/iOS/iOSSettingsView.swift"))
                .contains("struct iOSSettingsView"),
            "the settings scan is reading some other file"
        )
    }
}

// MARK: - Source-reading helpers

private func swiftSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks `//` line comments and `/* */` block comments so the assertions read code rather than
/// the prose about it. Crude on purpose, exactly as `CadenceCompactTabTests` does it: a `//` inside
/// a string literal is blanked too, which can only make these checks stricter.
private func strippingSwiftComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}
