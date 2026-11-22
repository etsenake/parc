import AppKit
import Testing
@testable import Parc

struct ShortcutRecorderSettingsTests {
    @MainActor private final class Window: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isVisible: Bool { true }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry: KeyboardShortcuts
        let settings: ShortcutsSettingsView
        let window: Window
        let table: NSTableView
        let input: ShortcutRecorderView
        let caps: ShortcutKeycapView
        let first = KeyboardShortcut(key: "a", flags: [.command, .option])
        let second = KeyboardShortcut(key: "b", flags: [.command, .option])

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let menu = NSMenu(title: "Test")
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            for (id, key) in [("alpha:", "a"), ("beta:", "b")] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = [.command, .option]
                menu.addItem(item)
                registry.register(item, group: "Test")
            }
            settings = ShortcutsSettingsView(shortcuts: registry)
            window = Window(contentRect: NSRect(x: 0, y: 0, width: 260, height: 100), styleMask: [.titled],
                            backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = settings
            table = try #require(Self.descendant(NSTableView.self, in: settings))
            let cell = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: true))
            input = try #require(Self.descendant(ShortcutRecorderView.self, in: cell))
            table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            input.onBegin?()
            caps = try #require(Self.descendant(ShortcutKeycapView.self, in: settings))
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        static func descendant<T: NSView>(_ type: T.Type, in parent: NSView) -> T? {
            if let value = parent as? T { return value }
            return parent.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }

        func modifiers(_ flags: NSEvent.ModifierFlags) throws {
            let event = try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 55))
            input.flagsChanged(with: event)
        }
    }

    @Test @MainActor func aSettingsRecorderTakesFocusWithoutReplacingItsRow() throws {
        let fixture = try Fixture()
        defer { fixture.input.cancelRecording() }
        #expect(fixture.window.makeFirstResponder(fixture.input))
        #expect(fixture.input.isRecording)
        #expect(fixture.window.firstResponder === fixture.input)
        #expect(!fixture.caps.acceptsFirstResponder)
    }

    @Test @MainActor func theDetailShowsTheHeldModifiersInPlaceAndKeepsItsContainer() throws {
        let fixture = try Fixture()
        defer { fixture.input.cancelRecording() }
        let frame = fixture.caps.frame
        #expect(fixture.window.makeFirstResponder(fixture.input))
        try fixture.modifiers([.control, .option, .shift, .command])
        #expect(fixture.caps.symbols == ["⌃", "⌥", "⇧", "⌘"])
        #expect(fixture.caps.frame == frame)
        #expect(fixture.caps.frame.width == 200)
        #expect(fixture.window.firstResponder === fixture.input)
        try fixture.modifiers([.command])
        #expect(fixture.caps.symbols == ["⌘"])
        #expect(fixture.caps.frame == frame)
    }

    @Test @MainActor func cancellingRestoresTheSavedChordInTheSameRegionWithoutWriting() throws {
        let fixture = try Fixture()
        let symbols = fixture.caps.symbols
        let frame = fixture.caps.frame
        let revision = fixture.registry.revision
        #expect(fixture.window.makeFirstResponder(fixture.input))
        try fixture.modifiers([.control, .command])
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 53))
        fixture.input.keyDown(with: escape)
        #expect(!fixture.input.isRecording)
        #expect(fixture.caps.symbols == symbols)
        #expect(fixture.caps.frame == frame)
        #expect(fixture.registry.shortcut(for: "alpha:") == fixture.first)
        #expect(fixture.registry.revision == revision)
    }

    @Test @MainActor func aChordAnotherCommandOwnsIsSavedAsAVisibleConflict() throws {
        let fixture = try Fixture()
        let revision = fixture.registry.revision
        #expect(fixture.input.onChange?(fixture.second) == true)
        #expect(fixture.input.isConflicting)
        #expect(fixture.registry.revision == revision + 1)
        #expect(fixture.registry.shortcut(for: "alpha:") == fixture.second)
        #expect(fixture.registry.activeShortcut(for: "alpha:") == nil)
    }

    @Test @MainActor func leavingThePaneKeepsTheSavedBindingAndItsConflict() throws {
        let fixture = try Fixture()
        _ = fixture.input.onChange?(fixture.second)
        let revision = fixture.registry.revision
        fixture.settings.endRecording()
        #expect(fixture.input.isConflicting)
        #expect(fixture.input.shortcut == fixture.second)
        #expect(fixture.registry.revision == revision)
    }
}
