import AppKit

/// The split cell menu's actions the window owns.
enum SplitCellMenuCommand: Equatable { case separateAll, addTab, convertOrientation, newFolder }

///
///
///
///
///
/// - for a single selected split, Convert to Vertical/Horizontal Split View
///
///
///   Horizontal), then a separator, the "Tab Options" header and one submenu
///
///   items);
/// - a separator, Reset Name and Icon (`resetTitleAndIcon`, unconditional,
///
///
///
///   private windows, the Move to submenu and New Folder with *n* Items
///
///   `createFolderFromSelectionInCurrentSpace`, case 20);
///
///
///
///   Tabs Below and Archive Tabs Above (`archiveUnselectedItems`,
///   `archiveItemsBelow`, `archiveItemsAbove`), and Close (`close`,
///
///
///
///
/// have, as for Share Space… (SidebarSpaceMenu). An item without its action
/// is disabled.
@MainActor
struct SidebarSplitCellMenu {
    static let separateAllTitle = "Separate All Tabs", addTabTitle = "Add Tab…"
    static let tabOptionsTitle = "Tab Options", resetTitle = "Reset Name and Icon"
    static let changeIconTitle = "Change Icon…", renameTitle = "Rename…"
    static let duplicateTitle = "Duplicate", archiveTitle = "Archive Item", closeTitle = "Close"
    static let separateChildTitle = "Separate from Split View"
    static let archiveGroupTitles = ["Archive Other Tabs", "Archive Tabs Below", "Archive Tabs Above"]

    ///
    /// "New Folder with " and " Items", so one item reads "1 Items".
    static func newFolderTitle(count: Int) -> String { "New Folder with \(count) Items" }

    /// The tab IDs each archive-group item archives for a split whose
    /// `children` are contiguous in the Today `order`: every other Today tab,
    /// the tabs below the split and the tabs above it.
    static func archiveGroupIDs(order: [UUID], children: Set<UUID>) -> [Set<UUID>]? {
        guard let first = order.firstIndex(where: { children.contains($0) }),
              let last = order.lastIndex(where: { children.contains($0) }) else { return nil }
        return [Set(order.filter { !children.contains($0) }), Set(order.dropFirst(last + 1)), Set(order.prefix(first))]
    }

    ///
    /// vertical; a stacked (vertical) one to horizontal.
    static func convertTitle(for orientation: SplitOrientation) -> String {
        orientation == .horizontal ? "Convert to Vertical Split View" : "Convert to Horizontal Split View"
    }

    var orientation: SplitOrientation
    /// The window's live discovery registry, separate from these item actions.
    var bindShortcut: ((NSMenuItem, String) -> Void)?
    var separateAll: (() -> Bool)?
    var addTab: (() -> Bool)?
    var convert: (() -> Bool)?
    /// The Tab Options submenus, titled by each child, in split order.
    var children: [(title: String, submenu: NSMenu)] = []
    var reset: (() -> Bool)?
    var changeIcon: (() -> Bool)?
    ///
    /// admits; disabled here when the split cannot be renamed.
    var rename: (() -> Bool)?
    var duplicate: (() -> Bool)?
    ///
    var moves: [NSMenuItem] = []
    /// New Folder with *n* Items, omitted in private windows with Move to.
    var showsNewFolder = true
    var itemCount = 1
    var newFolder: (() -> Bool)?
    /// Archive Item; a private window, which never archives, offers Close.
    var showsArchive = true
    var archive: (() -> Bool)?
    /// Archive Other Tabs / Below / Above, present only for an unpinned split.
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

    /// An item that runs `action` once when chosen, disabled without one.
    static func item(_ title: String, _ action: (() -> Bool)?) -> NSMenuItem {
        let target = SidebarSplitCellMenuTarget(action)
        let item = NSMenuItem(title: title, action: #selector(SidebarSplitCellMenuTarget.run), keyEquivalent: "")
        // NSMenuItem holds its target weakly; the represented object keeps it.
        item.target = target; item.representedObject = target
        item.isEnabled = action != nil
        return item
    }

    ///
    /// View, a separator, then the child's own tab items without their own
    /// split entries (`splitTitles`), since this one leads.
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
