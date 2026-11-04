import SwiftUI

enum CadenceSettingsCategoryKind: String, CaseIterable, Identifiable {
    case appearance
    case navigation
    case sidebar
    case sync
    case dataSafety
    case calendar
    case reminders
    case notifications
    case contexts
    case lists
    case tags
    case templates
    case ai
    case account
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .navigation: return "Navigation"
        case .sidebar: return "Sidebar"
        // T-580: "Account & Sync" for a category that is one iCloud status card on both
        // platforms, and — on macOS, where `.account` also exists — a second row reading
        // "Account" two groups below it. Neither screen shows an account here: the Sign in with
        // Apple card is the `.account` pane, on both platforms since [[T-8736]]. "iCloud Sync" is what
        // both actually draw, and what iOS's own card eyebrow has always said.
        case .sync: return "iCloud Sync"
        case .dataSafety: return "Data Safety"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .notifications: return "Notifications"
        case .contexts: return "Contexts"
        case .lists: return "Lists"
        case .tags: return "Tags"
        case .templates: return "Templates"
        case .ai: return "AI"
        case .account: return "Account"
        case .about: return "About"
        }
    }


    var icon: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .navigation: return "rectangle.stack.fill"
        case .sidebar: return "sidebar.left"
        case .sync: return "icloud.fill"
        case .dataSafety: return "externaldrive.fill.badge.timemachine"
        case .calendar: return "calendar"
        // Same glyph the Inbox already uses for its Apple Reminders section, so the
        // two surfaces read as the same integration.
        case .reminders: return "checklist"
        case .notifications: return "bell.fill"
        case .contexts: return CadenceListKindIcon.context
        case .lists: return CadenceFeatureDestination.lists.systemImage
        case .tags: return "tag.fill"
        case .templates: return "doc.text.fill"
        case .ai: return "sparkles"
        case .account: return "person.crop.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appearance:
            // Purple, and not the accent it is *about*: the rail glyph for this category has to
            // stay legible while the user is looking at every palette in turn, so it reads a
            // token like every other row rather than previewing the selection.
            return Theme.purple
        case .navigation:
            return Theme.green
        case .sidebar:
            return Theme.amber
        case .sync:
            return Theme.blue
        case .dataSafety:
            return Theme.amber
        case .calendar:
            return Theme.purple
        case .reminders:
            // Matches the purple accent the Inbox already gives Apple Reminders.
            return Theme.purple
        case .notifications:
            return Theme.amber
        case .contexts:
            return Theme.red
        case .lists:
            return Theme.amber
        case .tags:
            return Theme.green
        case .templates:
            return Theme.blue
        case .ai:
            return Theme.blue
        case .account:
            return Theme.green
        case .about:
            return Theme.amber
        }
    }
}

/// One quiet eyebrow and the categories filed under it.
struct CadenceSettingsCategoryGroup: Identifiable, Hashable {
    let title: String
    let kinds: [CadenceSettingsCategoryKind]

    var id: String { title }
}

/// One grouping vocabulary for the desktop rail, iPad rail and phone list.
enum CadenceSettingsLayout {
    static let groups: [CadenceSettingsCategoryGroup] = [
        CadenceSettingsCategoryGroup(title: "Interface", kinds: [.appearance, .navigation, .sidebar]),
        CadenceSettingsCategoryGroup(title: "Organization", kinds: [.contexts, .lists, .tags, .templates]),
        CadenceSettingsCategoryGroup(title: "System", kinds: [.calendar, .reminders, .sync, .notifications, .ai]),
        CadenceSettingsCategoryGroup(title: "Account & Safety", kinds: [.account, .dataSafety]),
        CadenceSettingsCategoryGroup(title: "App", kinds: [.about])
    ]
}

/// The mobile settings surface's shape: which categories it offers, and how they cluster.
///
/// Both mobile presentations read from here — the iPad rail and the iPhone category list — so the
/// two cannot drift into different groupings of the same destinations. It lives in `Shared` rather
/// than in `Cadence/iOS/` because everything under that tree is inside `#if os(iOS)` and therefore
/// invisible to the macOS-built test target; the "every category is filed exactly once" invariant
/// is worth a test.
enum CadenceMobileSettingsLayout {
    /// Every category mobile offers, in list order.
    static let categories: [CadenceSettingsCategoryKind] = groups.flatMap(\.kinds)

    /// The categories mobile deliberately does not offer, and the *only* ones it may omit.
    ///
    /// `sidebar` has no mobile category of its own: iPhone and iPad edit the same synced layout
    /// from a "Sidebar Rows" group inside Navigation ([[T-1274]], `iOSSidebarLayoutSettingsSection`),
    /// with Move Up / Move Down, so iPad DOES let you rearrange it. Whether the placement should match
    /// the Mac's own Sidebar category is an open owner call ([[T-11200]]), not a hardware fact.
    /// `account` sat here too, described as "the entitlement-gated Sign in with Apple surface,
    /// macOS-only today" — a current state rather than a constraint: `Cadence-iOS.entitlements`
    /// already declared `com.apple.developer.applesignin`, and the only thing missing was
    /// `AppleAccountManager`'s `#if os(macOS)`, lifted in [[T-8736]]. Stating the exclusions
    /// positively is what makes "mobile is missing a category" a test failure
    /// rather than something you find by opening the app: `reminders` sat outside this list for
    /// months on the theory that EventKit reminders were a desktop concern, and nothing said
    /// otherwise because absence looks exactly like a deliberate omission.
    static let desktopOnly: Set<CadenceSettingsCategoryKind> = [.sidebar]

    /// Both mobile presentations filter the canonical groups, retaining their names and order.
    static let groups: [CadenceSettingsCategoryGroup] = CadenceSettingsLayout.groups.compactMap { group in
        let kinds = group.kinds.filter { !desktopOnly.contains($0) }
        return kinds.isEmpty ? nil : CadenceSettingsCategoryGroup(title: group.title, kinds: kinds)
    }

}

/// Which settings category you are in, stored once, read two ways.
///
/// Mobile draws Settings as a rail beside the content at regular width and as a list you drill into
/// at compact width. Those were two `@State` properties on one view — `selectedCategory` for the
/// rail, `drilledCategory` for the phone — with nothing between them, and the view itself sits in a
/// different place in each shell, so a size-class change tore it down and reset both. Widening out
/// of Templates landed on Navigation and narrowing out of Calendar dropped back to the category
/// list (T-335).
///
/// The rule is the one Month's detail toggle already follows (`CadenceCalendarMonthLayout`): **the
/// category is user state, compact-versus-regular is presentation.** So there is one stored value
/// and two readings of it. The empty string is the phone's category list — a real place the user
/// can be, and the one state regular width has no way to show, which is why widening out of it
/// falls back to the default rather than to nothing.
///
/// Stored rather than held, because a value held in a view that the size class destroys is the bug.
/// It is `Shared/` for the usual reason: `Cadence/iOS/` is invisible to the macOS test target.
///
/// Not `nonisolated`, unlike most of `Shared/`: it reads `CadenceMobileSettingsLayout.categories`,
/// and this project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so that property is
/// main-actor isolated. The rest of this file is main-actor for the same reason.
enum CadenceMobileSettingsNavigation {
    /// Where the rail points before the user has chosen anything, matching macOS's own settings
    /// shell.
    static let defaultCategory: CadenceSettingsCategoryKind = .navigation

    /// The stored spelling of "the phone's category list". Not a sentinel word: an unset
    /// `@AppStorage` string is already `""`, so the cold-launch state and the popped-back-to-the-list
    /// state are the same value rather than two that have to agree.
    static let categoryListRawValue = ""

    /// What the iPad rail points at. Never `nil` — the rail is beside the content, so there is no
    /// "no category" state for it to be in, and the list state widens into the default.
    static func railCategory(storedRawValue: String) -> CadenceSettingsCategoryKind {
        guard let kind = category(storedRawValue: storedRawValue) else { return defaultCategory }
        return kind
    }

    /// What the phone has drilled into, or `nil` for the category list.
    static func drilledCategory(storedRawValue: String) -> CadenceSettingsCategoryKind? {
        category(storedRawValue: storedRawValue)
    }

    /// The value to store for a category, or for the list.
    static func storedRawValue(for category: CadenceSettingsCategoryKind?) -> String {
        category?.rawValue ?? categoryListRawValue
    }

    /// A stored category mobile actually offers, or `nil`.
    ///
    /// Filtered against `CadenceMobileSettingsLayout.categories`, not merely parsed: `sidebar` is a
    /// real `CadenceSettingsCategoryKind` case with no mobile category (`account` has had one since
    /// [[T-8736]]), so a raw value
    /// arriving from anywhere else — a synced default, a future desktop-only addition — must not
    /// select a category the rail cannot draw and the detail cannot render.
    private static func category(storedRawValue: String) -> CadenceSettingsCategoryKind? {
        guard
            let kind = CadenceSettingsCategoryKind(rawValue: storedRawValue),
            CadenceMobileSettingsLayout.categories.contains(kind)
        else { return nil }
        return kind
    }
}

/// Settings reflows labels and controls through the existing typography boundary.
nonisolated enum CadenceSettingsTypographyLayout {
    static func stacks(at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> Bool {
        scaling == .enabled && CadenceTypeScale.isAccessibilitySize(size)
    }

    static func usesRail(isRegularWidth: Bool, at size: DynamicTypeSize) -> Bool {
        isRegularWidth && !CadenceTypeScale.isAccessibilitySize(size)
    }

    static func glyphFrame(_ base: CGFloat, glyph: CGFloat, role: CadenceTypographyRole = .controlLabel,
                           at size: DynamicTypeSize, scaling: CadenceTypographyScaling) -> CGFloat {
        base + CadenceTypeScale.growth(role, base: glyph, at: size, scaling: scaling) * CadenceTypeScale.lineHeightRatio
    }
}
