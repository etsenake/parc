import AppKit

@MainActor private final class ActiveApplication: NSApplication {
    weak var browser: NSWindow?
    override var isActive: Bool { true }
    override var mainWindow: NSWindow? { browser }
}
@MainActor private final class BrowserWindow: NSWindow {
    var key = true
    override var isVisible: Bool { true }
    override var isKeyWindow: Bool { key }
    override var isMainWindow: Bool { true }
}
@MainActor private final class KeyGatedTarget: NSObject, NSMenuItemValidation {
    let browser: BrowserWindow
    var runs = 0
    init(browser: BrowserWindow) { self.browser = browser }
    @objc func showReleaseNotes(_ sender: Any?) { runs += 1 }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { browser.key }
}

@main @MainActor struct MenuCommandAvailabilityTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        let app = ActiveApplication.shared as! ActiveApplication
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-menu-availability-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let main = NSMenu(), help = NSMenu(title: "Help")
        let parent = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        parent.submenu = help; main.addItem(parent); app.mainMenu = main
        let browser = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [], backing: .buffered, defer: false)
        browser.isReleasedWhenClosed = false; app.browser = browser
        let target = KeyGatedTarget(browser: browser)
        let item = NSMenuItem(title: "Release Notes", action: #selector(KeyGatedTarget.showReleaseNotes), keyEquivalent: "")
        item.target = target; help.addItem(item)
        registry.register(item, group: "Help")
        func listed() -> KeyboardShortcuts.MenuCommand? { registry.menuCommands(in: browser).first { $0.id == "showReleaseNotes:" } }

        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 22))
        browser.contentView?.addSubview(field)
        expect(browser.makeFirstResponder(field), "The bar's field takes focus in its browser")
        guard let row = listed() else { preconditionFailure("Release Notes is listed") }
        expect(registry.canPerformMenuCommand(row), "A key-gated row is offered while a field in its key browser has focus")
        expect(registry.performMenuCommand(row) && target.runs == 1, "Choosing it opens the page once")
        browser.key = false
        expect(!registry.canPerformMenuCommand(row) && !registry.performMenuCommand(row) && target.runs == 1,
               "A browser that isn't key refuses the row")
        browser.key = true
        app.browser = nil
        expect(!registry.canPerformMenuCommand(row), "Another main window refuses the row")
        app.browser = browser
        registry.register(NSMenuItem(title: "New Space…", action: #selector(NSResponder.cancelOperation(_:)), keyEquivalent: ""),
                          group: "Help")
        expect(!registry.canPerformMenuCommand(row), "A registry change refuses the old row")
        guard let reread = listed() else { preconditionFailure("Release Notes is still listed") }
        expect(registry.canPerformMenuCommand(reread), "A row read again after the change is offered")
        help.removeItem(item)
        expect(!registry.canPerformMenuCommand(reread), "A detached item is refused")
        expect(listed() == nil, "A detached item leaves the list")
        print("PASS: \(checks) command-bar menu availability assertions")
    }
}
