import AppKit

/// The immediate hover state used by Settings' recovered custom controls.
/// Subclasses own their palette; NSButton continues to own accepted actions,
/// pressed tracking, keyboard activation and accessibility. No timing, scale or
/// haptic is shared between controls. See docs/settings-motion.md (SET25).
@MainActor
class SettingsHoverButton: PointingHandButton {
    private var hovered = false
    private var tracking: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []
    private var windowRetired = false
    private var sheetPresented = false

    var isHovered: Bool { hovered && canShowHover }

    private var canShowHover: Bool {
        guard isEnabled, !isHiddenOrHasHiddenAncestor, !windowRetired, !sheetPresented,
              let window else { return false }
        return window.isVisible && window.isKeyWindow && NSApp.isActive && window.attachedSheet == nil
    }

    override var isEnabled: Bool {
        didSet {
            if isEnabled { refreshHover() } else { setHovered(false) }
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
        refreshHover()
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === tracking else { return }
        updateHover(with: event)
    }
    override func mouseMoved(with event: NSEvent) { updateHover(with: event) }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === tracking, event.windowNumber == window?.windowNumber else { return }
        setHovered(false)
    }

    private func updateHover(with event: NSEvent) {
        guard event.windowNumber == window?.windowNumber else { return }
        guard canShowHover else { setHovered(false); return }
        setHovered(containsPointer(at: event.locationInWindow))
    }

    private func refreshHover() {
        guard canShowHover, let window else { setHovered(false); return }
        setHovered(containsPointer(at: window.mouseLocationOutsideOfEventStream))
    }

    private func containsPointer(at windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        guard bounds.contains(point), visibleRect.contains(point), let content = window?.contentView else { return false }
        let hit = content.hitTest(content.superview?.convert(windowPoint, from: nil) ?? windowPoint)
        return hit === self || hit?.isDescendant(of: self) == true
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        needsDisplay = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { setHovered(false) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        windowRetired = false
        sheetPresented = window?.attachedSheet != nil
        setHovered(false)
        guard let window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willBeginSheetNotification,
                     NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] note in
                MainActor.assumeIsolated {
                    guard let self, let window, self.window === window else { return }
                    if note.name == NSWindow.willCloseNotification { self.windowRetired = true }
                    if note.name == NSWindow.willBeginSheetNotification { self.sheetPresented = true }
                    self.setHovered(false)
                }
            })
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didEndSheetNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] note in
                MainActor.assumeIsolated {
                    guard let self, let window, self.window === window else { return }
                    if note.name == NSWindow.didBecomeKeyNotification { self.windowRetired = false }
                    if note.name == NSWindow.didEndSheetNotification { self.sheetPresented = false }
                    self.refreshHover()
                }
            })
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshHover() }
            })
        }
    }

    override func viewDidHide() { super.viewDidHide(); setHovered(false) }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshHover() }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
