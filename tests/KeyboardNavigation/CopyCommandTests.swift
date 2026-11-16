import AppKit

@main struct CopyCommandTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ reason: String) { checks += 1; precondition(value(), reason) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keyboard-shortcuts.json")
        let registry = KeyboardShortcuts()
        let ids = ["copyCurrentURL:", "copyCurrentURLAsMarkdown:", "copyCurrentURLAsQuote:"]
        let flags: [NSEvent.ModifierFlags] = [[.command, .shift], [.command, .shift, .option], [.command, .shift, .control]]
        let menu = NSMenu(title: "Edit")
        for (index, id) in ids.enumerated() {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: "c")
            item.keyEquivalentModifierMask = flags[index]; menu.addItem(item); registry.register(item, group: "Edit")
        }
        let close = NSMenuItem(title: "Archive Tab", action: NSSelectorFromString("closeTab:"), keyEquivalent: "w")
        close.keyEquivalentModifierMask = .command; menu.addItem(close); registry.register(close, group: "File")
        let selectAll = NSMenuItem(title: "Select All", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a")
        selectAll.keyEquivalentModifierMask = .command; menu.addItem(selectAll); registry.register(selectAll, group: "Edit")
        registry.configure(directory: directory)
        expect(registry.priority(for: "closeTab:") == .preferParc, "Fresh Close Tab follows recovered overrideWebView priority")
        expect(registry.shortcut(for: "closeTab:") == KeyboardShortcut(key: "w", flags: .command), "Plural close retains existing original command binding")
        expect(registry.shortcut(for: "selectAll:") == KeyboardShortcut(key: "a", flags: .command), "Select All retains native Command-A")
        expect(!registry.commands.contains { $0.id == "selectAll:" }, "Native responder editing remains outside browser priority customization")
        for (index, id) in ids.enumerated() {
            expect(registry.priority(for: id) == .preferParc, "Fresh recovered browser priority")
            expect(registry.shortcut(for: id) == KeyboardShortcut(key: "c", flags: flags[index]), "Distinct default chord")
        }
        try registry.setPriority(.preferWebsites, for: ids[0])
        registry.configure(directory: directory)
        expect(registry.priority(for: ids[0]) == .preferWebsites, "Explicit website choice persists against browser default")
        try registry.setPriority(.useBoth, for: ids[1])
        try registry.set(nil, for: ids[2])
        registry.configure(directory: directory)
        expect(registry.priority(for: ids[1]) == .useBoth, "Both choice persists")
        expect(registry.shortcut(for: ids[2]) == nil && menu.items[2].keyEquivalent.isEmpty, "Disabled quote remains disabled in real menu")
        try registry.reset(ids[0]); try registry.reset(ids[2])
        expect(registry.priority(for: ids[0]) == .preferParc, "Explicit reset adopts recovered priority")
        expect(registry.shortcut(for: ids[2])?.flags == flags[2], "Explicit reset restores quote chord")
        let old: [String: Any] = ["version": 2, "overrides": [
            ids[0]: ["shortcut": ["key": "j", "modifiers": NSEvent.ModifierFlags.command.rawValue]],
            "anotherAction:": ["shortcut": ["key": "c", "modifiers": flags[1].rawValue]]],
            "priorities": [:]]
        try JSONSerialization.data(withJSONObject: old).write(to: file)
        registry.configure(directory: directory)
        expect(registry.priority(for: ids[0]) == .preferWebsites, "Old omitted website default preserved")
        expect(registry.shortcut(for: ids[0])?.key == "j", "Custom URL chord follows same selector across menu relocation")
        expect(registry.shortcut(for: ids[1]) == nil, "New Markdown chord cannot steal a saved chord")
        expect(registry.priority(for: ids[1]) == .preferParc, "New command gets recovered priority")
        expect(registry.priority(for: "closeTab:") == .preferWebsites, "Existing implicit close priority remains unchanged by migration")
        try registry.setPriority(.useBoth, for: "closeTab:")
        registry.configure(directory: directory)
        expect(registry.priority(for: "closeTab:") == .useBoth, "Explicit close priority survives repeated configuration")
        try registry.set(nil, for: "closeTab:")
        registry.configure(directory: directory)
        expect(registry.shortcut(for: "closeTab:") == nil, "Disabled close binding remains disabled for plural actions")
        let migrated = try Data(contentsOf: file)
        registry.configure(directory: directory)
        let reloaded = try Data(contentsOf: file)
        expect(reloaded == migrated, "Priority migration is idempotent")
        try registry.resetAll()
        expect(ids.allSatisfy { registry.priority(for: $0) == .preferParc }, "Reset all applies actual defaults")
        expect(registry.priority(for: "closeTab:") == .preferParc, "Reset adopts the recovered close priority")
        print("PASS: \(checks) copy-command default/migration assertions")
    }
}
