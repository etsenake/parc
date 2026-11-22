import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit

@MainActor
struct SplitViewMenuTests {
    @MainActor private final class Menu {
        let delegate = AppDelegate()
        let registry: KeyboardShortcuts
        let root: NSMenu

        init() {
            _ = NSApplication.shared
            var menu: NSMenu?
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            root = delegate.buildMenus(shortcuts: registry, install: false, initialSpaces: BrowserState.initial().spaces)
            menu = root
        }

        func viewItem(_ title: String) throws -> NSMenuItem {
            let view = try #require(root.item(withTitle: "View")?.submenu)
            return try #require(view.item(withTitle: title))
        }
    }

    @Test func splitThisPaneIsInViewAndUsesControlShiftBackslash() throws {
        let menu = Menu()
        let item = try menu.viewItem("Split This Pane")
        #expect(!item.isHidden)
        #expect(item.target === menu.delegate)
        #expect(item.keyEquivalent == "\\")
        #expect(item.keyEquivalentModifierMask == [.control, .shift])
        let id = try #require(item.action.map(NSStringFromSelector))
        #expect(menu.registry.activeShortcut(for: id) == KeyboardShortcut(key: "\\", flags: [.control, .shift]))
        #expect(menu.registry.priority(for: id) == .useBoth)
    }

    @Test(arguments: ["Widen Current Split", "Narrow Current Split", "Make All Split Panes Equal"])
    func resizeCommandsAreHiddenButCanBeAssignedAShortcut(title: String) throws {
        let menu = Menu()
        let item = try menu.viewItem(title)
        let id = try #require(item.action.map(NSStringFromSelector))
        #expect(item.isHidden)
        #expect(item.allowsKeyEquivalentWhenHidden)
        #expect(item.keyEquivalent.isEmpty)
        #expect(menu.registry.shortcut(for: id) == nil)
        #expect(menu.registry.commands.contains { $0.id == id })
    }
}
