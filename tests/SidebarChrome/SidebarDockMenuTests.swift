import AppKit

/// The dock's Space items' context menu: the production SidebarDockItemMenu
/// and SidebarSpaceMenu.dock on a real session store and Space fixtures, on
/// the production SidebarDockStrip in an off-screen window that is never
/// shown or made key. Menus are read and their items performed directly; no
/// menu tracking, pointer input, browser or preferences.
@main @MainActor struct SidebarDockMenuTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarDockMenu: \(message)") }
    }
    static func space(_ name: String, icon: SidebarGroupIcon? = nil) -> BrowserSpace {
        var space = BrowserSpace(id: UUID(), name: name, symbol: "circle.fill", color: "B9B5D4", profileID: UUID())
        space.customIcon = icon
        if name.hasPrefix("Space "), Int(name.dropFirst(6)) == 1 { space.title = nil }
        return space
    }
    /// The accessibility actions an element advertises (AXShowMenu for Show
    /// Menu), read through the informal protocol without its deprecation.
    static func actions(_ element: Any?) -> [String] {
        let selector = NSSelectorFromString("accessibilityActionNames")
        guard let object = element as? NSObject, object.responds(to: selector) else { return [] }
        return object.perform(selector)?.takeUnretainedValue() as? [String] ?? []
    }

    /// Stands in for SidebarView: keeps one button and one item menu per
    /// Space, installs each menu on its button as a render does, and builds
    /// the Space menu with SidebarSpaceMenu.dock as SidebarView.dockSpaceMenu
    /// does, with the store's toggle.
    @MainActor final class Dock {
        let store: BrowserStore
        let strip: SidebarDockStrip
        var fixture: [BrowserSpace]?
        var creating = false
        var calls: [String] = []
        var buttons: [UUID: NSButton] = [:]
        var menus: [UUID: SidebarDockItemMenu] = [:]
        var spaces: [BrowserSpace] { fixture ?? store.state.spaces }
        var active: UUID? { fixture == nil ? store.state.activeSpaceID : fixture?.last?.id }
        init(store: BrowserStore, strip: SidebarDockStrip) { self.store = store; self.strip = strip }

        func spaceMenu(_ id: UUID) -> SidebarSpaceMenu? {
            SidebarSpaceMenu.dock(spaces: spaces, spaceID: id, activeSpaceID: active, creatingSpace: creating,
                                  showOnSingleUnnamedSpace: store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false,
                                  rename: { [unowned self] id in calls.append("rename " + (spaces.first { $0.id == id }?.name ?? "?")) },
                                  editTheme: { [unowned self] in calls.append("theme") },
                                  newFolder: { [unowned self] in calls.append("folder") },
                                  toggleHeader: { [unowned self] in store.toggleSpaceHeaderOnSingleUnnamedSpaces() })
        }
        func render() {
            let buttonsInOrder = spaces.map { space -> NSButton in
                let button = buttons[space.id] ?? NSButton(frame: .zero)
                buttons[space.id] = button
                button.isBordered = false; button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
                button.imagePosition = .imageOnly
                SidebarAccessibility.configureSpace(button, name: space.name)
                let id = space.id
                let menu = menus[id] ?? SidebarDockItemMenu { [unowned self] in spaceMenu(id) }
                menus[id] = menu
                menu.install(on: button)
                return button
            }
            let shown = SidebarChromeLayout.dockShowsSpaces(
                count: spaces.count, anyCustomIcon: spaces.contains { $0.customIcon != nil }, creating: creating)
            strip.items = shown ? buttonsInOrder : []
            strip.selectedIndex = shown ? spaces.firstIndex { $0.id == active } : nil
            strip.layoutSubtreeIfNeeded()
        }
        /// The item's menu as AppKit opens it: the delegate rebuilds it first.
        func opened(_ id: UUID) -> NSMenu? {
            guard let menu = buttons[id]?.menu else { return nil }
            menu.delegate?.menuNeedsUpdate?(menu)
            return menu
        }
    }

    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-dock-menu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        window.contentView = host
        let strip = SidebarDockStrip(frame: NSRect(x: 8, y: 0, width: 147, height: 50))
        host.addSubview(strip)
        let dock = Dock(store: store, strip: strip)
        let base = ["Rename Space…", "Edit Theme Color…", "New Folder"]
        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags, _ button: NSButton) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil),
                               modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)
        }

        //
        dock.render()
        let first = store.state.spaces[0]
        check(store.state.spaces.count == 1 && first.name == "Space 1" && store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == nil,
              "a new session has one untitled Space and the setting off")
        let button = dock.buttons[first.id]!, itemMenu = dock.menus[first.id]!
        check(strip.items.isEmpty && strip.selectedIndex == nil, "one untitled iconless Space is omitted from the dock")
        check(button.menu === itemMenu.menu, "the item's button carries its Space menu")
        check([event(.rightMouseDown, [], button), event(.leftMouseDown, .control, button)].allSatisfy { $0.flatMap { button.menu(for: $0) } === itemMenu.menu },
              "a right-click and a Control-click ask the button for the Space menu")
        check(actions(button.cell).contains("AXShowMenu")
              && !(strip.accessibilityChildren() ?? []).contains { ($0 as AnyObject) === button.cell },
              "the cell still offers Show Menu and the omitted Space is not in the VoiceOver order")
        var menu = dock.opened(first.id)
        check(menu?.items.map(\.title) == base + ["Show Space Header"] && menu?.items.allSatisfy(\.isEnabled) == true,
              "one untitled Space without an icon: the items, then Show Space Header, all enabled")
        menu?.performActionForItem(at: 3)
        check(store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true, "Show Space Header turns the setting on")
        menu = dock.opened(first.id)
        check(menu?.items.last?.title == "Hide Space Header" && menu?.items.count == 4, "the menu offers Hide Space Header as it next opens")
        menu?.performActionForItem(at: 3)
        check(store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == false, "Hide Space Header turns it off")
        check(dock.opened(first.id)?.items.last?.title == "Show Space Header", "and the menu offers Show Space Header again")
        for index in 0..<3 { dock.opened(first.id)?.performActionForItem(at: index) }
        check(dock.calls == ["rename Space 1", "theme", "folder"], "the active Space's item runs rename, theme and folder")
        check(store.state.activeSpaceID == first.id && strip.selectedIndex == nil, "the menu selects nothing")

        // Two Spaces: no toggle; each item acts on its own Space and only the
        // active Space's item offers Parc's theme editor and folder prompt.
        dock.calls.removeAll()
        let secondID = store.createSpace(name: "Work")
        let second = store.state.spaces.first { $0.id == secondID }!
        dock.render()
        check(store.state.activeSpaceID == second.id && strip.selectedIndex == 1, "the new Space is active")
        let other = dock.opened(first.id), current = dock.opened(second.id)
        check(other !== current && dock.buttons[first.id]?.menu === other && dock.buttons[second.id]?.menu === current,
              "each item keeps its own menu")
        check(other?.items.map(\.title) == base && other?.items.map(\.isEnabled) == [true, false, false],
              "another Space's item: the items, rename enabled, theme and folder disabled")
        check(current?.items.map(\.title) == base && current?.items.allSatisfy(\.isEnabled) == true,
              "the active Space's item: the items, all enabled, no toggle with two Spaces")
        for index in 0..<3 { other?.performActionForItem(at: index) }
        check(dock.calls == ["rename Space 1"], "another Space's item renames that Space and runs nothing else")
        dock.calls.removeAll()
        for index in 0..<3 { current?.performActionForItem(at: index) }
        check(dock.calls == ["rename Work", "theme", "folder"], "the active Space's item acts on it")
        check(store.state.activeSpaceID == second.id && strip.selectedIndex == 1, "neither menu switches Space")
        store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        check(dock.opened(first.id)?.items.count == 3 && dock.opened(second.id)?.items.count == 3,
              "the setting adds no toggle while the window has two Spaces")
        store.toggleSpaceHeaderOnSingleUnnamedSpaces()

        //
        let lone = space("Space 1"), titled = space("Trips"), starred = space("Space 1", icon: .symbol("star"))
        for (fixture, expected, rule) in [(lone, "Show Space Header", "an untitled Space offers the toggle"),
                                          (titled, nil, "a titled Space offers none"),
                                          (starred, nil, "a Space with a custom icon offers none")] as [(BrowserSpace, String?, String)] {
            dock.fixture = [fixture]; dock.render()
            let titles = dock.opened(fixture.id)?.items.map(\.title)
            check(titles == base + (expected.map { [$0] } ?? []), rule)
            check(strip.items.count == (fixture.customIcon == nil ? 0 : 1),
                  fixture.customIcon == nil ? "a lone iconless Space stays out of the dock" : "a lone custom icon stays in the dock")
        }
        let unnamed = space("")
        dock.fixture = [unnamed]; dock.render()
        check(dock.opened(unnamed.id)?.items.last?.title == "Show Space Header", "an empty name is untitled")
        let survivor = space("Space 2")
        dock.fixture = [survivor]; dock.render()
        check(dock.opened(survivor.id)?.items.count == 3, "a lone \"Space 2\" counts as titled (Parc's placeholder rule)")
        check(SidebarSpaceMenu.dock(spaces: [lone], spaceID: UUID(), activeSpaceID: lone.id, creatingSpace: false,
                                    showOnSingleUnnamedSpace: false, rename: { _ in }, editTheme: nil, newFolder: nil,
                                    toggleHeader: nil) == nil, "no menu for a Space the window does not have")
        dock.fixture = nil; dock.render()

        //
        dock.creating = true; dock.render()
        check(dock.spaces.count == 2 && dock.spaces.allSatisfy { dock.buttons[$0.id]?.menu == nil } && event(.rightMouseDown, [], button).flatMap { button.menu(for: $0) } == nil,
              "creating a Space removes every item's menu")
        check(!actions(button.cell).contains("AXShowMenu"), "and Show Menu with it")
        itemMenu.menuNeedsUpdate(itemMenu.menu)
        check(itemMenu.menu.items.isEmpty, "a menu opening during creation has no items")
        dock.creating = false; dock.render()
        check(button.menu === itemMenu.menu && actions(button.cell).contains("AXShowMenu")
              && dock.opened(first.id)?.items.map(\.title) == base, "the menus return when creation ends")
        check(!window.isVisible && !window.isKeyWindow, "the window is never shown or key")
        print("SidebarDockMenu: \(count) assertions passed")
    }
}
