import AppKit

@MainActor private final class TestApplication: NSApplication {
    var simulatedActive = true
    override var isActive: Bool { simulatedActive }
}
@MainActor private final class TestWindow: NSWindow {
    var simulatedVisible = true
    var key = true
    var simulatedSheet: TestWindow?
    var ended: [NSApplication.ModalResponse] = []
    override var isVisible: Bool { simulatedVisible }
    override var isKeyWindow: Bool { key }
    override var attachedSheet: NSWindow? { simulatedSheet }
    override func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse) {
        precondition(sheetWindow.attachedSheet == nil, "Nested sheet must retire first")
        ended.append(returnCode); simulatedSheet = nil
    }
}
@MainActor private final class FlippedView: NSView { override var isFlipped: Bool { true } }
@MainActor private final class Target: NSObject {
    var count = 0
    @objc func invoke() { count += 1 }
}

/// Inert AppKit components only: no windows are ordered, no OS input or browser
/// is driven, and no real preference, profile or application activation changes.
@main @MainActor struct SettingsFocusTests {
    static func main() {
        let app = TestApplication.shared as! TestApplication
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1; precondition(value(), message)
        }
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = root
        let first = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 25))
        first.stringValue = "Original draft"; first.setAccessibilityLabel("Profile name")
        let button = NSButton(title: "Apply", target: nil, action: nil)
        button.frame = NSRect(x: 230, y: 20, width: 80, height: 25)
        let lower = NSTextField(frame: NSRect(x: 20, y: 80, width: 200, height: 25))
        let label = NSTextField(labelWithString: "Explanation")
        // Insertion order intentionally disagrees with visual order.
        [lower, button, label, first].forEach(root.addSubview)
        SettingsFocusState.connectKeyViews(in: root)
        expect(SettingsFocusState.controls(in: root).count == 3, "Passive labels are not duplicate keyboard controls")
        expect(first.nextKeyView === button && button.nextKeyView === lower && lower.nextKeyView === first,
               "Tab and reverse traversal form one native visual-order loop")
        print("AX field", first.accessibilityRole()?.rawValue ?? "nil", first.accessibilityLabel() ?? "nil")
        expect(lower.previousKeyView === button && button.previousKeyView === first, "Native reverse links preserve Shift-Tab order")
        expect(first.accessibilityLabel() == "Profile name", "Configured native field label retained")
        let target = Target(); button.target = target; button.action = #selector(Target.invoke)
        button.isEnabled = false
        button.performClick(nil)
        expect(target.count == 0 && !button.isAccessibilityEnabled(), "Disabled native action cannot dispatch and reports unavailable")
        button.isEnabled = true
        button.performClick(nil)
        expect(target.count == 1, "Enabled native action still dispatches once")
        let state = SettingsFocusState()
        window.makeFirstResponder(first)
        let editor = first.currentEditor() as! NSTextView
        editor.setSelectedRange(NSRange(location: 4, length: 5))
        state.remember(in: window, root: root, context: "profiles:A")
        window.makeFirstResponder(lower)
        expect(state.restore(in: window, root: root, context: "profiles:A"), "Original context responder restored")
        expect(first.currentEditor() === window.firstResponder && (first.currentEditor() as? NSTextView)?.selectedRange() == NSRange(location: 4, length: 5), "Real shared field editor resolves to its original control and selection")
        window.makeFirstResponder(lower)
        state.restore(in: window, root: root, context: "profiles:B", fallback: lower)
        expect(lower.currentEditor() === window.firstResponder, "A different Profile never adopts another Profile's remembered control")
        window.makeFirstResponder(first)
        state.remember(in: window, root: root, context: "profiles:B")
        let survivingList = NSTableView(frame: NSRect(x: 20, y: 120, width: 200, height: 80))
        survivingList.addTableColumn(NSTableColumn(identifier: .init("profiles")))
        root.addSubview(survivingList)
        state.restore(in: window, root: root, context: nil, fallback: survivingList)
        expect(window.firstResponder === survivingList, "Deleted original Profile returns to its native list even when the survivor has a valid bookmark")
        window.key = false
        expect(!state.restore(in: window, root: root, context: "profiles:A"), "Non-key Settings never steals focus")
        window.key = true; app.simulatedActive = false
        expect(!state.restore(in: window, root: root, context: "profiles:A"), "Inactive application never changes focus")
        app.simulatedActive = true; window.simulatedVisible = false
        expect(!state.restore(in: window, root: root, context: "profiles:A"), "Closed Settings cannot restore a queued bookmark")
        window.simulatedVisible = true
        first.isEnabled = false
        expect(state.restore(in: window, root: root, context: "profiles:A", fallback: lower), "Disabled original control uses available fallback")
        expect(lower.currentEditor() === window.firstResponder, "Fallback keeps the original Settings window")
        first.isEnabled = true; first.isHidden = true
        state.restore(in: window, root: root, context: "profiles:A", fallback: lower)
        expect(lower.currentEditor() === window.firstResponder, "Hidden control is not revived")
        first.isHidden = false
        first.removeFromSuperview()
        state.restore(in: window, root: root, context: "profiles:A", fallback: lower)
        expect(lower.currentEditor() === window.firstResponder, "Detached original control is not revived")
        root.addSubview(first)
        let sheet = TestWindow(); let nested = TestWindow()
        window.simulatedSheet = sheet; sheet.simulatedSheet = nested
        expect(!state.restore(in: window, root: root, context: "profiles:A"), "A replacement sheet blocks queued restoration")
        SettingsFocusState.cancelAttachedSheets(of: window)
        expect(window.simulatedSheet == nil && sheet.simulatedSheet == nil && window.ended == [.cancel] && sheet.ended == [.cancel], "Parent close cancels innermost sheet before parent, never approving it")
        state.forget()
        state.restore(in: window, root: root, context: "profiles:A", fallback: lower)
        expect(lower.currentEditor() === window.firstResponder, "Reopened Settings cannot reuse retired original bookmark")
        let native = SettingsNativeWindow()
        expect(!native.responds(to: #selector(NSWindow.toggleToolbarShown(_:))), "Preference pane navigation cannot be hidden by toolbar command")
        print("Settings focus: \(assertions) assertions passed")
    }
}
