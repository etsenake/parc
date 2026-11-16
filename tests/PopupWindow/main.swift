import AppKit

@main struct PopupWindowChecks {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = BrowserPopupWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                                        styleMask: style, backing: .buffered, defer: false)
        precondition(window.canBecomeKey && window.canBecomeMain)
        precondition(!window.isRestorable && !window.hidesOnDeactivate && !window.becomesKeyOnlyIfNeeded)
        precondition(window.collectionBehavior.contains(.managed) && !window.isVisible)
        window.close()
        print("PopupWindow: panel eligibility and non-restoration passed")
    }
}
