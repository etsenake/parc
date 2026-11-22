import AppKit
import Testing
@testable import Parc

struct AlternateBindingTests {
    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var enabled = true
        var delivered: NSMenuItem?
        func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
        @objc func goBack(_ sender: NSMenuItem) { delivered = sender }
        @objc func goForward(_ sender: NSMenuItem) { delivered = sender }
        @objc func goBackArrow(_ sender: NSMenuItem) { delivered = sender }
        @objc func goForwardArrow(_ sender: NSMenuItem) { delivered = sender }
        @objc func developerTools(_ sender: NSMenuItem) { delivered = sender }
        @objc func zoomIn(_ sender: NSMenuItem) { delivered = sender }
        @objc func zoomOut(_ sender: NSMenuItem) { delivered = sender }
        @objc func custom(_ sender: NSMenuItem) { delivered = sender }
    }

    private static let rows: [(id: String, chord: KeyboardShortcut)] = [
        ("goBack_Alternate", .init(key: "\u{f702}", flags: .command)),
        ("goForward_Alternate", .init(key: "\u{f703}", flags: .command)),
        ("developerTools_Alternate", .init(key: "\u{f70f}", flags: [])),
    ]
    private static let customChord = KeyboardShortcut(key: "k", flags: [.command, .control])
    private static let equalsChord = KeyboardShortcut(key: "=", flags: .command)

    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = Target()
        let menu = NSMenu(title: "View")
        let registry: KeyboardShortcuts
        var items: [String: NSMenuItem] = [:]
        var file: URL { root.appendingPathComponent("keyboard-shortcuts.json") }

        init(document: [String: Any]? = nil) throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if let document { try JSONSerialization.data(withJSONObject: document).write(to: root.appendingPathComponent("keyboard-shortcuts.json")) }
            let menu = menu
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            registry.configure(directory: root)
            registerItems()
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func registerItems() {
            for (id, key, flags) in [
                ("goBack:", "[", NSEvent.ModifierFlags.command), ("goForward:", "]", .command),
                ("developerTools:", "i", [.command, .option]), ("zoomIn:", "+", .command),
                ("zoomOut:", "-", .command), ("custom:", "", [])] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags
                item.target = target
                menu.addItem(item)
                registry.register(item, group: "View")
                items[id] = item
            }
            for (id, chord) in AlternateBindingTests.rows {
                let action = id == "developerTools_Alternate" ? "developerTools:" : id.replacingOccurrences(of: "_Alternate", with: "Arrow:")
                let item = NSMenuItem(title: id, action: NSSelectorFromString(action), keyEquivalent: chord.key)
                item.target = target
                item.keyEquivalentModifierMask = chord.flags
                item.isHidden = true
                item.allowsKeyEquivalentWhenHidden = true
                menu.addItem(item)
                registry.register(item, group: "View", bindingID: id, discoverable: false)
                items[id] = item
            }
            for (id, key, flags) in [("zoomIn:", "=", NSEvent.ModifierFlags.command), ("zoomOut:", "-", [.command, .shift])] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.target = target
                item.keyEquivalentModifierMask = flags
                item.isHidden = true
                item.allowsKeyEquivalentWhenHidden = true
                menu.addItem(item)
                registry.registerEquivalent(item, for: id, shortcut: .init(key: key, flags: flags))
                items[id + "equivalent"] = item
            }
        }

        func event(_ code: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags = [], repeating: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: repeating, keyCode: code))
        }

        func f12() throws -> NSEvent { try event(111, "\u{f70f}", .function) }
        func plus() throws -> NSEvent { try event(24, "+", [.command, .shift]) }

        func reload() { registry.configure(directory: root) }

        func item(_ id: String) throws -> NSMenuItem { try #require(items[id]) }

        func savedData() throws -> Data { try Data(contentsOf: file) }
    }

    private static func encoded(_ chord: KeyboardShortcut?) -> [String: Any] {
        chord.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
    }

    private static func legacy(_ version: Int) -> [String: Any] {
        ["version": version, "developerDefaults": 1, "selectionCommandDefaults": 1, "menuPriorityDefaults": 1,
         "creationShortcutDefaults": 1,
         "overrides": ["goBack:": encoded(nil), "goForward:": encoded(customChord), "custom:": encoded(rows[2].chord)],
         "priorities": ["custom:": "preferParc"]]
    }

    @Test(arguments: rows)
    @MainActor func eachAlternateShipsItsOwnBindingAndMenuChord(id: String, chord: KeyboardShortcut) throws {
        let fixture = try Fixture()
        #expect(fixture.registry.shortcut(for: id) == chord)
        #expect(try fixture.item(id).keyEquivalent == chord.key)
        #expect(fixture.registry.supportsPriority(id))
    }

    @Test @MainActor func theArrowAlternateIsWebsiteFirstAndF12KeepsItsOriginalPriority() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.priority(for: "goBack_Alternate") == .preferWebsites)
        #expect(fixture.registry.priority(for: "developerTools_Alternate") == .useBoth)
    }

    @Test @MainActor func alternatesAndZoomEquivalentsAddNoActionsCandidates() throws {
        let fixture = try Fixture()
        let window = CommandBarTestSupport.borderlessWindow()
        let candidates = fixture.registry.menuCommands(in: window)
        #expect(candidates.count == 6)
        #expect(!candidates.contains { $0.id.contains("_Alternate") })
    }

    @Test @MainActor func onlyAlternatesGetTheirOwnEditableIdentity() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.commands.count == 9)
    }

    @Test(arguments: [("a", UInt16(0), false), ("\u{1b}", 53, false), ("a", 123, true)])
    @MainActor func plainReservedAndTypedCharacterEventsStayWithThePage(key: String, code: UInt16, command: Bool) throws {
        let fixture = try Fixture()
        let event = try fixture.event(code, key, command ? .command : [])
        #expect(fixture.registry.nativeCommand(for: event, editable: false) == nil)
    }

    @Test @MainActor func theArrowAlternateOwnsItsOriginalMenuItem() throws {
        let fixture = try Fixture()
        let event = try fixture.event(123, "\u{f702}", .command)
        let command = try #require(fixture.registry.nativeCommand(for: event, editable: false))
        #expect(command.item === (try fixture.item("goBack_Alternate")))
    }

    @Test @MainActor func anUnavailableOriginalTargetIsNotDispatched() throws {
        let fixture = try Fixture()
        fixture.target.enabled = false
        #expect(fixture.registry.nativeCommand(for: try fixture.f12(), editable: false) == nil)
    }

    @Test @MainActor func disablingAnAlternateLeavesItsPrimaryBindingAlone() throws {
        let fixture = try Fixture()
        let event = try fixture.f12()
        let retained = try #require(fixture.registry.nativeCommand(for: event, editable: false))
        try fixture.registry.set(nil, for: "developerTools_Alternate")
        #expect(fixture.registry.nativeCommand(for: event, editable: false) == nil)
        #expect(fixture.registry.shortcut(for: "developerTools:") == .init(key: "i", flags: [.command, .option]))
        #expect(!fixture.registry.perform(retained, event: event, editable: false))
    }

    @Test @MainActor func anAlternateIsEditedIndependentlyOfItsPrimary() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: "goBack:")
        #expect(fixture.registry.shortcut(for: "goBack_Alternate") != nil)
    }

    @Test @MainActor func aPriorityEditReachesTheNativeOwner() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: "developerTools_Alternate")
        try fixture.registry.reset("developerTools_Alternate")
        try fixture.registry.setPriority(.preferParc, for: "developerTools_Alternate")
        #expect(fixture.registry.nativeCommand(for: try fixture.f12(), editable: false)?.priority == .preferParc)
    }

    @Test @MainActor func zoomEquivalentsKeepTheirMenuChords() throws {
        let fixture = try Fixture()
        #expect(try fixture.item("zoomIn:equivalent").keyEquivalent == "=")
        #expect(try fixture.item("zoomOut:equivalent").keyEquivalentModifierMask == [.command, .shift])
    }

    @Test @MainActor func theEqualsSupplementUsesItsOwnValidatedMenuItem() throws {
        let fixture = try Fixture()
        let zoom = try #require(fixture.registry.nativeCommand(for: try fixture.event(24, "=", .command), editable: false))
        #expect(zoom.item === (try fixture.item("zoomIn:equivalent")))
        #expect(fixture.registry.settingsCommandID(for: zoom) == "zoomIn:")
    }

    @Test @MainActor func shiftedEqualsIsRecordedAsThePhysicalKey() throws {
        let fixture = try Fixture()
        let captured = KeyboardShortcut.capture(try fixture.plus())
        #expect(captured == .init(key: "=", flags: [.command, .shift]))
    }

    @Test @MainActor func appKitMatchesTheSymbolicPlusForTheOriginalZoomItem() throws {
        let fixture = try Fixture()
        let menu = NSMenu()
        let plus = NSMenuItem(title: "Zoom In", action: #selector(Target.zoomIn), keyEquivalent: "+")
        plus.target = fixture.target
        plus.keyEquivalentModifierMask = .command
        menu.addItem(plus)
        #expect(menu.performKeyEquivalent(with: try fixture.plus()))
        #expect(fixture.target.delivered === plus)
    }

    @Test @MainActor func shiftProducedPlusKeepsThePrimaryZoomOwner() throws {
        let fixture = try Fixture()
        let symbolic = try #require(fixture.registry.nativeCommand(for: try fixture.plus(), editable: false))
        #expect(symbolic.item === (try fixture.item("zoomIn:")))
        #expect(fixture.registry.settingsCommandID(for: symbolic) == "zoomIn:")
    }

    @Test @MainActor func aSavedPhysicalChordSuppressesTheSymbolicMenuFallback() throws {
        let fixture = try Fixture()
        try fixture.registry.set(.init(key: "=", flags: [.command, .shift]), for: "custom:")
        let event = try fixture.plus()
        #expect(fixture.registry.nativeCommand(for: event, editable: false)?.item === (try fixture.item("custom:")))
        _ = fixture.menu.performKeyEquivalent(with: event)
        #expect(fixture.target.delivered !== (try fixture.item("zoomIn:")))
        #expect(try fixture.item("zoomIn:").keyEquivalent.isEmpty)
        #expect(fixture.registry.shortcut(for: "zoomIn:") == .init(key: "+", flags: .command))
    }

    @Test @MainActor func aKeyboardLayoutChangeKeepsTheSuppressionAndExpiresTokens() throws {
        let fixture = try Fixture()
        try fixture.registry.set(.init(key: "=", flags: [.command, .shift]), for: "custom:")
        let before = fixture.registry.revision
        fixture.registry.keyboardLayoutDidChange()
        #expect(fixture.registry.revision > before)
        #expect(try fixture.item("zoomIn:").keyEquivalent.isEmpty)
    }

    @Test @MainActor func anUnavailablePhysicalOwnerBlocksTheNativeMenuFallback() throws {
        let fixture = try Fixture()
        try fixture.registry.set(.init(key: "=", flags: [.command, .shift]), for: "custom:")
        fixture.target.enabled = false
        _ = fixture.menu.performKeyEquivalent(with: try fixture.plus())
        #expect(fixture.target.delivered == nil)
    }

    @Test @MainActor func clearingThePhysicalConflictRestoresTheSymbolicZoom() throws {
        let fixture = try Fixture()
        try fixture.registry.set(.init(key: "=", flags: [.command, .shift]), for: "custom:")
        try fixture.registry.set(nil, for: "custom:")
        let event = try fixture.plus()
        #expect(fixture.registry.nativeCommand(for: event, editable: true)?.item === (try fixture.item("zoomIn:")))
        #expect(try fixture.item("zoomIn:").keyEquivalent == "+")
        #expect(fixture.menu.performKeyEquivalent(with: event))
        #expect(fixture.target.delivered === (try fixture.item("zoomIn:")))
    }

    @Test @MainActor func disablingZoomBlocksTheEqualsSupplementAndExpiresItsToken() throws {
        let fixture = try Fixture()
        let event = try fixture.event(24, "=", .command)
        let supplemental = try #require(fixture.registry.nativeCommand(for: event, editable: false))
        try fixture.registry.set(nil, for: "zoomIn:")
        #expect(try fixture.item("zoomIn:equivalent").keyEquivalent.isEmpty)
        #expect(!fixture.registry.perform(supplemental, event: event, editable: false))
    }

    @Test @MainActor func aCustomZoomChordSuppressesTheOldSymbolicDefaultAndEquals() throws {
        let fixture = try Fixture()
        try fixture.registry.set(Self.customChord, for: "zoomIn:")
        #expect(fixture.registry.nativeCommand(for: try fixture.plus(), editable: false) == nil)
        #expect(try fixture.item("zoomIn:equivalent").keyEquivalent.isEmpty)
    }

    @Test @MainActor func aCustomZoomOutChordDropsItsSupplementalChord() throws {
        let fixture = try Fixture()
        try fixture.registry.set(Self.customChord, for: "zoomOut:")
        #expect(try fixture.item("zoomOut:equivalent").keyEquivalent.isEmpty)
    }

    @Test @MainActor func aSavedChordWinsTheEqualsCollisionUntilItClears() throws {
        let fixture = try Fixture()
        try fixture.registry.set(Self.equalsChord, for: "custom:")
        let event = try fixture.event(24, "=", .command)
        #expect(try fixture.item("zoomIn:equivalent").keyEquivalent.isEmpty)
        #expect(fixture.registry.nativeCommand(for: event, editable: false)?.item === (try fixture.item("custom:")))
        try fixture.registry.set(nil, for: "custom:")
        #expect(try fixture.item("zoomIn:equivalent").keyEquivalent == "=")
    }

    @Test @MainActor func aStartupSavedChordSuppressesTheEqualsEquivalentUntilItClears() throws {
        let fixture = try Fixture(document: ["version": 3, "overrides": ["custom:": Self.encoded(Self.equalsChord)]])
        #expect(try fixture.item("zoomIn:equivalent").keyEquivalent.isEmpty)
        try fixture.registry.set(nil, for: "custom:")
        #expect(try fixture.item("zoomIn:equivalent").keyEquivalent == "=")
    }

    @Test @MainActor func arrowNavigationIsLeftToNativeTextResponders() throws {
        _ = NSApplication.shared
        let window = CommandBarTestSupport.borderlessWindow()
        let container = NSView()
        window.contentView = container
        let text = NSTextView()
        container.addSubview(text)
        let child = NSView()
        text.addSubview(child)
        let field = NSTextField()
        container.addSubview(field)
        window.makeFirstResponder(text)
        #expect(!KeyboardShortcuts.permitsArrowNavigation(in: window))
        window.makeFirstResponder(field)
        #expect(!KeyboardShortcuts.permitsArrowNavigation(in: window))
        window.makeFirstResponder(nil)
        #expect(KeyboardShortcuts.permitsArrowNavigation(in: window))
        #expect(!KeyboardShortcuts.permitsArrowNavigation(in: nil))
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func legacyCustomizationIsNotBypassedByTheAlternates(version: Int) throws {
        let fixture = try Fixture(document: Self.legacy(version))
        for row in Self.rows { #expect(fixture.registry.shortcut(for: row.id) == nil) }
        #expect(fixture.registry.shortcut(for: "goBack:") == nil)
        #expect(fixture.registry.shortcut(for: "goForward:") == Self.customChord)
        #expect(fixture.registry.priority(for: "custom:") == .preferParc)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func theAlternateMigrationIsIdempotent(version: Int) throws {
        let fixture = try Fixture(document: Self.legacy(version))
        let migrated = try fixture.savedData()
        fixture.reload()
        #expect(try fixture.savedData() == migrated)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func resettingAnAlternateAdoptsItsDefaultOrShowsItsConflict(version: Int) throws {
        let fixture = try Fixture(document: Self.legacy(version))
        try fixture.registry.reset("goBack_Alternate")
        #expect(fixture.registry.shortcut(for: "goBack_Alternate") == Self.rows[0].chord)
        try fixture.registry.reset("developerTools_Alternate")
        #expect(fixture.registry.isConflicting("developerTools_Alternate"))
        #expect(fixture.registry.activeShortcut(for: "developerTools_Alternate") == nil)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func resetAllRestoresTheAlternateDefaults(version: Int) throws {
        let fixture = try Fixture(document: Self.legacy(version))
        try fixture.registry.resetAll()
        for row in Self.rows { #expect(fixture.registry.shortcut(for: row.id) == row.chord) }
    }

    @Test @MainActor func anUneditedLegacyFileReceivesTheNewAlternates() throws {
        let fixture = try Fixture(document: ["version": 3, "overrides": [String: Any]()])
        for row in Self.rows { #expect(fixture.registry.shortcut(for: row.id) == row.chord) }
    }
}
