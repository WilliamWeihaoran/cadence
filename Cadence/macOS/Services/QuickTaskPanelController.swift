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
    // Ignore clicks that arrived before the panel was shown (e.g. the click
    // that focused the previous app is still in-flight when the hotkey fires).
    private var acceptingDismissal = false

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

        // Reset dismissal gate — clicks that predate the panel must be ignored.
        acceptingDismissal = false

        // orderFrontRegardless places the panel on the current Space first
        // (via .canJoinAllSpaces), before we activate the app.
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        logger.notice("Ordering quick task panel front")

        startMonitoringClickOutside()

        // Open the gate after one runloop pass so any pre-existing mouse events
        // in the queue are consumed without triggering a dismiss.
        DispatchQueue.main.async { [weak self] in
            self?.acceptingDismissal = true
        }
    }

    func close() {
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
