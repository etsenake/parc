import AppKit

@MainActor private final class CreationTarget: NSObject, NSMenuItemValidation {
    var enabled = true
    func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
    @objc func createNote(_ sender: Any?) {}
    @objc func createNoteInSplit(_ sender: Any?) {}
    @objc func createEasel(_ sender: Any?) {}
    @objc func capturePage(_ sender: Any?) {}
}

@main @MainActor struct CreationDefaultTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rows: [(String, String, KeyboardShortcut)] = [
            ("createNote:", "New Note", .init(key: "N", flags: .control)),
            ("createNoteInSplit:", "New Note in Split View", .init(key: "n", flags: [.control, .option])),
            ("createEasel:", "New Easel", .init(key: "E", flags: .control)),
            ("capturePage:", "Capture Portion…", .init(key: "2", flags: [.command, .shift]))
        ]
        let target = CreationTarget()
        func register(_ registry: KeyboardShortcuts) -> [String: NSMenuItem] {
            let rootMenu = NSMenu(), parent = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "File"); parent.submenu = menu; rootMenu.addItem(parent); NSApp.mainMenu = rootMenu
            var items: [String: NSMenuItem] = [:]
            for (id, title, _) in rows {
                let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: "")
                item.target = target; menu.addItem(item); items[id] = item; registry.register(item, group: "File")
            }
            return items
        }
        let file = root.appendingPathComponent("keyboard-shortcuts.json")
        func encoded(_ shortcut: KeyboardShortcut?) -> [String: Any] {
            shortcut.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
        }
        let fresh = KeyboardShortcuts(); fresh.configure(directory: root); let items = register(fresh)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [], backing: .buffered, defer: false)
        let snapshots = fresh.menuCommands(in: window)
        for (id, _, chord) in rows {
            expect(fresh.shortcut(for: id) == chord, "Fresh settings use original chord \(id)")
            expect(items[id]?.keyEquivalent == chord.key && items[id]?.keyEquivalentModifierMask == chord.flags, "Real menu uses normalized equivalent")
            expect(fresh.commands.first(where: { $0.id == id })?.defaultShortcut == chord, "Shortcut editor sees identical reset/default metadata")
            expect(snapshots.first(where: { $0.id == id })?.shortcut == chord, "Actions search carries live keycaps and original item")
            expect(fresh.supportsPriority(id), "Existing native priority route accepts the real chord")
        }
        expect(fresh.priority(for: "createNote:") == .useBoth && fresh.priority(for: "createNoteInSplit:") == .useBoth,
               "Both original Note priority defaults remain unchanged")
        expect(fresh.priority(for: "createEasel:") == .preferWebsites && fresh.priority(for: "capturePage:") == .preferWebsites,
               "Unattributed creation priorities are not invented")
        expect(!FileManager.default.fileExists(atPath: file.path), "Reading fresh defaults never writes user settings")

        let custom = KeyboardShortcut(key: "k", flags: [.command, .control])
        for version in 1...3 {
            let legacy: [String: Any] = ["version": version, "developerDefaults": 1,
                "selectionCommandDefaults": 1, "menuPriorityDefaults": 1,
                "overrides": ["createNote:": encoded(custom), "createEasel:": encoded(nil),
                              "unrelated:": encoded(rows[3].2)],
                "priorities": ["createNote:": "preferParc", "createEasel:": "useBoth", "unrelated:": "useBoth"]]
            try JSONSerialization.data(withJSONObject: legacy).write(to: file)
            let registry = KeyboardShortcuts(); registry.configure(directory: root); let legacyItems = register(registry)
            expect(registry.loadError == nil, "Version \(version) migration succeeds")
            expect(registry.shortcut(for: "createNote:") == custom, "Custom chord retained")
            expect(registry.shortcut(for: "createEasel:") == nil, "Explicitly disabled retained")
            expect(registry.shortcut(for: "createNoteInSplit:") == nil && registry.shortcut(for: "capturePage:") == nil,
                   "Ambiguous legacy absence keeps unbound behavior")
            expect(legacyItems["capturePage:"]?.keyEquivalent.isEmpty == true, "Actual migrated menu remains disabled by binding")
            expect(registry.priority(for: "createNote:") == .preferParc && registry.priority(for: "createEasel:") == .useBoth,
                   "Explicit priorities retained independently")
            let migrated = try Data(contentsOf: file), value = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
            expect(value["creationShortcutDefaults"] as? Int == 1, "Migration persists additive marker")
            let saved = value["overrides"] as! [String: Any]
            expect(saved["unrelated:"] != nil, "Unknown command override retained")
            registry.configure(directory: root)
            let reloaded = try Data(contentsOf: file)
            expect(reloaded == migrated, "Repeated configure is byte-idempotent")
            let other = NSMenuItem(title: "Unrelated", action: NSSelectorFromString("unrelated:"), keyEquivalent: "")
            registry.register(other, group: "Other")
            try registry.reset("capturePage:")
            expect(registry.isConflicting("capturePage:") && registry.activeShortcut(for: "capturePage:") == nil, "Explicit Reset persists visible conflict without stealing the chord")
            try registry.reset("createNoteInSplit:")
            expect(registry.shortcut(for: "createNoteInSplit:") == rows[1].2, "Explicit reset adopts original chord")
            registry.configure(directory: root)
            expect(registry.shortcut(for: "createNoteInSplit:") == rows[1].2, "Reset persists without legacy repinning")
            try registry.resetAll()
            for (id, _, chord) in rows { expect(registry.shortcut(for: id) == chord, "Reset All adopts all four defaults") }
            expect(registry.priority(for: "createNote:") == .useBoth, "Reset All uses recovered priority")
        }
        let registry = KeyboardShortcuts(); registry.configure(directory: root); _ = register(registry)
        try registry.set(nil, for: "createNote:"); registry.configure(directory: root)
        expect(registry.shortcut(for: "createNote:") == nil, "Explicit clear persists after defaults are introduced")
        try registry.set(custom, for: "createEasel:"); try registry.setPriority(.preferParc, for: "createEasel:")
        registry.configure(directory: root)
        expect(registry.shortcut(for: "createEasel:") == custom && registry.priority(for: "createEasel:") == .preferParc,
               "New-schema custom chord/priority survives reload")
        let corrupt = Data("broken shortcuts".utf8); try corrupt.write(to: file); registry.configure(directory: root)
        expect(registry.loadError != nil, "Malformed settings are reported")
        let unchanged = try Data(contentsOf: file)
        expect(unchanged == corrupt, "Malformed settings are never replaced by migration")
        print("PASS: \(count) creation-default/menu/migration assertions")
    }
}
