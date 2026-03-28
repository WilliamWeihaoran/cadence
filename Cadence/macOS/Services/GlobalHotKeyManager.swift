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

    func registerIfNeeded() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
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

        let identifier = EventHotKeyID(signature: signature, id: hotKeyID)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey),
            identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
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
            self.logger.notice("Global hotkey fired")
            if QuickTaskPanelController.shared.isVisible {
                self.logger.notice("Global hotkey toggled quick panel closed")
                QuickTaskPanelController.shared.close()
            } else {
                QuickTaskPanelController.shared.show()
            }
        }

        return noErr
    }
}
#endif
