import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// Pins the tag chip's state → appearance decision.
///
/// The chip is one component on both platforms, but the *reason* it is shared is that iOS was
/// silently missing three behaviours macOS had — the label width cap, the remove control, and any
/// rendering of `Tag.isArchived` at all. The first and the third are decided here, in
/// `CadenceTagChipStyle`, precisely so a call site cannot forget them; the second is a control the
/// chip draws itself. These tests are what stop any of the three drifting back out.
struct CadenceTagChipStyleTests {

    // MARK: Archived is a visible state, not a call-site convention

    /// **The bug this whole component exists to fix.** An archived tag drew identically to a live
    /// one on iPhone and iPad. Every channel the chip has must differ, so no single call site can
    /// flatten it back by overriding one of them.
    @Test func archivedChipDiffersFromLiveOnEveryChannel() {
        for size in CadenceTagChipSize.allCases {
            for input in CadenceTagChipInput.allCases {
                let live = CadenceTagChipStyle(size: size, isArchived: false, input: input)
                let archived = CadenceTagChipStyle(size: size, isArchived: true, input: input)

                #expect(live.usesTagColor)
                #expect(!archived.usesTagColor)
                #expect(archived.labelInk != live.labelInk)
                #expect(archived.fillOpacity != live.fillOpacity)
                #expect(archived.strokeOpacity != live.strokeOpacity)
                #expect(archived.chipOpacity < live.chipOpacity)
            }
        }
    }

    /// Archived wins over every selection state. The tag filter bar drives `selection`, and an
    /// archived tag that happened to be filtered on must still read as archived.
    @Test func archivedOverridesSelection() {
        for selection in CadenceTagChipSelection.allCases {
            let archived = CadenceTagChipStyle(selection: selection, isArchived: true)
            #expect(!archived.usesTagColor)
            #expect(archived.labelInk == .dimmed)
            #expect(archived.chipOpacity < 1)
        }
    }

    /// A live chip never dims its label, so "dimmed" stays unambiguous as the archived signal —
    /// except on a filter chip that is explicitly switched off, which is the one other thing
    /// "receded" can mean here.
    @Test func liveDisplayChipIsNotDimmed() {
        #expect(CadenceTagChipStyle(selection: .none, isArchived: false).labelInk == .muted)
        #expect(CadenceTagChipStyle(selection: .on, isArchived: false).labelInk == .emphasized)
        #expect(CadenceTagChipStyle(selection: .off, isArchived: false).labelInk == .dimmed)
    }

    // MARK: The truncation rule

    /// The cap exists so one long tag name cannot push a row's other metadata out of reach. Both
    /// sizes must have a finite one, and the dense size must be the tighter of the two.
    @Test func labelWidthIsCappedAndDenserSizeIsTighter() {
        let regular = CadenceTagChipStyle(size: .regular, isArchived: false)
        let compact = CadenceTagChipStyle(size: .compact, isArchived: false)

        #expect(regular.maximumLabelWidth.isFinite)
        #expect(compact.maximumLabelWidth.isFinite)
        #expect(compact.maximumLabelWidth < regular.maximumLabelWidth)
        #expect(compact.fontSize < regular.fontSize)
        #expect(compact.cornerRadius < regular.cornerRadius)
    }

    /// The cap does not depend on archived-ness or selection: chips in one strip have to line up.
    @Test func labelWidthDoesNotVaryWithState() {
        for size in CadenceTagChipSize.allCases {
            let widths = Set(
                CadenceTagChipSelection.allCases.flatMap { selection in
                    [true, false].map {
                        CadenceTagChipStyle(size: size, selection: selection, isArchived: $0).maximumLabelWidth
                    }
                }
            )
            #expect(widths.count == 1)
        }
    }

    // MARK: The remove control, and the platform difference that is deliberate

    /// A finger gets 44pt; a pointer gets the drawn control and nothing more. This is the one
    /// difference between the platforms that is kept on purpose rather than flattened.
    @Test func touchRemoveControlReaches44AndPointerDoesNotGrow() {
        for size in CadenceTagChipSize.allCases {
            let touch = CadenceTagChipStyle(size: size, isArchived: false, input: .touch)
            #expect(touch.removeHitTargetSize == 44)
            #expect(touch.removeControlSize + touch.removeHitInset * 2 == 44)
            #expect(touch.removeControlSize > CadenceTagChipStyle(size: size, isArchived: false, input: .pointer).removeControlSize)

            let pointer = CadenceTagChipStyle(size: size, isArchived: false, input: .pointer)
            #expect(pointer.removeHitInset == 0)
            #expect(pointer.removeHitTargetSize == pointer.removeControlSize)
        }
    }

    /// The hazard the expansion creates: a hit area grown past its chip reaches into the chip next
    /// to it, and an expanded filled shape eating a neighbour's tap is a failure this repo has
    /// shipped before. The strip spacing must cover the spill in both axes — the editable strips on
    /// both platforms read these numbers rather than picking their own.
    @Test func editableStripSpacingCoversTheHitAreaSpill() {
        for size in CadenceTagChipSize.allCases {
            for input in CadenceTagChipInput.allCases {
                let style = CadenceTagChipStyle(size: size, isArchived: false, input: input)
                let overhang = style.removeHitOverhang()

                let spacing = CadenceTagChipStyle.editableStripSpacing(for: size, input: input)
                let lineSpacing = CadenceTagChipStyle.editableStripLineSpacing(for: size, input: input)

                // Two adjacent chips each spill `overhang` toward each other.
                #expect(spacing >= overhang.horizontal * 2)
                #expect(lineSpacing >= overhang.vertical * 2)
                #expect(spacing > 0)
                #expect(lineSpacing > 0)
            }
        }
    }

    /// A pointer chip has no expansion at all, so it must not be paying for touch's clearance.
    @Test func pointerStripsAreNotSpacedForTouch() {
        for size in CadenceTagChipSize.allCases {
            #expect(
                CadenceTagChipStyle.editableStripLineSpacing(for: size, input: .pointer)
                    <= CadenceTagChipStyle.editableStripLineSpacing(for: size, input: .touch)
            )
        }
    }

    // MARK: The label itself

    /// `Tag.name` is free text and may be blank. iOS fell back to the slug and macOS did not, so an
    /// unnamed tag drew as a bare dot on one platform and a named chip on the other.
    @Test func blankNameFallsBackToSlugThenToAWord() {
        #expect(CadenceTagChipStyle.displayName(name: "bug", slug: "bug") == "bug")
        #expect(CadenceTagChipStyle.displayName(name: "  ", slug: "deep-work") == "deep-work")
        #expect(CadenceTagChipStyle.displayName(name: "", slug: "") == "tag")
        #expect(CadenceTagChipStyle.displayName(name: "  Deep Work  ", slug: "deep-work") == "Deep Work")
    }

    /// Dimming is invisible to VoiceOver, so archived has to be spoken as well as drawn.
    @Test func archivedIsSpokenNotOnlyDrawn() {
        #expect(CadenceTagChipStyle.accessibilityLabel(name: "bug", slug: "bug", isArchived: false) == "bug")
        #expect(CadenceTagChipStyle.accessibilityLabel(name: "bug", slug: "bug", isArchived: true) == "bug (archived)")
        #expect(CadenceTagChipStyle.accessibilityLabel(name: "", slug: "old-tag", isArchived: true) == "old-tag (archived)")
    }
}

/// **T-1412: what the reader's text size does to a chip twelve surfaces draw.**
///
/// The difficulty is not the arithmetic, it is the blast radius. `iOSTaskTagPickerPopover` could
/// not convert until the chip did — converting the panel alone gives ~69pt rows around a 12pt tag
/// name, the mirror image of the defect T-1398 closed — but changing the chip changes all twelve
/// surfaces at once, and eleven of them have no `.cadenceScaledTypography()` root.
///
/// The invariant that makes that safe is the one `2cabfeb` asserts and this suite re-asserts for
/// this component specifically: **a role at `.fixed` resolves to exactly the literal it replaces**,
/// at every one of the twelve `DynamicTypeSize` cases and not merely at the default. The first test
/// below is that claim over every metric on the type; the rest price the three judgements the
/// conversion had to make rather than inherit.
///
/// **Nothing here claims Larger Text eligibility, and nothing here is a rendering.** Every
/// assertion is over the layout model. No screenshot, simulator run, accessibility audit or
/// VoiceOver traversal was performed, and nothing asserts that the scaling environment crosses a
/// presentation — see `CadenceTypographyScaling` for why that may not be pinned.
struct CadenceTagChipScaleTests {

    private let everySize = DynamicTypeSize.allCases

    private func styles(
        at dynamicTypeSize: DynamicTypeSize,
        scaling: CadenceTypographyScaling
    ) -> [CadenceTagChipStyle] {
        CadenceTagChipSize.allCases.flatMap { size in
            CadenceTagChipInput.allCases.map { input in
                CadenceTagChipStyle(
                    size: size, isArchived: false, input: input,
                    dynamicTypeSize: dynamicTypeSize, scaling: scaling
                )
            }
        }
    }

    // MARK: - The invariant that let this land ahead of eleven of its callers

    /// **Every metric on the chip, under `.fixed`, at all twelve sizes, is the number the file
    /// drew before T-1412.**
    ///
    /// This is what makes converting a twelve-surface shared component a refactor for eleven of
    /// them. The expected values are the literals themselves, written out here rather than read
    /// from the same properties they are checking — comparing a property to itself would pass
    /// however the curve behaved.
    @Test("Every chip metric is its old literal under fixed scaling, at all twelve sizes")
    func everyChipMetricIsItsOldLiteralUnderFixedScaling() {
        #expect(everySize.count == 12, "a shorter walk would prove less than it claims")

        let expectedFont: [CadenceTagChipSize: CGFloat] = [.regular: 12, .compact: 10]
        let expectedDot: [CadenceTagChipSize: CGFloat] = [.regular: 6, .compact: 5]
        let expectedCap: [CadenceTagChipSize: CGFloat] = [.regular: 130, .compact: 92]
        let expectedRemove: [CadenceTagChipInput: [CadenceTagChipSize: CGFloat]] = [
            .touch: [.regular: 22, .compact: 18],
            .pointer: [.regular: 14, .compact: 12],
        ]

        for size in everySize {
            for style in styles(at: size, scaling: .fixed) {
                #expect(style.fontSize == expectedFont[style.size], "font moved at \(size)")
                #expect(style.dotDiameter == expectedDot[style.size], "dot moved at \(size)")
                #expect(style.maximumLabelWidth == expectedCap[style.size], "cap moved at \(size)")
                #expect(style.removeControlSize == expectedRemove[style.input]?[style.size],
                        "remove control moved at \(size)")
                #expect(style.labelGrowth == 0)
                #expect(style.labelMultiplier == 1)
            }

            // The two figures that are computed from the above, and the two strip spacings that
            // are computed from those.
            for chipSize in CadenceTagChipSize.allCases {
                for input in CadenceTagChipInput.allCases {
                    let pinned = CadenceTagChipStyle(
                        size: chipSize, isArchived: false, input: input,
                        dynamicTypeSize: size, scaling: .fixed
                    )
                    let atDefault = CadenceTagChipStyle(size: chipSize, isArchived: false, input: input)
                    #expect(pinned.chipHeight(hasRemoveControl: true)
                        == atDefault.chipHeight(hasRemoveControl: true))
                    #expect(pinned.chipHeight(hasRemoveControl: false)
                        == atDefault.chipHeight(hasRemoveControl: false))
                    #expect(pinned.removeHitTargetSize == atDefault.removeHitTargetSize)
                    #expect(pinned.removeHitInset == atDefault.removeHitInset)

                    #expect(CadenceTagChipStyle.editableStripSpacing(
                        for: chipSize, input: input, at: size, scaling: .fixed
                    ) == CadenceTagChipStyle.editableStripSpacing(for: chipSize, input: input))
                    #expect(CadenceTagChipStyle.editableStripLineSpacing(
                        for: chipSize, input: input, at: size, scaling: .fixed
                    ) == CadenceTagChipStyle.editableStripLineSpacing(for: chipSize, input: input))
                }
            }
        }
    }

    /// And the other half, or the test above is satisfied by a chip that never moves at all.
    @Test("The same chip does grow once the surface drawing it says it is scaled")
    func theScaledChipGrowsOrTheFixedAssertionIsVacuous() {
        for style in styles(at: .accessibility5, scaling: .enabled) {
            #expect(style.fontSize > style.baseFontSize, "the label does not grow")
            #expect(style.dotDiameter > style.baseDotDiameter, "the dot does not grow")
            #expect(style.maximumLabelWidth > style.baseMaximumLabelWidth, "the cap does not grow")
            #expect(style.removeControlSize > style.baseRemoveControlSize)
        }
        // One role, two bases: the dense chip stays the dense one at every size.
        for size in everySize {
            let regular = CadenceTagChipStyle(size: .regular, isArchived: false,
                                              dynamicTypeSize: size, scaling: .enabled)
            let compact = CadenceTagChipStyle(size: .compact, isArchived: false,
                                              dynamicTypeSize: size, scaling: .enabled)
            #expect(compact.fontSize < regular.fontSize, "the two sizes converged at \(size)")
            #expect(compact.maximumLabelWidth < regular.maximumLabelWidth)
            #expect(compact.dotDiameter < regular.dotDiameter)
        }
    }

    // MARK: - The eleven surfaces that did not move

    /// **The other half of the safety claim, derived from the tree rather than asserted.**
    ///
    /// The test above says a chip under `.fixed` is its old literal. This one says which surfaces
    /// are under `.fixed`: of every file that draws a `CadenceTagChip`, a `CompactTagStrip` or a
    /// `CadenceTagOverflowBadge`, **exactly one** declares `.cadenceScaledTypography()`. The rest
    /// declare nothing, so the environment default is their answer and they render as they did
    /// before T-1412.
    ///
    /// Two things this deliberately does *not* claim. It does not claim the eleven are unreachable
    /// from a converted root — the flag crosses a presentation on at least one toolchain, so
    /// reachability is not a property of the source; what it claims is that none of them opted
    /// itself in. And it says nothing about pixels: no screenshot or simulator run was taken.
    @Test("Exactly one file that draws a tag chip has opted itself into scaling")
    func onlyOneTagChipSurfaceDeclaresItselfConverted() throws {
        let drawsAChip = try CadenceScanInstrument(
            "tag chip draw site",
            fires: "HStack { CadenceTagChip(tag: tag, size: .compact) }",
            andNotOn: "let style = CadenceTagChipStyle(size: .regular, isArchived: false)",
            by: {
                $0.contains("CadenceTagChip(")
                    || $0.contains("CompactTagStrip(")
                    || $0.contains("CadenceTagOverflowBadge(")
            }
        )
        let declaresScaled = try CadenceScanInstrument(
            "scaled typography scope",
            fires: "VStack { rows }.cadenceScaledTypography().background(Theme.bg)",
            andNotOn: "func cadenceScaledTypography() -> some View { modifier(scope) }",
            by: { $0.contains(".cadenceScaledTypography()") }
        )

        let read = CadenceSourceScan.strippedSourceReader()
        var paths: [String] = []
        for root in ["Cadence", "CadenceWidgets"] {
            paths += try CadenceSourceScan.swiftFiles(under: root)
        }

        let drawSites = try drawsAChip.sweep(
            paths,
            atLeast: 300,
            including: "Cadence/Shared/Components/CadenceTagChip.swift",
            read: read
        )
        #expect(drawSites.count >= 10,
                "the chip is drawn by \(drawSites.count) files, so this is not the component T-1412 is about")

        let optedIn = try declaresScaled.sweep(
            drawSites,
            atLeast: drawSites.count,
            including: "Cadence/Shared/Components/CadenceTagChip.swift",
            read: read
        )
        #expect(optedIn == ["Cadence/iOS/iOSTaskDetailComponents.swift"],
                "the set of opted-in tag surfaces moved: \(optedIn.joined(separator: ", "))")

        // And the component itself does not opt anything in, which is what makes the default the
        // eleven surfaces' answer rather than something they each have to say.
        let chipFile = try read("Cadence/Shared/Components/CadenceTagChip.swift")
        #expect(!chipFile.contains(".cadenceScaledTypography()"))
        #expect(!chipFile.contains(".cadenceFixedTypography()"))
        #expect(chipFile.contains("@Environment(\\.cadenceTypographyScaling)"),
                "the chip stopped reading the boundary, so it cannot follow a converted surface")

        try assertPageChromeCallerInventory(paths: paths, read: read)
    }

    /// Like the chip, these shared components are prepared before their pages opt in. This pins
    /// direct callers, not transitive reachability or framework presentation propagation.
    private func assertPageChromeCallerInventory(paths: [String], read: (String) throws -> String) throws {
        let families: [(pattern: String, fires: String, anchor: String, undeclared: Set<String>, declared: Set<String>)] = [
            (
                #"\bEmptyStateView\s*\("#,
                "EmptyStateView(message: title, icon: icon)",
                "Cadence/iOS/iOSTaskViews.swift",
                [
                    "Cadence/iOS/iOSAINoteActionsViews.swift",
                    "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
                    "Cadence/iOS/iOSTaskViews.swift",
                    "Cadence/macOS/Views/GoalTimelineView.swift",
                    "Cadence/macOS/Views/GoalsView.swift",
                    "Cadence/macOS/Views/HabitsView.swift",
                    "Cadence/macOS/Views/LinksView.swift",
                    "Cadence/macOS/Views/ListDetailComponents.swift",
                    "Cadence/macOS/Views/ListDetailSupportViews.swift",
                    "Cadence/macOS/Views/ListDetailView.swift",
                    "Cadence/macOS/Views/ListNotesViewSupportViews.swift",
                    "Cadence/macOS/Views/NoteActionReviewSheets.swift",
                    "Cadence/macOS/Views/NotesView.swift",
                    "Cadence/macOS/Views/TasksListView.swift",
                    "Cadence/macOS/Views/TasksPanel.swift",
                ], []
            ),
            (
                #"\b(?:CadenceTaskGroupHeading|CadenceTodayRolloverBanner|CadenceTodayOverdue(?:ListCard|SectionCard|SummaryHeading))\s*\("#,
                "CadenceTodayRolloverBanner(tasks: tasks) { roll() }",
                "Cadence/iOS/iOSTodayTaskSections.swift",
                [
                    "Cadence/iOS/iOSTaskGroupSection.swift",
                    "Cadence/iOS/iOSTodayTaskSections.swift",
                    "Cadence/macOS/Views/TasksPanel.swift",
                ], []
            ),
            (
                #"\biOS(?:PageHeader|CompactPageHeader)\s*\("#,
                "iOSPageHeader(title: name)",
                "Cadence/iOS/iOSFeatureComponents.swift",
                [
                    "Cadence/iOS/iOSFeatureComponents.swift",
                    "Cadence/iOS/iOSFocusView.swift",
                    "Cadence/iOS/iOSListDetailView.swift",
                    "Cadence/iOS/iOSListSupportViews.swift",
                    "Cadence/iOS/iOSSettingsComponents.swift",
                    "Cadence/iOS/iOSTaskViews.swift",
                    "Cadence/iOS/iOSTodayCompactViews.swift",
                    "Cadence/iOS/iPadTodaySupportViews.swift",
                ], [
                    "Cadence/iOS/iOSTaskCollectionPage.swift",
                    "Cadence/iOS/iOSTasksPageView.swift",
                    "Cadence/iOS/iOSTasksTabView.swift",
                ]
            ),
            (
                #"\biOSSegmentedPill(?:Group)?\s*[({]"#,
                "iOSSegmentedPillGroup { iOSSegmentedPill(title: title) }",
                "Cadence/iOS/iOSDesignSystem.swift",
                [
                    "Cadence/iOS/iOSAINoteActionsViews.swift",
                    "Cadence/iOS/iOSCalendarChromeViews.swift",
                    "Cadence/iOS/iOSDesignSystem.swift",
                    "Cadence/iOS/iOSSearchSupportViews.swift",
                    "Cadence/iOS/iPadTodaySupportViews.swift",
                ], [
                    "Cadence/iOS/iOSTasksPageView.swift",
                    "Cadence/iOS/iOSTasksTabView.swift",
                ]
            ),
            (
                #"\bCadenceBoardColumn(?:Header|TitleRow|DueDateLine)\s*\("#,
                "CadenceBoardColumnHeader(dotColor: color, title: title, count: count)",
                "Cadence/iOS/iOSListSupportViews.swift",
                [
                    "Cadence/Shared/Components/CadenceBoardColumnHeader.swift",
                    "Cadence/iOS/iOSCalendarBoardView.swift",
                    "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
                    "Cadence/iOS/iOSListSupportViews.swift",
                    "Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift",
                    "Cadence/macOS/Views/CalendarBoardRailSupportViews.swift",
                    "Cadence/macOS/Views/KanbanColumnSupportViews.swift",
                    "Cadence/macOS/Views/KanbanListColumnView.swift",
                ], []
            ),
            (
                #"\biOSBoardTaskCard\s*\("#,
                "iOSBoardTaskCard(task: task)",
                "Cadence/iOS/iOSListSupportViews.swift",
                ["Cadence/iOS/iOSCalendarBoardView.swift", "Cadence/iOS/iOSListSupportViews.swift"], []
            ),
        ]
        for family in families {
            let instrument = try CadenceScanInstrument(
                "shared page chrome caller",
                fires: family.fires,
                andNotOn: "// \(family.fires)\nlet prose = \(String(reflecting: family.fires))",
                by: { CadenceSourceScan.codeOnly($0).range(of: family.pattern, options: .regularExpression) != nil }
            )
            let sites = try instrument.sweep(paths, atLeast: 300, including: family.anchor, read: read)
            #expect(Set(sites) == family.undeclared.union(family.declared), "\(family.pattern): reclassify the new or removed chrome caller")
            for path in sites {
                #expect(CadenceSourceScan.codeOnly(try read(path)).contains(".cadenceScaledTypography()") == family.declared.contains(path),
                        "\(family.pattern): scope classification changed for \(path); verify whole-page geometry before changing the declared/undeclared inventory")
            }
        }

        let controls = try CadenceScanInstrument(
            "prepared icon, metadata and action control caller",
            fires: "iOSActionButton(title: title) { save() }",
            andNotOn: "// iOSIconTile(icon: name)\nlet prose = \"iOSMetaChip(text: title)\"",
            by: { CadenceSourceScan.codeOnly($0).range(of: #"\biOS(?:IconTile|MetaChip|ActionButton)\s*\("#, options: .regularExpression) != nil }
        )
        let undeclaredControls: Set<String> = [
            "Cadence/Shared/Components/HabitProgressViews.swift",
            "Cadence/iOS/iOSAINoteActionsViews.swift",
            "Cadence/iOS/iOSArchiveImportSettingsSection.swift",
            "Cadence/iOS/iOSCalendarBundleDetailSheet.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift",
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            "Cadence/iOS/iOSCalendarSettingsSection.swift",
            "Cadence/iOS/iOSDataExportSettingsSection.swift",
            "Cadence/iOS/iOSDataResetSettingsSection.swift",
            "Cadence/iOS/iOSFeatureComponents.swift",
            "Cadence/iOS/iOSFeatureDetailViews.swift",
            "Cadence/iOS/iOSFocusView.swift",
            "Cadence/iOS/iOSGoalAttachListsSheet.swift",
            "Cadence/iOS/iOSInboxRemindersSection.swift",
            "Cadence/iOS/iOSListDeletionSupport.swift",
            "Cadence/iOS/iOSListEditorViews.swift",
            "Cadence/iOS/iOSListNotesView.swift",
            "Cadence/iOS/iOSListSupportViews.swift",
            "Cadence/iOS/iOSMarkdownAccessoryViews.swift",
            "Cadence/iOS/iOSNoteDeletionSupport.swift",
            "Cadence/iOS/iOSNoteExportMenu.swift",
            "Cadence/iOS/iOSNotesView.swift",
            "Cadence/iOS/iOSNotificationsSettingsSection.swift",
            "Cadence/iOS/iOSRemindersSettingsSection.swift",
            "Cadence/iOS/iOSRootSidebar.swift",
            "Cadence/iOS/iOSSearchSupportViews.swift",
            "Cadence/iOS/iOSSettingsComponents.swift",
            "Cadence/iOS/iOSSettingsContextSection.swift",
            "Cadence/iOS/iOSSettingsOverviewSections.swift",
            "Cadence/iOS/iOSSettingsTagsSection.swift",
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
            "Cadence/iOS/iOSSettingsView.swift",
            "Cadence/iOS/iOSSidebarLayoutSettingsSection.swift",
            "Cadence/iOS/iOSTaskDetailSheetSections.swift",
            "Cadence/iOS/iOSTodayCompactViews.swift",
            "Cadence/iOS/iOSTodaySchedulePanel.swift",
            "Cadence/iOS/iOSWindDownConfirmation.swift",
        ]
        let declaredControls: Set<String> = [
            "Cadence/iOS/iOSTaskDetailSheet.swift",
            "Cadence/iOS/iOSSearchView.swift",
        ]
        let controlSites = try controls.sweep(paths, atLeast: 300,
                                             including: "Cadence/iOS/iOSTodayCompactViews.swift", read: read)
        #expect(Set(controlSites) == undeclaredControls.union(declaredControls))
        for path in controlSites {
            #expect(CadenceSourceScan.codeOnly(try read(path)).contains(".cadenceScaledTypography()")
                == declaredControls.contains(path), "reclassify the control caller only after its page is size-aware: \(path)")
        }
    }

    // MARK: - Judgement 1: the dot and the `x` are content

    /// The dot scales **proportionally** and the paddings do not, and the arithmetic is what
    /// decides it: this repo's additive rule applied to a 6pt dot produces a disc.
    @Test("The dot follows the label's multiplier while the chip's padding stays put")
    func theDotIsProportionalAndThePaddingIsNot() {
        for size in everySize {
            let style = CadenceTagChipStyle(size: .regular, isArchived: false,
                                            dynamicTypeSize: size, scaling: .enabled)
            let proportional: CGFloat = style.baseDotDiameter * style.labelMultiplier
            #expect(style.dotDiameter == proportional)

            // The paddings, the spacing and the radius are the literals they always were.
            #expect(style.horizontalPadding == 8)
            #expect(style.verticalPadding == 5)
            #expect(style.contentSpacing == 5)
            #expect(style.cornerRadius == 7)
        }

        // What the additive rule would have produced here, and why it is the wrong rule for a dot.
        let largest = CadenceTagChipStyle(size: .regular, isArchived: false,
                                          dynamicTypeSize: .accessibility5, scaling: .enabled)
        let additiveDot: CGFloat = largest.baseDotDiameter + largest.labelGrowth
        #expect(additiveDot > largest.dotDiameter,
                "additive growth is not larger here, so there was nothing to reject")
        #expect(additiveDot > largest.fontSize * 0.6,
                "an additive dot would not have been oversized, so re-argue this")
        // The proportional dot keeps the ratio the chip was drawn with.
        let baseRatio: CGFloat = largest.baseDotDiameter / largest.baseFontSize
        let grownRatio: CGFloat = largest.dotDiameter / largest.fontSize
        #expect(abs(baseRatio - grownRatio) < 0.0001)
    }

    /// The remove control is content too, and the touch target has to stop being a constant once
    /// what is drawn is bigger than it.
    @Test("The remove control grows with the label and its hit target never falls under it")
    func theRemoveControlAndItsTargetBothStayCoherent() {
        for size in everySize {
            for style in styles(at: size, scaling: .enabled) {
                #expect(style.removeHitTargetSize >= style.removeControlSize,
                        "the target is smaller than the control at \(size)")
                #expect(style.removeHitInset >= 0)
                #expect(style.removeControlSize + style.removeHitInset * 2 == style.removeHitTargetSize)
                if style.input == .touch {
                    #expect(style.removeHitTargetSize >= CadenceTagChipStyle.touchTargetSize,
                            "a finger lost its 44pt at \(size)")
                }
            }
        }
        // At the default size the touch target is exactly the platform's 44, which is the number
        // the chip has always drawn.
        let touch = CadenceTagChipStyle(size: .regular, isArchived: false, input: .touch)
        #expect(touch.removeHitTargetSize == CadenceTagChipStyle.touchTargetSize)
        // And past some accessibility size the drawn control is itself the target.
        let largest = CadenceTagChipStyle(size: .regular, isArchived: false, input: .touch,
                                          dynamicTypeSize: .accessibility5, scaling: .enabled)
        #expect(largest.removeControlSize > CadenceTagChipStyle.touchTargetSize)
        #expect(largest.removeHitInset == 0)
    }

    /// The chip's plate holds the label on it, at every size — the "font grew, box did not" case
    /// for this component.
    @Test("The chip's own height holds its label and its remove control at all twelve sizes")
    func theChipHeightHoldsWhatIsInIt() {
        for size in everySize {
            for scaling in CadenceTypographyScaling.allCases {
                for style in styles(at: size, scaling: scaling) {
                    let withControl = style.chipHeight(hasRemoveControl: true)
                    let withoutControl = style.chipHeight(hasRemoveControl: false)
                    #expect(withoutControl >= style.fontSize + style.verticalPadding * 2,
                            "the chip is \(withoutControl) around \(style.fontSize) of label at \(size)/\(scaling)")
                    #expect(withControl >= style.removeControlSize + style.verticalPadding * 2,
                            "the chip clips its own remove control at \(size)/\(scaling)")
                    #expect(withControl >= withoutControl)
                    #expect(withoutControl > style.dotDiameter)
                }
            }
        }

        // The box frozen at what it drew before could not hold the label once the label moves.
        let frozen = CadenceTagChipStyle(size: .regular, isArchived: false)
            .chipHeight(hasRemoveControl: false)
        var overflowingSizes: [DynamicTypeSize] = []
        for size in everySize {
            let style = CadenceTagChipStyle(size: .regular, isArchived: false,
                                            dynamicTypeSize: size, scaling: .enabled)
            if style.fontSize + style.verticalPadding * 2 > frozen { overflowingSizes.append(size) }
        }
        #expect(overflowingSizes.contains(.accessibility5))
        #expect(overflowingSizes.count >= 2,
                "only one size overflowed the old box, so the derivation is cosmetic")
        #expect(!overflowingSizes.contains(.large),
                "the default size must be unaffected or this was never a refactor")
    }

    // MARK: - Judgement 2: the cap

    /// **A cap grows additively or it stops being a cap.**
    ///
    /// The rejected alternative is measured rather than asserted away: the proportional cap is
    /// wider than the narrowest iPhone, so it would sit outside every container it exists to
    /// protect. The honest cost of the additive answer — a grown chip showing fewer characters —
    /// is asserted too, so nobody has to rediscover it.
    @Test("The label cap grows additively and stays inside the narrowest iPhone")
    func theLabelCapGrowsAdditivelyRatherThanProportionally() {
        let narrowestPhoneWidth: CGFloat = 375

        var previous: CGFloat = 0
        for size in everySize {
            let style = CadenceTagChipStyle(size: .regular, isArchived: false,
                                            dynamicTypeSize: size, scaling: .enabled)
            let additive: CGFloat = style.baseMaximumLabelWidth + style.labelGrowth
            #expect(style.maximumLabelWidth == additive)
            #expect(style.maximumLabelWidth >= previous, "the cap narrowed at \(size)")
            previous = style.maximumLabelWidth
            #expect(style.maximumLabelWidth < narrowestPhoneWidth,
                    "the cap is \(style.maximumLabelWidth) at \(size), which is off a 375pt screen")
        }

        let largest = CadenceTagChipStyle(size: .regular, isArchived: false,
                                          dynamicTypeSize: .accessibility5, scaling: .enabled)
        let proportional: CGFloat = largest.baseMaximumLabelWidth * largest.labelMultiplier
        #expect(proportional > narrowestPhoneWidth,
                "a proportional cap fits a phone after all, so this judgement needs re-arguing")
        #expect(largest.maximumLabelWidth < proportional)

        // The cost, stated: the text tripled and its box grew by a fifth, so the same cap holds
        // roughly a third of the characters. The chip's identity survives it — the dot is a colour
        // and the untruncated name is what a screen reader and a tooltip get.
        let charactersAtDefault: CGFloat = 130 / 12
        let charactersAtLargest: CGFloat = largest.maximumLabelWidth / largest.fontSize
        #expect(charactersAtLargest < charactersAtDefault)
        #expect(CadenceTagChipStyle.accessibilityLabel(name: "a very long tag name", slug: "x", isArchived: false)
            == "a very long tag name")
    }

    // MARK: - Judgement 3: the spacings derived from the overhang

    /// The strip spacings **shrink**, and that is the derivation working rather than failing.
    ///
    /// They exist to clear the spill of a 44pt touch target grown around a smaller drawn control.
    /// Once the drawn control passes 44 there is no spill, so the right answer is the floor.
    @Test("The strip spacings follow the remove control's overhang and fall to the floor")
    func theStripSpacingsFollowTheOverhangAndShrink() {
        for size in everySize {
            for chipSize in CadenceTagChipSize.allCases {
                for input in CadenceTagChipInput.allCases {
                    let style = CadenceTagChipStyle(
                        size: chipSize, isArchived: false, input: input,
                        dynamicTypeSize: size, scaling: .enabled
                    )
                    let overhang = style.removeHitOverhang()
                    let spacing = CadenceTagChipStyle.editableStripSpacing(
                        for: chipSize, input: input, at: size, scaling: .enabled
                    )
                    let lineSpacing = CadenceTagChipStyle.editableStripLineSpacing(
                        for: chipSize, input: input, at: size, scaling: .enabled
                    )
                    // The relationship the spacing exists for, at every size rather than only at
                    // the one the chip was drawn at.
                    #expect(spacing >= overhang.horizontal * 2,
                            "one chip's hit area reaches its neighbour at \(size)/\(chipSize)/\(input)")
                    #expect(lineSpacing >= overhang.vertical * 2,
                            "one chip's hit area reaches the row below at \(size)/\(chipSize)/\(input)")
                    #expect(spacing >= CadenceTagChipStyle.stripSpacingFloor)
                    #expect(lineSpacing >= CadenceTagChipStyle.stripSpacingFloor)
                }
            }
        }

        // At the largest size there is nothing left to clear, so both are the floor.
        #expect(CadenceTagChipStyle.editableStripSpacing(
            for: .regular, input: .touch, at: .accessibility5, scaling: .enabled
        ) == CadenceTagChipStyle.stripSpacingFloor)
        #expect(CadenceTagChipStyle.editableStripLineSpacing(
            for: .regular, input: .touch, at: .accessibility5, scaling: .enabled
        ) == CadenceTagChipStyle.stripSpacingFloor)
        // And at the default size the touch strip really does pay for a spill, or the sentence
        // above is about nothing.
        #expect(CadenceTagChipStyle.editableStripLineSpacing(for: .regular, input: .touch)
            > CadenceTagChipStyle.stripSpacingFloor)
    }
}
