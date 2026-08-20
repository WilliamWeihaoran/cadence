import SwiftUI

enum CadenceSettingsCategoryKind: String, CaseIterable, Identifiable {
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
    case coverage
    case account
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigation: return "Navigation"
        case .sidebar: return "Sidebar"
        case .sync: return "Account & Sync"
        case .dataSafety: return "Data Safety"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .notifications: return "Notifications"
        case .contexts: return "Contexts"
        case .lists: return "Lists"
        case .tags: return "Tags"
        case .templates: return "Templates"
        case .ai: return "AI"
        case .coverage: return "Coverage"
        case .account: return "Account"
        case .about: return "About"
        }
    }


    var icon: String {
        switch self {
        case .navigation: return "rectangle.stack.fill"
        case .sidebar: return "sidebar.left"
        case .sync: return "icloud.fill"
        case .dataSafety: return "externaldrive.fill.badge.timemachine"
        case .calendar: return "calendar"
        // Same glyph the Inbox already uses for its Apple Reminders section, so the
        // two surfaces read as the same integration.
        case .reminders: return "checklist"
        case .notifications: return "bell.fill"
        case .contexts: return "square.stack.3d.up.fill"
        case .lists: return CadenceFeatureDestination.lists.systemImage
        case .tags: return "tag.fill"
        case .templates: return "doc.text.fill"
        case .ai: return "sparkles"
        case .coverage: return "iphone.and.arrow.forward"
        case .account: return "person.crop.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
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
        case .coverage:
            return Theme.purple
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
    /// `sidebar` configures a column iPhone does not have and iPad does not let you rearrange;
    /// `account` is the entitlement-gated Sign in with Apple surface, macOS-only today. Stating
    /// the exclusions positively is what makes "mobile is missing a category" a test failure
    /// rather than something you find by opening the app: `reminders` sat outside this list for
    /// months on the theory that EventKit reminders were a desktop concern, and nothing said
    /// otherwise because absence looks exactly like a deliberate omission.
    static let desktopOnly: Set<CadenceSettingsCategoryKind> = [.sidebar, .account]

    /// Three groups, not one flat run of rows: how the app behaves, what you organise with, and
    /// what it talks to. macOS's own settings shell keeps its flat category list — this is the mobile
    /// shape, where the list *is* the top level rather than a rail beside the content.
    static let groups: [CadenceSettingsCategoryGroup] = [
        CadenceSettingsCategoryGroup(
            title: "App",
            kinds: [.navigation, .notifications, .ai]
        ),
        CadenceSettingsCategoryGroup(
            title: "Content",
            kinds: [.contexts, .lists, .tags, .templates]
        ),
        CadenceSettingsCategoryGroup(
            title: "System",
            // `.reminders` sits beside `.calendar` because they are the same kind of thing —
            // a separately-authorized EventKit store the app reads. It was absent for a while
            // on the theory that reminders were a macOS concern; EventKit reminders are fully
            // available on iOS, and `NSRemindersFullAccessUsageDescription` already ships in
            // the shared `Info.plist`, so the omission was the bug, not the boundary.
            kinds: [.calendar, .reminders, .sync, .dataSafety, .coverage, .about]
        )
    ]
}
