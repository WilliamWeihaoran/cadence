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

        // Remember who had focus so we can restore them when the panel closes
        previousApp = NSWorkspace.shared.frontmostApplication

        // Place the panel on the current Space FIRST (via .canJoinAllSpaces)
        panel.orderFrontRegardless()

        // Activate WITHOUT .activateAllWindows — that flag is what causes macOS
        // to switch to Cadence's Space. Using only .activateIgnoringOtherApps
        // makes the app active (so it can receive keyboard events) without
        // forcing all Cadence windows to the front.
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        panel.makeKeyAndOrderFront(nil)
        logger.notice("Ordering quick task panel front")

        startMonitoringClickOutside()
    }

    func close() {
        logger.notice("Closing quick task panel")
        stopMonitoringClickOutside()
        panel?.orderOut(nil)
        // Restore focus to whatever app the user was in before the panel appeared
        previousApp?.activate(options: [.activateIgnoringOtherApps])
        previousApp = nil
    }

    // MARK: - Click-outside dismissal

    private func startMonitoringClickOutside() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
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
        // .canJoinAllSpaces: panel is visible on every Space simultaneously
        // .fullScreenAuxiliary: remains visible when target app goes full-screen
        // .ignoresCycle: excluded from Cmd+` window cycling
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Must be false — true causes the panel to hide during space-switch
        // deactivation events, which makes the panel vanish before the user sees it
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
