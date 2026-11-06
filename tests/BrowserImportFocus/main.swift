import AppKit

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
        print("Browser import focus: 9 checks passed")
    }
}
