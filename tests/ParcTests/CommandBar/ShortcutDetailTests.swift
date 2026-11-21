import AppKit
import Testing
@testable import Parc

struct ShortcutDetailTests {
    @MainActor private final class Window: NSWindow {
        var permitsCommands = true
        override var isKeyWindow: Bool { permitsCommands }
        override var isVisible: Bool { true }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "Parc.ShortcutDetail." + UUID().uuidString
        let registry: KeyboardShortcuts
        let view: ShortcutsSettingsView
        let window: Window
        let caps: ShortcutKeycapView
        let picker: NSPopUpButton

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let menu = NSMenu(title: "File")
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            for (id, title, key) in [("closeTab:", "Archive Tab", "w"), ("captureFullPage:", "Capture Full Page", "")] {
                let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = .command
                menu.addItem(item)
                registry.register(item, group: menu.title)
            }
            view = ShortcutsSettingsView(shortcuts: registry, numberedTargetDefaults: try #require(UserDefaults(suiteName: suite)))
            window = Window(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            caps = try #require(view.subviews.compactMap { $0 as? ShortcutKeycapView }.first)
            picker = try #require(view.subviews.compactMap { $0 as? NSPopUpButton }.first)
        }

        deinit {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        func removeAction() throws -> NSMenuItem {
            try #require(view.commandMenu(for: "closeTab:")?.items.first { $0.title == "Remove Shortcut" })
        }

        func invoke(_ item: NSMenuItem) throws {
            _ = NSApp.sendAction(try #require(item.action), to: item.target, from: item)
        }
    }

    @Test @MainActor func theIntroductionShowsArtworkWithoutABinding() throws {
        let fixture = try Fixture()
        #expect(fixture.caps.presentation == .introduction)
        #expect(fixture.caps.symbols.isEmpty)
        #expect(fixture.caps.accessibilityValue() as? String == "Customize keyboard shortcuts")
        #expect(fixture.picker.isHidden)
    }

    @Test(arguments: ["closeTab:", "captureFullPage:"])
    @MainActor func detailShowsTheSelectedCommandsRealBinding(id: String) throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand(id))
        let chord = fixture.registry.shortcut(for: id)
        #expect(fixture.caps.presentation == (chord == nil ? .unassigned : .binding))
        #expect(fixture.caps.accessibilityValue() as? String == (chord?.spokenDisplay ?? "No shortcut"))
        #expect(fixture.picker.isHidden == (chord == nil))
    }

    @Test @MainActor func aSavedConflictLeavesPriorityEditable() throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand("captureFullPage:"))
        let duplicate = try #require(fixture.registry.shortcut(for: "closeTab:"))
        let tables = fixture.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTableView }
        let table = try #require(tables.first)
        let recorders = (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) }
            .flatMap(\.subviews).compactMap { $0 as? ShortcutRecorderView }
        let recorder = try #require(recorders.first { $0.identifier?.rawValue == "captureFullPage:" })
        try #require(recorder.onChange?(duplicate) == true)
        #expect(fixture.caps.isInConflict)
        #expect(!fixture.picker.isHidden)
        #expect(fixture.picker.isEnabled)
    }

    @Test(arguments: [false, true])
    @MainActor func aShortcutMenuNeedsTheOriginalKeyWindow(key: Bool) throws {
        let fixture = try Fixture()
        let item = try fixture.removeAction()
        fixture.window.permitsCommands = key
        try fixture.invoke(item)
        #expect((fixture.registry.shortcut(for: "closeTab:") == nil) == key)
    }

    @Test @MainActor func aMenuReceiptCannotRemoveALaterBinding() throws {
        let fixture = try Fixture()
        let item = try fixture.removeAction()
        let latest = KeyboardShortcut(key: "j", flags: [.control, .command])
        try fixture.registry.set(latest, for: "closeTab:")
        try fixture.invoke(item)
        #expect(fixture.registry.shortcut(for: "closeTab:") == latest)
    }

    @Test @MainActor func editingAnUnselectedRowKeepsTheSelectedDetail() throws {
        let fixture = try Fixture()
        try #require(fixture.view.selectCommand("captureFullPage:"))
        let before = fixture.caps.accessibilityValue() as? String
        try fixture.invoke(fixture.removeAction())
        #expect(fixture.registry.shortcut(for: "closeTab:") == nil)
        #expect(fixture.caps.accessibilityValue() as? String == before)
    }
}
