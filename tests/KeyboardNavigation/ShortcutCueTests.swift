import AppKit

@main struct ShortcutCueTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = KeyboardShortcuts(); registry.configure(directory: directory)
        let menu = NSMenu(title: "Component"); NSApp.mainMenu = menu
        let item = NSMenuItem(title: "Component Action", action: NSSelectorFromString("componentAction:"), keyEquivalent: "j")
        item.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(item); registry.register(item, group: "Component")
        try registry.setPriority(.useBoth, for: "componentAction:")
        let command = PCNativeShortcutCommand(item: item, revision: UInt64(registry.revision), priority: .useBoth)
        expect(registry.settingsCommandID(for: command) == "componentAction:", "Exact registered menu identity resolves Settings target")
        let other = NSMenuItem(title: item.title, action: item.action, keyEquivalent: item.keyEquivalent)
        let impostor = PCNativeShortcutCommand(item: other, revision: command.revision, priority: command.priority)
        expect(registry.settingsCommandID(for: impostor) == nil, "Same title and selector do not authorize a replacement item")
        menu.removeItem(item)
        expect(registry.settingsCommandID(for: command) == nil, "Detached menu cannot be edited through an old cue")
        menu.addItem(item)
        try registry.setPriority(.preferParc, for: "componentAction:")
        expect(registry.settingsCommandID(for: command) == nil, "Changed priority/revision rejects old cue")
        let current = PCNativeShortcutCommand(item: item, revision: UInt64(registry.revision), priority: .preferParc)
        expect(registry.settingsCommandID(for: current) == "componentAction:", "New exact identity is usable")

        let settings = ShortcutsSettingsView(shortcuts: registry)
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        let search = descendants(settings).compactMap { $0 as? ShortcutSearchHeader }.first!.field
        search.stringValue = "does not match"
        settings.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        let before = registry.revision
        expect(settings.selectCommand("componentAction:"), "Cue selects the actual command despite an old search filter")
        expect(search.stringValue.isEmpty, "Selection clears the stale filter")
        let table = descendants(settings).compactMap { $0 as? NSTableView }.first!
        expect(table.selectedRow >= 0, "Original command is visibly selected")
        expect(descendants(settings).compactMap { $0 as? NSTextField }.contains(where: { $0.stringValue == "Component Action" }), "Command detail is visible")
        expect(!descendants(settings).compactMap { $0 as? ShortcutRecorderView }.contains(where: \.isRecording), "Opening editor does not begin recording")
        expect(!settings.selectCommand("missing:"), "Unregistered command refuses targeted editing")
        expect(registry.revision == before, "Selecting and revealing never changes binding or priority")

        let hint = ShortcutPriorityHintView(title: "Component Action", shortcut: "⌥⌘J", canEdit: true, theme: SpaceTheme(),
            basicBackground: nil)
        expect(!hint.acceptsFirstResponder, "Cue cannot take editor focus")
        expect(hint.originalWindow == nil && hint.hitTest(NSPoint(x: 300, y: 300)) == nil, "Unpresented cue has no input target")
        expect(!hint.containsPointer, "Unpresented cue cannot extend native lifetime")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 130), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        expect(!hint.present(in: window) && window.childWindows?.isEmpty != false, "A window that is not key cannot own a cue")
        window.close()
        print("\(checks) shortcut cue component assertions passed; no browser, renderer or Apple Events.")
    }
}
