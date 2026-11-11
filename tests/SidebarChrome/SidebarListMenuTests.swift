import AppKit

@MainActor final class Sidebar: SidebarSpaceMenuSurface {
    var received: [NSEvent] = []
    override func rightMouseDown(with event: NSEvent) { received.append(event) }
}

@MainActor final class Host: NSView {
    var clicks: [NSEvent] = []
    override func mouseDown(with event: NSEvent) { clicks.append(event) }
    override func rightMouseDown(with event: NSEvent) {}
}

@MainActor final class Row: NSView {
    let ownMenu = NSMenu(title: "row")
    var opened = 0
    override func menu(for event: NSEvent) -> NSMenu? { ownMenu }
    override func rightMouseDown(with event: NSEvent) { opened += 1 }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event) }
    }
}

@main @MainActor struct SidebarListMenuTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarListMenu: \(message)") }
    }
    static func space(_ name: String, icon: SidebarGroupIcon? = nil) -> BrowserSpace {
        var space = BrowserSpace(id: UUID(), name: name, symbol: "circle.fill", color: "B9B5D4", profileID: UUID())
        space.customIcon = icon
        if name.hasPrefix("Space "), Int(name.dropFirst(6)) != nil { space.title = nil }
        return space
    }

    @MainActor final class Model {
        let store: BrowserStore
        var fixture: (spaces: [BrowserSpace], active: UUID?)?
        var creating = false, privateWindow = false
        var calls: [String] = []
        var spaces: [BrowserSpace] { fixture?.spaces ?? store.state.spaces }
        var active: UUID? { fixture == nil ? store.state.activeSpaceID : fixture?.active }
        init(store: BrowserStore) { self.store = store }
        func menu() -> SidebarSpaceMenu? {
            SidebarSpaceMenu.sidebar(spaces: spaces, activeSpaceID: active, creatingSpace: creating, privateWindow: privateWindow,
                                     showOnSingleUnnamedSpace: store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false,
                                     rename: { [unowned self] id in calls.append("rename " + (spaces.first { $0.id == id }?.name ?? "?")) },
                                     editTheme: { [unowned self] in calls.append("theme") },
                                     newFolder: { [unowned self] in calls.append("folder") },
                                     toggleHeader: { [unowned self] in store.toggleSpaceHeaderOnSingleUnnamedSpaces() })
        }
    }

    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-list-menu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let model = Model(store: store)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 228, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = Host(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        let sidebar = Sidebar(frame: host.bounds)
        window.contentView = host
        host.addSubview(sidebar)
        sidebar.spaceMenu = { [unowned model] in model.menu() }
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 40, width: 212, height: 600))
        scroll.drawsBackground = false; scroll.adoptTablistScroller(); scroll.horizontalScrollElasticity = .none
        let list = SidebarOutlineView(frame: .zero)
        scroll.documentView = list
        sidebar.addSubview(scroll)
        let pinned = [Row(), Row()], today = [Row(), Row()]
        let clear = ActionButton("↓ Clear"), newTab = ActionButton("New Tab", symbol: "plus")
        let divider = NSView(); divider.addSubview(clear)
        var pinnedRows = pinned.makeIterator(), todayRows = today.makeIterator()
        var entries: [SidebarOutlineEntry] = []
        for slot in SidebarChromeLayout.tablistSlots(pinnedItems: 2, todayItems: 2, isPrivate: false) {
            switch slot {
            case .pinnedHeader: entries.append(.init(key: "header", content: nil, row: slot.row))
            case .pinnedItem: entries.append(.item(.tab(UUID()), content: pinnedRows.next()!, depth: 0, in: nil))
            case .sectionDivider: entries.append(.init(key: "divider", content: divider, row: slot.row))
            case .newTab: entries.append(.init(key: "newTab", content: newTab, row: slot.row))
            case .todayItem: entries.append(.item(.tab(UUID()), content: todayRows.next()!, depth: 0, in: nil))
            case .privateHeading: break
            }
        }
        list.reload(entries)
        list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(0, list.fittingSize.height))
        sidebar.layoutSubtreeIfNeeded(); list.layoutSubtreeIfNeeded()
        clear.frame = NSRect(x: divider.bounds.maxX - 60, y: 2, width: 60, height: 20)
        let lastRow = list.rows.last!
        check(list.rows.count == 7 && lastRow.cell.content === today[1], "the list has the seven rows, the last a Today item")
        check(abs(list.frame.height - (lastRow.frame.maxY + SidebarChromeLayout.tablistBottomInset)) < 0.5
              && list.frame.height < scroll.contentSize.height, "the outline ends with the bottom inset, shorter than its scroll view")

        func point(_ view: NSView, _ local: NSPoint) -> NSPoint { view.convert(local, to: nil) }
        func event(_ type: NSEvent.EventType, _ location: NSPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func deliver(_ type: NSEvent.EventType, at location: NSPoint, _ flags: NSEvent.ModifierFlags = []) -> NSView? {
            guard let hit = sidebar.hitTest(location) else { return nil }
            let delivered = event(type, location, flags)
            if type == .rightMouseDown { hit.rightMouseDown(with: delivered) } else { hit.mouseDown(with: delivered) }
            return hit
        }
        let base = ["Rename Space…", "Edit Theme Color…", "New Folder"]
        func menuTitles() -> [String]? { sidebar.menu(for: event(.rightMouseDown, .zero))?.items.map(\.title) }

        let inset = point(list, NSPoint(x: list.bounds.midX, y: lastRow.frame.maxY + SidebarChromeLayout.tablistBottomInset / 2))
        let below = point(scroll.contentView, NSPoint(x: scroll.contentView.bounds.midX, y: list.frame.maxY + 40))
        let firstToday = list.rows[list.rows.count - 2]
        let gap = point(firstToday, NSPoint(x: firstToday.bounds.midX, y: firstToday.bounds.maxY - 0.5))
        let margin = point(lastRow, NSPoint(x: lastRow.bounds.midX, y: 0.5))
        let header = point(list.rows[0], NSPoint(x: list.rows[0].bounds.midX, y: list.rows[0].bounds.midY))
        let newTabPoint = point(newTab, NSPoint(x: newTab.bounds.midX, y: newTab.bounds.midY))
        let clearPoint = point(clear, NSPoint(x: clear.bounds.midX, y: clear.bounds.midY))
        let empty: [(NSPoint, (NSView?) -> Bool, String, Bool)] = [
            (inset, { $0 === list }, "the bottom inset below the last row", true),
            (below, { $0 === scroll.contentView }, "below the outline", true),
            (gap, { $0 is SidebarOutlineRow }, "the intercell gap between two rows", true),
            (margin, { $0 is SidebarOutlineCell }, "a cell's margin above its visible row", true),
            (header, { $0 is SidebarOutlineCell }, "the empty pinned header row", true),
            (newTabPoint, { $0 === newTab }, "New Tab", false),
            (clearPoint, { $0 === clear }, "Clear", false)]
        for (location, isTarget, place, control) in empty {
            sidebar.received.removeAll()
            let hit = deliver(.rightMouseDown, at: location)
            check(isTarget(hit), "a right-click at \(place) lands on its own view")
            check(sidebar.received.count == 1 && sidebar.received[0].type == .rightMouseDown,
                  "a right-click at \(place) passes up the responder chain to the sidebar")
            guard control else { continue }
            host.clicks.removeAll()
            _ = deliver(.leftMouseDown, at: location, .control)
            check(sidebar.received.count == 2 && sidebar.received[1].type == .leftMouseDown && host.clicks.isEmpty,
                  "a Control-click at \(place) reaches the sidebar's mouseDown:, which opens its menu")
            _ = deliver(.leftMouseDown, at: location)
            check(sidebar.received.count == 2 && host.clicks.count == 1,
                  "a plain click at \(place) opens no menu and passes on to super")
        }
        check(pinned.allSatisfy { $0.opened == 0 } && today.allSatisfy { $0.opened == 0 }, "no row opened its menu for the empty area")

        sidebar.received.removeAll()
        for row in pinned + today {
            let centre = point(row, NSPoint(x: row.bounds.midX, y: row.bounds.midY))
            check(sidebar.hitTest(centre) === row && row.menu(for: event(.rightMouseDown, centre)) === row.ownMenu,
                  "a right-click on a row asks the row for its own menu")
            _ = deliver(.rightMouseDown, at: centre); _ = deliver(.leftMouseDown, at: centre, .control)
            check(row.opened == 2, "the row opens its own menu for a right-click and a Control-click")
        }
        check(sidebar.received.isEmpty, "nothing on a row reaches the sidebar's Space menu")

        let first = store.state.spaces[0]
        check(store.state.spaces.count == 1 && first.name == "Space 1" && store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == nil,
              "a new session has one untitled Space and the setting off")
        var menu = sidebar.menu(for: event(.rightMouseDown, inset))
        check(menu?.items.map(\.title) == base + ["Show Space Header"] && menu?.items.allSatisfy(\.isEnabled) == true,
              "one untitled Space without an icon: the items, then Show Space Header, all enabled")
        menu?.performActionForItem(at: 3)
        check(store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true, "Show Space Header turns the setting on")
        menu = sidebar.menu(for: event(.rightMouseDown, inset))
        check(menu?.items.last?.title == "Hide Space Header" && menu?.items.count == 4, "the next menu offers Hide Space Header")
        menu?.performActionForItem(at: 3)
        check(store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == false && menuTitles()?.last == "Show Space Header",
              "Hide Space Header turns it off and the menu offers Show Space Header again")
        for index in 0..<3 { sidebar.menu(for: event(.rightMouseDown, inset))?.performActionForItem(at: index) }
        check(model.calls == ["rename Space 1", "theme", "folder"], "the menu renames, edits the theme of and adds a folder to the active Space")

        model.calls.removeAll()
        let secondID = store.createSpace(name: "Work")
        check(store.state.activeSpaceID == secondID && menuTitles() == base
              && sidebar.menu(for: event(.rightMouseDown, inset))?.items.allSatisfy(\.isEnabled) == true,
              "two Spaces: the items for the active Space, all enabled, no toggle")
        sidebar.menu(for: event(.rightMouseDown, inset))?.performActionForItem(at: 0)
        store.selectSpace(first.id)
        sidebar.menu(for: event(.rightMouseDown, inset))?.performActionForItem(at: 0)
        check(model.calls == ["rename Work", "rename Space 1"], "Rename Space… names whichever Space is active")
        check(store.state.activeSpaceID == first.id, "the menu switches no Space")
        store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        check(menuTitles() == base, "the setting adds no toggle while the window has two Spaces")
        store.toggleSpaceHeaderOnSingleUnnamedSpaces()

        let lone = space("Space 1"), titled = space("Trips"), starred = space("Space 1", icon: .symbol("star")), unnamed = space("")
        for (fixture, expected, rule) in [(lone, "Show Space Header", "an untitled Space offers the toggle"),
                                          (titled, nil, "a titled Space offers none"),
                                          (starred, nil, "a Space with a custom icon offers none"),
                                          (unnamed, "Show Space Header", "an empty name is untitled")] as [(BrowserSpace, String?, String)] {
            model.fixture = ([fixture], fixture.id)
            check(menuTitles() == base + (expected.map { [$0] } ?? []), rule)
        }
        model.fixture = ([titled, lone], lone.id)
        check(menuTitles() == base, "the active Space's toggle counts the window's Spaces")
        model.fixture = ([lone], nil)
        check(sidebar.menu(for: event(.rightMouseDown, inset)) == nil, "no menu without an active Space")
        model.fixture = ([lone], UUID())
        check(sidebar.menu(for: event(.rightMouseDown, inset)) == nil, "no menu for a Space the window does not have")
        model.fixture = nil

        model.creating = true
        check(sidebar.menu(for: event(.rightMouseDown, inset)) == nil, "no menu while a Space is created")
        model.creating = false; model.privateWindow = true
        check(sidebar.menu(for: event(.rightMouseDown, inset)) == nil, "no menu in a private window")
        model.privateWindow = false
        check(menuTitles() == base, "the menu returns afterwards")
        check(!window.isVisible && !window.isKeyWindow, "the window is never shown or key")
        print("SidebarListMenu: \(count) assertions passed")
    }
}
