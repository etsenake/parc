import AppKit

@main
@MainActor
struct ShortcutPersistSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keyboard-shortcuts.json")
        let registry = KeyboardShortcuts()
        registry.configure(directory: directory)
        let menu = NSMenu(); NSApp.mainMenu = menu
        let item = NSMenuItem(title: "Archive Tab", action: NSSelectorFromString("closeTab:"), keyEquivalent: "w")
        item.keyEquivalentModifierMask = .command
        menu.addItem(item)
        registry.register(item, group: "File")

        let custom = KeyboardShortcut(key: "e", flags: [.command, .option])
        try registry.set(custom, for: "closeTab:")
        expect(FileManager.default.fileExists(atPath: file.path), "First binding change must persist")
        let written = try Data(contentsOf: file)
        let revision = registry.revision
        let firstModified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date

        try registry.set(custom, for: "closeTab:")
        expect(registry.revision == revision, "Identical shortcut recommit must not publish")
        let again = try Data(contentsOf: file)
        expect(again == written, "Identical shortcut recommit must keep pretty JSON bytes")
        let secondModified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date
        expect(secondModified == firstModified, "Identical shortcut recommit must skip atomic rewrite")

        let other = KeyboardShortcut(key: "r", flags: [.command, .option])
        try registry.set(other, for: "closeTab:")
        expect(registry.revision == revision + 1, "Changed shortcut must still publish")
        let changed = try Data(contentsOf: file)
        expect(changed != written, "Changed shortcut must still rewrite pretty JSON")
        expect(registry.shortcut(for: "closeTab:") == other, "Changed shortcut remains live")

        print("\(assertions) shortcut persist skip assertions passed")
    }
}
