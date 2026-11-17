import AppKit

@main struct MigrationTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) { checks += 1; precondition(value(), message) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keyboard-shortcuts.json")
        let custom = KeyboardShortcut(key: "j", flags: [.command, .option])
        let conflicting = KeyboardShortcut(key: "\u{f701}", flags: [.command, .option])
        func encoded(_ chord: KeyboardShortcut?) -> [String: Any] {
            guard let chord else { return [:] }
            return ["shortcut": ["key": chord.key, "modifiers": chord.modifiers]]
        }
        let old: [String: Any] = ["version": 1, "overrides": ["nextTab:": encoded(custom), "previousTab:": encoded(nil), "someOtherAction:": encoded(conflicting)],
                                  "priorities": ["nextTab:": "useBoth", "previousTab:": "preferParc"]]
        try JSONSerialization.data(withJSONObject: old).write(to: file)
        let registry = KeyboardShortcuts()
        registry.configure(directory: directory)
        var menuItems: [NSMenuItem] = []
        func register(_ id: String, _ key: String, _ flags: NSEvent.ModifierFlags) {
            let menu = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
            menu.keyEquivalentModifierMask = flags; menuItems.append(menu); registry.register(menu, group: "Tabs")
        }
        register("nextTab:", "\u{f701}", [.command,.option]); register("previousTab:", "\u{f700}", [.command,.option])
        register("cycleTabForward:", "\u{f703}", [.command,.control]); register("cycleTabBackward:", "\u{f702}", [.command,.control])
        register("cycleToNextRecentTab:", "\t", [.control]); register("cycleToPreviousRecentTab:", "\t", [.control,.shift])
        register("someOtherAction:", "", [])
        expect(registry.loadError == nil, "Migration readable")
        expect(registry.shortcut(for: "cycleToNextRecentTab:") == custom, "Custom chord follows original MRU behavior")
        expect(registry.shortcut(for: "cycleToPreviousRecentTab:") == nil, "Disabled MRU remains disabled")
        expect(registry.priority(for: "cycleToNextRecentTab:") == .useBoth, "Priority follows behavior")
        expect(registry.priority(for: "cycleToPreviousRecentTab:") == .preferParc, "Disabled priority preserved")
        expect(registry.shortcut(for: "nextTab:") == nil, "New default never steals custom chord")
        expect(registry.shortcut(for: "previousTab:")?.flags == [.command,.option], "New positional default independent")
        expect(registry.shortcut(for: "cycleTabForward:")?.key == "\u{f703}", "Linear history default independent")
        expect(menuItems[4].keyEquivalent == custom.key && menuItems[4].keyEquivalentModifierMask == custom.flags, "Actual menu applies migrated binding")
        expect(menuItems[5].keyEquivalent.isEmpty, "Actual menu disables migrated chord")
        let saved = try Data(contentsOf: file)
        let document = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        expect(document["version"] as? Int == 3, "Migration durably versioned")
        registry.configure(directory: directory)
        let reloaded = try Data(contentsOf: file)
        expect(reloaded == saved, "Version three reload is idempotent")
        expect(registry.shortcut(for: "cycleToNextRecentTab:") == custom, "Reload preserves custom MRU")
        try registry.reset("nextTab:")
        expect(registry.isConflicting("nextTab:") && registry.activeShortcut(for: "nextTab:") == nil, "Explicit Reset saves the default conflict without taking the chord")
        try registry.resetAll()
        expect(registry.shortcut(for: "nextTab:") == conflicting, "Reset restores positional default")
        expect(registry.shortcut(for: "cycleToNextRecentTab:") == .init(key: "\t", flags: .control), "Reset restores MRU default")
        expect(registry.priority(for: "cycleToNextRecentTab:") == .preferParc, "Reset restores recovered MRU priority")
        let bad = Data("not JSON".utf8); try bad.write(to: file)
        registry.configure(directory: directory)
        expect(registry.loadError != nil, "Unreadable document reported")
        let unchanged = try Data(contentsOf: file)
        expect(unchanged == bad, "Unreadable document not overwritten")

        let browserIDs = ["goBack:", "goForward:", "cycleTabForward:", "cycleTabBackward:",
                          "focusAddress:", "newTab:", "newWindow:", "newIncognitoWindow:", "restoreTab:",
                          "nextTab:", "previousTab:", "cycleToNextRecentTab:", "cycleToPreviousRecentTab:",
                          "hide:", "quitMenu:", "performMiniaturize:"]
        let bothIDs = ["split:", "closeSplitPane:", "createNote:", "createNoteInSplit:", "printPage:",
                       "toggleSidebar:", "togglePin:", "focusSidebar:"]
        let recoveredIDs = browserIDs + bothIDs
        try FileManager.default.removeItem(at: file)
        let menuRegistry = KeyboardShortcuts()
        menuRegistry.configure(directory: directory)
        var originalItems: [String: NSMenuItem] = [:]
        for (index, id) in recoveredIDs.enumerated() {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(id),
                                  keyEquivalent: String(UnicodeScalar(0xf704 + index)!))
            item.keyEquivalentModifierMask = [.control]
            originalItems[id] = item; menuRegistry.register(item, group: "Reference commands")
        }
        for id in browserIDs { expect(menuRegistry.priority(for: id) == .preferParc, "Fresh original browser priority: \(id)") }
        for id in bothIDs { expect(menuRegistry.priority(for: id) == .useBoth, "Fresh consumed-key cue priority: \(id)") }
        expect(menuRegistry.priority(for: "unknownFutureCommand:") == .preferWebsites, "Unproven command remains unchanged")
        expect(menuRegistry.priority(for: "closeTab:") == .preferParc && menuRegistry.priority(for: "developerTools:") == .useBoth,
               "Earlier recovered policies remain intact")

        for version in 1...3 {
            let legacyOverrides = ["goBack:": encoded(custom), "printPage:": encoded(nil),
                                   "unknownFutureCommand:": encoded(conflicting)]
            let legacy: [String: Any] = ["version": version, "overrides": legacyOverrides,
                                        "priorities": ["goForward:": "useBoth", "split:": "preferParc", "future:": "useBoth"],
                                        "developerDefaults": 1, "selectionCommandDefaults": 1]
            try JSONSerialization.data(withJSONObject: legacy).write(to: file)
            menuRegistry.configure(directory: directory)
            expect(menuRegistry.loadError == nil, "Legacy v\(version) is readable")
            for id in recoveredIDs where id != "goForward:" && id != "split:" {
                expect(menuRegistry.priority(for: id) == .preferWebsites, "Ambiguous omitted v\(version) choice preserved: \(id)")
            }
            expect(menuRegistry.priority(for: "goForward:") == .useBoth && menuRegistry.priority(for: "split:") == .preferParc,
                   "Explicit nondefault choices preserved")
            expect(menuRegistry.priority(for: "future:") == .useBoth, "Unknown saved priority preserved")
            expect(menuRegistry.shortcut(for: "goBack:") == custom && originalItems["goBack:"]?.keyEquivalent == custom.key,
                   "Custom binding still reaches the same menu item")
            expect(menuRegistry.shortcut(for: "printPage:") == nil && originalItems["printPage:"]?.keyEquivalent == "",
                   "Disabled command remains disabled")
            let migrated = try Data(contentsOf: file)
            let json = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
            expect(json["version"] as? Int == 3 && json["menuPriorityDefaults"] as? Int == 1, "Additive marker persists without a schema rollback")
            let savedOverrides = json["overrides"] as! [String: [String: Any]]
            expect(legacyOverrides.allSatisfy { key, value in
                guard let saved = savedOverrides[key] else { return false }
                return NSDictionary(dictionary: saved).isEqual(to: value)
            }, "Original custom/disabled/unknown records unchanged while prior collision migrations still run")
            expect(savedOverrides["javaScriptConsole:"] != nil && menuRegistry.shortcut(for: "javaScriptConsole:") == nil,
                   "Existing Developer collision protection still preserves the custom chord")
            menuRegistry.configure(directory: directory)
            let migratedAgain = try Data(contentsOf: file)
            expect(migratedAgain == migrated, "Migration is byte-idempotent")
        }
        try menuRegistry.reset("goBack:")
        expect(menuRegistry.priority(for: "goBack:") == .preferParc, "Individual Reset adopts proven browser policy")
        expect(menuRegistry.priority(for: "printPage:") == .preferWebsites && menuRegistry.shortcut(for: "printPage:") == nil,
               "Individual Reset preserves another command's old choice and disabled chord")
        menuRegistry.configure(directory: directory)
        expect(menuRegistry.priority(for: "goBack:") == .preferParc, "Reset choice is not pinned again on reload")
        try menuRegistry.setPriority(.preferWebsites, for: "goBack:")
        menuRegistry.configure(directory: directory)
        expect(menuRegistry.priority(for: "goBack:") == .preferWebsites, "New explicit website choice is durably distinguishable")
        try menuRegistry.resetAll()
        for id in browserIDs { expect(menuRegistry.priority(for: id) == .preferParc, "Reset All restores browser policy: \(id)") }
        for id in bothIDs { expect(menuRegistry.priority(for: id) == .useBoth, "Reset All restores consumed-key policy: \(id)") }
        menuRegistry.configure(directory: directory)
        expect(!menuRegistry.hasOverrides, "Reset All reload stays at current defaults")
        let future = Data(#"{"version":4,"overrides":{},"priorities":{"goBack:":"useBoth"}}"#.utf8)
        try future.write(to: file); menuRegistry.configure(directory: directory)
        expect(menuRegistry.loadError != nil, "Future schema remains protected")
        let preservedFuture = try Data(contentsOf: file)
        expect(preservedFuture == future, "Migration never rewrites an unknown schema")
        let gatedDirectory = directory.appendingPathComponent("gated")
        try FileManager.default.createDirectory(at: gatedDirectory, withIntermediateDirectories: true)
        let gatedFile = gatedDirectory.appendingPathComponent("keyboard-shortcuts.json")
        let savedCycle = KeyboardShortcut(key: "y", flags: [.command, .control])
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": ["cycleTabForward:": encoded(savedCycle), "cycleTabBackward:": encoded(nil)],
                                                    "priorities": ["cycleTabForward:": "useBoth"]]).write(to: gatedFile)
        let gated = KeyboardShortcuts()
        gated.configure(directory: gatedDirectory)
        let gatedNext = NSMenuItem(title: "Next Tab", action: NSSelectorFromString("nextTab:"), keyEquivalent: "\u{f701}")
        gatedNext.keyEquivalentModifierMask = [.command, .option]; gated.register(gatedNext, group: "Tabs")
        expect(gated.loadError == nil && !gated.commands.contains { $0.id.hasPrefix("cycleTab") }, "Gated Cycle commands are absent from Shortcuts")
        try gated.set(.init(key: "n", flags: [.command, .option, .shift]), for: "nextTab:")
        let gatedSaved = try JSONSerialization.jsonObject(with: Data(contentsOf: gatedFile)) as! [String: Any]
        let gatedOverrides = gatedSaved["overrides"] as? [String: Any], gatedPriorities = gatedSaved["priorities"] as? [String: String]
        expect(gatedOverrides?["cycleTabForward:"] != nil && gatedOverrides?["cycleTabBackward:"] != nil, "Saved Cycle bindings survive another edit")
        expect(gatedPriorities?["cycleTabForward:"] == "useBoth", "Saved Cycle priority survives another edit")
        let gatedCycle = NSMenuItem(title: "Cycle Tab Forward", action: NSSelectorFromString("cycleTabForward:"), keyEquivalent: "\u{f703}")
        gatedCycle.keyEquivalentModifierMask = [.command, .control]; gated.register(gatedCycle, group: "Tabs")
        expect(gated.shortcut(for: "cycleTabForward:") == savedCycle && gatedCycle.keyEquivalent == "y", "Enabling the flag restores the saved custom chord")
        let splitDirectory = directory.appendingPathComponent("split-this-pane")
        try FileManager.default.createDirectory(at: splitDirectory, withIntermediateDirectories: true)
        let splitFile = splitDirectory.appendingPathComponent("keyboard-shortcuts.json")
        let splitChord = KeyboardShortcut(key: "\\", flags: [.control, .shift])
        func splitRegistry(_ overrides: [String: Any]) throws -> KeyboardShortcuts {
            try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": overrides]).write(to: splitFile)
            let registry = KeyboardShortcuts()
            registry.configure(directory: splitDirectory)
            let item = NSMenuItem(title: "Split This Pane", action: NSSelectorFromString("splitThisPane:"), keyEquivalent: "\\")
            item.keyEquivalentModifierMask = [.control, .shift]; registry.register(item, group: "View")
            return registry
        }
        let fresh = try splitRegistry([:])
        expect(fresh.activeShortcut(for: "splitThisPane:") == splitChord && fresh.priority(for: "splitThisPane:") == .useBoth,
               "Split This Pane defaults to Control-Shift-Backslash with Add Split View's Use Both priority")
        let claimed = try splitRegistry(["other:": encoded(splitChord)])
        expect(claimed.activeShortcut(for: "splitThisPane:") == nil && claimed.shortcut(for: "other:") == splitChord,
               "Split This Pane's new default never steals a saved Control-Shift-Backslash")
        let splitSaved = try JSONSerialization.jsonObject(with: Data(contentsOf: splitFile)) as! [String: Any]
        expect(splitSaved["splitThisPaneShortcutDefaults"] as? Int == 1, "Split This Pane's migration marker persists")
        let customSplit = KeyboardShortcut(key: "s", flags: [.control, .option])
        let kept = try splitRegistry(["splitThisPane:": encoded(customSplit), "other:": encoded(splitChord)])
        expect(kept.activeShortcut(for: "splitThisPane:") == customSplit, "A saved custom Split This Pane chord survives")
        print("PASS: \(checks) shortcut-migration assertions")
    }
}
