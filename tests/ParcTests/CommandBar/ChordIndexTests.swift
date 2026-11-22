import AppKit
import Testing
@testable import Parc

struct ChordIndexTests {
    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var enabled = true
        func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
        @objc func zoomIn(_ sender: NSMenuItem) {}
        @objc func custom(_ sender: NSMenuItem) {}
        @objc func decoy(_ sender: NSMenuItem) {}
        @objc func developerTools(_ sender: NSMenuItem) {}
    }

    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = Target()
        let menu = NSMenu(title: "View")
        let registry: KeyboardShortcuts
        var decoys: [NSMenuItem] = []
        var zoom: NSMenuItem!
        var equals: NSMenuItem!
        var custom: NSMenuItem!
        var f12: NSMenuItem!

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let menu = menu
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            registry.configure(directory: root)
            for index in 0..<40 {
                let letter = String(UnicodeScalar(UInt8(97 + (index % 26))))
                decoys.append(add("decoy\(index):", key: letter, flags: index < 26 ? [.command, .option] : [.control, .option], action: "decoy:"))
            }
            zoom = add("zoomIn:", key: "+", flags: .command, action: "zoomIn:")
            let equals = NSMenuItem(title: "zoomIn:", action: #selector(Target.zoomIn), keyEquivalent: "=")
            equals.target = target
            equals.keyEquivalentModifierMask = .command
            equals.isHidden = true
            equals.allowsKeyEquivalentWhenHidden = true
            menu.addItem(equals)
            registry.registerEquivalent(equals, for: "zoomIn:", shortcut: .init(key: "=", flags: .command))
            self.equals = equals
            custom = add("custom:", key: "", flags: [], action: "custom:")
            f12 = add("developerTools_Alternate", key: "\u{f70f}", flags: [], action: "developerTools:")
            f12.isHidden = true
            f12.allowsKeyEquivalentWhenHidden = true
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        private func add(_ id: String, key: String, flags: NSEvent.ModifierFlags, action: String) -> NSMenuItem {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = flags
            item.target = target
            menu.addItem(item)
            registry.register(item, group: "View", bindingID: id)
            return item
        }

        func event(_ code: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: code))
        }

        func f12Event() throws -> NSEvent { try event(111, "\u{f70f}", .function) }
        func plus() throws -> NSEvent { try event(24, "+", [.command, .shift]) }
    }

    @Test @MainActor func f12StillResolvesAmongManyUnrelatedChords() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.nativeCommand(for: try fixture.f12Event(), editable: true)?.item === fixture.f12)
    }

    @Test @MainActor func theIndexedEqualsEquivalentOwnsCommandEquals() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.nativeCommand(for: try fixture.event(24, "=", .command), editable: true)?.item === fixture.equals)
    }

    @Test @MainActor func theIndexedSymbolicPlusOwnsShiftCommandEquals() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.nativeCommand(for: try fixture.plus(), editable: true)?.item === fixture.zoom)
    }

    @Test @MainActor func aNewlyAssignedChordIsVisibleToTheNextLookup() throws {
        let fixture = try Fixture()
        try fixture.registry.set(.init(key: "k", flags: [.command, .control]), for: "custom:")
        let event = try fixture.event(40, "k", [.command, .control])
        #expect(fixture.registry.nativeCommand(for: event, editable: false)?.item === fixture.custom)
    }

    @Test @MainActor func theFirstRegisteredOwnerOfASharedChordWins() throws {
        let fixture = try Fixture()
        let duplicate = NSMenuItem(title: "decoy0-dup", action: #selector(Target.decoy), keyEquivalent: "a")
        duplicate.keyEquivalentModifierMask = [.command, .option]
        duplicate.target = fixture.target
        fixture.menu.addItem(duplicate)
        fixture.registry.register(duplicate, group: "View", bindingID: "decoy0:")
        let event = try fixture.event(0, "a", [.command, .option])
        #expect(fixture.registry.nativeCommand(for: event, editable: false)?.item === fixture.decoys[0])
    }

    @Test @MainActor func aPhysicalOwnerIndexedAfterMutationBeatsSymbolicPlus() throws {
        let fixture = try Fixture()
        try fixture.registry.set(.init(key: "=", flags: [.command, .shift]), for: "custom:")
        #expect(fixture.registry.nativeCommand(for: try fixture.plus(), editable: false)?.item === fixture.custom)
    }

    @Test @MainActor func anUnavailablePhysicalOwnerStillBlocksSymbolicZoom() throws {
        let fixture = try Fixture()
        try fixture.registry.set(.init(key: "=", flags: [.command, .shift]), for: "custom:")
        fixture.target.enabled = false
        #expect(fixture.registry.nativeCommand(for: try fixture.plus(), editable: false) == nil)
    }

    @Test @MainActor func clearingThePhysicalChordRestoresSymbolicZoom() throws {
        let fixture = try Fixture()
        try fixture.registry.set(.init(key: "=", flags: [.command, .shift]), for: "custom:")
        try fixture.registry.set(nil, for: "custom:")
        #expect(fixture.registry.nativeCommand(for: try fixture.plus(), editable: true)?.item === fixture.zoom)
    }

    @Test @MainActor func disabledZoomLeavesTheIndexAndResetRestoresIt() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: "zoomIn:")
        #expect(fixture.registry.nativeCommand(for: try fixture.plus(), editable: false) == nil)
        #expect(fixture.registry.nativeCommand(for: try fixture.event(24, "=", .command), editable: false) == nil)
        try fixture.registry.reset("zoomIn:")
        #expect(fixture.registry.nativeCommand(for: try fixture.plus(), editable: false)?.item === fixture.zoom)
    }

    private static let layout: KeyboardShortcut.LayoutTyping = { code, _ in code == 0 ? "a" : nil }

    @Test(arguments: [(UInt16(0), "A", NSEvent.ModifierFlags([.command, .option, .shift])),
                      (UInt16(97), "\u{f709}", NSEvent.ModifierFlags([.control, .function]))])
    @MainActor func noticeFocusShortcutsStartOutsideEveryParcCommand(code: UInt16, key: String, flags: NSEvent.ModifierFlags) throws {
        let fixture = try Fixture()
        #expect(!fixture.registry.isAssigned(try fixture.event(code, key, flags), layout: Self.layout))
    }

    @Test(arguments: [(UInt16(0), "A", NSEvent.ModifierFlags([.command, .option, .shift]), "a", "custom:"),
                      (UInt16(97), "\u{f709}", NSEvent.ModifierFlags([.control, .function]), "\u{f709}", "decoy1:")])
    @MainActor func assigningANoticeShortcutToACommandMakesItThePersons(code: UInt16, key: String, flags: NSEvent.ModifierFlags,
                                                                       chordKey: String, id: String) throws {
        let fixture = try Fixture()
        let chordFlags: NSEvent.ModifierFlags = flags.contains(.shift) ? [.command, .option, .shift] : .control
        try fixture.registry.set(.init(key: chordKey, flags: chordFlags), for: id)
        #expect(fixture.registry.isAssigned(try fixture.event(code, key, flags), layout: Self.layout))
    }

    @Test(arguments: [(UInt16(0), "A", NSEvent.ModifierFlags([.command, .option, .shift]), "a", "custom:"),
                      (UInt16(97), "\u{f709}", NSEvent.ModifierFlags([.control, .function]), "\u{f709}", "decoy1:")])
    @MainActor func clearingThatAssignmentGivesTheShortcutBackToNotices(code: UInt16, key: String, flags: NSEvent.ModifierFlags,
                                                                       chordKey: String, id: String) throws {
        let fixture = try Fixture()
        let chordFlags: NSEvent.ModifierFlags = flags.contains(.shift) ? [.command, .option, .shift] : .control
        try fixture.registry.set(.init(key: chordKey, flags: chordFlags), for: id)
        try fixture.registry.set(nil, for: id)
        if id == "decoy1:" { try fixture.registry.reset(id) }
        #expect(!fixture.registry.isAssigned(try fixture.event(code, key, flags), layout: Self.layout))
    }
}
