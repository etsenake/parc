import AppKit
import ParcEngine
import Testing
@testable import Parc
@testable import ParcKit

struct ShortcutChordTests {
    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var enabled = true
        var delivered: NSMenuItem?
        func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
        @objc func zoomIn(_ sender: NSMenuItem) { delivered = sender }
        @objc func goBack(_ sender: NSMenuItem) { delivered = sender }
        @objc func custom(_ sender: NSMenuItem) { delivered = sender }
        @objc func developerTools(_ sender: NSMenuItem) { delivered = sender }
    }

    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let menu = NSMenu(title: "View")
        let target = Target()
        let registry: KeyboardShortcuts
        let zoom: NSMenuItem
        let equals: NSMenuItem
        let f12: NSMenuItem
        let arrow: NSMenuItem
        let custom: NSMenuItem

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let rootMenu = menu
            let registry = KeyboardShortcuts(mainMenu: { rootMenu }, observesKeyboardLayout: false)
            self.registry = registry
            registry.configure(directory: root)
            let target = target
            func register(_ id: String, key: String, flags: NSEvent.ModifierFlags,
                          action: Selector, hidden: Bool = false, equivalent: Bool = false) -> NSMenuItem {
                let item = NSMenuItem(title: id, action: action, keyEquivalent: key)
                item.keyEquivalentModifierMask = flags
                item.target = target
                item.isHidden = hidden
                item.allowsKeyEquivalentWhenHidden = hidden
                rootMenu.addItem(item)
                if equivalent { registry.registerEquivalent(item, for: id, shortcut: .init(key: key, flags: flags)) }
                else { registry.register(item, group: "View", bindingID: id, discoverable: !hidden) }
                return item
            }
            zoom = register("zoomIn:", key: "+", flags: .command, action: #selector(Target.zoomIn(_:)))
            equals = register("zoomIn:", key: "=", flags: .command, action: #selector(Target.zoomIn(_:)), hidden: true, equivalent: true)
            f12 = register("developerTools_Alternate", key: "\u{f70f}", flags: [], action: #selector(Target.developerTools(_:)), hidden: true)
            arrow = register("goBack_Alternate", key: "\u{f702}", flags: .command, action: #selector(Target.goBack(_:)), hidden: true)
            custom = register("custom:", key: "", flags: [], action: #selector(Target.custom(_:)))
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func event(_ key: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: repeatKey, keyCode: code))
        }

        func plus() throws -> NSEvent { try event("+", 24, [.command, .shift]) }

        func setPhysicalPlus() throws {
            try registry.set(KeyboardShortcut(key: "=", flags: [.command, .shift]), for: "custom:")
        }
    }

    @Test(arguments: [
        ("a", UInt16(0), NSEvent.ModifierFlags(), false),
        ("a", 0, .shift, false), ("å", 0, .option, false), ("\u{f702}", 123, NSEvent.ModifierFlags(), false),
        ("c", 8, .command, false), ("\u{f70f}", 111, .function, true),
    ])
    @MainActor func nativeLookupLeavesOrdinaryEditingAndRepeatEventsAlone(key: String, code: UInt16,
                                                                          flags: NSEvent.ModifierFlags, repeats: Bool) throws {
        let fixture = try Fixture()
        let event = try fixture.event(key, code, flags, repeatKey: repeats)
        #expect(fixture.registry.nativeCommand(for: event, editable: true) == nil)
    }

    @Test @MainActor func f12DispatchesItsOriginalAlternateMenuItem() throws {
        let fixture = try Fixture()
        let event = try fixture.event("\u{f70f}", 111, .function)
        let command = try #require(fixture.registry.nativeCommand(for: event, editable: true))
        #expect(command.item === fixture.f12)
        #expect(fixture.registry.settingsCommandID(for: command) == "developerTools_Alternate")
        #expect(fixture.registry.perform(command, event: event, editable: true))
        #expect(fixture.target.delivered === fixture.f12)
    }

    @Test @MainActor func anArrowAlternateKeepsItsWebsiteFirstPriorityWhileEditing() throws {
        let fixture = try Fixture()
        let event = try fixture.event("\u{f702}", 123, .command)
        let command = try #require(fixture.registry.nativeCommand(for: event, editable: true))
        #expect(command.item === fixture.arrow)
        #expect(command.priority == .preferWebsites)
    }

    @Test @MainActor func theEqualsSupplementTargetsTheOriginalZoomBinding() throws {
        let fixture = try Fixture()
        let event = try fixture.event("=", 24, .command)
        let native = try #require(fixture.registry.nativeCommand(for: event, editable: true))
        #expect(native.item === fixture.equals)
        #expect(fixture.registry.settingsCommandID(for: native) == "zoomIn:")
    }

    @Test @MainActor func aPhysicalChordWinsOverSymbolicZoom() throws {
        let fixture = try Fixture()
        try fixture.setPhysicalPlus()
        let event = try fixture.plus()
        #expect(fixture.registry.nativeCommand(for: event, editable: false)?.item === fixture.custom)
        #expect(fixture.zoom.keyEquivalent.isEmpty)
        #expect(fixture.registry.shortcut(for: "zoomIn:") == KeyboardShortcut(key: "+", flags: .command))
    }

    @Test @MainActor func anUnavailablePhysicalChordCannotFallThroughToZoom() throws {
        let fixture = try Fixture()
        try fixture.setPhysicalPlus()
        fixture.target.enabled = false
        let event = try fixture.plus()
        #expect(fixture.registry.nativeCommand(for: event, editable: false) == nil)
        #expect(!fixture.menu.performKeyEquivalent(with: event))
        #expect(fixture.target.delivered == nil)
    }

    @Test @MainActor func deletingThePhysicalBindingRestoresSymbolicZoom() throws {
        let fixture = try Fixture()
        try fixture.setPhysicalPlus()
        try fixture.registry.set(nil, for: "custom:")
        let event = try fixture.plus()
        #expect(fixture.registry.nativeCommand(for: event, editable: false)?.item === fixture.zoom)
        #expect(fixture.zoom.keyEquivalent == "+")
    }

    @Test @MainActor func disablingZoomDropsBothNativeEquivalentRoutes() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: "zoomIn:")
        let plus = try fixture.plus()
        let equals = try fixture.event("=", 24, .command)
        #expect(fixture.registry.nativeCommand(for: plus, editable: false) == nil)
        #expect(fixture.registry.nativeCommand(for: equals, editable: false) == nil)
    }

    @Test @MainActor func aBindingRevisionRetiresThePreviousNativeCommand() throws {
        let fixture = try Fixture()
        let event = try fixture.event("\u{f70f}", 111, .function)
        let retained = try #require(fixture.registry.nativeCommand(for: event, editable: false))
        try fixture.registry.setPriority(.preferParc, for: "developerTools_Alternate")
        #expect(!fixture.registry.perform(retained, event: event, editable: false))
        #expect(fixture.registry.nativeCommand(for: event, editable: false)?.priority == .preferParc)
    }

    @Test @MainActor func aDetachedMenuItemCannotDispatchItsIndexedChord() throws {
        let fixture = try Fixture()
        fixture.menu.removeItem(fixture.f12)
        let event = try fixture.event("\u{f70f}", 111, .function)
        #expect(fixture.registry.nativeCommand(for: event, editable: false) == nil)
    }
}
