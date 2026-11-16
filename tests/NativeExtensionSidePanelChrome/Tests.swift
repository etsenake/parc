import AppKit

private final class InertKeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@main struct ExtensionSidePanelChromeTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(condition(), message)
        }
        let panel = ExtensionSidePanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        let window = InertKeyWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = panel
        panel.layoutSubtreeIfNeeded()
        let content = panel.content
        let nativePage = NSView(frame: content.bounds)
        nativePage.autoresizingMask = [.width, .height]
        content.addSubview(nativePage)
        expect(content.frame == NSRect(x: 0, y: 32, width: 300, height: 468),
               "The real native page receives only the content area below the shell header")
        expect(panel.closeButton.frame.size == NSSize(width: 32, height: 24)
               && panel.closeButton.frame.maxY <= content.frame.minY,
               "Close control retains its native surface without overlapping extension content")
        expect(panel.closeButton.accessibilityLabel() == "Close Extension Side Panel",
               "Reused native control has panel semantics instead of split-pane semantics")
        expect(panel.closeButton.acceptsFirstResponder, "The shell close button remains a native focus target")
        var closes = 0
        panel.onClose = { closes += 1; return true }
        panel.closeButton.performClick(nil)
        expect(closes == 1, "Native button activation reaches the shell's real-close callback once")
        panel.cancelOperation(nil)
        expect(closes == 2, "Escape in shell controls reaches the same native close owner")
        panel.isHidden = true
        panel.closeButton.performClick(nil)
        panel.cancelOperation(nil)
        expect(closes == 2, "A hidden panel cannot dismiss a replacement through its old control or Escape")
        panel.isHidden = false
        panel.frame.size = NSSize(width: 240, height: 320)
        panel.needsLayout = true; panel.layoutSubtreeIfNeeded()
        expect(panel.content === content && nativePage.superview === content,
               "Resize preserves the original page container and page identity")
        expect(nativePage.frame == content.bounds && content.frame == NSRect(x: 0, y: 32, width: 240, height: 288),
               "The native host follows content resizing without covering shell controls")
        panel.frame.size = NSSize(width: 20, height: 10)
        panel.needsLayout = true; panel.layoutSubtreeIfNeeded()
        expect(panel.closeButton.isHidden && content.frame.height == 0 && content.frame.width == 20,
               "Undersized hosts keep nonnegative content and hide controls that cannot fit")
        panel.onClose = nil
        window.contentView = nil
        window.close()
        print("PASS: \(assertions) inert extension side-panel chrome assertions")
    }
}
