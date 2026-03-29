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
    private var acceptingDismissal = false

    private override init() {}

    var isVisible: Bool { panel?.isVisible == true }

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
        acceptingDismissal = false

        // .nonactivatingPanel means makeKeyAndOrderFront makes the panel key
        // (so it receives keyboard events) WITHOUT activating the app.
        // No NSApp.activate = no space switch = panel appears right where the
        // user is, over whatever app they were using.
        panel.makeKeyAndOrderFront(nil)
        logger.notice("Ordering quick task panel front")

        startMonitoringClickOutside()
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
            // .nonactivatingPanel: the panel can become key (receive keyboard
            // input) without activating the application or switching spaces.
            styleMask: [.titled, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
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

        guard let screen else { panel.center(); return }

        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2
        ))
    }
}

private final class QuickTaskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
#endif
