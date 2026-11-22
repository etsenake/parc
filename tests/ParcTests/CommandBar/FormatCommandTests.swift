import AppKit
import Testing
@testable import ParcKit

struct FormatCommandTests {
    @MainActor private final class Editor: NSView, NSMenuItemValidation {
        var available = true
        var performed: TextFormatCommand?
        override var acceptsFirstResponder: Bool { true }
        func validateMenuItem(_ item: NSMenuItem) -> Bool { available }
        @objc func formatText(_ sender: Any?) { performed = TextFormatCommand(sender) }
    }

    @MainActor private final class Fixture {
        let menu = NSMenu(title: "Edit")
        let editor = Editor(frame: .zero)
        let registry: KeyboardShortcuts
        let format: NSMenuItem
        let items: [TextFormatCommand: NSMenuItem]

        init() {
            _ = NSApplication.shared
            let root = menu
            let registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            self.registry = registry
            let editor = editor
            var items: [TextFormatCommand: NSMenuItem] = [:]
            format = TextFormatMenu.add(to: root) { item, command in
                item.target = editor
                registry.register(item, group: "Format", bindingID: command.bindingID,
                                  title: command.commandTitle, discoverable: false)
                items[command] = item
            }
            self.items = items
        }
    }

    @Test(arguments: TextFormatCommand.allCases)
    @MainActor func everyFormatMenuItemKeepsItsMeaning(command: TextFormatCommand) throws {
        let fixture = Fixture()
        let item = try #require(fixture.items[command])
        #expect(TextFormatCommand(item) == command)
        #expect(fixture.registry.shortcut(for: command.bindingID) == KeyboardShortcuts.formatShortcuts[command.bindingID])
    }

    @Test(arguments: [(UInt16(11), "b"), (UInt16(34), "i"), (UInt16(32), "u")])
    @MainActor func standardTextChordsStayWithTheWebEditor(code: UInt16, key: String) {
        let fixture = Fixture()
        let event = CommandBarTestSupport.keyEvent(code, .command, characters: key)
        #expect(fixture.registry.nativeCommand(for: event, editable: true) == nil)
    }

    @Test(arguments: [false, true])
    @MainActor func headingOneNeedsAnAvailableFormattingOwner(available: Bool) {
        let fixture = Fixture()
        fixture.editor.available = available
        let event = CommandBarTestSupport.keyEvent(4, [.command, .shift], characters: "h")
        let command = fixture.registry.nativeCommand(for: event, editable: true)
        if available {
            #expect(command?.item === fixture.items[.heading1])
            #expect(command?.priority == .preferWebsites)
        } else {
            #expect(command == nil)
        }
    }

    @Test @MainActor func aFormattingActionFollowsTheFocusedEditor() throws {
        let fixture = Fixture()
        let window = CommandBarTestSupport.borderlessWindow()
        let body = NSTextView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        fixture.editor.addSubview(body)
        window.contentView = fixture.editor
        try #require(window.makeFirstResponder(body))
        let item = try #require(fixture.items[.bold])
        #expect(body.tryToPerform(TextFormatCommand.action, with: item))
        #expect(fixture.editor.performed == .bold)
    }

    @Test @MainActor func theCommandBarOmitsFocusBoundFormatting() {
        let fixture = Fixture()
        let window = CommandBarTestSupport.borderlessWindow()
        #expect(fixture.registry.menuCommands(in: window).allSatisfy { !$0.id.hasPrefix("format") })
    }
}

extension FormatCommandTests {
    static let collisionRows: [(String, String, NSEvent.ModifierFlags)] = [
            ("newTab:", "t", .command), ("restoreTab:", "t", [.command, .shift]), ("downloads:", "j", [.command, .shift]),
            ("goBack:", "[", .command), ("goForward:", "]", .command), ("zoomIn:", "+", .command), ("zoomOut:", "-", .command),
            ("copyCurrentURL:", "c", [.command, .shift]), ("inspectElements:", "c", [.command, .option]),
            ("nextTab", "}", .command), ("previousTab", "{", .command),
        ]

    @MainActor private final class ParcTarget: NSObject, NSMenuItemValidation {
        func validateMenuItem(_ item: NSMenuItem) -> Bool { true }
        @objc func parcCommand(_ sender: Any?) {}
    }

    @MainActor private final class PageView: NSView {
        override var acceptsFirstResponder: Bool { true }
        @objc func underline(_ sender: Any?) {}
        @objc func pasteAndMatchStyle(_ sender: Any?) {}
    }

    @MainActor private final class Bench {
        static let expected: [TextFormatCommand: KeyboardShortcut] = [
            .bold: .init(key: "b", flags: .command), .italic: .init(key: "i", flags: .command),
            .underline: .init(key: "u", flags: .command),
            .heading1: .init(key: "h", flags: [.command, .shift]), .body: .init(key: "b", flags: [.command, .shift]),
            .bulletedList: .init(key: "7", flags: [.command, .shift]), .numberedList: .init(key: "9", flags: [.command, .shift]),
            .link: .init(key: "k", flags: .command),
        ]

        let directory: URL
        let file: URL
        let parc = ParcTarget()
        let menu = NSMenu(title: "Edit")
        var registry: KeyboardShortcuts
        var format = NSMenuItem()
        var items: [TextFormatCommand: NSMenuItem] = [:]

        init() throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("keyboard-shortcuts.json")
            registry = KeyboardShortcuts(observesKeyboardLayout: false)
            registry = makeRegistry()
            build(target: nil)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        private func makeRegistry() -> KeyboardShortcuts {
            let registry = KeyboardShortcuts(mainMenu: { [menu] in menu }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            return registry
        }

        func rebuild(target: AnyObject? = nil) {
            registry = makeRegistry()
            build(target: target)
        }

        private func build(target: AnyObject?) {
            menu.removeAllItems()
            for (id, key, flags) in FormatCommandTests.collisionRows {
                let item = NSMenuItem(title: id, action: #selector(ParcTarget.parcCommand(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags
                item.target = parc
                menu.addItem(item)
                registry.register(item, group: "Parc", bindingID: id)
            }
            var items: [TextFormatCommand: NSMenuItem] = [:]
            let registry = registry
            format = TextFormatMenu.add(to: menu) { item, command in
                item.target = target
                registry.register(item, group: "Format", bindingID: command.bindingID,
                                  title: command.commandTitle, discoverable: false)
                items[command] = item
            }
            self.items = items
        }

        static func chord(_ item: NSMenuItem?) -> KeyboardShortcut? {
            guard let item, !item.keyEquivalent.isEmpty else { return nil }
            return KeyboardShortcut(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask)
        }

        static func titles(_ menu: NSMenu?) -> [String] { menu?.items.map { $0.isSeparatorItem ? "-" : $0.title } ?? [] }
    }

    @Test @MainActor func theFormatMenuFollowsAppleGroupingWithParcsOwnStyles() throws {
        let bench = try Bench()
        #expect(bench.format.title == "Format")
        #expect(bench.format.menu?.items.last === bench.format)
        #expect(Bench.titles(bench.format.submenu) == ["Font", "-", "Heading 1", "Heading 2", "Heading 3", "Body", "-",
                                                       "Bulleted List", "Numbered List", "-", "Indentation", "-", "Add Link…"])
        #expect(Bench.titles(bench.format.submenu?.item(withTitle: "Font")?.submenu)
                == ["Bold", "Italic", "Underline", "Strikethrough", "-", "Bigger", "Smaller"])
        #expect(Bench.titles(bench.format.submenu?.item(withTitle: "Indentation")?.submenu) == ["Increase", "Decrease"])
    }

    @Test @MainActor func everyCommandIsOneResponderChainItemWithNoFixedTarget() throws {
        let bench = try Bench()
        #expect(bench.items.count == TextFormatCommand.allCases.count)
        for (command, item) in bench.items {
            #expect(item.action == TextFormatCommand.action)
            #expect(item.target == nil)
            #expect(item.tag == command.rawValue)
            #expect(TextFormatCommand(item) == command)
        }
        #expect(TextFormatCommand(NSMenuItem(title: "Other", action: NSSelectorFromString("other:"), keyEquivalent: "")) == nil)
    }

    @Test(arguments: TextFormatCommand.allCases)
    @MainActor func eachCommandCarriesOnlyItsFreeStandardChord(command: TextFormatCommand) throws {
        let bench = try Bench()
        #expect(Bench.chord(bench.items[command]) == Bench.expected[command])
        #expect(bench.registry.shortcut(for: command.bindingID) == Bench.expected[command])
        if Bench.expected[command] != nil { #expect(!bench.registry.isConflicting(command.bindingID)) }
    }

    @Test @MainActor func theRegistryDefaultsAreTheMenusOnlyChordSource() {
        #expect(KeyboardShortcuts.formatShortcuts.count == Bench.expected.count)
        for (command, chord) in Bench.expected { #expect(KeyboardShortcuts.formatShortcuts[command.bindingID] == chord) }
    }

    @Test(arguments: FormatCommandTests.collisionRows.indices)
    @MainActor func aParcCommandKeepsItsChordAgainstFormatting(index: Int) throws {
        let bench = try Bench()
        let (id, key, flags) = FormatCommandTests.collisionRows[index]
        let chord = KeyboardShortcut(key: key, flags: flags)
        #expect(!bench.registry.isConflicting(id))
        #expect(Bench.chord(bench.menu.items.first { $0.title == id }) == chord)
        #expect(!bench.items.values.contains { Bench.chord($0) == chord })
    }

    @Test(arguments: [TextFormatCommand.bold, .italic, .underline])
    @MainActor func emphasisChordsAreReservedFixedAndOutsideSettings(command: TextFormatCommand) throws {
        let bench = try Bench()
        #expect(try #require(Bench.expected[command]).isReserved)
        #expect(!bench.registry.commands.contains { $0.id == command.bindingID })
        #expect(throws: (any Error).self) {
            try bench.registry.set(KeyboardShortcut(key: "j", flags: [.command, .control]), for: command.bindingID)
        }
    }

    @Test(arguments: TextFormatCommand.allCases.filter { ![.bold, .italic, .underline].contains($0) })
    @MainActor func theOtherCommandsAreEditableAndLetWebsitesGoFirst(command: TextFormatCommand) throws {
        let bench = try Bench()
        let entry = bench.registry.commands.first { $0.id == command.bindingID }
        #expect(entry?.group == "Format")
        #expect(entry?.title == command.commandTitle)
        #expect(bench.registry.priority(for: command.bindingID) == .preferWebsites)
    }

    @Test @MainActor func aSavedCustomChordSurvivesTheNewFormatDefaultsAndMigratesOnce() throws {
        let bench = try Bench()
        let heading = KeyboardShortcut(key: "h", flags: [.command, .shift])
        let saved: [String: Any] = ["version": 3, "overrides": ["newTab:": ["shortcut": ["key": heading.key, "modifiers": heading.modifiers]]]]
        try JSONSerialization.data(withJSONObject: saved).write(to: bench.file)
        bench.rebuild()
        let registry = bench.registry
        #expect(registry.loadError == nil)
        #expect(registry.shortcut(for: "newTab:") == heading)
        #expect(Bench.chord(bench.menu.items.first { $0.title == "newTab:" }) == heading)
        #expect(registry.shortcut(for: "formatHeading1") == nil)
        #expect(bench.items[.heading1]?.keyEquivalent.isEmpty == true)
        #expect(registry.shortcut(for: "formatBody") == Bench.expected[.body])
        let migrated = try Data(contentsOf: bench.file)
        let document = try #require(JSONSerialization.jsonObject(with: migrated) as? [String: Any])
        #expect(document["formatShortcutDefaults"] as? Int == 1)
        registry.configure(directory: bench.directory)
        #expect(try Data(contentsOf: bench.file) == migrated)
    }

    @Test @MainActor func aWebPageAndAPlainTextFieldHaveNoFormattingOwner() throws {
        let bench = try Bench()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let page = PageView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let text = NSTextView(frame: NSRect(x: 100, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(page)
        window.contentView?.addSubview(text)
        let probe = try #require(bench.items[.bold])
        #expect(window.makeFirstResponder(page))
        #expect(!page.tryToPerform(TextFormatCommand.action, with: probe))
        #expect(window.makeFirstResponder(text))
        #expect(!text.tryToPerform(TextFormatCommand.action, with: probe))
        #expect(!text.responds(to: TextFormatCommand.action) && !page.responds(to: TextFormatCommand.action))
    }

    @Test @MainActor func openingTheMenuClearsStaleCheckmarksAndLinkTitle() throws {
        let bench = try Bench()
        let submenu = try #require(bench.format.submenu)
        try #require(submenu.item(withTitle: "Heading 1")).state = .on
        let link = try #require(submenu.item(withTitle: "Add Link…"))
        link.title = TextFormatCommand.editLinkTitle
        submenu.delegate?.menuNeedsUpdate?(submenu)
        #expect(submenu.item(withTitle: "Heading 1")?.state == .off)
        #expect(link.title == TextFormatCommand.addLinkTitle)
    }
}
