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
        logger.debug("Preparing quick task panel")

        let content = CreateTaskPanelSurface(
            seed: seed,
            dismissAction: { [weak self] in self?.close() },
            successAction: { [weak self] in self?.showCaptureSuccessThenClose() }
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
        panel.setContentSize(NSSize(width: 600, height: 320))

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
        logger.debug("Ordering quick task panel front")

        startMonitoringClickOutside()
        DispatchQueue.main.async { [weak self] in
            self?.acceptingDismissal = true
        }
    }

    func close() {
        guard panel?.isVisible == true else { return }
        logger.debug("Closing quick task panel")
        sizeObserver?.invalidate()
        sizeObserver = nil
        acceptingDismissal = false
        stopMonitoringClickOutside()
        panel?.orderOut(nil)
    }

    private func showCaptureSuccessThenClose() {
        guard let panel else { return }
        logger.debug("Showing quick capture success")
        sizeObserver?.invalidate()
        sizeObserver = nil
        acceptingDismissal = false
        stopMonitoringClickOutside()

        let content = QuickTaskCaptureSuccessView()
            .preferredColorScheme(.dark)
        let hc = NSHostingController(rootView: AnyView(content))
        panel.contentViewController = hc
        hostingController = hc
        setPanelContentSize(NSSize(width: 600, height: 150), for: panel)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in
            self?.close()
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
            // .nonactivatingPanel: the panel can become key (receive keyboard
            // input) without activating the application or switching spaces.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
        let w: CGFloat = 600
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

    private func setPanelContentSize(_ size: NSSize, for panel: NSPanel) {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(
            x: center.x - panel.frame.width / 2,
            y: center.y - panel.frame.height / 2
        ))
    }
}

private final class QuickTaskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct QuickTaskCaptureSuccessView: View {
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.green.opacity(0.18))
                Image(systemName: "checkmark")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.green)
            }
            .frame(width: 42, height: 42)
            .scaleEffect(isVisible ? 1 : 0.7)
            .opacity(isVisible ? 1 : 0)

            VStack(alignment: .leading, spacing: 3) {
                Text("Captured")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Task added to Cadence")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(width: 600, height: 150)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.95), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 34, x: 0, y: 18)
        .shadow(color: Theme.green.opacity(0.12), radius: 18, x: 0, y: 0)
        .scaleEffect(isVisible ? 1 : 0.98)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                isVisible = true
            }
        }
    }
}
#endif
