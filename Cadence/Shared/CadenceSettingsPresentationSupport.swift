import SwiftUI

enum CadenceSettingsCategoryKind: String, CaseIterable, Identifiable {
    case navigation
    case sidebar
    case sync
    case dataSafety
    case calendar
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

    var subtitle: String {
        switch self {
        case .navigation:
            return "Layouts and defaults."
        case .sidebar:
            return "Tabs, order, and visibility."
        case .sync:
            return "iCloud and account."
        case .dataSafety:
            return "Backups, counts, and storage."
        case .calendar:
            return "Access and linked calendars."
        case .notifications:
            return "Task and habit reminders."
        case .contexts:
            return "Active and archived contexts."
        case .lists:
            return "Areas and projects."
        case .tags:
            return "Task and note labels."
        case .templates:
            return "Reusable note scaffolds."
        case .ai:
            return "OpenAI key and model."
        case .coverage:
            return "Mobile feature surface."
        case .account:
            return "Apple identity status."
        case .about:
            return "Version and bundle."
        }
    }

    var detailDescription: String {
        switch self {
        case .navigation:
            return "Choose default layouts and opening behavior for task, calendar, list, and note workflows."
        case .sidebar:
            return "Arrange the main sidebar tabs and decide which ones stay visible."
        case .sync:
            return "Check whether this device can use iCloud and CloudKit for Cadence sync."
        case .dataSafety:
            return "Review workspace counts, local storage, backups, and restore points."
        case .calendar:
            return "Connect Apple Calendar and choose which calendar each area or project uses."
        case .notifications:
            return "Enable local reminders for scheduled task starts, due dates, and daily habit check-ins."
        case .contexts:
            return "Manage the top-level groups that organize areas, projects, tasks, milestones, and habits."
        case .lists:
            return "Review completed and archived areas or projects and return them to active work."
        case .tags:
            return "Create, edit, archive, and restore the tags used by tasks and notes."
        case .templates:
            return "Edit the templates available from the note sidebar. Defaults stay recoverable."
        case .ai:
            return "Store your OpenAI API key in Keychain and choose the model for AI actions."
        case .coverage:
            return "Track which companion app workflows are currently implemented on iPhone and iPad."
        case .account:
            return "Use Sign in with Apple for your Cadence identity. The app still works when signed out."
        case .about:
            return "Review the installed app version and bundle details for TestFlight diagnostics."
        }
    }

    var icon: String {
        switch self {
        case .navigation: return "rectangle.stack.fill"
        case .sidebar: return "sidebar.left"
        case .sync: return "icloud.fill"
        case .dataSafety: return "externaldrive.fill.badge.timemachine"
        case .calendar: return "calendar"
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
