#if os(macOS)
import AppKit
import Carbon
import os

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()
    private let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "GlobalHotKey")

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x4344544b // "CDTK"
    private let hotKeyID: UInt32 = 1

    private init() {}

    /// [[T-18294]]. The hosted `CadenceTests` app runs `CadenceAppDelegate`'s launch, so without
    /// this a test run took the owner's system-wide ⌃Space from their own Cadence and could open
    /// `QuickTaskPanelController.shared` inside the test process. Only the XCTest host is skipped:
    /// a `CADENCE_UI_TEST_MODE=1` launch (`run-macos-app.sh`, `CadenceUITests`) keeps the key,
    /// because those launches exercise the real capture path. Pure over its input so the decision
    /// is tested with literal environments rather than by registering a real hotkey.
    static func shouldRegister(in environment: [String: String]) -> Bool {
        !CadenceUITestStoreDirectory.isXCTestHost(in: environment)
    }

    /// Whether this process currently holds the Carbon registration.
    var isRegistered: Bool { hotKeyRef != nil }

    func registerIfNeeded() {
        guard Self.shouldRegister(in: ProcessInfo.processInfo.environment) else { return }
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKey(eventRef)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            logger.error("Failed to install global hotkey handler: \(installStatus)")
            eventHandlerRef = nil
            publish(.failed(installStatus))
            return
        }

        let identifier = EventHotKeyID(signature: signature, id: hotKeyID)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey),
            identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            logger.error("Failed to register Control-Space global hotkey: \(registerStatus)")
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            hotKeyRef = nil
            publish(.failed(registerStatus))
            return
        }

        logger.debug("Registered Control-Space global hotkey")
        publish(.registered)
    }

    /// T-5883. Both refusals above used to end at `logger.error` and nothing else, which is a
    /// diagnostic for whoever is reading the log — nobody, in a shipped app. Carbon refuses
    /// ⌃Space whenever something else already owns it, and on a Mac with two input sources macOS
    /// itself does; the user then had a quick-capture key that silently did nothing. Settings
    /// reads this.
    private func publish(_ registration: QuickCaptureHotKeyRegistration) {
        DispatchQueue.main.async {
            QuickCaptureHotKeyStatus.shared.registration = registration
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        // Back to "not asked", not to a failure: nothing refused anything here.
        publish(.notAttempted)
    }

    private func handleHotKey(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else { return noErr }

        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )

        guard status == noErr,
              identifier.signature == signature,
              identifier.id == hotKeyID else {
            return noErr
        }

        DispatchQueue.main.async {
            self.logger.debug("Global hotkey fired")
            self.handleTaskPanelShortcut()
        }

        return noErr
    }

    /// What one ⌃Space press does.
    nonisolated enum TaskPanelShortcutAction: Equatable {
        /// The floating quick panel is up: the key closes it.
        case closeQuickTaskPanel
        /// The in-app New Task panel is up: the key closes it.
        case dismissTaskCreation
        /// Cmd+K's own New Task command, through the menu route File ▸ New Task uses.
        case routeNewTask
        /// The app is not in front: the floating quick panel.
        case showQuickTaskPanel
    }

    /// **[[T-18796]] — the hotkey's in-app arm goes through the menu route, as File ▸ New Task
    /// does.** It used to call the manager's `present()` direct -- the call
    /// [[T-17170]] moved File ▸ New Task off -- so ⌃Space opened New Task under a standing delete
    /// confirmation or hovered-task date picker, and the Return that committed the typed title
    /// confirmed the delete (or wrote the date) instead; with Cmd+K open it left the palette
    /// standing over the panel. `.routeNewTask` reaches `RootCommandHandler.handleMenuCommand`,
    /// whose `RootViewMenuGate` stands it down behind a modal and which dismisses Cmd+K. The
    /// panel arm needs no gate here: the root monitor passes a key addressed to the panel before
    /// the modal step (`RootModalKeyDisposition.passToQuickTaskPanel`).
    ///
    /// Pure over its inputs so the table is tested without a hotkey, a panel or an active app.
    nonisolated static func taskPanelShortcutAction(
        isQuickTaskPanelVisible: Bool,
        isAppActive: Bool,
        isTaskCreationPresented: Bool
    ) -> TaskPanelShortcutAction {
        if isQuickTaskPanelVisible { return .closeQuickTaskPanel }
        guard isAppActive else { return .showQuickTaskPanel }
        return isTaskCreationPresented ? .dismissTaskCreation : .routeNewTask
    }

    private func handleTaskPanelShortcut() {
        let action = Self.taskPanelShortcutAction(
            isQuickTaskPanelVisible: QuickTaskPanelController.shared.isVisible,
            isAppActive: NSApp.isActive,
            isTaskCreationPresented: TaskCreationManager.shared.isPresented
        )
        switch action {
        case .closeQuickTaskPanel:
            logger.debug("Global hotkey toggled quick panel closed")
            QuickTaskPanelController.shared.close()
        case .dismissTaskCreation:
            logger.debug("Global hotkey toggled in-app task panel closed")
            TaskCreationManager.shared.dismiss()
        case .routeNewTask:
            logger.debug("Global hotkey routing New Task through the menu route")
            CadenceMenuCommandRoute.shared.send(CadenceNewItemMenu.newTaskCommand)
        case .showQuickTaskPanel:
            QuickTaskPanelController.shared.show()
        }
    }
}
#endif
