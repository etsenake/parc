import AppKit
import Testing
@testable import Parc

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
