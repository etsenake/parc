import AppKit

@MainActor private final class ChordIndexTarget: NSObject, NSMenuItemValidation {
    var enabled = true
    var delivered: NSMenuItem?
    func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
    @objc func zoomIn(_ sender: NSMenuItem) { delivered = sender }
    @objc func custom(_ sender: NSMenuItem) { delivered = sender }
    @objc func decoy(_ sender: NSMenuItem) { delivered = sender }
    @objc func developerTools(_ sender: NSMenuItem) { delivered = sender }
}

@main @MainActor struct ChordIndexTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = ChordIndexTarget()
        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let rootMenu = NSMenu(), parent = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "View"); parent.submenu = menu; rootMenu.addItem(parent); NSApp.mainMenu = rootMenu
        func add(_ id: String, key: String, flags: NSEvent.ModifierFlags, action: String) -> NSMenuItem {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = flags; item.target = target; menu.addItem(item)
            registry.register(item, group: "View", bindingID: id)
            return item
        }
        func event(_ code: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags = [], repeat repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                             windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                             isARepeat: repeating, keyCode: code)!
        }
        var decoys: [NSMenuItem] = []
        for index in 0..<40 {
            let letter = String(UnicodeScalar(UInt8(97 + (index % 26))))
            let flags: NSEvent.ModifierFlags = index < 26 ? [.command, .option] : [.control, .option]
            decoys.append(add("decoy\(index):", key: letter, flags: flags, action: "decoy:"))
        }
        let zoom = add("zoomIn:", key: "+", flags: .command, action: "zoomIn:")
        let equals = NSMenuItem(title: "zoomIn:", action: #selector(ChordIndexTarget.zoomIn), keyEquivalent: "=")
        equals.target = target; equals.keyEquivalentModifierMask = .command
        equals.isHidden = true; equals.allowsKeyEquivalentWhenHidden = true; menu.addItem(equals)
        registry.registerEquivalent(equals, for: "zoomIn:", shortcut: .init(key: "=", flags: .command))
        let custom = add("custom:", key: "", flags: [], action: "custom:")
        let f12 = add("developerTools_Alternate", key: "\u{f70f}", flags: [], action: "developerTools:")
        f12.isHidden = true; f12.allowsKeyEquivalentWhenHidden = true
        f12.keyEquivalent = "\u{f70f}"; f12.keyEquivalentModifierMask = []

        expect(registry.nativeCommand(for: event(0, "a"), editable: true) == nil,
               "Unmodified letter in an editable field is not a native shortcut")
        expect(registry.nativeCommand(for: event(0, "a"), editable: false) == nil,
               "Unmodified letter outside editing is still not a native shortcut")
        expect(registry.nativeCommand(for: event(0, "a", .shift), editable: true) == nil,
               "Shift-letter without Command/Control/Option stays with the page")
        expect(registry.nativeCommand(for: event(0, "å", .option), editable: true) == nil,
               "Option letter that is not a registered chord does not scan into a command")
        expect(registry.nativeCommand(for: event(123, "\u{f702}"), editable: true) == nil,
               "Unmodified arrow stays with the page")
        expect(registry.nativeCommand(for: event(0, "a", .command, repeat: true), editable: false) == nil,
               "Autorepeat remains excluded")
        expect(registry.nativeCommand(for: event(8, "c", .command), editable: true) == nil,
               "Reserved Command-C stays with text editing")
        let f12Event = event(111, "\u{f70f}", .function)
        expect(registry.nativeCommand(for: f12Event, editable: true)?.item === f12,
               "F12 still resolves among many unrelated chords, including in editable content")
        expect(registry.nativeCommand(for: event(24, "=", .command), editable: true)?.item === equals,
               "Indexed equals equivalent still owns Command-equals")
        let plus = event(24, "+", [.command, .shift])
        expect(registry.nativeCommand(for: plus, editable: true)?.item === zoom,
               "Indexed symbolic plus still owns Shift-Command-equals")
        try registry.set(.init(key: "k", flags: [.command, .control]), for: "custom:")
        expect(registry.nativeCommand(for: event(40, "k", [.command, .control]), editable: false)?.item === custom,
               "A newly assigned chord is visible to the next lookup")
        let duplicate = NSMenuItem(title: "decoy0-dup", action: #selector(ChordIndexTarget.decoy), keyEquivalent: "a")
        duplicate.keyEquivalentModifierMask = [.command, .option]; duplicate.target = target; menu.addItem(duplicate)
        registry.register(duplicate, group: "View", bindingID: "decoy0:")
        expect(registry.nativeCommand(for: event(0, "a", [.command, .option]), editable: false)?.item === decoys[0],
               "First registered live owner of a shared command chord still wins")
        try registry.set(.init(key: "=", flags: [.command, .shift]), for: "custom:")
        expect(registry.nativeCommand(for: plus, editable: false)?.item === custom,
               "Physical owner indexed after mutation wins over symbolic plus")
        target.enabled = false
        expect(registry.nativeCommand(for: plus, editable: false) == nil,
               "Unavailable physical owner still blocks symbolic Zoom")
        target.enabled = true
        try registry.set(nil, for: "custom:")
        expect(registry.nativeCommand(for: plus, editable: true)?.item === zoom,
               "Clearing the physical chord restores indexed symbolic Zoom")
        try registry.set(nil, for: "zoomIn:")
        expect(registry.nativeCommand(for: plus, editable: false) == nil,
               "Disabled Zoom is dropped from the live-chord index")
        expect(registry.nativeCommand(for: event(24, "=", .command), editable: false) == nil,
               "Disabled Zoom also drops its equals equivalent")
        try registry.reset("zoomIn:")
        expect(registry.nativeCommand(for: plus, editable: false)?.item === zoom,
               "Reset restores the indexed symbolic default")
        f12.menu?.removeItem(f12)
        expect(registry.nativeCommand(for: f12Event, editable: false) == nil,
               "Detached indexed owner cannot dispatch")
        print("PASS: \(count) live-chord index assertions")
    }
}
