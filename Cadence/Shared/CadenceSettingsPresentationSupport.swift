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
