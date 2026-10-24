#if os(macOS)
import SwiftUI
import AppKit
import SwiftData
import os

final class QuickTaskPanelController: NSObject {
    static let shared = QuickTaskPanelController()
    private static let panelSurfaceSize = NSSize(width: 600, height: 320)
    private static let panelSuccessSurfaceSize = NSSize(width: 600, height: 150)
    private static let shadowPadding: CGFloat = 24
    private let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "QuickTaskPanel")

    private var panel: QuickTaskPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var panelResignKeyObserver: NSObjectProtocol?
    private var acceptingDismissal = false
    private var sizeObserver: NSKeyValueObservation?
    /// [[T-5302]] — whether the form standing in `hostingController` is a draft the next open
    /// should get back.
    private var draftRetention = QuickTaskPanelDraftRetention()

    private override init() {}

    var isVisible: Bool { panel?.isVisible == true }

    func show(seed: TaskCreationSeed = TaskCreationSeed()) {
        // T-817: `container` is `nil` on the one launch where nothing SwiftData could open
        // worked at all. There is no task store to capture into, and the global hotkey that
        // drives this is registered independently of whether the main window ever got one — see
        // `CadenceAppDelegate` — so this has to fail silently rather than crash on a force unwrap
        // that used to be implicit in `container`'s non-optional type.
        guard let container = PersistenceController.shared.container else {
            logger.error("Quick task panel requested with no ModelContainer available; ignoring.")
            return
        }

        let panel = ensurePanel()
        logger.debug("Preparing quick task panel")

        let content = CreateTaskPanelSurface(
            seed: seed,
            dismissAction: { [weak self] in self?.closeDiscardingDraft() },
            successAction: { [weak self] in self?.showCaptureSuccessThenClose() }
        )
        .padding(Self.shadowPadding)
        .modelContainer(container)
        .environment(TaskCreationManager.shared)
        .preferredColorScheme(.dark)

        // [[T-5302]]. **The half-typed task survives a click into another app.** The panel still
        // closes on resign-key — the owner declined the alternative, because a panel that will not
        // go away when you click somewhere else is its own irritation and getting out of the way
        // is the point of it. What changed is that the standing form is handed back on the next
        // open instead of being rebuilt: the draft lives in `CreateTaskSheet`'s `@State`, so
        // keeping the hosting controller alive is keeping the draft, and the comment that used to
        // sit here ("Always create a fresh hosting controller so @State resets on each open") was
        // the whole defect stated as an intention.
        //
        // It is handed back only for an **empty** seed. A caller that pre-fills the form is asking
        // for that form, and a stale draft must not win over it.
        sizeObserver?.invalidate()
        sizeObserver = nil
        let restoring = draftRetention.reusesTheStandingForm(
            hasForm: hostingController != nil,
            seedIsEmpty: Self.seedIsEmpty(seed)
        )
        let hc: NSHostingController<AnyView>
        if restoring, let standing = hostingController {
            hc = standing
        } else {
            hc = NSHostingController(rootView: AnyView(content))
        }
        installHostingController(hc, in: panel)
        self.hostingController = hc
        // A restored draft may have grown past the default surface — subtasks add rows — so the
        // panel takes the size the form already asked for rather than snapping back and clipping.
        let preferred = hc.preferredContentSize
        if restoring, preferred.height > 50, preferred.width > 0 {
            panel.setContentSize(preferred)
        } else {
            panel.setContentSize(panelContentSize(for: Self.panelSurfaceSize))
        }

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

        startObservingPanelResignKey(panel)
        DispatchQueue.main.async { [weak self] in
            self?.acceptingDismissal = true
        }
    }

    /// Puts the panel away and **keeps** whatever is typed in it ([[T-5302]]).
    ///
    /// This is the resign-key path and the hotkey's own toggle: neither is the user saying they
    /// are finished with the draft. Saving and Escape are, and they go through
    /// `closeDiscardingDraft()`.
    func close() {
        guard panel?.isVisible == true else { return }
        draftRetention.panelClosedWithTheDraftUnresolved()
        orderPanelOut()
    }

    /// Puts the panel away and throws the draft away with it: the next open starts blank.
    ///
    /// Escape and the sheet's own Cancel ✕, which is the owner's "cleared on save or Esc" — plus
    /// the beat after a successful capture, where the form has already become the success view.
    func closeDiscardingDraft() {
        guard panel?.isVisible == true else { return }
        draftRetention.draftResolved()
        hostingController = nil
        orderPanelOut()
    }

    private func orderPanelOut() {
        logger.debug("Closing quick task panel")
        sizeObserver?.invalidate()
        sizeObserver = nil
        acceptingDismissal = false
        stopObservingPanelResignKey()
        panel?.orderOut(nil)
    }

    private func showCaptureSuccessThenClose() {
        guard let panel else { return }
        logger.debug("Showing quick capture success")
        sizeObserver?.invalidate()
        sizeObserver = nil
        acceptingDismissal = false
        stopObservingPanelResignKey()

        // [[T-5302]]: the capture landed, so the draft is spent. Marked here rather than in the
        // timer below because the form has already been replaced by the success view — a later
        // `close()` that kept "the draft" would hand the next open a tick and a Captured label.
        draftRetention.draftResolved()

        let content = QuickTaskCaptureSuccessView()
            .padding(Self.shadowPadding)
            .preferredColorScheme(.dark)
        let hc = NSHostingController(rootView: AnyView(content))
        installHostingController(hc, in: panel)
        hostingController = hc
        setPanelContentSize(panelContentSize(for: Self.panelSuccessSurfaceSize), for: panel)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in
            self?.closeDiscardingDraft()
        }
    }

    // MARK: - Focus-loss dismissal

    private func startObservingPanelResignKey(_ panel: NSPanel) {
        guard panelResignKeyObserver == nil else { return }
        panelResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard self?.acceptingDismissal == true else { return }
            self?.close()
        }
    }

    private func stopObservingPanelResignKey() {
        if let observer = panelResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            panelResignKeyObserver = nil
        }
    }

    /// Whether a seed asks for anything, measured against a freshly built one rather than against
    /// retyped defaults — the defaults are `TaskCreationSeed`'s to change ([[T-5302]]).
    static func seedIsEmpty(_ seed: TaskCreationSeed) -> Bool {
        let blank = TaskCreationSeed()
        return seed.title == blank.title
            && seed.notes == blank.notes
            && seed.dueDateKey == blank.dueDateKey
            && seed.doDateKey == blank.doDateKey
            && seed.scheduledStartMin == blank.scheduledStartMin
            && seed.estimatedMinutes == blank.estimatedMinutes
            && seed.priority == blank.priority
            && seed.container == blank.container
            && seed.sectionName == blank.sectionName
            && seed.subtaskTitles == blank.subtaskTitles
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
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.animationBehavior = .utilityWindow
        configureTransparentContentView(for: panel)
        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        // Use design dimensions directly — panel.frame.size can be zero on the
        // first show before SwiftUI has completed its initial layout pass.
        let w: CGFloat = max(panel.frame.width > 10 ? panel.frame.width : panelContentSize(for: Self.panelSurfaceSize).width, 280)
        let h: CGFloat = max(panel.frame.height > 10 ? panel.frame.height : panelContentSize(for: Self.panelSurfaceSize).height, 280)
        let screen = screenForPanelPlacement()

        guard let screen else { panel.center(); return }

        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - w / 2,
            y: visibleFrame.midY - h / 2
        ))
    }

    private func screenForPanelPlacement() -> NSScreen? {
        let validScreens = NSScreen.screens.filter { screen in
            let frame = screen.frame
            return frame.width.isFinite &&
                frame.height.isFinite &&
                frame.origin.x.isFinite &&
                frame.origin.y.isFinite &&
                !frame.isEmpty
        }
        let mouseLocation = NSEvent.mouseLocation
        return validScreens.first { $0.frame.contains(mouseLocation) } ??
            NSScreen.main ??
            validScreens.first
    }

    private func setPanelContentSize(_ size: NSSize, for panel: NSPanel) {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(
            x: center.x - panel.frame.width / 2,
            y: center.y - panel.frame.height / 2
        ))
    }

    private func panelContentSize(for surfaceSize: NSSize) -> NSSize {
        NSSize(
            width: surfaceSize.width + (Self.shadowPadding * 2),
            height: surfaceSize.height + (Self.shadowPadding * 2)
        )
    }

    private func installHostingController(_ hostingController: NSHostingController<AnyView>, in panel: NSPanel) {
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
        configureTransparentContentView(for: panel)
    }

    private func configureTransparentContentView(for panel: NSPanel) {
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class QuickTaskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// [[T-5302]] — Escape is the user saying they are finished with this draft, so it clears.
    ///
    /// The panel is borderless and has no close button, so `NSWindow`'s own `cancelOperation` did
    /// nothing here; the key simply fell on the floor. It has to mean something now that closing
    /// otherwise *keeps* what is typed — the owner's decision names Escape as one of the two ways
    /// a draft goes away.
    override func cancelOperation(_ sender: Any?) {
        QuickTaskPanelController.shared.closeDiscardingDraft()
    }
}

/// **[[T-5302]] — whether the next open of the quick-capture panel gets the last one's draft.**
///
/// A value type rather than a `Bool` on the controller because this is the whole decision the
/// ticket is about and the controller cannot be driven from a test: `show()` wants a real
/// `ModelContainer` and puts a floating panel on the screen.
///
/// The asymmetry is deliberate. Closing is the default and it **keeps** — clicking into another
/// app to copy a link is the exact move that used to empty the form. Only the two acts that
/// finish with the draft, saving it and pressing Escape, resolve it.
struct QuickTaskPanelDraftRetention: Equatable {
    /// `true` when a form was left standing with something possibly typed in it.
    private(set) var holdsDraft = false

    /// The panel went away without the user finishing with the draft: resign-key, or the hotkey
    /// pressed a second time.
    mutating func panelClosedWithTheDraftUnresolved() {
        holdsDraft = true
    }

    /// Saved, or dismissed with Escape or Cancel. Either way the next open starts blank.
    mutating func draftResolved() {
        holdsDraft = false
    }

    /// `hasForm` is separate from `holdsDraft` because the success view takes the form's place in
    /// the controller: a held draft with nothing standing is still nothing to restore.
    func reusesTheStandingForm(hasForm: Bool, seedIsEmpty: Bool) -> Bool {
        holdsDraft && hasForm && seedIsEmpty
    }
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
        .shadow(color: Theme.overlayCardShadow, radius: 34, x: 0, y: 18)
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
