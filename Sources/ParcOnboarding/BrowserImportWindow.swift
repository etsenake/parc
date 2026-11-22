import AppKit
import ParcCore
import QuartzCore
import ParcKit

@MainActor
package final class BrowserImportWindow: NSWindowController, NSWindowDelegate {
    package var onClose: ((Bool) -> Void)?
    package var onRequestRestart: ((BrowserImportRestartIntent, @escaping (String?) -> Void) -> Void)? {
        didSet { content.onRequestRestart = onRequestRestart }
    }
    private var content: BrowserImportViewController!
    private weak var parent: NSWindow?
    private var parentCloseObserver: NSObjectProtocol?
    private var parentIsClosing = false
    private var closed = false

    package init(store: BrowserStore, destination: BrowserImportDestination, parent: NSWindow?,
         ownerIsCurrent: @escaping () -> Bool) {
        let window = BrowserImportNativeWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 454),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Import from Another Browser"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true; window.tabbingMode = .disallowed
        window.backgroundColor = ParcDialogStyle.popoverBackground
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        super.init(window: window)
        self.parent = parent; window.delegate = self
        content = BrowserImportViewController(store: store, destination: destination, window: window,
            onboarding: false, ownerIsCurrent: ownerIsCurrent)
        window.contentView = content.view
        content.onClose = { [weak self] in self?.window?.performClose(nil) }
        if let parent {
            parentCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.parentIsClosing = true; self?.close() }
            }
        }
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package func present() {
        guard let window, !closed else { return }
        if let parent {
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2,
                                          y: parent.frame.midY - window.frame.height / 2))
            parent.addChildWindow(window, ordered: .above)
        } else { window.center() }
        window.setFrame(BrowserImportGeometry.clamped(window.frame, to: parent?.screen ?? window.screen), display: false)
        showWindow(nil); window.makeKeyAndOrderFront(nil); content.start()
    }
    package func resumeSafariImport(sourceBundleID: String = "com.apple.Safari") {
        guard !closed else { return }
        content.resumeSafariImport(sourceBundleID: sourceBundleID)
    }
    package func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        let restoreFocus = !parentIsClosing && NSApp.isActive && Self.owning(NSApp.keyWindow) === self
        closed = true; content.cancel()
        if let parentCloseObserver { NotificationCenter.default.removeObserver(parentCloseObserver) }
        parentCloseObserver = nil
        if let window { parent?.removeChildWindow(window) }
        let callback = onClose; onClose = nil; callback?(restoreFocus)
    }
    package static func owning(_ window: NSWindow?) -> BrowserImportWindow? {
        var current = window
        while let candidate = current {
            if let owner = candidate.windowController as? BrowserImportWindow { return owner }
            current = candidate.sheetParent ?? candidate.parent
        }
        return nil
    }
}

@MainActor
private final class BrowserImportNativeWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, [UInt16(36), UInt16(53), UInt16(76)].contains(event.keyCode),
           let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
enum BrowserImportGeometry {
    private static let targets = NSMapTable<NSView, NSValue>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private static let windowSizes = NSMapTable<NSWindow, NSValue>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    static func clamped(_ frame: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    static func resize(_ window: NSWindow, contentSize: NSSize) {
        guard windowSizes.object(forKey: window)?.sizeValue != contentSize else { return }
        windowSizes.setObject(NSValue(size: contentSize), forKey: window)
        let current = window.frame
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let target = clamped(NSRect(x: current.midX - size.width / 2,
            y: current.midY - size.height / 2, width: size.width, height: size.height), to: window.screen)
        animate(window: window, target: target) {
            window.animator().setFrame(target, display: true)
        } immediate: {
            window.setFrame(target, display: true)
        }
    }

    static func resizeContent(_ view: NSView, to target: NSRect) {
        guard targets.object(forKey: view)?.rectValue != target else { return }
        targets.setObject(NSValue(rect: target), forKey: view)
        guard view.frame != target else { return }
        guard let window = view.window, view.frame.width > 0, view.frame.height > 0 else {
            view.frame = target; view.layoutSubtreeIfNeeded(); return
        }
        let reference = NSRect(origin: window.frame.origin, size: NSSize(
            width: window.frame.width + target.width - view.frame.width,
            height: window.frame.height + target.height - view.frame.height))
        animate(window: window, target: reference) {
            view.animator().frame = target
        } immediate: {
            view.frame = target
        }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    private static func animate(window: NSWindow, target: NSRect,
                                changes: () -> Void, immediate: () -> Void) {
        if !window.isVisible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                immediate()
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = window.animationResizeTime(target)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                changes()
            }
        }
    }
}
