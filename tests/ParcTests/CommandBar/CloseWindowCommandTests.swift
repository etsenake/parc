import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct CloseWindowCommandTests {
    @MainActor private final class ProbeWindow: NSWindow {
        var requests = 0
        var closed = 0
        override var isVisible: Bool { true }
        override var isKeyWindow: Bool { true }
        override func performClose(_ sender: Any?) {
            requests += 1
            if delegate?.windowShouldClose?(self) ?? true { close() }
        }
        override func close() { closed += 1; super.close() }
        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    @MainActor private final class Target: NSObject, NSMenuItemValidation, NSWindowDelegate {
        var available = true
        var pending = false
        var approved = false
        var delegateRequests = 0
        func validateMenuItem(_ item: NSMenuItem) -> Bool { available && !pending }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            delegateRequests += 1
            if approved { return true }
            pending = true
            return false
        }
        @objc func closeWindow(_ sender: NSMenuItem) {}
        @objc func custom(_ sender: NSMenuItem) {}
    }

    @MainActor private final class Fixture {
        let target = Target()
        let window = ProbeWindow()
        let other = ProbeWindow()

        init() {
            _ = NSApplication.shared
            window.delegate = target
        }

        func command() -> BrowserWindowCloseCommand {
            BrowserWindowCloseCommand(window: window, ownerIsAvailable: { [target] in !target.pending })
        }
    }

    @Test @MainActor func theOriginalDelegateCanDeferTheClose() {
        let fixture = Fixture()
        #expect(fixture.command().perform(nil))
        #expect(fixture.window.requests == 1)
        #expect(fixture.target.delegateRequests == 1)
        #expect(fixture.window.closed == 0)
    }

    @Test @MainActor func oneRequestCannotReplayAndNoOtherWindowIsTargeted() {
        let fixture = Fixture()
        let command = fixture.command()
        #expect(command.perform(nil))
        #expect(!command.isAvailable)
        #expect(!command.perform(nil))
        #expect(fixture.other.requests == 0)
    }

    @Test @MainActor func aPendingCloseRejectsADuplicateRequest() {
        let fixture = Fixture()
        #expect(fixture.command().perform(nil))
        #expect(!fixture.command().perform(nil))
        #expect(fixture.target.delegateRequests == 1)
    }

    @Test @MainActor func aFreshRequestAfterARefusalReachesTheOriginalDelegate() {
        let fixture = Fixture()
        #expect(fixture.command().perform(nil))
        fixture.target.pending = false
        #expect(fixture.command().perform(nil))
        #expect(fixture.target.delegateRequests == 2)
    }

    @Test @MainActor func onlyTheOriginalDelegateApprovalClosesTheWindow() {
        let fixture = Fixture()
        fixture.target.approved = true
        #expect(fixture.window.closed == 0)
        fixture.window.performClose(nil)
        #expect(fixture.window.closed == 1)
        #expect(fixture.target.delegateRequests == 1)
    }

    private static let chord = KeyboardShortcut(key: "w", flags: [.command, .shift])
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
            let parent = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let child = NSMenu(title: "File")
            parent.submenu = child
            menu.addItem(parent)
            item = NSMenuItem(title: "Close Window", action: #selector(Target.closeWindow), keyEquivalent: "w")
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = target
            child.addItem(item)
            registry.register(item, group: "File")
            let custom = NSMenuItem(title: "Custom", action: #selector(Target.custom), keyEquivalent: "")
            custom.target = target
            child.addItem(custom)
            registry.register(custom, group: "File")
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func event(repeating: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 1,
                windowNumber: 0, context: nil, characters: "W", charactersIgnoringModifiers: "W",
                isARepeat: repeating, keyCode: 13))
        }

        func reload() { registry.configure(directory: root) }

        func savedData() throws -> Data { try Data(contentsOf: file) }
    }

    private static func encoded(_ shortcut: KeyboardShortcut?) -> [String: Any] {
        shortcut.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
    }

    private static func legacy(_ version: Int) -> [String: Any] {
        ["version": version, "developerDefaults": 1, "selectionCommandDefaults": 1, "menuPriorityDefaults": 1,
         "creationShortcutDefaults": 1, "alternateShortcutDefaults": 1,
         "overrides": ["custom:": encoded(chord)], "priorities": ["custom:": "useBoth"]]
    }

    @Test @MainActor func closeWindowShipsItsRecoveredChordMenuEquivalentAndPriority() throws {
        let fixture = try Registry()
        #expect(fixture.registry.shortcut(for: "closeWindow:") == Self.chord)
        #expect(fixture.item.keyEquivalent == "w")
        #expect(fixture.item.keyEquivalentModifierMask == Self.chord.flags)
        #expect(fixture.registry.priority(for: "closeWindow:") == .preferParc)
    }

    @Test(arguments: [false, true])
    @MainActor func theNativeQueryOwnsTheExactMenuItemEvenWhileEditing(editable: Bool) throws {
        let fixture = try Registry()
        let native = try #require(fixture.registry.nativeCommand(for: try fixture.event(), editable: editable))
        #expect(native.item === fixture.item)
        #expect(native.priority == .preferParc)
    }

    @Test @MainActor func aHeldRepeatDoesNotGenerateCloseRequests() throws {
        let fixture = try Registry()
        #expect(fixture.registry.nativeCommand(for: try fixture.event(repeating: true), editable: false) == nil)
    }

    @Test @MainActor func anUnavailableOriginalCommandDoesNotDispatch() throws {
        let fixture = try Registry()
        fixture.target.available = false
        #expect(fixture.registry.nativeCommand(for: try fixture.event(), editable: false) == nil)
    }

    @Test @MainActor func actionsSearchShowsOneRowWithTheLiveKeycap() throws {
        let fixture = try Registry()
        let window = CommandBarTestSupport.borderlessWindow()
        let rows = fixture.registry.menuCommands(in: window).filter { $0.id == "closeWindow:" }
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Close Window")
        #expect(rows.first?.shortcut == Self.chord)
    }

    @Test @MainActor func closeWindowIsAnEditableSettingsEntry() throws {
        let fixture = try Registry()
        #expect(fixture.registry.commands.contains { $0.id == "closeWindow:" && $0.group == "File" })
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func closeWindowNeverTakesAnExistingCustomChord(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        #expect(fixture.registry.loadError == nil)
        #expect(fixture.registry.shortcut(for: "custom:") == Self.chord)
        #expect(fixture.registry.shortcut(for: "closeWindow:") == nil)
        #expect(fixture.item.keyEquivalent.isEmpty)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func theNewCommandGetsItsPolicyAndExistingPrioritiesStay(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        #expect(fixture.registry.priority(for: "closeWindow:") == .preferParc)
        #expect(fixture.registry.priority(for: "custom:") == .useBoth)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func theCloseWindowMigrationMarkerIsSavedAndIdempotent(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        let saved = try fixture.savedData()
        let value = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        #expect(value["closeWindowShortcutDefaults"] as? Int == 1)
        fixture.reload()
        #expect(try fixture.savedData() == saved)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func anExplicitResetShowsTheConflictThenAdoptsTheDefault(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        try fixture.registry.reset("closeWindow:")
        #expect(fixture.registry.isConflicting("closeWindow:"))
        #expect(fixture.registry.activeShortcut(for: "closeWindow:") == nil)
        try fixture.registry.set(nil, for: "custom:")
        try fixture.registry.reset("closeWindow:")
        #expect(fixture.registry.shortcut(for: "closeWindow:") == Self.chord)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func aDisabledBindingAndExplicitPrioritySurviveReloadUntilResetAll(version: Int) throws {
        let fixture = try Registry(document: Self.legacy(version))
        try fixture.registry.set(nil, for: "custom:")
        try fixture.registry.reset("closeWindow:")
        try fixture.registry.setPriority(.preferWebsites, for: "closeWindow:")
        try fixture.registry.set(nil, for: "closeWindow:")
        fixture.reload()
        #expect(fixture.registry.shortcut(for: "closeWindow:") == nil)
        #expect(fixture.registry.priority(for: "closeWindow:") == .preferWebsites)
        try fixture.registry.resetAll()
        #expect(fixture.registry.shortcut(for: "closeWindow:") == Self.chord)
        #expect(fixture.registry.priority(for: "closeWindow:") == .preferParc)
    }

    @Test @MainActor func anUnassignedLegacyFileReceivesTheNewCommand() throws {
        let fixture = try Registry(document: ["version": 3, "overrides": [String: Any]()])
        #expect(fixture.registry.shortcut(for: "closeWindow:") == Self.chord)
        #expect(fixture.registry.priority(for: "closeWindow:") == .preferParc)
    }

    @Test @MainActor func explicitChoicesInAnewerFileArePreserved() throws {
        let fixture = try Registry(document: ["version": 3, "overrides": ["closeWindow:": Self.encoded(Self.customChord)],
                                              "priorities": ["closeWindow:": "useBoth"]])
        #expect(fixture.registry.shortcut(for: "closeWindow:") == Self.customChord)
        #expect(fixture.registry.priority(for: "closeWindow:") == .useBoth)
    }
}
