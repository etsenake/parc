import AppKit

@main @MainActor struct SplitCellMenuTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "—" : $0.title } }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        try menuOrder()
        try marginHandle()
        print("SplitCellMenuTests: \(count) assertions passed")
    }

    static func menuOrder() throws {
        var ran: [String] = []
        let action: (String) -> () -> Bool = { name in { ran.append(name); return true } }
        let childTab = NSMenu()
        childTab.addItem(NSMenuItem(title: "Separate Tab from Split View", action: nil, keyEquivalent: ""))
        childTab.addItem(NSMenuItem(title: "Open in Split View", action: nil, keyEquivalent: ""))
        childTab.addItem(NSMenuItem(title: "Pin tab", action: nil, keyEquivalent: ""))
        childTab.addItem(.separator())
        childTab.addItem(NSMenuItem(title: "Copy Link", action: nil, keyEquivalent: ""))
        childTab.addItem(NSMenuItem(title: "Archive Tab", action: nil, keyEquivalent: ""))
        let child = SidebarSplitCellMenu.childSubmenu(separate: action("separate child"), tabMenu: childTab,
                                                      replacing: ["Separate Tab from Split View", "Open in Split View"])
        try check(titles(child) == ["Separate from Split View", "—", "Pin tab", "—", "Copy Link", "Archive Tab"],
                  "A child submenu leads with Separate from Split View and drops the tab menu's own split entries")
        try check(childTab.items.isEmpty, "The child's tab items move into its submenu")

        var model = SidebarSplitCellMenu(orientation: .horizontal)
        var bindings: [String: String] = [:]
        model.bindShortcut = { item, id in bindings[item.title] = id }
        model.separateAll = action("separate all"); model.addTab = action("add")
        model.convert = action("convert")
        model.children = [("First", child), ("Second", NSMenu())]
        model.reset = action("reset"); model.changeIcon = action("icon"); model.rename = action("rename")
        model.duplicate = action("duplicate"); model.newFolder = action("folder")
        model.moves = [NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")]
        model.archive = action("archive"); model.close = action("close")
        model.archiveGroup = zip(SidebarSplitCellMenu.archiveGroupTitles, ["others", "below", "above"]).map { ($0, action($1)) }
        let menu = model.makeMenu()
        try check(bindings == ["Rename…": "renameCurrentItem:", "Duplicate": "duplicateCurrentItem:",
                               "New Folder with 1 Items": "createFolder:"],
                  "The window binds only the recovered Rename, Duplicate and New Folder discovery entries")
        try check(titles(menu) == ["Separate All Tabs", "Add Tab…", "Convert to Vertical Split View",
                                   "—", "Tab Options", "First", "Second",
                                   "—", "Reset Name and Icon", "Change Icon…", "Rename…",
                                   "—", "Duplicate", "Move to", "New Folder with 1 Items",
                                   "—", "Archive Item", "Archive Other Tabs", "Archive Tabs Below", "Archive Tabs Above", "Close"],
                  "The split menu follows its append order")
        try check(menu.item(withTitle: "Tab Options")?.isEnabled == false && menu.item(withTitle: "First")?.submenu === child,
                  "Tab Options is a header over one submenu per child")
        try check(!menu.items.contains { $0.title.hasPrefix("Share") }, "Share Split View… is absent")
        try check((menu.items + child.items).allSatisfy { $0.image == nil },
                  "No split cell menu item has an image")
        for item in menu.items where item.action != nil && item.isEnabled && item.submenu == nil {
            _ = (item.target as? NSObject)?.perform(item.action, with: item)
        }
        try check(ran == ["separate all", "add", "convert", "reset", "icon", "rename", "duplicate", "folder", "archive", "others", "below", "above", "close"],
                  "Each enabled item runs its own prepared action once")

        var stacked = SidebarSplitCellMenu(orientation: .vertical)
        stacked.showsNewFolder = false
        let bare = stacked.makeMenu()
        try check(titles(bare) == ["Separate All Tabs", "Add Tab…", "Convert to Horizontal Split View",
                                   "—", "Reset Name and Icon", "Change Icon…", "Rename…",
                                   "—", "Duplicate", "—", "Archive Item", "Close"],
                  "A stacked split converts to horizontal; no children omits Tab Options; a pinned split has no archive group; private windows omit New Folder")
        try check(SidebarSplitCellMenu.newFolderTitle(count: 3) == "New Folder with 3 Items", "The folder item counts the selected items")
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        let sets = SidebarSplitCellMenu.archiveGroupIDs(order: [a, b, c, d, e], children: [b, c])
        try check(sets == [[a, d, e], [d, e], [a]], "Archive Other/Below/Above take the Today tabs around the split's children")
        try check(SidebarSplitCellMenu.archiveGroupIDs(order: [a, d], children: [b]) == nil, "A split outside the Today order has no archive group")
        try check(bare.items.filter { !$0.isSeparatorItem }.allSatisfy { !$0.isEnabled },
                  "Reset Name and Icon and every other item without an action stays visible and disabled")
    }

    static func marginHandle() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let root = NSView(frame: window.contentLayoutRect)
        window.contentView = root
        let handle = SplitMarginHandleView(frame: NSRect(x: 390, y: 10, width: 10, height: 280))
        root.addSubview(handle)
        let split = ParcSplitView(frame: NSRect(x: 10, y: 10, width: 380, height: 280))
        root.addSubview(split)
        split.marginHandle = handle
        try check(!handle.isShown && handle.region.isEmpty, "Nothing shows until the window and split both admit it")
        let page = NSView(), other = NSView()
        split.addArrangedSubview(page)
        split.configure(orientation: .horizontal, factors: [1])
        handle.windowAllows = true
        try check(handle.isShown, "One page outside a split shows the margin grip")
        try check(handle.region == NSRect(x: 0, y: 140 - 22, width: 10, height: 44),
                  "The draggable band is the handle's width, 44 points centred vertically")
        let grip = handle.layer?.sublayers?.first { $0.name == "Split margin grip" }
        try check(grip?.frame == NSRect(x: 4, y: 128, width: 2, height: 24) && grip?.isHidden == false,
                  "The two-by-24 grip is centred on the handle")
        try check(handle.hitTest(NSPoint(x: 395, y: 150)) == nil, "The handle takes no mouse events (pan and double click do nothing here)")
        try check(handle.trackingAreas.count == 1 && handle.trackingAreas[0].rect == handle.region
                  && handle.trackingAreas[0].options == [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .enabledDuringMouseDrag],
                  "Hover tracks the band with the handle's 0x423 options")
        split.addArrangedSubview(other)
        split.configure(orientation: .horizontal, factors: [1, 1])
        try check(!handle.isShown && handle.region.isEmpty && handle.trackingAreas.isEmpty && grip?.isHidden == true,
                  "A second pane (the split's last pane) hides the grip and empties the band")
        split.removeArrangedSubview(other)
        split.configure(orientation: .horizontal, factors: [1])
        try check(handle.isShown, "Returning to one page shows it again")
        handle.windowAllows = false
        try check(!handle.isShown && handle.trackingAreas.isEmpty, "A split, draft, stacked layout or popup window hides it")
        handle.windowAllows = true
        handle.frame = .zero
        try check(!handle.isShown, "No margin (full screen or beside the side panel) hides it")
    }
}
