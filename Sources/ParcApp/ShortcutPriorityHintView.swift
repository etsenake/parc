import AppKit
import SwiftUI

/// The renderer owns the command/expiry. This original-window child owns only
/// the attributed toast presentation; it never installs another key handler.
@MainActor
final class ShortcutPriorityHintView: NSView {
    var onEdit: (() -> Void)?
    var onDismiss: (() -> Void)?
    private(set) weak var originalWindow: NSWindow?
    private weak var toastWindow: ShortcutHintWindow?
    let state: PArcToastState
    private var host: NSHostingView<PArcToastCard>!
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    private var revealWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var generation = UUID()
    private(set) var isRetiring = false
    private(set) var bodyRect = NSRect.zero
    private(set) var accessoryRect = NSRect.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let toastWindow, newWindow !== toastWindow {
            requestDismissal()
            dismiss(animated: false)
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidHide() {
        super.viewDidHide()
        requestDismissal()
        dismiss(animated: false)
    }

    init(title: String, shortcut: String, canEdit: Bool, theme: SpaceTheme, basicBackground: NSColor?) {
        state = PArcToastState(content: .pressAgain(shortcut: shortcut, title: title),
            accessory: canEdit ? PArcToastAccessory(text: "Edit the shortcut", image: "arrow.up.right",
                                                   accessibilityLabel: "Edit the shortcut for " + title) : nil,
            theme: theme, basicBackground: basicBackground)
        super.init(frame: NSRect(x: 0, y: 0, width: PArcToastPlacement.windowSide, height: PArcToastPlacement.windowSide))
        host = NSHostingView(rootView: PArcToastCard(state: state, actions: PArcToastActions(
            tap: nil, accessory: { [weak self] in self?.edit() },
            dismiss: { [weak self] in self?.requestDismissal() },
            share: { _ in },
            frames: { [weak self] frames in
                guard let self, !self.isRetiring else { return }
                self.bodyRect = frames.body; self.accessoryRect = frames.accessory
            })))
        host.frame = bounds; host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        revealWork?.cancel(); closeWork?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    static func frame(for parent: NSRect) -> NSRect { PArcToastPlacement.windowFrame(for: parent) }
    @discardableResult
    func present(in parent: NSWindow) -> Bool {
        guard !isRetiring, originalWindow == nil, parent.isKeyWindow, parent.isVisible,
              !parent.isMiniaturized, parent.attachedSheet == nil else { return false }
        let panel = ShortcutHintWindow(contentRect: Self.frame(for: parent.frame), styleMask: .borderless,
                                       backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = false
        panel.contentView = self; panel.acceptsMouseMovedEvents = true
        originalWindow = parent; toastWindow = panel
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.appearance = parent.effectiveAppearance
        parent.addChildWindow(panel, ordered: .above)
        panel.setFrame(Self.frame(for: parent.frame), display: true)
        observe(parent)
        layoutSubtreeIfNeeded()
        guard panel.parent === parent, panel.isVisible else { dismiss(animated: false); return false }
        let token = generation
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, self.generation == token, self.toastWindow === panel, self.isAvailable else { return }
            self.state.show()
        }
        let reveal = DispatchWorkItem { [weak self, weak panel] in
            guard let self, self.generation == token, self.toastWindow === panel, self.isAvailable else { return }
            self.state.showAccessory = true
        }
        revealWork = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + PArcToastTiming.accessoryDelay, execute: reveal)
        return true
    }

    func update(theme: SpaceTheme, basicBackground: NSColor?) {
        guard !isRetiring else { return }
        state.theme = theme; state.basicBackground = basicBackground
        if let originalWindow { toastWindow?.appearance = originalWindow.effectiveAppearance }
    }
    private var isAvailable: Bool {
        guard !isRetiring, let parent = originalWindow, let panel = toastWindow else { return false }
        return panel.parent === parent && panel.isVisible && parent.isKeyWindow && parent.isVisible &&
            !parent.isMiniaturized && parent.attachedSheet == nil && !isHiddenOrHasHiddenAncestor
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isAvailable else { return nil }
        let local = superview.map { convert(point, from: $0) } ?? point
        guard bodyRect.contains(local) || (state.showAccessory && accessoryRect.contains(local)) else { return nil }
        return super.hitTest(point)
    }
    var containsPointer: Bool {
        guard isAvailable, let panel = toastWindow else { return false }
        let point = convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return bodyRect.contains(point) || (state.showAccessory && accessoryRect.contains(point))
    }
    private func edit() {
        guard isAvailable, state.accessory != nil, state.showAccessory else { return }
        onEdit?()
    }
    private func requestDismissal() {
        guard !isRetiring, let parent = originalWindow, let panel = toastWindow,
              panel.parent === parent else { return }
        // The native queue revalidates its page/document. A view being hidden
        // or detached must still request consumption of that exact old cue.
        onDismiss?()
    }

    /// Revoke input synchronously. Only the same passive child may finish its
    /// original exit; no delayed callback can clear a replacement command.
    func dismiss(animated: Bool) {
        guard !isRetiring else { if !animated { closePresentation() }; return }
        let shouldAnimate = animated && isAvailable && !state.reduceMotion
        isRetiring = true; generation = UUID()
        onEdit = nil; onDismiss = nil
        revealWork?.cancel(); revealWork = nil
        toastWindow?.ignoresMouseEvents = true
        state.hide(animated: shouldAnimate)
        guard shouldAnimate else { closePresentation(); return }
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.isRetiring else { return }
            self.closePresentation()
        }
        closeWork = work
        // The original ToastWindow retains its passive child for one second.
        DispatchQueue.main.asyncAfter(deadline: .now() + PArcToastTiming.retirement, execute: work)
    }
    private func closePresentation() {
        generation = UUID(); isRetiring = true
        revealWork?.cancel(); revealWork = nil; closeWork?.cancel(); closeWork = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }; scrollMonitor = nil
        let panel = toastWindow
        toastWindow = nil; originalWindow = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil); panel.contentView = nil; panel.close()
        }
    }
    ///
    /// then moves with its parent. A full-screen transition consumes the cue.
    private func observe(_ parent: NSWindow) {
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestDismissal(); self?.dismiss(animated: false) }
            })
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.willMiniaturizeNotification, NSWindow.willBeginSheetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(animated: false) }
            })
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    if self.state.reduceMotion && self.isRetiring { self.closePresentation() }
                }
            }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak parent] event in
            MainActor.assumeIsolated {
                guard let self, PArcToastScroll.dismisses(window: event.window, deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY, owners: [parent, self.toastWindow]) else { return }
                self.requestDismissal()
            }
            return event
        }
    }
}

@MainActor
private final class ShortcutHintWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
