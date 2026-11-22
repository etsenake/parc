import AppKit
import Testing
@testable import Parc

struct FindCommandTests {
    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var available = true
        func validateMenuItem(_ item: NSMenuItem) -> Bool { available }
        @objc func find(_ sender: NSMenuItem) {}
        @objc func findNext(_ sender: NSMenuItem) {}
        @objc func findPrevious(_ sender: NSMenuItem) {}
        @objc func useSelectionForFind(_ sender: NSMenuItem) {}
        @objc func custom(_ sender: NSMenuItem) {}
    }

    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = Target()
        let main = NSMenu()
        let registry: KeyboardShortcuts
        var rows: [String: NSMenuItem] = [:]
        var file: URL { root.appendingPathComponent("keyboard-shortcuts.json") }

        init(document: [String: Any]? = nil) throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if let document { try JSONSerialization.data(withJSONObject: document).write(to: root.appendingPathComponent("keyboard-shortcuts.json")) }
            let main = main
            registry = KeyboardShortcuts(mainMenu: { main }, observesKeyboardLayout: false)
            registry.configure(directory: root)
            let edit = NSMenu(title: "Edit"), find = NSMenu(title: "Find")
            let editRow = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            let findRow = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
            editRow.submenu = edit
            main.addItem(editRow)
            findRow.submenu = find
            edit.addItem(findRow)
            for (id, title) in [("find:", "Find…"), ("findNext:", "Find Next"), ("findPrevious:", "Find Previous"),
                                ("useSelectionForFind:", "Use Selection to Find"), ("custom:", "Custom")] {
                let chord = id == "find:" ? KeyboardShortcut(key: "f", flags: .command) : KeyboardShortcuts.recoveredFindShortcuts[id]
                let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: chord?.key ?? "")
                item.keyEquivalentModifierMask = chord?.flags ?? .command
                item.target = target
                find.addItem(item)
                registry.register(item, group: "Find")
                rows[id] = item
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func event(shift: Bool) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : .command,
                timestamp: 1, windowNumber: 0, context: nil, characters: shift ? "G" : "g",
                charactersIgnoringModifiers: shift ? "G" : "g", isARepeat: false, keyCode: 5))
        }

        func reload() { registry.configure(directory: root) }

        func savedData() throws -> Data { try Data(contentsOf: file) }
    }

    private static let defaults: [(String, KeyboardShortcut)] = [
        ("findNext:", .init(key: "g", flags: [.command])),
        ("findPrevious:", .init(key: "g", flags: [.command, .shift])),
    ]
    private static let migrations = [1, 2, 3].flatMap { version in defaults.map { (version, $0.0, $0.1) } }

    private static func encoded(_ chord: KeyboardShortcut) -> [String: Any] {
        ["shortcut": ["key": chord.key, "modifiers": chord.modifiers]]
    }

    private static func document(_ version: Int, custom chord: KeyboardShortcut) -> [String: Any] {
        ["version": version, "overrides": ["custom:": encoded(chord)], "priorities": ["custom:": "useBoth"]]
    }

    @Test(arguments: ["moveLeft:", "moveRight:"])
    func nativeCaretMotionStaysWithTheField(selector: String) {
        #expect(BrowserFindAction.fieldAction(NSSelectorFromString(selector), shift: false, composing: false) == nil)
    }

    @Test(arguments: [("insertNewline:", false), ("insertNewline:", true), ("moveUp:", false), ("moveDown:", true)])
    func markedTextCommandsAreNotIntercepted(selector: String, shift: Bool) {
        #expect(BrowserFindAction.fieldAction(NSSelectorFromString(selector), shift: shift, composing: true) == nil)
    }

    @Test func theFindItemsKeepTheirTags() {
        #expect(BrowserFindAction.allCases.map(\.rawValue) == [0, 1, 2, 3, 7, 12])
    }

    @Test func theFindItemsKeepTheirShippedTitles() {
        #expect(BrowserFindAction.replace.title == "Find and Replace")
        #expect(BrowserFindAction.jumpToSelection.title == "Jump to Selection")
    }

    @Test(arguments: defaults)
    @MainActor func eachFindDefaultReachesTheRealMenuWithoutAnInventedPriority(id: String, chord: KeyboardShortcut) throws {
        let fixture = try Fixture()
        #expect(fixture.registry.shortcut(for: id) == chord)
        #expect(fixture.rows[id]?.keyEquivalent == chord.key)
        #expect(fixture.registry.priority(for: id) == .preferWebsites)
    }

    @Test @MainActor func useSelectionForFindStaysUnbound() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.shortcut(for: "useSelectionForFind:") == nil)
    }

    @Test @MainActor func everyFindCommandIsInTheShortcutEditor() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.commands.filter { $0.group == "Find" }.count == 5)
    }

    @Test @MainActor func actionsSearchShowsTheRealFindNextKeycap() throws {
        let fixture = try Fixture()
        let window = CommandBarTestSupport.borderlessWindow()
        let defaultChord = KeyboardShortcuts.recoveredFindShortcuts["findNext:"]
        #expect(fixture.registry.menuCommands(in: window).contains { $0.id == "findNext:" && $0.shortcut == defaultChord })
    }

    @Test(arguments: [(false, "findNext:"), (true, "findPrevious:")])
    @MainActor func theNativeQueryReachesTheExactDirectionItem(shift: Bool, id: String) throws {
        let fixture = try Fixture()
        #expect(fixture.registry.nativeCommand(for: try fixture.event(shift: shift), editable: false)?.item === fixture.rows[id])
    }

    @Test @MainActor func anUnavailableFindOwnerNeverFallsThrough() throws {
        let fixture = try Fixture()
        fixture.target.available = false
        #expect(fixture.registry.nativeCommand(for: try fixture.event(shift: false), editable: false) == nil)
    }

    @Test(arguments: migrations)
    @MainActor func aNewFindDefaultNeverStealsACustomBinding(version: Int, id: String, chord: KeyboardShortcut) throws {
        let fixture = try Fixture(document: Self.document(version, custom: chord))
        #expect(fixture.registry.shortcut(for: "custom:") == chord)
        #expect(fixture.registry.shortcut(for: id) == nil)
        #expect(fixture.rows[id]?.keyEquivalent == "")
        #expect(fixture.registry.priority(for: "custom:") == .useBoth)
    }

    @Test(arguments: migrations)
    @MainActor func theFindMigrationIsIdempotent(version: Int, id: String, chord: KeyboardShortcut) throws {
        let fixture = try Fixture(document: Self.document(version, custom: chord))
        let saved = try fixture.savedData()
        fixture.reload()
        #expect(try fixture.savedData() == saved)
    }

    @Test(arguments: migrations)
    @MainActor func resettingAFindDefaultShowsTheConflictThenRestoresIt(version: Int, id: String, chord: KeyboardShortcut) throws {
        let fixture = try Fixture(document: Self.document(version, custom: chord))
        try fixture.registry.reset(id)
        #expect(fixture.registry.isConflicting(id))
        #expect(fixture.registry.activeShortcut(for: id) == nil)
        try fixture.registry.set(nil, for: "custom:")
        try fixture.registry.reset(id)
        #expect(fixture.registry.shortcut(for: id) == chord)
    }

    @Test(arguments: migrations)
    @MainActor func aDisabledFindBindingAndExplicitPrioritySurviveReload(version: Int, id: String, chord: KeyboardShortcut) throws {
        let fixture = try Fixture(document: Self.document(version, custom: chord))
        try fixture.registry.set(nil, for: "custom:")
        try fixture.registry.reset(id)
        try fixture.registry.setPriority(.preferParc, for: id)
        try fixture.registry.set(nil, for: id)
        fixture.reload()
        #expect(fixture.registry.shortcut(for: id) == nil)
        #expect(fixture.registry.priority(for: id) == .preferParc)
    }

    private static let numberedIDs = ["findAndReplace:", "jumpToSelection:"]
        + (1...9).flatMap { ["item\($0)", "space\($0)"] }

    @Test(arguments: numberedIDs)
    @MainActor func aNumberedTargetDefaultNeverStealsASavedChord(id: String) throws {
        let chord = try #require(KeyboardShortcuts.numberedTargetShortcuts[id])
        let fixture = try Fixture(document: ["version": 3, "findShortcutDefaults": 1,
                                             "overrides": ["custom:": Self.encoded(chord)]])
        #expect(fixture.registry.loadError == nil)
        #expect(fixture.registry.shortcut(for: "custom:") == chord)
        #expect(fixture.registry.shortcut(for: id) == nil)
        let saved = try #require(JSONSerialization.jsonObject(with: fixture.savedData()) as? [String: Any])
        let overrides = saved["overrides"] as? [String: Any] ?? [:]
        let others = KeyboardShortcuts.numberedTargetShortcuts.keys.filter { $0 != id }
        #expect(saved["numberedTargetShortcutDefaults"] as? Int == 1)
        #expect(others.allSatisfy { overrides[$0] == nil })
    }

    @Test @MainActor func theRecoveredNumberedAndFindDefaultsAreTheShippedChords() {
        let table = KeyboardShortcuts.numberedTargetShortcuts
        #expect(table["item1"] == .init(key: "1", flags: [.command]))
        #expect(table["space9"] == .init(key: "9", flags: [.control]))
        #expect(table["findAndReplace:"] == .init(key: "f", flags: [.command, .option]))
        #expect(table["jumpToSelection:"] == .init(key: "j", flags: [.command]))
    }

    @MainActor private final class SpaceFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = KeyboardShortcuts(observesKeyboardLayout: false)
        let space = NSMenuItem(title: "Work", action: NSSelectorFromString("selectSpace:"), keyEquivalent: "1")

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            registry.configure(directory: directory)
            space.keyEquivalentModifierMask = .control
            registry.register(space, group: "Spaces", bindingID: "space1", title: "Work")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @Test @MainActor func renamingANumberedSpacePreservesItsDisabledBinding() throws {
        let fixture = try SpaceFixture()
        try fixture.registry.set(nil, for: "space1")
        fixture.registry.register(fixture.space, group: "Spaces", bindingID: "space1", title: "Personal")
        #expect(fixture.registry.commands.first { $0.id == "space1" }?.title == "Personal")
        #expect(fixture.registry.shortcut(for: "space1") == nil)
    }

    @Test @MainActor func aTenthSpaceIsDiscoverableWithoutADefaultAndAcceptsACustomChord() throws {
        let fixture = try SpaceFixture()
        let tenth = NSMenuItem(title: "Tenth Space", action: NSSelectorFromString("selectSpace:"), keyEquivalent: "")
        fixture.registry.register(tenth, group: "Spaces", bindingID: "space10", title: tenth.title)
        #expect(fixture.registry.commands.contains { $0.id == "space10" })
        #expect(fixture.registry.shortcut(for: "space10") == nil)
        try fixture.registry.set(.init(key: "0", flags: [.control]), for: "space10")
        #expect(fixture.registry.shortcut(for: "space10") == .init(key: "0", flags: [.control]))
    }

    @Test @MainActor func aRemovedSpaceLeavesDiscoveryAndKeepsItsSavedChoiceWhenItReturns() throws {
        let fixture = try SpaceFixture()
        try fixture.registry.set(nil, for: "space1")
        fixture.registry.retireCommands(["space1"])
        #expect(!fixture.registry.commands.contains { $0.id == "space1" })
        fixture.registry.register(fixture.space, group: "Spaces", bindingID: "space1", title: "Restored")
        #expect(fixture.registry.shortcut(for: "space1") == nil)
    }
}
