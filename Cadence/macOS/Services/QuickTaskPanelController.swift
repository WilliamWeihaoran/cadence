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
    private var sizeObserver: NSKeyValueObservation?

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

        // Always create a fresh hosting controller so @State resets on each open
        sizeObserver?.invalidate()
        sizeObserver = nil
        let hc = NSHostingController(rootView: AnyView(content))
        panel.contentViewController = hc
        self.hostingController = hc
        panel.setContentSize(NSSize(width: 680, height: 320))

        // Auto-resize panel to fit SwiftUI content (e.g. when subtasks are added)
        sizeObserver = hc.observe(\.preferredContentSize, options: [.new]) { [weak self] _, change in
            guard let self, let panel = self.panel,
                  let size = change.newValue, size.height > 50, size.width > 0 else { return }
            DispatchQueue.main.async {
                var frame = panel.frame
                let delta = size.height - frame.size.height
                frame.size.height = size.height
                frame.origin.y -= delta
                panel.setFrame(frame, display: true, animate: false)
            }
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
        sizeObserver?.invalidate()
        sizeObserver = nil
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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
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
        // Use design dimensions directly — panel.frame.size can be zero on the
        // first show before SwiftUI has completed its initial layout pass.
        let w: CGFloat = 680
        let h: CGFloat = max(panel.frame.height > 10 ? panel.frame.height : 320, 280)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main

        guard let screen else { panel.center(); return }

        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - w / 2,
            y: visibleFrame.midY - h / 2
        ))
    }
}

private final class QuickTaskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
#endif
