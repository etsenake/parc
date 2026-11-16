import AppKit

@MainActor private final class FormatEditor: NSView, NSMenuItemValidation {
    var available = true
    var performed: [TextFormatCommand] = []
    override var acceptsFirstResponder: Bool { true }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { available }
    @objc func formatText(_ sender: Any?) { if let command = TextFormatCommand(sender) { performed.append(command) } }
}
@MainActor private final class PageView: NSView {
    override var acceptsFirstResponder: Bool { true }
    @objc func underline(_ sender: Any?) {}
    @objc func pasteAndMatchStyle(_ sender: Any?) {}
}
@MainActor private final class ParcTarget: NSObject, NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool { true }
    @objc func parcCommand(_ sender: Any?) {}
}

@main @MainActor struct FormatCommandTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let parc = ParcTarget()
        let collisions: [(String, String, NSEvent.ModifierFlags)] = [
            ("newTab:", "t", .command), ("restoreTab:", "t", [.command, .shift]), ("downloads:", "j", [.command, .shift]),
            ("goBack:", "[", .command), ("goForward:", "]", .command), ("zoomIn:", "+", .command), ("zoomOut:", "-", .command),
            ("copyCurrentURL:", "c", [.command, .shift]), ("inspectElements:", "c", [.command, .option]),
            ("nextTab", "}", .command), ("previousTab", "{", .command)
        ]
        func build(_ registry: KeyboardShortcuts, target: AnyObject? = nil) -> (NSMenuItem, [TextFormatCommand: NSMenuItem]) {
            let main = NSMenu(), parent = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            let edit = NSMenu(title: "Edit"); parent.submenu = edit; main.addItem(parent); NSApp.mainMenu = main
            for (id, key, flags) in collisions {
                let item = NSMenuItem(title: id, action: #selector(ParcTarget.parcCommand(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags; item.target = parc; edit.addItem(item)
                registry.register(item, group: "Parc", bindingID: id)
            }
            var items: [TextFormatCommand: NSMenuItem] = [:]
            let format = TextFormatMenu.add(to: edit) { item, command in
                item.target = target
                registry.register(item, group: "Format", bindingID: command.bindingID, title: command.commandTitle, discoverable: false)
                items[command] = item
            }
            return (format, items)
        }
        func titles(_ menu: NSMenu?) -> [String] { menu?.items.map { $0.isSeparatorItem ? "-" : $0.title } ?? [] }
        func chord(_ item: NSMenuItem?) -> KeyboardShortcut? {
            guard let item, !item.keyEquivalent.isEmpty else { return nil }
            return KeyboardShortcut(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask)
        }

        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let (format, items) = build(registry)
        expect(format.title == "Format" && format.menu?.items.last === format, "Format is the last Edit submenu")
        expect(titles(format.submenu) == ["Font", "-", "Heading 1", "Heading 2", "Heading 3", "Body", "-",
                                          "Bulleted List", "Numbered List", "-", "Indentation", "-", "Add Link…"], "Format follows Apple's grouping with Parc's own styles")
        expect(titles(format.submenu?.item(withTitle: "Font")?.submenu) == ["Bold", "Italic", "Underline", "Strikethrough", "-", "Bigger", "Smaller"], "Font holds emphasis, then size steps")
        expect(titles(format.submenu?.item(withTitle: "Indentation")?.submenu) == ["Increase", "Decrease"], "Indentation holds the list indent pair")
        expect(items.count == TextFormatCommand.allCases.count && items.allSatisfy { command, item in
            item.action == TextFormatCommand.action && item.target == nil && item.tag == command.rawValue && TextFormatCommand(item) == command
        }, "Every command is one responder-chain item with no fixed target")
        expect(TextFormatCommand(NSMenuItem(title: "Other", action: NSSelectorFromString("other:"), keyEquivalent: "")) == nil, "Other actions are never mistaken for formatting")

        let expected: [TextFormatCommand: KeyboardShortcut] = [
            .bold: .init(key: "b", flags: .command), .italic: .init(key: "i", flags: .command), .underline: .init(key: "u", flags: .command),
            .heading1: .init(key: "h", flags: [.command, .shift]), .body: .init(key: "b", flags: [.command, .shift]),
            .bulletedList: .init(key: "7", flags: [.command, .shift]), .numberedList: .init(key: "9", flags: [.command, .shift]),
            .link: .init(key: "k", flags: .command)
        ]
        for command in TextFormatCommand.allCases {
            expect(chord(items[command]) == expected[command], "\(command.title) carries only its free standard chord")
            expect(registry.shortcut(for: command.bindingID) == expected[command], "\(command.title) registry default")
        }
        expect(KeyboardShortcuts.formatShortcuts.count == expected.count &&
               expected.allSatisfy { KeyboardShortcuts.formatShortcuts[$0.key.bindingID] == $0.value }, "Registry defaults are the menu's only chord source")
        for (id, key, flags) in collisions {
            let parcChord = KeyboardShortcut(key: key, flags: flags)
            expect(!registry.isConflicting(id) && chord(format.menu?.items.first { $0.title == id }) == parcChord, "\(id) keeps its own chord")
            expect(!items.values.contains { chord($0) == parcChord }, "No Format item takes \(parcChord.display)")
        }
        for command in TextFormatCommand.allCases where expected[command] != nil {
            expect(!registry.isConflicting(command.bindingID), "\(command.title) has a conflict-free default")
        }
        for command in [TextFormatCommand.bold, .italic, .underline] {
            expect(expected[command]!.isReserved, "\(command.title) is a reserved text-editing chord")
            expect(!registry.commands.contains { $0.id == command.bindingID }, "\(command.title) stays fixed like Undo, outside Settings")
            do { try registry.set(KeyboardShortcut(key: "j", flags: [.command, .control]), for: command.bindingID); expect(false, "Fixed chord accepted a rebind") }
            catch { count += 1 }
        }
        for command in TextFormatCommand.allCases where ![.bold, .italic, .underline].contains(command) {
            let entry = registry.commands.first { $0.id == command.bindingID }
            expect(entry?.group == "Format" && entry?.title == command.commandTitle, "\(command.commandTitle) is editable in Settings")
            expect(registry.priority(for: command.bindingID) == .preferWebsites, "\(command.commandTitle) lets websites go first")
        }
        expect(registry.menuCommands(in: NSWindow()).allSatisfy { !$0.id.hasPrefix("format") }, "Command search omits focus-bound formatting")

        func encoded(_ chord: KeyboardShortcut) -> [String: Any] { ["shortcut": ["key": chord.key, "modifiers": chord.modifiers]] }
        let file = root.appendingPathComponent("keyboard-shortcuts.json")
        let heading = KeyboardShortcut(key: "h", flags: [.command, .shift])
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": ["newTab:": encoded(heading)]]).write(to: file)
        let saved = KeyboardShortcuts(); saved.configure(directory: root)
        let (savedFormat, savedItems) = build(saved)
        expect(saved.loadError == nil && saved.shortcut(for: "newTab:") == heading && chord(savedFormat.menu?.items.first { $0.title == "newTab:" }) == heading,
               "A saved custom chord survives the new Format defaults")
        expect(saved.shortcut(for: "formatHeading1") == nil && savedItems[.heading1]?.keyEquivalent.isEmpty == true, "Heading 1 never steals a saved chord")
        expect(saved.shortcut(for: "formatBody") == expected[.body], "Unclaimed Format defaults still apply")
        let migrated = try Data(contentsOf: file)
        let document = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
        expect(document["formatShortcutDefaults"] as? Int == 1, "Format migration marker is durable")
        saved.configure(directory: root)
        let repeated = try Data(contentsOf: file)
        expect(repeated == migrated, "Format migration is byte-idempotent")
        try FileManager.default.removeItem(at: file)

        let editor = FormatEditor()
        let targeted = KeyboardShortcuts(); targeted.configure(directory: root)
        let (_, targetedItems) = build(targeted, target: editor)
        func event(_ code: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1, windowNumber: 0, context: nil,
                             characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)!
        }
        for (code, key) in [(UInt16(11), "b"), (34, "i"), (32, "u")] {
            expect(targeted.nativeCommand(for: event(code, key, .command), editable: true) == nil,
                   "Command-\(key.uppercased()) never enters Parc's pre-page interception, so web editors keep it")
        }
        let headingCommand = targeted.nativeCommand(for: event(4, "h", [.command, .shift]), editable: true)
        expect(headingCommand?.item === targetedItems[.heading1] && headingCommand?.priority == .preferWebsites,
               "A Parc editor's Heading 1 waits for the page to decline Shift-Command-H")
        editor.available = false
        expect(targeted.nativeCommand(for: event(4, "h", [.command, .shift]), editable: true) == nil, "A refusing editor offers no command")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let page = PageView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)), text = NSTextView(frame: NSRect(x: 100, y: 0, width: 100, height: 100))
        let note = FormatEditor(frame: NSRect(x: 200, y: 0, width: 100, height: 100)), body = NSTextView(frame: note.bounds)
        note.addSubview(body); [page, text, note].forEach(window.contentView!.addSubview)
        let probe = NSMenuItem(title: "Bold", action: TextFormatCommand.action, keyEquivalent: "")
        probe.tag = TextFormatCommand.bold.rawValue
        expect(window.makeFirstResponder(page) && !page.tryToPerform(TextFormatCommand.action, with: probe), "A web page's responder chain has no formatting owner")
        expect(window.makeFirstResponder(text) && !text.tryToPerform(TextFormatCommand.action, with: probe), "A plain text field has no formatting owner")
        expect(!text.responds(to: TextFormatCommand.action) && !page.responds(to: TextFormatCommand.action), "Formatting never uses a selector that native text or the engine view answer")
        expect(window.makeFirstResponder(body) && body.tryToPerform(TextFormatCommand.action, with: probe) && note.performed == [.bold],
               "The owning editor receives the command through the responder chain")
        window.close()

        let reset = format.submenu!
        reset.item(withTitle: "Heading 1")!.state = .on
        let link = reset.item(withTitle: "Add Link…")!; link.title = TextFormatCommand.editLinkTitle
        reset.delegate?.menuNeedsUpdate?(reset)
        expect(reset.item(withTitle: "Heading 1")?.state == .off && link.title == TextFormatCommand.addLinkTitle,
               "Opening the menu clears stale checkmarks from a previous editor")
        print("FormatCommandTests: \(count) checks passed")
    }
}
