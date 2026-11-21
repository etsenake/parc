import AppKit
import ParcEngine
import Testing
@testable import Parc
@testable import ParcCore

struct ShortcutCueTests {
    enum Ownership: CaseIterable { case original, detached, replaced, revised }

    @Test(arguments: Ownership.allCases)
    @MainActor func aCueRevealsOnlyItsOriginalRegisteredCommand(ownership: Ownership) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let menu = NSMenu(title: "Component")
        let registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
        registry.configure(directory: directory)
        let id = "componentAction:"
        let item = NSMenuItem(title: "Component Action", action: NSSelectorFromString(id), keyEquivalent: "j")
        item.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(item)
        registry.register(item, group: menu.title)
        try registry.setPriority(.useBoth, for: id)
        let target = ownership == .replaced ? NSMenuItem(title: item.title, action: item.action, keyEquivalent: "j") : item
        let command = PCNativeShortcutCommand(item: target, revision: UInt64(registry.revision), priority: .useBoth)
        if ownership == .detached { menu.removeItem(item) }
        if ownership == .revised { try registry.setPriority(.preferParc, for: id) }
        #expect(registry.settingsCommandID(for: command) == (ownership == .original ? id : nil))
    }

    @Test @MainActor func anUnpresentedCueCannotTakeKeyboardOrPointerFocus() {
        _ = NSApplication.shared
        let cue = ShortcutPriorityHintView(title: "Component Action", shortcut: "⌥⌘J", canEdit: true, theme: SpaceTheme(),
                                           basicBackground: nil)
        #expect(!cue.acceptsFirstResponder)
        #expect(cue.originalWindow == nil)
        #expect(!cue.containsPointer)
        #expect(cue.hitTest(NSPoint(x: 300, y: 300)) == nil)
    }
}
