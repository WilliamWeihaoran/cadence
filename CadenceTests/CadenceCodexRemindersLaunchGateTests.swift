import Foundation
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexRemindersLaunchGateTests {
    @Test func everyDisarmedReminderLaunchRefusesFetchAndCompletionEvenPastAuthorization() async {
        for environment in [
            ["CADENCE_LOCAL_STORE_ONLY": "1"],
            ["CADENCE_UI_TEST_MODE": "1"],
            ["CADENCE_UI_TEST_STORE_ID": "codex-reminders-launch-gate"]
        ] {
            var fetches = 0
            let manager = RemindersManager(
                fetchIncompleteReminders: { _ in fetches += 1 },
                startsAuthorized: true,
                launchEnvironment: environment
            )
            #expect(manager.isAuthorized)
            manager.reload()
            #expect(fetches == 0)
            #expect(manager.reminders.isEmpty)
            #expect(!manager.isLoading)
            #expect(manager.completeReminder(id: "codex-no-native-reminder") == .notAuthorized)
            #expect(!manager.isDenied)
            #expect(!manager.isRestricted)
            #expect(!manager.isObservingStoreChanges)
            let granted = await manager.requestAccess()
            #expect(!granted)
            #expect(!manager.deniedInThisSession)
            #expect(!manager.isAuthorized)
            #expect(manager.connectionState == .notDetermined)
            manager.refreshAuthorizationState()
            #expect(!manager.isAuthorized)
            #expect(!manager.isObservingStoreChanges)
            #expect(manager.connectionState == .notDetermined)
            #expect(fetches == 0)
        }
    }

    @Test func anArmedInjectedReminderFetcherStillPublishesNormally() {
        var fetches = 0
        let item = AppleReminderItem(id: "fixture", title: "Fixture", notes: "", listTitle: "Fixture", dueDate: nil, priority: 0, allowsCompletion: false)
        let manager = RemindersManager(
            fetchIncompleteReminders: { publish in
                fetches += 1
                publish([item])
            },
            startsAuthorized: true,
            launchEnvironment: [:]
        )
        manager.reload()
        #expect(fetches == 1)
        #expect(manager.reminders.map(\.id) == ["fixture"])
        #expect(!manager.isLoading)
    }

    @Test func reminderNativeDoorsAreGatedBeforeAnyStoreOrTCCWork() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let code = try read("Cadence/Services/CadenceRemindersManager.swift")
        #expect(code.contains("final class RemindersManager"))
        #expect(code.contains("private let isEventKitDisarmed: Bool"))
        #expect(code.contains("self.isEventKitDisarmed = CadenceEventKitLaunchGate.isDisarmedForThisProcess"))
        for name in ["refreshAuthorizationState", "requestAccess"] {
            let body = try #require(CadenceSourceScan.functionBody(named: name, in: code))
            let gate = try #require(body.range(of: "guard !isEventKitDisarmed"))
            let status = try #require(body.range(of: "EKEventStore.authorizationStatus"))
            #expect(gate.lowerBound < status.lowerBound)
        }
        for name in ["isDenied", "isRestricted"] {
            let body = try #require(CadenceSourceScan.declarationBody("var \(name): Bool", in: code))
            let gate = try #require(body.range(of: "guard !isEventKitDisarmed"))
            let status = try #require(body.range(of: "EKEventStore.authorizationStatus"))
            #expect(gate.lowerBound < status.lowerBound)
        }
        let refresh = try #require(CadenceSourceScan.functionBody(named: "refreshAuthorizationState", in: code))
        #expect(refresh.contains("if isAuthorized, !isEventKitDisarmed"))
        let reload = try #require(CadenceSourceScan.functionBody(named: "reload", in: code))
        let reloadGate = try #require(reload.range(of: "guard isAuthorized, !isEventKitDisarmed"))
        let fetch = try #require(reload.range(of: "fetchIncompleteReminders {"))
        #expect(reloadGate.lowerBound < fetch.lowerBound)
        let observer = try #require(CadenceSourceScan.functionBody(named: "startObserving", in: code))
        let observerGate = try #require(observer.range(of: "guard !isEventKitDisarmed, storeObserver == nil"))
        let registration = try #require(observer.range(of: "NotificationCenter.default.addObserver"))
        #expect(observerGate.lowerBound < registration.lowerBound)
        #expect(observer.contains("guard let self, !self.isEventKitDisarmed else { return }"))
        #expect(observer.contains("self.reload()"))
        let completion = try #require(CadenceSourceScan.functionBody(named: "completeReminder", in: code))
        let writeGate = try #require(completion.range(of: "guard !isEventKitDisarmed else { return .notAuthorized }"))
        let lookup = try #require(completion.range(of: "store.calendarItem(withIdentifier:"))
        let edit = try #require(completion.range(of: "reminder.isCompleted = true"))
        let save = try #require(completion.range(of: "try store.save(reminder, commit: true)"))
        #expect(writeGate.lowerBound < lookup.lowerBound)
        #expect(writeGate.lowerBound < edit.lowerBound)
        #expect(writeGate.lowerBound < save.lowerBound)
    }
}
