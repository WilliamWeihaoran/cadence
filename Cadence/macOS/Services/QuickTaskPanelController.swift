#if os(macOS)
import SwiftUI
import AppKit
import SwiftData
import os

final class QuickTaskPanelController: NSObject {
    static let shared = QuickTaskPanelController()
    private let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "QuickTaskPanel")

    private var panel: QuickTaskPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var clickOutsideMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var acceptingDismissal = false
    private var activationObserver: NSObjectProtocol?

    private override init() {}

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show(seed: TaskCreationSeed = TaskCreationSeed()) {
        let panel = ensurePanel()
        logger.notice("Preparing quick task panel")

        let content = CreateTaskSheet(
            seed: seed,
            dismissAction: { [weak self] in self?.close() }
        )
        .modelContainer(PersistenceController.shared.container)
        .environment(TaskCreationManager.shared)
        .preferredColorScheme(.dark)

        if let hostingController {
            hostingController.rootView = AnyView(content)
        } else {
            let hc = NSHostingController(rootView: AnyView(content))
            panel.contentViewController = hc
            self.hostingController = hc
        }

        positionPanel(panel)
        previousApp = NSWorkspace.shared.frontmostApplication
        acceptingDismissal = false

        if NSApp.isActive {
            // Cadence is already frontmost — bring panel up immediately.
            bringPanelFront(panel)
        } else {
            // Cadence is in the background (possibly a different Space).
            // Activate first; show the panel only after activation settles
            // so makeKeyAndOrderFront lands in the correct Space context.
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak panel] _ in
                guard let self, let panel else { return }
                NotificationCenter.default.removeObserver(self.activationObserver as Any)
                self.activationObserver = nil
                self.bringPanelFront(panel)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func bringPanelFront(_ panel: QuickTaskPanel) {
        logger.notice("Ordering quick task panel front")
        panel.makeKeyAndOrderFront(nil)
        startMonitoringClickOutside()
        // Defer dismissal gate by one runloop pass so any click events
        // already in the queue (e.g. the click that focused the previous app)
        // are consumed before we start listening for click-outside dismissals.
        DispatchQueue.main.async { [weak self] in
            self?.acceptingDismissal = true
        }
    }

    func close() {
        if let obs = activationObserver {
            NotificationCenter.default.removeObserver(obs)
            activationObserver = nil
        }
        guard panel?.isVisible == true else { return }
        logger.notice("Closing quick task panel")
        acceptingDismissal = false
        stopMonitoringClickOutside()
        panel?.orderOut(nil)
        previousApp?.activate(options: [.activateIgnoringOtherApps])
        previousApp = nil
    }

    // MARK: - Click-outside dismissal

    private func startMonitoringClickOutside() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard self?.acceptingDismissal == true else { return }
            self?.close()
        }
    }

    private func stopMonitoringClickOutside() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Panel setup

    private func ensurePanel() -> QuickTaskPanel {
        if let panel { return panel }

        let panel = QuickTaskPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Must be false — hidesOnDeactivate causes the panel to vanish during
        // space-switch deactivation events before the user sees it.
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.animationBehavior = .utilityWindow
        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        let panelSize = panel.frame.size
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main

        guard let screen else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (panelSize.width / 2),
            y: visibleFrame.midY - (panelSize.height / 2)
        )
        panel.setFrameOrigin(origin)
    }
}

private final class QuickTaskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
#endif
