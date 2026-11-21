import AppKit
import Testing
@testable import Parc

struct PasteStyleCommandTests {
    @MainActor private final class Page: NSView {
        var mainFrame = true
        var requests = 0
        override var acceptsFirstResponder: Bool { true }
        @objc func pasteAndMatchStyle(_ sender: Any?) { requests += 1 }
        @objc func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            item.action == #selector(pasteAndMatchStyle(_:)) && mainFrame
        }
    }

    @MainActor private final class Fixture {
        let window = CommandBarTestSupport.borderlessWindow()
        let page = Page(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let item = NSMenuItem(title: "Paste and Match Style", action: WebpageEditCommands.pasteMatchingStyle,
                              keyEquivalent: "")

        init() throws {
            window.contentView?.addSubview(page)
            try #require(window.makeFirstResponder(page))
        }
    }

    @Test(arguments: [false, true])
    @MainActor func theFocusedPageControlsPasteMatchingStyle(mainFrame: Bool) throws {
        let fixture = try Fixture()
        fixture.page.mainFrame = mainFrame
        #expect(WebpageEditCommands.canPasteMatchingStyle(fixture.item, in: fixture.window) == mainFrame)
        WebpageEditCommands.pasteMatchingStyle(from: fixture.item, in: fixture.window)
        #expect(fixture.page.requests == (mainFrame ? 1 : 0))
    }

    @Test @MainActor func nativeTextKeepsItsOwnPasteMatchingStyle() throws {
        let fixture = try Fixture()
        let text = NSTextView(frame: fixture.page.frame)
        fixture.window.contentView?.addSubview(text)
        try #require(fixture.window.makeFirstResponder(text))
        #expect(WebpageEditCommands.pageTarget(in: fixture.window) == nil)
        #expect(!WebpageEditCommands.canPasteMatchingStyle(fixture.item, in: fixture.window))
    }

    @Test @MainActor func aFocusedPageIsFoundBeforeItsTextAncestor() throws {
        let fixture = try Fixture()
        let text = NSTextView(frame: fixture.page.frame)
        fixture.window.contentView?.addSubview(text)
        text.addSubview(fixture.page)
        try #require(fixture.window.makeFirstResponder(fixture.page))
        #expect(WebpageEditCommands.pageTarget(in: fixture.window) === fixture.page)
    }
}

extension PasteStyleCommandTests {
    @Test(arguments: [false, true])
    @MainActor func theLegacyPasteEquivalentFollowsTheVisibleBinding(customized: Bool) throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let menu = NSMenu(title: "Edit")
        let registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
        registry.configure(directory: root)
        let action = WebpageEditCommands.pasteMatchingStyle
        let main = NSMenuItem(title: "Paste and Match Style", action: action, keyEquivalent: "v")
        main.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(main)
        registry.register(main, group: "Edit")
        let equivalent = NSMenuItem(title: main.title, action: action, keyEquivalent: "v")
        let alternate = KeyboardShortcut(key: "v", flags: [.command, .option, .shift])
        equivalent.keyEquivalentModifierMask = alternate.flags
        equivalent.isHidden = true
        equivalent.allowsKeyEquivalentWhenHidden = true
        menu.addItem(equivalent)
        registry.registerEquivalent(equivalent, for: "pasteAsPlainText:", shortcut: alternate)
        if customized { try registry.set(KeyboardShortcut(key: "p", flags: [.command, .option]), for: "pasteAsPlainText:") }
        #expect(main.keyEquivalent == (customized ? "p" : "v"))
        #expect(equivalent.keyEquivalent == (customized ? "" : "v"))
        #expect(registry.priority(for: "pasteAsPlainText:") == .preferWebsites)
        #expect(registry.commands.filter { $0.id == "pasteAsPlainText:" }.count == 1)
    }
}
