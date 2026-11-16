import AppKit

@main @MainActor struct SpaceManagementTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func rejects(_ body: () throws -> Void, _ message: String) throws {
        do { try body() } catch { count += 1; return }
        throw NSError(domain: message, code: -1)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-management-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let original = store.activeSpace
        try check(original.title == nil && original.name == "Space 1", "fresh Space is untitled")
        let secondID = store.createSpace(name: "")
        try check(store.activeSpace.id == secondID && store.activeSpace.title == nil && store.activeSpace.name == "Space 2", "empty creation uses position")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.state)) as! [String: Any]
        var spaces = legacy["spaces"] as! [[String: Any]]
        for index in spaces.indices { spaces[index].removeValue(forKey: "title") }
        legacy["spaces"] = spaces
        let migrated = try JSONDecoder().decode(BrowserState.self, from: JSONSerialization.data(withJSONObject: legacy))
        try check(migrated.spaces.allSatisfy { $0.title == nil }, "legacy positional names migrate once")
        var shifted = migrated.spaces[1]; shifted.updateDisplayName(position: 0)
        try check(shifted.title == nil && shifted.name == "Space 1", "untitled Space follows reordered position")
        try store.saveSpaceTitle(original, title: "Space 1")
        let explicit = store.state.spaces[0]
        try check(explicit.title == "Space 1", "literal placeholder remains an authored title")
        let reloaded = try BrowserStore(directory: directory)
        try check(reloaded.state.spaces[0].title == "Space 1", "explicit positional title survives persistence")
        try rejects({ try store.saveSpaceTitle(original, title: "Overwritten") }, "stale title lease must fail")
        try check(store.state.spaces[0].title == "Space 1", "stale edit preserves competing title")
        var theme = explicit.theme; theme.noise = 0.35
        _ = store.setSpaceTheme(explicit.id, theme: theme)
        try store.saveSpaceTitle(explicit, title: "Work")
        try check(store.state.spaces[0].title == "Work" && store.state.spaces[0].theme == theme, "rename preserves independently edited theme")
        let work = store.state.spaces[0]
        try store.saveSpaceTitle(work, title: "")
        try check(store.state.spaces[0].title == nil && store.state.spaces[0].name == "Space 1", "empty rename restores placeholder")
        let untitled = store.state.spaces[0]
        try store.saveSpaceIcon(untitled, icon: .emoji("🌿"))
        try check(store.state.spaces[0].customIcon == .emoji("🌿"), "real icon mutation")
        try rejects({ try store.saveSpaceIcon(untitled, icon: .emoji("🌊")) }, "stale icon lease must fail")
        let iconSpace = store.state.spaces[0]
        try store.saveSpaceIcon(iconSpace, icon: nil)
        try check(store.state.spaces[0].customIcon == nil, "Remove resets custom icon")
        var alien = store.state.spaces[0]; alien.profileID = UUID()
        try rejects({ try store.saveSpaceTitle(alien, title: "Foreign") }, "reassigned profile refuses retained rename")
        let snapshot = store.state
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        try rejects({ try store.saveSpaceTitle(snapshot.spaces[0], title: "Not saved") }, "disk failure must throw")
        try check(store.state == snapshot, "failed persistence publishes no partial state")
        try FileManager.default.removeItem(at: directory)

        let header = SidebarSpaceHeaderView(frame: NSRect(x: 0, y: 0, width: 228, height: 36))
        let window = NSWindow(contentRect: header.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = header
        header.canShowHeaderButtonsIfPossible = true
        var results: [String?] = []
        try check(header.beginNameEditing(title: "Work") { results.append($0) }, "native name editor begins")
        try check(header.isEditing && header.nameField.isEditable && header.editButton.title == "Done", "editing updates the real header")
        if let editor = header.nameField.currentEditor() as? NSTextView {
            editor.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            header.editButton.performClick(nil)
            try check(header.isEditing && results.isEmpty && editor.hasMarkedText(), "Done preserves marked text")
            editor.unmarkText()
        } else { throw NSError(domain: "missing native field editor", code: -1) }
        header.nameField.stringValue = "Updated"
        _ = header.control(header.nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        try check(results.count == 1 && results[0] == "Updated" && !header.isEditing, "Return commits once")
        _ = header.beginNameEditing(title: "Updated") { results.append($0) }
        header.nameField.stringValue = "Cancelled"
        _ = header.control(header.nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        try check(results.count == 2 && results[1] == nil && !header.nameField.isEditable, "Escape cancels native draft")
        let coverHost = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 36))
        let hoverWindow = NSWindow(contentRect: coverHost.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        hoverWindow.contentView = coverHost
        let titleRow = SidebarSpaceHeaderView(frame: coverHost.bounds)
        coverHost.addSubview(titleRow)
        let centre = NSPoint(x: 114, y: 18)
        let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        let moved = NSEvent.mouseEvent(with: .mouseMoved, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        let cover = NSView(frame: coverHost.bounds)
        coverHost.addSubview(cover)
        titleRow.mouseEntered(with: entered)
        try check(!titleRow.isHovered, "a command surface over the Space title row keeps its hover off")
        cover.removeFromSuperview()
        titleRow.mouseMoved(with: moved)
        try check(titleRow.isHovered, "moving out from under the cover lights the Space title row again")
        let list = NSView(), favorites = NSView()
        let chain = SidebarAccessibility.keyViewChain(leading: [], favorites: favorites, list: list, regions: [],
            trailing: [], space: header, beforeList: [header])
        try check(!chain.contains { $0 === header.editButton } && chain.first === list,
            "the header adds no keyboard stop of its own, so Tab moves straight to the item list")
        var selected = 0
        let menu = SidebarSpaceMenu(includesManagement: true, changeIcon: {},
            shareData: [("Work", true, {}), ("Play", false, { selected += 1 }), ("Retiring", false, nil)],
            keepSeparate: (selected: false, action: { selected += 100 }),
            rename: {}, editTheme: {}, newFolder: {}, toggleTitle: nil, toggleHeader: nil)
        let native = menu.makeMenu()
        try check(native.items.map(\.title) == ["Change Space Icon…", "Rename Space…", "Edit Theme Color…", "Share data with", "New Folder", "Delete Space", "Manage Spaces…"], "menu order and titles")
        let sharing = native.item(withTitle: "Share data with")!.submenu!
        try check(sharing.items.map(\.title) == ["Work", "Play", "Retiring", "", "Keep separate"], "each other Space, a separator and Keep separate")
        try check(sharing.items[0].state == .on && sharing.items[1].state == .off && sharing.items[4].state == .off && !sharing.items[2].isEnabled,
                  "checkmarks show who shares and retirement availability")
        sharing.performActionForItem(at: 1)
        try check(selected == 1, "native submenu reaches actual action")
        sharing.performActionForItem(at: 4)
        try check(selected == 101, "Keep separate reaches its action")
        try check(menu.accessibilityActions.contains { $0.name == "Share data with Play" }, "Space choice is keyboard-independent AX action")
        try check(menu.accessibilityActions.contains { $0.name == "Keep separate" }, "Keep separate is an AX action")
        try check(!menu.accessibilityActions.contains { $0.name == "Share data with Retiring" }, "unavailable Space omitted from AX actions")
        try check(!native.items.contains { $0.title.contains("Profile") } && !sharing.items.contains { $0.title.contains("Profile") }, "the menu never says Profile")
        let alone = SidebarSpaceMenu(includesManagement: true, changeIcon: {}, keepSeparate: (selected: true, action: {}),
                                     rename: {}, editTheme: {}, newFolder: {}, toggleTitle: nil, toggleHeader: nil).makeMenu()
        let aloneChoices = alone.item(withTitle: "Share data with")!.submenu!
        try check(aloneChoices.items.map(\.title) == ["Keep separate"] && aloneChoices.items[0].state == .on, "a lone Space only offers a checked Keep separate")
        selected = 0
        header.onRenameSpace = { selected += 10 }
        header.managementMenu = { nil }
        try check(header.makeMenu().items.isEmpty && header.nameField.accessibilityCustomActions()?.isEmpty == true,
                  "unavailable management owner cannot fall back to stale actions")
        window.contentView = nil
        print("SpaceManagement: \(count) assertions passed")
    }
}
