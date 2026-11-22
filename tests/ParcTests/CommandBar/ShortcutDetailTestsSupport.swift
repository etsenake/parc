import AppKit
import Carbon.HIToolbox
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcCommandBar

enum ShortcutDetailTestsSupport {
    @MainActor final class Window: NSWindow {
        var permitsCommands = true
        override var isKeyWindow: Bool { permitsCommands }
        override var isVisible: Bool { true }
    }

    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry: KeyboardShortcuts
        let view: ShortcutsSettingsView
        let window: Window
        let caps: ShortcutKeycapView
        let picker: NSPopUpButton
        let defaults: UserDefaults

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let menu = NSMenu(title: "File")
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            for (id, title, key) in [("closeTab:", "Archive Tab", "w"), ("captureFullPage:", "Capture Full Page", ""), ("capturePage:", "Capture Portion…", "2"),
                                       ("nextSplitPane:", "Switch to next Split View", "")] {
                let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = .command
                menu.addItem(item)
                registry.register(item, group: menu.title)
            }
            for number in [1, 9] {
                let item = NSMenuItem(title: "Go to Sidebar Item " + String(number),
                    action: NSSelectorFromString("goToSidebarItem:"), keyEquivalent: String(number))
                item.keyEquivalentModifierMask = .command
                menu.addItem(item)
                registry.register(item, group: "Tabs", bindingID: NumberedTarget.itemBindingID(number))
            }
            defaults = try #require(TestDefaults("Parc.ShortcutDetail."))
            view = ShortcutsSettingsView(shortcuts: registry, numberedTargetDefaults: defaults)
            window = Window(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            caps = try #require(view.subviews.compactMap { $0 as? ShortcutKeycapView }.first)
            picker = try #require(view.subviews.compactMap { $0 as? NSPopUpButton }.first)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func removeAction() throws -> NSMenuItem {
            try #require(view.commandMenu(for: "closeTab:")?.items.first { $0.title == "Remove Shortcut" })
        }

        func button(_ title: String) throws -> NSButton {
            let matches = view.subviews.compactMap { $0 as? NSButton }
            return try #require(matches.first { $0.title == title })
        }

        func invoke(_ item: NSMenuItem) throws {
            _ = NSApp.sendAction(try #require(item.action), to: item.target, from: item)
        }
    }

    @MainActor static func labels(_ fixture: Fixture) -> [NSTextField] { fixture.view.subviews.compactMap { $0 as? NSTextField } }

    @MainActor static func table(_ view: ShortcutsSettingsView) throws -> NSTableView {
        let found: NSTableView? = view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTableView }.first
        return try #require(found)
    }

    @MainActor static func cell(_ id: String, in view: ShortcutsSettingsView) throws -> NSView {
        let table = try table(view)
        let found = (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) }.first {
            $0.subviews.contains { ($0 as? ShortcutRecorderView)?.identifier?.rawValue == id }
        }
        return try #require(found)
    }

    @MainActor static func recorder(_ id: String, in view: ShortcutsSettingsView) throws -> ShortcutRecorderView {
        try #require(try cell(id, in: view).subviews.compactMap { $0 as? ShortcutRecorderView }.first)
    }
}
