import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct SidebarFocusTests {
    @Test(arguments: [
        ("split", 1, ["favorite", "split", "today"], "today"),
        ("today", 1, ["favorite", "split", "today"], nil),
        (nil, 1, ["favorite", "split", "today"], "favorite"),
        ("favorite", -1, ["favorite", "split", "today"], nil),
        (nil, -1, ["favorite", "split", "today"], "today"),
        ("today", 1, ["today", "favorite", "split"], "favorite"),
        ("today", 0, ["favorite", "split", "today"], "today"),
        ("today", 1, [], nil), (nil, -1, [], nil),
        (nil, 1, ["only"], "only"), ("only", 1, ["only"], nil),
    ] as [(String?, Int, [String], String?)])
    func arrowsFollowTheCurrentSidebarOrder(highlighted: String?, direction: Int, ids: [String], expected: String?) {
        var cursor = SidebarKeyboardCursor(highlightedID: highlighted)
        cursor.move(direction, in: ids)
        #expect(cursor.highlightedID == expected)
    }

    @Test(arguments: [(["today", "favorite", "split"], "favorite"), (["split", "today"], nil)] as [([String], String?)])
    func reconcilingKeepsTheOriginalIdentityOrClearsIt(ids: [String], expected: String?) {
        var cursor = SidebarKeyboardCursor(highlightedID: "favorite")
        cursor.reconcile(ids)
        #expect(cursor.highlightedID == expected)
    }

    @MainActor private final class Fixture {
        let controlSpace = KeyboardShortcut(key: " ", flags: .control)
        let custom = KeyboardShortcut(key: "s", flags: [.command, .option])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        let focus = NSMenuItem(title: "Focus Sidebar", action: NSSelectorFromString("focusSidebar:"), keyEquivalent: " ")
        let other = NSMenuItem(title: "Other", action: NSSelectorFromString("other:"), keyEquivalent: "")
        var file: URL { directory.appendingPathComponent("keyboard-shortcuts.json") }

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            focus.keyEquivalentModifierMask = .control
            registry.register(focus, group: "Tabs")
            registry.register(other, group: "Tabs")
            registry.configure(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func binding(_ chord: KeyboardShortcut?) -> [String: Any] {
            chord.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers] as [String: Any]] } ?? [:]
        }

        func load(_ overrides: [String: Any]) throws {
            let document: [String: Any] = ["version": 2, "overrides": overrides, "priorities": ["other:": "preferParc"]]
            try JSONSerialization.data(withJSONObject: document).write(to: file)
            registry.configure(directory: directory)
        }
    }

    @Test(arguments: [false, true])
    @MainActor func theSidebarFocusDefaultIsControlSpace(legacyInstallation: Bool) throws {
        let fixture = try Fixture()
        if legacyInstallation { try fixture.load([:]) }
        #expect(fixture.registry.activeShortcut(for: "focusSidebar:") == fixture.controlSpace)
    }

    @Test @MainActor func aSavedControlSpaceKeepsItsOriginalOwner() throws {
        let fixture = try Fixture()
        try fixture.load(["other:": fixture.binding(fixture.controlSpace)])
        #expect(fixture.registry.activeShortcut(for: "focusSidebar:") == nil)
        #expect(fixture.registry.activeShortcut(for: "other:") == fixture.controlSpace)
        #expect(fixture.registry.priority(for: "other:") == .preferParc)
        #expect(fixture.focus.keyEquivalent.isEmpty && fixture.other.keyEquivalent == " ")
    }

    @Test @MainActor func aMigratedSidebarBindingKeepsItsBytesOnReload() throws {
        let fixture = try Fixture()
        try fixture.load(["other:": fixture.binding(fixture.controlSpace)])
        let original = try Data(contentsOf: fixture.file)
        fixture.registry.configure(directory: fixture.directory)
        #expect(try Data(contentsOf: fixture.file) == original)
    }

    @Test @MainActor func resettingFocusMakesAnOccupiedChordAnExplicitConflict() throws {
        let fixture = try Fixture()
        try fixture.load(["other:": fixture.binding(fixture.controlSpace)])
        try fixture.registry.reset("focusSidebar:")
        #expect(fixture.registry.isConflicting("focusSidebar:"))
        #expect(fixture.focus.keyEquivalent.isEmpty && fixture.other.keyEquivalent.isEmpty)
    }

    @Test(arguments: [false, true])
    @MainActor func aSavedSidebarFocusOverrideSurvives(disabled: Bool) throws {
        let fixture = try Fixture()
        let expected = disabled ? nil : fixture.custom
        try fixture.load(["focusSidebar:": fixture.binding(expected)])
        #expect(fixture.registry.shortcut(for: "focusSidebar:") == expected)
    }
}
