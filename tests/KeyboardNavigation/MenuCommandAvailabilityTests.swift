import AppKit

/// An active app whose main window is the test browser, without activating.
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
/// A validator that needs its browser to be key, as Edit Theme…, Back and Zoom
/// do. The command bar's own panel takes key from that browser while it's open.
@MainActor private final class KeyGatedTarget: NSObject, NSMenuItemValidation {
    let browser: BrowserWindow
    var runs = 0
    init(browser: BrowserWindow) { self.browser = browser }
    @objc func editTheme(_ sender: Any?) { runs += 1 }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { browser.key }
}

@main @MainActor struct MenuCommandAvailabilityTests {
    static func main() {
        let app = ActiveApplication.shared as! ActiveApplication
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-menu-availability-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let main = NSMenu(), spaces = NSMenu(title: "Spaces")
        let parent = NSMenuItem(title: "Spaces", action: nil, keyEquivalent: "")
        parent.submenu = spaces; main.addItem(parent); app.mainMenu = main
        let browser = BrowserWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        browser.isReleasedWhenClosed = false; app.browser = browser
        let target = KeyGatedTarget(browser: browser)
        let item = NSMenuItem(title: "Edit Theme…", action: #selector(KeyGatedTarget.editTheme), keyEquivalent: "")
        item.target = target; spaces.addItem(item)
        registry.register(item, group: "Spaces")
        func listed() -> KeyboardShortcuts.MenuCommand? { registry.menuCommands(in: browser).first { $0.id == "editTheme:" } }

        // The bar reads its list as it opens, while its browser is still key.
        guard let row = listed() else { preconditionFailure("Edit Theme… is listed") }
        expect(row.wasAvailable, "A list read while the browser is key records the command as available")
        expect(registry.canPerformMenuCommand(row), "Available before the panel takes key")
        browser.key = false
        expect(!registry.canPerformMenuCommand(row), "Once the panel holds key, the live check alone dims the row")
        expect(registry.canPerformMenuCommand(row, availableAtOpen: row.wasAvailable), "The open-time answer keeps the row offered")
        expect(listed()?.wasAvailable == false, "A list read again while the panel holds key cannot stand in for it")
        expect(!registry.performMenuCommand(row) && target.runs == 0, "Dispatch never uses the open-time answer")
        // Choosing the row dismisses the panel and its browser is key again.
        browser.key = true
        expect(registry.performMenuCommand(row) && target.runs == 1, "The chosen row runs once its browser is key")
        app.browser = nil
        expect(!registry.canPerformMenuCommand(row, availableAtOpen: true), "Another main window refuses the row")
        app.browser = browser
        registry.register(NSMenuItem(title: "New Space…", action: #selector(NSResponder.cancelOperation(_:)), keyEquivalent: ""),
                          group: "Spaces")
        expect(!registry.canPerformMenuCommand(row, availableAtOpen: true), "A registry change refuses the old row")
        // The bar reads its list again after a registry change, with its panel key.
        browser.key = false
        guard let reread = listed() else { preconditionFailure("Edit Theme… is still listed") }
        expect(!reread.wasAvailable && registry.canPerformMenuCommand(reread, availableAtOpen: row.wasAvailable),
               "A row read again while the panel holds key keeps the open-time answer by command ID")
        spaces.removeItem(item)
        expect(!registry.canPerformMenuCommand(reread, availableAtOpen: true), "A detached item is refused despite its open-time answer")
        expect(listed() == nil, "A detached item leaves the list")
        print("PASS: \(checks) command-bar menu availability assertions")
    }
}
