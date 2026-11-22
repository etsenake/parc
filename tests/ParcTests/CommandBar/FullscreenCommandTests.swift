import AppKit
import Testing
@testable import Parc

struct FullscreenCommandTests {
    @MainActor private class InertWindow: NSWindow {
        var key = true
        var requests = 0
        override var isVisible: Bool { true }
        override var isKeyWindow: Bool { key }
        override var isMainWindow: Bool { true }
        override func toggleFullScreen(_ sender: Any?) { requests += 1 }
        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            isReleasedWhenClosed = false
            collectionBehavior = .fullScreenPrimary
        }
    }

    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var available = true
        var inFullscreen = false
        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            if item.action == #selector(toggleFullScreen) {
                item.title = inFullscreen ? "Exit Full Screen" : "Enter Full Screen"
            }
            return available
        }
        @objc func toggleFullScreen(_ sender: NSMenuItem) {}
        @objc func custom(_ sender: NSMenuItem) {}
    }

    @MainActor private final class Fixture {
        let original = InertWindow()
        let other = InertWindow()
        let item = NSMenuItem(title: "Enter/Exit Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")

        init() {
            _ = NSApplication.shared
            item.keyEquivalentModifierMask = [.command, .control]
        }

        func command() -> BrowserWindowFullscreenCommand {
            BrowserWindowFullscreenCommand(window: original, ownerIsAvailable: { true })
        }
    }

    @Test @MainActor func nativeValidationAcceptsAnEligibleWindowAndKeepsTheMenuChord() {
        let fixture = Fixture()
        #expect(fixture.command().validate(fixture.item))
        #expect(fixture.item.title == "Enter Full Screen")
        #expect(fixture.item.keyEquivalent == "f")
        #expect(fixture.item.keyEquivalentModifierMask == [.command, .control])
    }

    @Test @MainActor func theNativeActionReachesOnlyTheOriginalWindowWithoutSynthesizingATransition() {
        let fixture = Fixture()
        #expect(fixture.command().perform(nil))
        #expect(fixture.original.requests == 1)
        #expect(fixture.other.requests == 0)
        #expect(!fixture.original.styleMask.contains(.fullScreen))
    }

    @Test @MainActor func oneRequestCannotReplay() {
        let fixture = Fixture()
        let command = fixture.command()
        #expect(command.perform(nil))
        #expect(!command.validate(fixture.item))
        #expect(!command.perform(nil))
    }

    @Test @MainActor func aWindowThatForbidsFullscreenRejectsValidationAndDispatch() {
        let fixture = Fixture()
        fixture.original.collectionBehavior = .fullScreenNone
        #expect(!fixture.command().validate(fixture.item))
        #expect(!fixture.command().perform(nil))
        #expect(fixture.original.requests == 0)
    }

    @Test @MainActor func theNativeCapabilityStaysQueryableBehindItsOwnedCommandPanel() {
        let fixture = Fixture()
        fixture.original.key = false
        #expect(fixture.command().validate(fixture.item))
        #expect(!fixture.command().perform(nil))
    }

    @Test @MainActor func aNativeRefusalOfTheTransitionStaysAuthoritative() {
        let fixture = Fixture()
        let window = RefusingWindow()
        let command = BrowserWindowFullscreenCommand(window: window, ownerIsAvailable: { true })
        #expect(command.validate(fixture.item))
        #expect(fixture.item.title == "Exit Full Screen")
        window.available = false
        #expect(!command.perform(nil))
        #expect(window.requests == 0)
    }

    @MainActor private final class RefusingWindow: InertWindow {
        var available = true
        override func validateMenuItem(_ item: NSMenuItem) -> Bool {
            item.title = "Exit Full Screen"
            return available
        }
    }

    private static let chord = KeyboardShortcut(key: "f", flags: [.command, .control])
    private static let customChord = KeyboardShortcut(key: "k", flags: [.command, .control])

    @MainActor private final class Registry {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = Target()
        let menu = NSMenu()
        let registry: KeyboardShortcuts
        let item: NSMenuItem
        var file: URL { root.appendingPathComponent("keyboard-shortcuts.json") }

        init(document: [String: Any]? = nil) throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if let document { try JSONSerialization.data(withJSONObject: document).write(to: root.appendingPathComponent("keyboard-shortcuts.json")) }
            let menu = menu
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            registry.configure(directory: root)
            let parent = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
            let child = NSMenu(title: "View")
            parent.submenu = child
            menu.addItem(parent)
            item = NSMenuItem(title: "Enter Full Screen", action: #selector(Target.toggleFullScreen), keyEquivalent: "f")
            item.keyEquivalentModifierMask = [.command, .control]
            item.target = target
            child.addItem(item)
            registry.register(item, group: "View")
            let custom = NSMenuItem(title: "Custom", action: #selector(Target.custom), keyEquivalent: "")
            custom.target = target
            child.addItem(custom)
            registry.register(custom, group: "View")
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func event(repeating: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .control], timestamp: 1,
                windowNumber: 0, context: nil, characters: "f", charactersIgnoringModifiers: "f",
                isARepeat: repeating, keyCode: 3))
        }

        func reload() { registry.configure(directory: root) }

        func savedData() throws -> Data { try Data(contentsOf: file) }
    }

    private static func encoded(_ shortcut: KeyboardShortcut?) -> [String: Any] {
        shortcut.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
    }

    private static func legacy(_ version: Int) -> [String: Any] {
        ["version": version, "developerDefaults": 1, "selectionCommandDefaults": 1, "menuPriorityDefaults": 1,
         "creationShortcutDefaults": 1, "alternateShortcutDefaults": 1, "closeWindowShortcutDefaults": 1,
         "overrides": ["custom:": encoded(chord)], "priorities": ["custom:": "preferWebsites"]]
    }

    @Test @MainActor func fullscreenShipsItsRecoveredChordAndUseBothPolicy() throws {
        let fixture = try Registry()
        #expect(fixture.registry.shortcut(for: "toggleFullScreen:") == Self.chord)
        #expect(fixture.registry.priority(for: "toggleFullScreen:") == .useBoth)
    }

    @Test(arguments: [false, true])
    @MainActor func theNativeQueryReturnsTheOriginalItemWithUseBothEvenWhileEditing(editable: Bool) throws {
        let fixture = try Registry()
        let native = try #require(fixture.registry.nativeCommand(for: try fixture.event(), editable: editable))
        #expect(native.item === fixture.item)
        #expect(native.priority == .useBoth)
    }

    @Test @MainActor func aHeldRepeatCannotIssueToggleRequests() throws {
        let fixture = try Registry()
        #expect(fixture.registry.nativeCommand(for: try fixture.event(repeating: true), editable: false) == nil)
    }

    @Test @MainActor func anUnavailableOriginalOwnerIsRespected() throws {
        let fixture = try Registry()
        fixture.target.available = false
        #expect(fixture.registry.nativeCommand(for: try fixture.event(), editable: false) == nil)
    }

    @Test @MainActor func actionsSearchShowsOneDynamicRowWithTheOriginalKeycap() throws {
        let fixture = try Registry()
        fixture.target.inFullscreen = true
        let window = CommandBarTestSupport.borderlessWindow()
        let rows = fixture.registry.menuCommands(in: window).filter { $0.id == "toggleFullScreen:" }
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Exit Full Screen")
        #expect(rows.first?.shortcut == Self.chord)
    }

    @Test @MainActor func fullscreenIsAnEditableShortcutsEntry() throws {
        let fixture = try Registry()
        #expect(fixture.registry.commands.contains { $0.id == "toggleFullScreen:" && $0.group == "View" })
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func fullscreenNeverTakesASavedCustomChord(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        #expect(fixture.registry.loadError == nil)
        #expect(fixture.registry.shortcut(for: "custom:") == Self.chord)
        #expect(fixture.registry.shortcut(for: "toggleFullScreen:") == nil)
        #expect(fixture.item.keyEquivalent.isEmpty)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func theNewPolicyAndTheExistingExplicitChoiceBothStay(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        #expect(fixture.registry.priority(for: "toggleFullScreen:") == .useBoth)
        #expect(fixture.registry.priority(for: "custom:") == .preferWebsites)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func theFullscreenMigrationMarkerIsSavedAndIdempotent(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        let saved = try fixture.savedData()
        let value = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(value["fullscreenShortcutDefaults"] as? Int == 1)
        fixture.reload()
        #expect(try fixture.savedData() == saved)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func anExplicitResetShowsTheConflictThenRestoresTheChord(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        try fixture.registry.reset("toggleFullScreen:")
        #expect(fixture.registry.isConflicting("toggleFullScreen:"))
        #expect(fixture.registry.activeShortcut(for: "toggleFullScreen:") == nil)
        try fixture.registry.set(nil, for: "custom:")
        try fixture.registry.reset("toggleFullScreen:")
        #expect(fixture.registry.shortcut(for: "toggleFullScreen:") == Self.chord)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func aDisabledBindingAndExplicitPrioritySurviveReloadUntilResetAll(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        try fixture.registry.set(nil, for: "custom:")
        try fixture.registry.reset("toggleFullScreen:")
        try fixture.registry.setPriority(.preferWebsites, for: "toggleFullScreen:")
        try fixture.registry.set(nil, for: "toggleFullScreen:")
        fixture.reload()
        #expect(fixture.registry.shortcut(for: "toggleFullScreen:") == nil)
        #expect(fixture.registry.priority(for: "toggleFullScreen:") == .preferWebsites)
        try fixture.registry.resetAll()
        #expect(fixture.registry.shortcut(for: "toggleFullScreen:") == Self.chord)
        #expect(fixture.registry.priority(for: "toggleFullScreen:") == .useBoth)
    }

    @Test @MainActor func anUnassignedLegacyInstallReceivesTheNewCommand() throws {
        let fixture = try Registry(document: ["version": 3, "overrides": [String: Any]()])
        #expect(fixture.registry.shortcut(for: "toggleFullScreen:") == Self.chord)
        #expect(fixture.registry.priority(for: "toggleFullScreen:") == .useBoth)
    }

    @Test @MainActor func explicitPreferencesInANewerFileArePreserved() throws {
        let fixture = try Registry(document: ["version": 3, "overrides": ["toggleFullScreen:": Self.encoded(Self.customChord)],
                                              "priorities": ["toggleFullScreen:": "preferParc"]])
        #expect(fixture.registry.shortcut(for: "toggleFullScreen:") == Self.customChord)
        #expect(fixture.registry.priority(for: "toggleFullScreen:") == .preferParc)
    }
}
