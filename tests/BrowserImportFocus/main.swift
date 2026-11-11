import AppKit
import SwiftUI

@MainActor private final class ProbeWindow: NSWindow {
    var shown = true
    var minimized = false
    var testSheet: NSWindow?
    override var isVisible: Bool { shown }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { testSheet }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.titled], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}
@main @MainActor struct BrowserImportFocusTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let parent = ProbeWindow(), importer = ProbeWindow(), other = ProbeWindow()
        func canReturn(_ requested: Bool = true, _ active: Bool = true, _ key: NSWindow? = nil) -> Bool {
            BrowserImportFocus.mayReturn(requested: requested, appIsActive: active,
                                         parent: parent, importer: importer, key: key)
        }
        precondition(canReturn(true, true, importer))
        precondition(canReturn(true, true, parent))
        precondition(canReturn())
        precondition(!canReturn(false) && !canReturn(true, false))
        precondition(!canReturn(true, true, other))
        parent.shown = false; precondition(!canReturn()); parent.shown = true
        parent.minimized = true; precondition(!canReturn()); parent.minimized = false
        parent.testSheet = other; precondition(!canReturn()); parent.testSheet = nil
        precondition(!BrowserImportFocus.mayReturn(requested: true, appIsActive: true,
                                                  parent: parent, importer: nil, key: other))
        keyViewOrder()
        print("Browser import focus: 9 checks and setup key-view order passed")
    }

    static func keyViewOrder() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        window.contentView = content
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 400))
        let importer = FlippedView(frame: NSRect(x: 100, y: 0, width: 300, height: 400))
        content.addSubview(accessory); content.addSubview(importer)
        let accessoryButton = NSButton(frame: NSRect(x: 0, y: 10, width: 80, height: 20))
        accessory.addSubview(accessoryButton)
        let column = FlippedView(frame: importer.bounds)
        importer.addSubview(column)
        let lower = NSButton(frame: NSRect(x: 0, y: 300, width: 80, height: 20))
        let upper = NSButton(frame: NSRect(x: 0, y: 20, width: 80, height: 20))
        let right = NSButton(frame: NSRect(x: 120, y: 20, width: 80, height: 20))
        let hidden = NSButton(frame: NSRect(x: 0, y: 200, width: 80, height: 20)); hidden.isHidden = true
        let disabled = NSButton(frame: NSRect(x: 0, y: 250, width: 80, height: 20)); disabled.isEnabled = false
        let label = NSTextField(wrappingLabelWithString: "Status"); label.frame = NSRect(x: 0, y: 100, width: 80, height: 20)
        let field = NSTextField(frame: NSRect(x: 0, y: 150, width: 80, height: 20))
        let host = NSHostingView(rootView: VStack { Button("A") {}; Button("B") {} })
        host.frame = NSRect(x: 0, y: 60, width: 200, height: 30); host.layoutSubtreeIfNeeded()
        let focusable = FocusableView(frame: NSRect(x: 0, y: 350, width: 200, height: 40))
        let nested = NSButton(frame: NSRect(x: 0, y: 5, width: 50, height: 20))
        focusable.addSubview(nested)
        [lower, right, upper, hidden, disabled, label, field, host, focusable].forEach(column.addSubview)
        let order = BrowserImportFocus.keyViews(in: [accessory, importer])
        let expected: [NSView] = [accessoryButton, upper, right, host, field, hidden, disabled, lower, focusable, nested]
        precondition(order.count == expected.count && zip(order, expected).allSatisfy { $0 === $1 },
                     "Setup import key views out of reading order: \(order.map { type(of: $0) })")
        precondition(BrowserImportFocus.keyViews(in: []).isEmpty)
    }
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }
private final class FocusableView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
