import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct KeyboardRegistryMigrationTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry: KeyboardShortcuts
        let delegate = AppDelegate()
        let main: NSMenu
        var file: URL { directory.appendingPathComponent("keyboard-shortcuts.json") }

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var root: NSMenu?
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            main = delegate.buildMenus(shortcuts: registry, install: false, initialSpaces: BrowserState.initial().spaces)
            root = main
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func encoded(_ chord: KeyboardShortcut?) -> [String: Any] {
            chord.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers] as [String: Any]] } ?? [:]
        }

        func legacy(_ version: Int, overrides: [String: [String: Any]], priorities: [String: String] = [:],
                    markers: [String: Int] = [:]) throws {
            var document: [String: Any] = ["version": version, "overrides": overrides, "priorities": priorities]
            markers.forEach { document[$0.key] = $0.value }
            try JSONSerialization.data(withJSONObject: document).write(to: file)
            reload()
        }

        func reload() { registry.configure(directory: directory) }

        func saved() throws -> [String: Any] {
            let data = try Data(contentsOf: file)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        func item(_ id: String, in menu: NSMenu? = nil) -> NSMenuItem? {
            for item in (menu ?? main).items {
                if item.action.map(NSStringFromSelector) == id { return item }
                if let submenu = item.submenu, let match = self.item(id, in: submenu) { return match }
            }
            return nil
        }
    }

    @Test(arguments: [
        ("nextTab:", "cycleToNextRecentTab:", false, "useBoth"),
        ("previousTab:", "cycleToPreviousRecentTab:", true, "preferParc"),
    ])
    @MainActor func anOldRecentTabBindingFollowsTheRecentTabCommand(oldID: String, id: String, disabled: Bool, priority: String) throws {
        let fixture = try Fixture()
        let chord = disabled ? nil : KeyboardShortcut(key: "j", flags: [.command, .option])
        try fixture.legacy(1, overrides: [oldID: fixture.encoded(chord)], priorities: [oldID: priority])
        #expect(fixture.registry.shortcut(for: id) == chord)
        #expect(fixture.registry.priority(for: id).rawValue == priority)
        let menu = try #require(fixture.item(id))
        #expect(menu.keyEquivalent == (chord?.key ?? ""))
    }

    @Test @MainActor func aPositionalDefaultCannotTakeASavedChord() throws {
        let fixture = try Fixture()
        let claimed = KeyboardShortcut(key: "\u{f701}", flags: [.command, .option])
        try fixture.legacy(1, overrides: ["another:": fixture.encoded(claimed)])
        #expect(fixture.registry.shortcut(for: "another:") == claimed)
        #expect(fixture.registry.shortcut(for: "nextTab:") == nil)
        #expect(fixture.registry.shortcut(for: "previousTab:")?.key == "\u{f700}")
    }

    static let priorities: [(String, String)] = [
        ("goBack:", "preferParc"), ("goForward:", "preferParc"), ("cycleTabForward:", "preferParc"),
        ("cycleTabBackward:", "preferParc"), ("focusAddress:", "preferParc"), ("newTab:", "preferParc"),
        ("newWindow:", "preferParc"), ("newIncognitoWindow:", "preferParc"), ("restoreTab:", "preferParc"),
        ("nextTab:", "preferParc"), ("previousTab:", "preferParc"), ("cycleToNextRecentTab:", "preferParc"),
        ("cycleToPreviousRecentTab:", "preferParc"), ("hide:", "preferParc"), ("quitMenu:", "preferParc"),
        ("performMiniaturize:", "preferParc"), ("split:", "useBoth"), ("closeSplitPane:", "useBoth"),
        ("createNote:", "useBoth"), ("createNoteInSplit:", "useBoth"), ("printPage:", "useBoth"),
        ("toggleSidebar:", "useBoth"), ("togglePin:", "useBoth"), ("focusSidebar:", "useBoth"),
        ("closeTab:", "preferParc"), ("developerTools:", "useBoth"), ("unregistered:", "preferWebsites"),
    ]

    @Test(arguments: priorities)
    @MainActor func freshCommandsUseTheirOwnPriority(id: String, expected: String) throws {
        let fixture = try Fixture()
        #expect(fixture.registry.priority(for: id).rawValue == expected)
    }

    @Test(arguments: [1, 2, 3], ["goBack:", "newTab:", "split:", "toggleSidebar:"])
    @MainActor func anImplicitOldPriorityStaysWebsiteFirst(version: Int, id: String) throws {
        let fixture = try Fixture()
        try fixture.legacy(version, overrides: [:], markers: ["developerDefaults": 1, "selectionCommandDefaults": 1])
        #expect(fixture.registry.priority(for: id) == .preferWebsites)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func additiveMigrationKeepsExplicitVersionsAndPriorities(version: Int) throws {
        let fixture = try Fixture()
        let chord = KeyboardShortcut(key: "j", flags: [.command, .option])
        try fixture.legacy(version, overrides: ["goBack:": fixture.encoded(chord), "printPage:": [:]],
            priorities: ["goForward:": "useBoth", "split:": "preferParc", "future:": "useBoth"],
            markers: ["developerDefaults": 1, "selectionCommandDefaults": 1])
        #expect(fixture.registry.shortcut(for: "goBack:") == chord)
        #expect(fixture.registry.shortcut(for: "printPage:") == nil)
        #expect(fixture.registry.priority(for: "goForward:") == .useBoth)
        #expect(fixture.registry.priority(for: "split:") == .preferParc)
        #expect(fixture.registry.priority(for: "future:") == .useBoth)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func reloadingTheMigratedSchemaKeepsItsBytes(version: Int) throws {
        let fixture = try Fixture()
        try fixture.legacy(version, overrides: [:])
        let data = try Data(contentsOf: fixture.file)
        let document = try fixture.saved()
        #expect(document["version"] as? Int == 3)
        #expect(document["menuPriorityDefaults"] as? Int == 1)
        fixture.reload()
        #expect(try Data(contentsOf: fixture.file) == data)
    }

    @Test(arguments: [false, true])
    @MainActor func resettingACommandRestoresItsCurrentPriority(all: Bool) throws {
        let fixture = try Fixture()
        try fixture.legacy(3, overrides: ["printPage:": [:]])
        if all { try fixture.registry.resetAll() }
        else { try fixture.registry.reset("goBack:") }
        fixture.reload()
        #expect(fixture.registry.priority(for: "goBack:") == .preferParc)
        #expect(fixture.registry.shortcut(for: "printPage:") == (all ? KeyboardShortcut(key: "p", flags: .command) : nil))
    }

    @Test(arguments: ["bad JSON", #"{"version":4,"overrides":{}}"#])
    @MainActor func unreadableOrFutureSettingsAreNeverRewritten(content: String) throws {
        let fixture = try Fixture()
        let document = Data(content.utf8)
        try document.write(to: fixture.file)
        fixture.reload()
        #expect(fixture.registry.loadError != nil)
        #expect(try Data(contentsOf: fixture.file) == document)
    }

    @Test @MainActor func hiddenHistoryCommandsKeepTheirSavedDataAcrossOtherEdits() throws {
        let fixture = try Fixture()
        let saved = KeyboardShortcut(key: "y", flags: [.command, .control])
        try fixture.legacy(3, overrides: ["cycleTabForward:": fixture.encoded(saved), "cycleTabBackward:": [:]],
                           priorities: ["cycleTabForward:": "useBoth"])
        #expect(!fixture.registry.commands.contains { $0.id.hasPrefix("cycleTab") })
        try fixture.registry.set(KeyboardShortcut(key: "n", flags: [.command, .option, .shift]), for: "nextTab:")
        let document = try fixture.saved()
        let overrides = document["overrides"] as? [String: Any]
        let priorities = document["priorities"] as? [String: String]
        #expect(overrides?["cycleTabForward:"] != nil && overrides?["cycleTabBackward:"] != nil)
        #expect(priorities?["cycleTabForward:"] == "useBoth")
    }

    @Test(arguments: [false, true])
    @MainActor func splitThisPaneDoesNotStealAnOccupiedDefault(claimed: Bool) throws {
        let fixture = try Fixture()
        let chord = KeyboardShortcut(key: "\\", flags: [.control, .shift])
        try fixture.legacy(3, overrides: claimed ? ["other:": fixture.encoded(chord)] : [:])
        #expect(fixture.registry.activeShortcut(for: "splitThisPane:") == (claimed ? nil : chord))
        #expect(fixture.registry.priority(for: "splitThisPane:") == .useBoth)
    }

    @Test(arguments: [
        ("copyCurrentURL:", NSEvent.ModifierFlags([.command, .shift])),
        ("copyCurrentURLAsMarkdown:", NSEvent.ModifierFlags([.command, .shift, .option])),
        ("copyCurrentURLAsQuote:", NSEvent.ModifierFlags([.command, .shift, .control])),
    ])
    @MainActor func copyFormatsKeepTheirDistinctBrowserDefaults(id: String, flags: NSEvent.ModifierFlags) throws {
        let fixture = try Fixture()
        #expect(fixture.registry.shortcut(for: id) == KeyboardShortcut(key: "c", flags: flags))
        #expect(fixture.registry.priority(for: id) == .preferParc)
    }

    @Test @MainActor func aNewCopyFormatDoesNotStealASavedChord() throws {
        let fixture = try Fixture()
        let occupied = KeyboardShortcut(key: "c", flags: [.command, .shift, .option])
        let custom = KeyboardShortcut(key: "j", flags: .command)
        try fixture.legacy(2, overrides: ["copyCurrentURL:": fixture.encoded(custom), "anotherAction:": fixture.encoded(occupied)])
        #expect(fixture.registry.shortcut(for: "copyCurrentURL:") == custom)
        #expect(fixture.registry.priority(for: "copyCurrentURL:") == .preferWebsites)
        #expect(fixture.registry.shortcut(for: "copyCurrentURLAsMarkdown:") == nil)
        #expect(fixture.registry.shortcut(for: "anotherAction:") == occupied)
    }

    @Test @MainActor func anExplicitCopyPrioritySurvivesReload() throws {
        let fixture = try Fixture()
        try fixture.registry.setPriority(.preferWebsites, for: "copyCurrentURL:")
        fixture.reload()
        #expect(fixture.registry.priority(for: "copyCurrentURL:") == .preferWebsites)
    }
}

extension KeyboardRegistryMigrationTests {
    static let recoveredIDs = ["goBack:", "goForward:", "cycleTabForward:", "cycleTabBackward:", "focusAddress:", "newTab:",
                               "newWindow:", "newIncognitoWindow:", "restoreTab:", "nextTab:", "previousTab:",
                               "cycleToNextRecentTab:", "cycleToPreviousRecentTab:", "hide:", "quitMenu:", "performMiniaturize:",
                               "split:", "closeSplitPane:", "createNote:", "createNoteInSplit:", "printPage:",
                               "toggleSidebar:", "togglePin:", "focusSidebar:"]

    @Test(arguments: [1, 2, 3], recoveredIDs.filter { $0 != "goForward:" && $0 != "split:" })
    @MainActor func everyRecoveredCommandKeepsItsImplicitOldPriority(version: Int, id: String) throws {
        let fixture = try Fixture()
        try fixture.legacy(version, overrides: [:], priorities: ["goForward:": "useBoth", "split:": "preferParc"],
                           markers: ["developerDefaults": 1, "selectionCommandDefaults": 1])
        #expect(fixture.registry.priority(for: id) == .preferWebsites)
    }

    @Test @MainActor func aLinearHistoryCommandKeepsItsOwnDefaultChord() throws {
        let registry = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        registry.configure(directory: directory)
        let item = NSMenuItem(title: "Cycle", action: NSSelectorFromString("cycleTabForward:"), keyEquivalent: "\u{f703}")
        item.keyEquivalentModifierMask = [.command, .control]
        registry.register(item, group: "Tabs")
        #expect(registry.shortcut(for: "cycleTabForward:")?.key == "\u{f703}")
    }

    @Test @MainActor func reloadingKeepsACustomRecentTabChord() throws {
        let fixture = try Fixture()
        let chord = KeyboardShortcut(key: "j", flags: [.command, .option])
        try fixture.legacy(1, overrides: ["nextTab:": fixture.encoded(chord)])
        fixture.reload()
        #expect(fixture.registry.shortcut(for: "cycleToNextRecentTab:") == chord)
    }

    @Test @MainActor func anExplicitResetKeepsAnOccupiedDefaultInConflictUntilResetAllRestoresIt() throws {
        let fixture = try Fixture()
        let original = try #require(fixture.registry.shortcut(for: "nextTab:"))
        let mruDefault = try #require(fixture.registry.shortcut(for: "cycleToNextRecentTab:"))
        let custom = KeyboardShortcut(key: "j", flags: [.command, .option])
        try fixture.legacy(1, overrides: ["nextTab:": fixture.encoded(custom), "someOtherAction:": fixture.encoded(original)],
                           priorities: ["nextTab:": "useBoth"])
        let other = NSMenuItem(title: "Other", action: NSSelectorFromString("someOtherAction:"), keyEquivalent: "")
        fixture.registry.register(other, group: "Test")
        try fixture.registry.reset("nextTab:")
        #expect(fixture.registry.isConflicting("nextTab:"))
        #expect(fixture.registry.activeShortcut(for: "nextTab:") == nil)
        try fixture.registry.resetAll()
        #expect(fixture.registry.shortcut(for: "nextTab:") == original)
        #expect(fixture.registry.shortcut(for: "cycleToNextRecentTab:") == mruDefault)
        #expect(fixture.registry.priority(for: "cycleToNextRecentTab:") == .preferParc)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func migratingKeepsEverySavedRecordAndTheCustomMenuBinding(version: Int) throws {
        let fixture = try Fixture()
        let custom = KeyboardShortcut(key: "j", flags: [.command, .option])
        let conflicting = KeyboardShortcut(key: "\u{f701}", flags: [.command, .option])
        let overrides = ["goBack:": fixture.encoded(custom), "printPage:": fixture.encoded(nil),
                         "unknownFutureCommand:": fixture.encoded(conflicting)]
        try fixture.legacy(version, overrides: overrides, markers: ["developerDefaults": 1, "selectionCommandDefaults": 1])
        #expect(try #require(fixture.item("goBack:")).keyEquivalent == custom.key)
        #expect(try #require(fixture.item("printPage:")).keyEquivalent == "")
        let saved = try #require(fixture.saved()["overrides"] as? [String: [String: Any]])
        #expect(overrides.allSatisfy { key, value in
            saved[key].map { NSDictionary(dictionary: $0).isEqual(to: value) } == true
        })
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func theDeveloperCollisionProtectionStillPreservesACustomChord(version: Int) throws {
        let fixture = try Fixture()
        let custom = KeyboardShortcut(key: "j", flags: [.command, .option])
        try fixture.legacy(version, overrides: ["goBack:": fixture.encoded(custom)],
                           markers: ["developerDefaults": 1, "selectionCommandDefaults": 1])
        let saved = try #require(fixture.saved()["overrides"] as? [String: Any])
        #expect(saved["javaScriptConsole:"] != nil)
        #expect(fixture.registry.shortcut(for: "javaScriptConsole:") == nil)
    }

    @Test @MainActor func anIndividualResetAdoptsTheProvenPolicyWithoutDisturbingOtherSavedChoices() throws {
        let fixture = try Fixture()
        try fixture.legacy(3, overrides: ["goBack:": fixture.encoded(KeyboardShortcut(key: "j", flags: [.command, .option])),
                                          "printPage:": fixture.encoded(nil)])
        try fixture.registry.reset("goBack:")
        #expect(fixture.registry.priority(for: "goBack:") == .preferParc)
        #expect(fixture.registry.priority(for: "printPage:") == .preferWebsites)
        #expect(fixture.registry.shortcut(for: "printPage:") == nil)
        fixture.reload()
        #expect(fixture.registry.priority(for: "goBack:") == .preferParc)
    }

    @Test @MainActor func aNewExplicitWebsiteChoiceIsDurablyDistinguishable() throws {
        let fixture = try Fixture()
        try fixture.legacy(3, overrides: [:])
        try fixture.registry.reset("goBack:")
        try fixture.registry.setPriority(.preferWebsites, for: "goBack:")
        fixture.reload()
        #expect(fixture.registry.priority(for: "goBack:") == .preferWebsites)
    }

    @Test(arguments: priorities.filter { $0.0 != "unregistered:" })
    @MainActor func resetAllRestoresEveryCommandsPolicyAndLeavesNoOverrides(id: String, expected: String) throws {
        let fixture = try Fixture()
        try fixture.legacy(3, overrides: ["printPage:": fixture.encoded(nil)], priorities: ["goBack:": "preferWebsites"])
        try fixture.registry.resetAll()
        #expect(fixture.registry.priority(for: id).rawValue == expected)
        fixture.reload()
        #expect(!fixture.registry.hasOverrides)
    }

    @Test @MainActor func enablingAGatedCommandRestoresItsSavedCustomChord() throws {
        let fixture = try Fixture()
        let saved = KeyboardShortcut(key: "y", flags: [.command, .control])
        try fixture.legacy(3, overrides: ["cycleTabForward:": fixture.encoded(saved)])
        let registry = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        registry.configure(directory: fixture.directory)
        let item = NSMenuItem(title: "Cycle Tab Forward", action: NSSelectorFromString("cycleTabForward:"), keyEquivalent: "\u{f703}")
        item.keyEquivalentModifierMask = [.command, .control]
        registry.register(item, group: "Tabs")
        #expect(registry.shortcut(for: "cycleTabForward:") == saved)
        #expect(item.keyEquivalent == "y")
    }

    @Test @MainActor func splitThisPanesMigrationMarkerPersists() throws {
        let fixture = try Fixture()
        let chord = KeyboardShortcut(key: "\\", flags: [.control, .shift])
        try fixture.legacy(3, overrides: ["other:": fixture.encoded(chord)])
        #expect(try fixture.saved()["splitThisPaneShortcutDefaults"] as? Int == 1)
    }

    @Test @MainActor func aSavedCustomSplitThisPaneChordSurvives() throws {
        let fixture = try Fixture()
        let occupied = KeyboardShortcut(key: "\\", flags: [.control, .shift])
        let custom = KeyboardShortcut(key: "s", flags: [.control, .option])
        try fixture.legacy(3, overrides: ["splitThisPane:": fixture.encoded(custom), "other:": fixture.encoded(occupied)])
        #expect(fixture.registry.activeShortcut(for: "splitThisPane:") == custom)
    }
}
