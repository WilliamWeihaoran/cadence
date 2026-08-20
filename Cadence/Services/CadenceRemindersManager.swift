// EventKit reminders, shared by both platforms. This lived in `macOS/Services/` inside an
// `#if os(macOS)` guard, which read as a platform constraint and was only an accident of
// where it was written: nothing here touches AppKit, and `NSRemindersFullAccessUsageDescription`
// ships on iOS as well as macOS. iOS Settings > Reminders needs it.
//
// The *file* carries the `Cadence` prefix and the *type* does not — the same mismatch
// `Shared/CadenceCalendarVisibilityPreferences.swift` has, and for the same reason: the old
// path keeps a tombstone comment under its original name, and two `RemindersManager.swift`
// files in one target collide on `.stringsdata`. Grep for the declaration, not the filename.
import EventKit
import Foundation
import Observation

struct AppleReminderItem: Identifiable {
    let id: String
    let title: String
    let notes: String
    let listTitle: String
    let dueDate: Date?
    let priority: Int
    let allowsCompletion: Bool
}

@Observable
final class RemindersManager {
    static let shared = RemindersManager()

    private(set) var reminders: [AppleReminderItem] = []
    private(set) var isAuthorized = false
    private(set) var isLoading = false

    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .denied || status == .restricted
    }

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    private init() {
        refreshAuthorizationState()
    }

    /// `.authorized` is the pre-macOS-14 spelling of `.fullAccess` — the same enum case with
    /// the same raw value, not a second state — so matching `.fullAccess` alone still accepts
    /// every status that used to pass here. This also matches `CalendarManager`.
    func refreshAuthorizationState() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        isAuthorized = status == .fullAccess

        if isAuthorized {
            startObserving()
            reload()
        } else {
            stopObserving()
            reminders = []
            isLoading = false
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess {
            refreshAuthorizationState()
            return true
        }
        guard status == .notDetermined else {
            refreshAuthorizationState()
            return false
        }

        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else {
            refreshAuthorizationState()
            return false
        }

        // Trust the request's own answer instead of re-reading `authorizationStatus`.
        // That class method is cached per process and, on iOS, still reports `.notDetermined`
        // for the rest of the launch after the user taps Allow — measured on the iOS 26
        // simulator, where the Settings card kept offering "Allow Access" until the app was
        // relaunched even though TCC had already recorded the grant. Re-reading it here made
        // connecting from iOS Settings look like it had failed. `granted == true` *is* the
        // authorization; nothing else needs to confirm it.
        //
        // `reset()` because this store was created before the grant and would otherwise keep
        // serving its pre-authorization view of the database.
        store.reset()
        isAuthorized = true
        startObserving()
        reload()
        return true
    }

    func reload() {
        guard isAuthorized else {
            reminders = []
            isLoading = false
            return
        }

        isLoading = true
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? []).map(Self.makeItem).sorted(by: Self.sortItems)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reminders = items
                self.isLoading = false
            }
        }
    }

    func completeReminder(id: String) {
        guard isAuthorized,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder,
              reminder.calendar.allowsContentModifications else { return }

        reminder.isCompleted = true
        reminder.completionDate = Date()
        do {
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == id }
        } catch {
            print("RemindersManager: failed to complete reminder: \(error)")
            reload()
        }
    }

    private func startObserving() {
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    private func stopObserving() {
        guard let storeObserver else { return }
        NotificationCenter.default.removeObserver(storeObserver)
        self.storeObserver = nil
    }

    /// `nonisolated` because `fetchReminders` already calls this from EventKit's background
    /// completion queue — the annotation states where the work actually happens rather than
    /// moving it. Both helpers are pure functions over their arguments.
    nonisolated private static func makeItem(from reminder: EKReminder) -> AppleReminderItem {
        AppleReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            notes: reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            listTitle: reminder.calendar.title,
            dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
            priority: reminder.priority,
            allowsCompletion: reminder.calendar.allowsContentModifications
        )
    }

    nonisolated private static func sortItems(_ lhs: AppleReminderItem, _ rhs: AppleReminderItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
