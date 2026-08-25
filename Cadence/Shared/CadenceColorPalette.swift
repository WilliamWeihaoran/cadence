import Foundation

/// The swatch palettes offered wherever a user picks a `colorHex` — `colors` for a **list, goal
/// or habit**, `sectionColors` for a **kanban section**.
///
/// This existed three times: `ColorGrid.colors` (macOS, `#if os(macOS)`), `iOSListPalette.colors`
/// (a deliberate iOS mirror of it, added precisely because `ColorGrid` could not be reached), and
/// `iOSTrackingColorGrid.colors` — which had already drifted to a *different eight colours*, so a
/// goal or habit could be tinted `#38d5c7` or `#94a3b8` while no list could, and lists offered five
/// hues that goals did not. One palette, no `#if`, so the next surface that needs swatches has
/// somewhere to get them.
///
/// `TagSupport.colorOptions` is deliberately **not** folded in here. Tags are a different palette
/// with a different job, and it is already shared.
/// **Everything here that reads a `Theme` accent is computed, not stored.** The six accents are
/// selectable (T-15), and a `static let` initialises exactly once — a stored `colors` would freeze
/// on whichever palette happened to be active the first time a colour grid was drawn, and
/// `destinationTints` would stop containing `CadenceFeatureDestination.defaultColorHex`, which is
/// the T-245 bug (a destination's own default falling out of the menu that edits it) arriving by a
/// different road. The arrays are still literals; only their storage changed.
enum CadenceColorPalette {
    /// `Area.colorHex`'s model default. Named rather than respelled at each seeding site.
    static var areaDefault: String { Theme.blueHex }

    /// `Project.colorHex`'s model default.
    static var projectDefault: String { Theme.greenHex }

    /// One lap of the hue circle, warm through cool, ending on a neutral. Twelve reads as a 6×2 or
    /// 4×3 grid on macOS and wraps cleanly into a strip on iOS.
    ///
    /// **Five of the twelve are `Theme` accents, and they read the token rather than re-typing the
    /// hex** (T-246): blue, purple, red, amber, green. Blue and green already did, through
    /// `areaDefault` / `projectDefault`; purple, red and amber were literals that happened to match
    /// `Theme.purpleHex` / `redHex` / `amberHex` exactly, which is the shape
    /// `CadenceFeatureDestination.defaultColorHex` was in before T-166 — green forever under a
    /// value test, and one hue change to `Theme` away from two purples. (T-246 was filed calling
    /// this four; four is the number of *literals* it replaced, not the number of accents here.)
    ///
    /// The other seven are hues `Theme` does not carry, and that is deliberate rather than an
    /// omission to be corrected. `Theme` holds **six** accents, several of them semantically
    /// spoken for — red is danger, green is done — so a twelve-swatch menu cannot be built from it
    /// without collisions. The no-hardcoded-colour rule reads "from `Theme.*`, **or** from a
    /// user-owned `colorHex`", and this array is the menu of user-owned `colorHex` values: it is
    /// that second clause, not an exception to the first. Do not "fix" these eight by adding a
    /// second amber or a second purple to `Theme`.
    static var colors: [String] { [
        areaDefault, "#6366f1", Theme.purpleHex, "#e879f9", "#f472b6", Theme.redHex,
        Theme.amberHex, "#fbbf24", projectDefault, "#14b8a6", "#06b6d4", "#6b7a99",
    ] }

    /// The swatches offered for a **kanban section**'s `colorHex` — the column editor's colour row.
    ///
    /// A fourth palette, and it lived in `macOS/Views/KanbanBoardSupport.swift` as a bare
    /// `let kanbanSectionColorOptions` until T-246 moved it here **byte-identically**. Its eight
    /// values did not change and must not be read as having been re-decided: three of them are
    /// tokens now (`TaskSectionDefaults.defaultColorHex`, `Theme.blueHex`, `Theme.greenHex`) that
    /// resolve to the same `#6b7a99` / `#4a9eff` / `#4ecb71` the literals spelled, and the
    /// remaining five are the same five hexes in the same order.
    ///
    /// It is here rather than in `Theme` for the reason `colors` gives above, and here rather than
    /// under `macOS/` because the three-way split `colors` exists to end had reopened on this very
    /// field: iOS's `iOSSectionColorPicker` offered `TagSupport.colorOptions` plus the default — a
    /// different set for the same `TaskSectionConfig.colorHex` — so a column tinted on the phone
    /// opened on the Mac wearing a hue the Mac's grid did not contain.
    /// `offeredSectionColors(for:)` is what stopped that from silently replacing it; T-261 then
    /// pointed **both** pickers here.
    ///
    /// **These eight won the convergence, and iOS's nine lost, on their contents rather than on
    /// seniority.** iOS's set was `[TaskSectionDefaults.defaultColorHex] + TagSupport.colorOptions`
    /// — a *borrowed* palette, whose own doc comment says tags are deliberately separate with a
    /// separate job, so a hue decision about tags would have silently redrawn every kanban column
    /// editor on the phone. And three of the eight it borrowed (`#ffb84d`, `#5aa2ff`, `#9e8cff`)
    /// are the pre-T-166 drifted near-copies of `Theme.amberHex` / `blueHex` / `purpleHex`:
    /// adopting them here would have re-imported into a second palette the exact literals T-166
    /// deleted from the sidebar for having drifted. This set already leads with the default every
    /// section starts on and reads three `Theme` tokens by name.
    ///
    /// The default is first and comes from `TaskSectionDefaults` so the grid cannot stop offering
    /// the colour every new section starts on.
    static var sectionColors: [String] { [
        TaskSectionDefaults.defaultColorHex, Theme.blueHex, Theme.greenHex, "#f59e0b",
        "#ef4444", "#a855f7", "#14b8a6", "#f97316",
    ] }

    /// The swatches offered for a **sidebar destination's glyph tint** — Settings → Sidebar's
    /// per-tab colour editor, stored in `CadencePreferenceKeys.sidebarTabColors`.
    ///
    /// **This is the one swatch menu that *is* `Theme`, and the exception is principled rather
    /// than convenient.** `colors` and `sectionColors` are menus of *user-owned* `colorHex` values
    /// — the second clause of the no-hardcoded-colour rule — so they may not be built out of six
    /// semantically loaded accents. A destination tint is not user-owned data: it is app chrome,
    /// and `CadenceFeatureDestination.defaultColorHex` already assigns every destination a `Theme`
    /// accent by name (T-166), which the sidebar, the iPad column and the Cmd+K palette all draw
    /// from. The menu that *edits* that value should offer the same six families the app itself
    /// assigns, and no more.
    ///
    /// Pointing this editor at `colors` was T-245: `Theme.tealHex` is not in the twelve, so Focus —
    /// the one destination whose default is teal — opened its editor showing a **thirteenth**
    /// swatch beside the palette's own `#14b8a6`, two teals for one decision, which `ColorGrid`'s
    /// comment forbids in as many words. Worse than cosmetic: `offered(_:from:)` appends the stored
    /// value, so teal was reachable only while it was already selected. One tap on any other hue
    /// and Focus's own default dropped out of the grid permanently, with no reset anywhere. Every
    /// default is offered here, so that is now unreachable.
    ///
    /// Rejected: adding `Theme.tealHex` to `colors` (a second teal in the *list* palette, and a
    /// permanent 13th swatch instead of a conditional one); swapping `#14b8a6` for `Theme.tealHex`
    /// in `colors` (re-decides the list/goal/habit menu, and `sectionColors`' `#14b8a6` beside it,
    /// over a sidebar bug); a new `Theme` accent (T-166 rejected that outright).
    ///
    /// Hue order, warm through cool, so the row reads as one lap like `colors` does. Six is the
    /// whole of `Theme`'s accent set — adding a seventh entry here means adding a seventh accent,
    /// which is the decision T-166 says to bring to the user rather than take.
    static var destinationTints: [String] { [
        Theme.redHex, Theme.amberHex, Theme.greenHex, Theme.tealHex, Theme.blueHex, Theme.purpleHex,
    ] }

    /// The palette, plus `selected` when the palette no longer contains it.
    ///
    /// Trimming or changing the palette must never silently re-colour something already saved. A
    /// stored hex that is not offered is appended, so its owner still shows a selected swatch and
    /// keeps its colour; it drops out of the grid the moment the user picks something else. This
    /// is what makes consolidating the three palettes safe — a goal sitting on one of the retired
    /// tracking-only hues keeps it.
    static func offeredColors(for selected: String) -> [String] {
        offered(selected, from: colors)
    }

    /// `sectionColors`, plus `selected` when the section palette does not contain it — the same
    /// rule `offeredColors(for:)` applies to lists, and the kanban column editor did **not** have.
    ///
    /// That grid rendered a fixed eight and marked one selected with `editorColorHex == hex`, so a
    /// section already wearing a hue the grid does not offer showed *nothing* selected and the next
    /// tap silently replaced it. Not hypothetical: iOS offers a different set for this same field
    /// (see `sectionColors`), and the old comparison was case-sensitive besides, so a stored
    /// `#F59E0B` failed to match the `#f59e0b` right beside it. This is the same hazard
    /// `CadenceIconPalette` documents for the icon grid.
    static func offeredSectionColors(for selected: String) -> [String] {
        offered(selected, from: sectionColors)
    }

    /// The keep-the-stored-value rule itself, for a grid that is handed its palette rather than
    /// naming one — `ColorGrid` takes a `palette` so the sidebar tint editor and the four list
    /// grids are one view rather than two. It was `private` while every caller went through a
    /// named accessor above; it is the same body, still the only implementation of the rule.
    static func offered(_ selected: String, from palette: [String]) -> [String] {
        let stored = selected.trimmingCharacters(in: .whitespaces)
        guard !stored.isEmpty, !palette.contains(where: { matches($0, stored) }) else {
            return palette
        }
        return palette + [stored]
    }

    /// Hex comparison is case-insensitive: stored values predate any casing convention, so
    /// `#4A9EFF` and `#4a9eff` are the same swatch and must not both render as selected.
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}


/// The SF Symbol set offered wherever a user picks an `icon` for a list, goal or habit.
///
/// This had the same three-way split the colour palette did, with a sharper edge: macOS's
/// `IconGrid` offered 44 symbols, iOS offered a 12-symbol strip that was *not* a subset — it
/// included `dollarsign.circle.fill`, which macOS could not select — and `IconGrid` had no
/// "keep a stored value that is no longer offered" rule. So an icon chosen on iPhone could open
/// on the Mac with no swatch reading as selected, and the next save would silently replace it.
///
/// One set, and the same append rule as `CadenceColorPalette`.
enum CadenceIconPalette {
    static let icons = [
        // Organization
        "square.stack.fill", "folder.fill", "tray.fill", "archivebox.fill",
        "doc.fill", "doc.text.fill", "checklist", "list.bullet.clipboard",
        // Work & study
        "briefcase.fill", "graduationcap.fill", "book.fill", "pencil",
        "chart.bar.fill", "chart.line.uptrend.xyaxis", "lightbulb.fill", "brain",
        // Home & life
        "house.fill", "heart.fill", "person.fill", "person.2.fill",
        "star.fill", "bookmark.fill", "flag.fill", "tag.fill",
        // Activities
        "dumbbell.fill", "flame.fill", "leaf.fill", "drop.fill",
        "music.note", "headphones", "gamecontroller.fill", "paintbrush.fill",
        // Travel & places
        "airplane", "car.fill", "map.fill", "globe",
        // Other
        "bolt.fill", "camera.fill", "cart.fill", "stethoscope",
        "trophy.fill", "medal.fill", "crown.fill", "building.2.fill",
    ]

    /// The palette, plus `selected` when the palette no longer contains it — so a stored symbol
    /// is never silently swapped for a different one just because the grid changed.
    static func offeredIcons(for selected: String) -> [String] {
        let stored = selected.trimmingCharacters(in: .whitespaces)
        guard !stored.isEmpty, !icons.contains(stored) else { return icons }
        return icons + [stored]
    }
}
