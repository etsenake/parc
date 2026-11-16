import AppKit

@main @MainActor struct RenameCommandTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-rename-command-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root)
        let first = store.openResolvedURL(URL(string: "https://first.test/")!)
        let second = store.openResolvedURL(URL(string: "https://second.test/")!)
        let state = store.state, space = state.activeSpaceID, profile = state.spaces.first { $0.id == space }!.profileID
        func target(_ value: BrowserState = state, selection: [UUID]) -> BrowserTab? {
            SidebarTabTitle.currentRenameTab(state: value, spaceID: space, profileID: profile, selectedTabIDs: selection)
        }
        expect(state.selectedTabIDs == [second], "Fixture store has another selected item")
        expect(target(selection: [first])?.id == first, "Window-local selection wins over shared store selection")
        expect(target(selection: []) == nil, "No current item has no rename target")
        expect(target(selection: [first, second]) == nil, "Multiple panes never fall back to first or focused child")
        expect(target(selection: [UUID()]) == nil, "Missing original item is unavailable")
        var grouped = state
        grouped.splitLayouts.append(BrowserSplitLayout(spaceID: space, tabIDs: [first, second], widthFactors: [0.5, 0.5]))
        expect(target(grouped, selection: [first]) == nil, "A saved split child is not its container rename target")
        var changed = state
        changed.tabs[changed.tabs.firstIndex { $0.id == first }!].kind = .favorite
        expect(target(changed, selection: [first]) == nil, "Favorite editor is not fabricated from an ordinary row")
        changed = state; changed.tabs[changed.tabs.firstIndex { $0.id == first }!].archivedAt = Date()
        expect(target(changed, selection: [first]) == nil, "Archived original item is unavailable")
        changed = state; changed.tabs[changed.tabs.firstIndex { $0.id == first }!].spaceID = UUID()
        expect(target(changed, selection: [first]) == nil, "Moved item cannot target another Space")
        changed = state; changed.tabs[changed.tabs.firstIndex { $0.id == first }!].profileID = UUID()
        expect(target(changed, selection: [first]) == nil, "Foreign profile cannot be renamed")
        changed = state; changed.tabs[changed.tabs.firstIndex { $0.id == first }!].url = "parc://note/" + UUID().uuidString
        expect(target(changed, selection: [first]) == nil, "Local document/page naming retains its own owner")
        let before = store.state
        try store.saveSidebarTitle(target(selection: [first])!, title: "Window one")
        expect(store.state.tabs.first { $0.id == first }?.customTitle == "Window one", "Resolved original item uses real title transaction")
        expect(store.state.tabs.first { $0.id == second }?.customTitle == nil, "Another selected window's item remains unchanged")
        expect(store.state.selectedTabIDs == before.selectedTabIDs && store.state.history == before.history, "Rename preserves selection and history")

        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let main = NSMenu(), tabs = NSMenu(title: "Tabs")
        let parent = NSMenuItem(title: "Tabs", action: nil, keyEquivalent: "")
        parent.submenu = tabs; main.addItem(parent); NSApp.mainMenu = main
        let id = "renameCurrentItem:"
        let item = NSMenuItem(title: "Rename Current Tab…", action: NSSelectorFromString(id), keyEquivalent: "")
        item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true; tabs.addItem(item)
        registry.register(item, group: "Tabs")
        expect(registry.commands.contains { $0.id == id }, "Actual hidden command appears in customization")
        expect(registry.shortcut(for: id) == nil, "No invented default key")
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        expect(registry.menuCommands(in: window).contains { $0.id == id && $0.title == "Rename Current Tab…" }, "Attached hidden command appears in genuine command search")
        let chord = KeyboardShortcut(key: "r", flags: [.command, .option])
        try registry.set(chord, for: id); try registry.setPriority(.useBoth, for: id)
        expect(item.keyEquivalent == chord.key && item.keyEquivalentModifierMask == chord.flags, "Custom binding reaches the original menu item")
        registry.configure(directory: root)
        expect(registry.shortcut(for: id) == chord && registry.priority(for: id) == .useBoth, "Binding and priority persist through existing owner")
        try registry.reset(id)
        expect(registry.shortcut(for: id) == nil, "Reset restores unassigned command")
        tabs.removeItem(item)
        expect(!registry.menuCommands(in: window).contains { $0.id == id }, "Detached original item cannot remain an executable search row")
        print("PASS: \(checks) original Rename selection/registry assertions")
    }
}
