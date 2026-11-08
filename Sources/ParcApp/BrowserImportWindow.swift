import AppKit

/// The application menu owns a separate import window. First launch embeds the
/// same presentation in its setup window and never creates this controller.
@MainActor
final class BrowserImportWindow: NSWindowController, NSWindowDelegate {
    var onClose: ((Bool) -> Void)?
    var onRequestRestart: ((BrowserImportRestartIntent, @escaping (String?) -> Void) -> Void)? {
        didSet { content.onRequestRestart = onRequestRestart }
    }
    private var content: BrowserImportViewController!
    private weak var parent: NSWindow?
    private var parentCloseObserver: NSObjectProtocol?
    private var parentIsClosing = false
    private var closed = false

    init(store: BrowserStore, destination: BrowserImportDestination, parent: NSWindow?,
         ownerIsCurrent: @escaping () -> Bool) {
        let window = BrowserImportNativeWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 454),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Import from Another Browser"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true; window.tabbingMode = .disallowed
        // ImportDialogView sits in a Dialogs sheet: PopoverBackground, which
        // follows the system appearance (the navy seen in dark mode).
        window.backgroundColor = PArcDialogStyle.popoverBackground
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
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        guard let window, !closed else { return }
        if let parent {
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2,
                                          y: parent.frame.midY - window.frame.height / 2))
            parent.addChildWindow(window, ordered: .above)
        } else { window.center() }
        showWindow(nil); window.makeKeyAndOrderFront(nil); content.start()
    }
    func resumeSafariImport(sourceBundleID: String = "com.apple.Safari") {
        guard !closed else { return }
        content.resumeSafariImport(sourceBundleID: sourceBundleID)
    }
    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        // Only the active import (or one of its sheets) may return focus to
        // its original browser. A background close must not raise that browser
        // over the window the user has since chosen.
        let restoreFocus = !parentIsClosing && NSApp.isActive && Self.owning(NSApp.keyWindow) === self
        closed = true; content.cancel()
        if let parentCloseObserver { NotificationCenter.default.removeObserver(parentCloseObserver) }
        parentCloseObserver = nil
        if let window { parent?.removeChildWindow(window) }
        let callback = onClose; onClose = nil; callback?(restoreFocus)
    }
    static func owning(_ window: NSWindow?) -> BrowserImportWindow? {
        var current = window
        while let candidate = current {
            if let owner = candidate.windowController as? BrowserImportWindow { return owner }
            current = candidate.sheetParent ?? candidate.parent
        }
        return nil
    }
}

/// Leave composition keys in the native field editor before the window's
/// Return/Escape equivalents can submit or cancel this import.
@MainActor
private final class BrowserImportNativeWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, [UInt16(36), UInt16(53), UInt16(76)].contains(event.keyCode),
           let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        return super.performKeyEquivalent(with: event)
    }
}
