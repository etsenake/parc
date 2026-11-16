import AppKit

@main struct SidebarFocusTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let ids = ["favorite", "split", "today"]
        var cursor = SidebarKeyboardCursor(highlightedID: "split")
        cursor.move(1, in: ids)
        expect(cursor.highlightedID == "today", "Down highlights next identity")
        cursor.move(1, in: ids)
        expect(cursor.highlightedID == nil, "Last item crosses to no highlight")
        cursor.move(1, in: ids)
        expect(cursor.highlightedID == "favorite", "Down from no highlight enters first")
        cursor.move(-1, in: ids)
        expect(cursor.highlightedID == nil, "First item crosses to no highlight")
        cursor.move(-1, in: ids)
        expect(cursor.highlightedID == "today", "Up from no highlight enters last")
        cursor.reconcile(["today", "favorite", "split"])
        expect(cursor.highlightedID == "today", "Reordering keeps stable identity")
        cursor.move(1, in: ["today", "favorite", "split"])
        expect(cursor.highlightedID == "favorite", "Next uses actual refreshed order")
        cursor.reconcile(["split", "today"])
        expect(cursor.highlightedID == nil, "Removed highlight never changes to another item")
        cursor.move(-1, in: ["split", "today"])
        expect(cursor.highlightedID == "today", "Removed item reentry respects direction")
        cursor.move(0, in: ids)
        expect(cursor.highlightedID == "today", "No movement preserves highlight")
        cursor.move(1, in: [])
        expect(cursor.highlightedID == nil, "Empty list clears retired identity")
        cursor.move(-1, in: [])
        expect(cursor.highlightedID == nil, "Empty list cannot acquire a target")
        cursor.move(1, in: ["only"])
        expect(cursor.highlightedID == "only", "One-item list enters")
        cursor.move(1, in: ["only"])
        expect(cursor.highlightedID == nil, "One-item list still has sentinel")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keyboard-shortcuts.json")
        let chord = KeyboardShortcut(key: " ", flags: [.control])
        let custom = KeyboardShortcut(key: "s", flags: [.command, .option])
        func encoded(_ chord: KeyboardShortcut?) -> [String: Any] {
            guard let chord else { return [:] }
            return ["shortcut": ["key": chord.key, "modifiers": chord.modifiers]]
        }
        func write(_ overrides: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: ["version": 2, "overrides": overrides,
                "priorities": ["other:": "preferParc"]]).write(to: file)
        }
        let registry = KeyboardShortcuts()
        let reveal = NSMenuItem(title: "Reveal Current Tab", action: NSSelectorFromString("focusSidebar:"), keyEquivalent: " ")
        reveal.keyEquivalentModifierMask = .control
        let other = NSMenuItem(title: "Other", action: NSSelectorFromString("other:"), keyEquivalent: "")
        registry.register(reveal, group: "Tabs"); registry.register(other, group: "Tabs")
        registry.configure(directory: directory)
        expect(registry.shortcut(for: "focusSidebar:") == chord, "Fresh installation receives recovered default")
        expect(chord.isValid && !chord.isReserved, "Default passes original registry validation")
        try write(["other:": encoded(chord)])
        registry.configure(directory: directory)
        expect(registry.loadError == nil, "Saved custom chord is readable")
        expect(registry.shortcut(for: "focusSidebar:") == nil, "New default does not steal saved chord")
        expect(registry.shortcut(for: "other:") == chord, "Original custom owner remains")
        expect(registry.priority(for: "other:") == .preferParc, "Original priority remains")
        expect(reveal.keyEquivalent.isEmpty && other.keyEquivalent == " ", "Actual menu binding follows original owner")
        let saved = try Data(contentsOf: file)
        registry.configure(directory: directory)
        let reloaded = try Data(contentsOf: file)
        expect(reloaded == saved, "Saved conflict protection is idempotent")
        try registry.reset("focusSidebar:")
        expect(registry.isConflicting("focusSidebar:") && reveal.keyEquivalent.isEmpty && other.keyEquivalent.isEmpty, "Explicit Reset exposes the conflict and suppresses both menu bindings")
        try write(["focusSidebar:": encoded(custom), "other:": encoded(chord)])
        registry.configure(directory: directory)
        expect(registry.shortcut(for: "focusSidebar:") == custom, "Explicit custom focus binding survives")
        try write(["focusSidebar:": encoded(nil)])
        registry.configure(directory: directory)
        expect(registry.shortcut(for: "focusSidebar:") == nil, "Explicitly disabled focus command survives")
        try write([:])
        registry.configure(directory: directory)
        expect(registry.shortcut(for: "focusSidebar:") == chord, "Uncontested existing file receives default")
        try registry.resetAll()
        expect(registry.shortcut(for: "focusSidebar:") == chord, "Explicit Reset All restores current default")
        print("PASS: \(checks) sidebar-focus assertions")
    }
}
