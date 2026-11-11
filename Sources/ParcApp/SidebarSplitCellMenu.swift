import AppKit

enum SplitCellMenuCommand: Equatable { case separateAll, addTab, convertOrientation, newFolder }

@MainActor
struct SidebarSplitCellMenu {
    static let separateAllTitle = "Separate All Tabs", addTabTitle = "Add Tab…"
    static let tabOptionsTitle = "Tab Options", resetTitle = "Reset Name and Icon"
    static let changeIconTitle = "Change Icon…", renameTitle = "Rename…"
    static let duplicateTitle = "Duplicate", archiveTitle = "Archive Item", closeTitle = "Close"
    static let separateChildTitle = "Separate from Split View"
    static let archiveGroupTitles = ["Archive Other Tabs", "Archive Tabs Below", "Archive Tabs Above"]

    static func newFolderTitle(count: Int) -> String { "New Folder with \(count) Items" }

    static func archiveGroupIDs(order: [UUID], children: Set<UUID>) -> [Set<UUID>]? {
        guard let first = order.firstIndex(where: { children.contains($0) }),
              let last = order.lastIndex(where: { children.contains($0) }) else { return nil }
        return [Set(order.filter { !children.contains($0) }), Set(order.dropFirst(last + 1)), Set(order.prefix(first))]
    }

    static func convertTitle(for orientation: SplitOrientation) -> String {
        orientation == .horizontal ? "Convert to Vertical Split View" : "Convert to Horizontal Split View"
    }

    var orientation: SplitOrientation
    var bindShortcut: ((NSMenuItem, String) -> Void)?
    var separateAll: (() -> Bool)?
    var addTab: (() -> Bool)?
    var convert: (() -> Bool)?
    var children: [(title: String, submenu: NSMenu)] = []
    var reset: (() -> Bool)?
    var changeIcon: (() -> Bool)?
    var rename: (() -> Bool)?
    var duplicate: (() -> Bool)?
    var moves: [NSMenuItem] = []
    var showsNewFolder = true
    var itemCount = 1
    var newFolder: (() -> Bool)?
    var showsArchive = true
    var archive: (() -> Bool)?
    var archiveGroup: [(title: String, action: (() -> Bool)?)] = []
    var close: (() -> Bool)?

    func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        func add(_ title: String, _ action: (() -> Bool)?, commandID: String? = nil) {
            let item = Self.item(title, action)
            if let commandID { bindShortcut?(item, commandID) }
            menu.addItem(item)
        }
        add(Self.separateAllTitle, separateAll)
        add(Self.addTabTitle, addTab)
        add(Self.convertTitle(for: orientation), convert)
        if !children.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: Self.tabOptionsTitle, action: nil, keyEquivalent: "")
            header.isEnabled = false; menu.addItem(header)
            for child in children {
                let item = NSMenuItem(title: child.title, action: nil, keyEquivalent: "")
                item.submenu = child.submenu; menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        add(Self.resetTitle, reset)
        add(Self.changeIconTitle, changeIcon)
        add(Self.renameTitle, rename, commandID: "renameCurrentItem:")
        menu.addItem(.separator())
        add(Self.duplicateTitle, duplicate, commandID: "duplicateCurrentItem:")
        for item in moves { menu.addItem(item) }
        if showsNewFolder { add(Self.newFolderTitle(count: itemCount), newFolder, commandID: "createFolder:") }
        menu.addItem(.separator())
        if showsArchive { add(Self.archiveTitle, archive) }
        for entry in archiveGroup { add(entry.title, entry.action) }
        add(Self.closeTitle, close)
        return menu
    }

    static func item(_ title: String, _ action: (() -> Bool)?) -> NSMenuItem {
        let target = SidebarSplitCellMenuTarget(action)
        let item = NSMenuItem(title: title, action: #selector(SidebarSplitCellMenuTarget.run), keyEquivalent: "")
        item.target = target; item.representedObject = target
        item.isEnabled = action != nil
        return item
    }

    static func childSubmenu(separate: (() -> Bool)?, tabMenu: NSMenu, replacing splitTitles: Set<String>) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.addItem(item(separateChildTitle, separate))
        menu.addItem(.separator())
        var previousWasSeparator = true
        for entry in tabMenu.items {
            tabMenu.removeItem(entry)
            if splitTitles.contains(entry.title) { continue }
            if entry.isSeparatorItem && previousWasSeparator { continue }
            previousWasSeparator = entry.isSeparatorItem
            menu.addItem(entry)
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        return menu
    }
}

@MainActor
private final class SidebarSplitCellMenuTarget: NSObject {
    let action: (() -> Bool)?
    init(_ action: (() -> Bool)?) { self.action = action }
    @objc func run() { _ = action?() }
}
