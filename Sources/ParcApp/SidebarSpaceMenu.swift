import AppKit

@MainActor
struct SidebarSpaceMenu {
    static let renameTitle = "Rename Space…", editThemeTitle = "Edit Theme Color…", newFolderTitle = "New Folder"
    static let shareDataTitle = "Share data with", keepSeparateTitle = "Keep separate"

    var includesManagement = false
    var changeIcon: (() -> Void)? = nil
    var shareData: [(name: String, shared: Bool, action: (() -> Void)?)] = []
    var keepSeparate: (selected: Bool, action: (() -> Void)?)? = nil
    var delete: (() -> Void)? = nil
    var manage: (() -> Void)? = nil
    var turnIntoFolder: [(name: String, action: (() -> Void)?)] = []
    var rename: (() -> Void)?
    var editTheme: (() -> Void)?
    var newFolder: (() -> Void)?
    var toggleTitle: String?
    var toggleHeader: (() -> Void)?

    private var entries: [(title: String, action: (() -> Void)?)] {
        (includesManagement ? [("Change Space Icon…", changeIcon)] : [])
            + [(Self.renameTitle, rename), (Self.editThemeTitle, editTheme), (Self.newFolderTitle, newFolder)]
            + (toggleTitle.map { [($0, toggleHeader)] } ?? [])
            + (includesManagement ? [("Delete Space", delete), ("Manage Spaces…", manage)] : [])
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    func populate(_ menu: NSMenu) {
        menu.autoenablesItems = false
        menu.removeAllItems()
        for (title, action) in entries {
            let target = SidebarSpaceMenuTarget(action)
            let item = NSMenuItem(title: title, action: #selector(SidebarSpaceMenuTarget.run), keyEquivalent: "")
            item.target = target; item.representedObject = target
            item.isEnabled = action != nil
            if title == "Delete Space", !turnIntoFolder.isEmpty {
                let parent = NSMenuItem(title: "Turn into Folder", action: nil, keyEquivalent: "")
                let submenu = NSMenu(); submenu.autoenablesItems = false
                for option in turnIntoFolder {
                    let target = SidebarSpaceMenuTarget(option.action)
                    let item = NSMenuItem(title: option.name, action: #selector(SidebarSpaceMenuTarget.run), keyEquivalent: "")
                    item.target = target; item.representedObject = target; item.isEnabled = option.action != nil
                    submenu.addItem(item)
                }
                parent.submenu = submenu; menu.addItem(parent)
            }
            menu.addItem(item)
            if title == Self.editThemeTitle, let keepSeparate {
                let parent = NSMenuItem(title: Self.shareDataTitle, action: nil, keyEquivalent: "")
                parent.submenu = shareDataMenu(keepSeparate)
                parent.isEnabled = true; menu.addItem(parent)
            }
        }
    }

    func shareDataMenu(_ keepSeparate: (selected: Bool, action: (() -> Void)?)) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        func add(_ title: String, checked: Bool, action: (() -> Void)?) {
            let target = SidebarSpaceMenuTarget(action)
            let item = NSMenuItem(title: title, action: #selector(SidebarSpaceMenuTarget.run), keyEquivalent: "")
            item.target = target; item.representedObject = target
            item.state = checked ? .on : .off
            item.isEnabled = action != nil; menu.addItem(item)
        }
        for space in shareData { add(space.name, checked: space.shared, action: space.action) }
        if !shareData.isEmpty { menu.addItem(.separator()) }
        add(Self.keepSeparateTitle, checked: keepSeparate.selected, action: keepSeparate.action)
        return menu
    }

    var accessibilityActions: [NSAccessibilityCustomAction] {
        (entries + shareData.map { ("Share data with " + $0.name, $0.action) }
            + (keepSeparate.map { [(Self.keepSeparateTitle, $0.action)] } ?? []) + turnIntoFolder.map { ("Turn into Folder in " + $0.name, $0.action) }).compactMap { title, action in
            action.map { run in NSAccessibilityCustomAction(name: title) { run(); return true } }
        }
    }
}

@MainActor
private final class SidebarSpaceMenuTarget: NSObject {
    let action: (() -> Void)?
    init(_ action: (() -> Void)?) { self.action = action }
    @objc func run() { action?() }
}

extension SidebarSpaceMenu {
    static func dock(spaces: [BrowserSpace], spaceID: UUID, activeSpaceID: UUID?, creatingSpace: Bool,
                     showOnSingleUnnamedSpace: Bool, rename: @escaping (UUID) -> Void,
                     editTheme: (() -> Void)?, newFolder: (() -> Void)?, toggleHeader: (() -> Void)?) -> SidebarSpaceMenu? {
        guard !creatingSpace, let position = spaces.firstIndex(where: { $0.id == spaceID }) else { return nil }
        typealias Header = SidebarChromeLayout.SpaceHeader
        let space = spaces[position], active = spaceID == activeSpaceID
        return SidebarSpaceMenu(rename: { rename(spaceID) },
                                editTheme: active ? editTheme : nil,
                                newFolder: active ? newFolder : nil,
                                toggleTitle: Header.toggleTitle(spaceCount: spaces.count,
                                                                titled: space.title != nil,
                                                                customIcon: space.customIcon != nil,
                                                                showOnSingleUnnamedSpace: showOnSingleUnnamedSpace),
                                toggleHeader: toggleHeader)
    }
}

extension SidebarSpaceMenu {
    static func sidebar(spaces: [BrowserSpace], activeSpaceID: UUID?, creatingSpace: Bool, privateWindow: Bool,
                        showOnSingleUnnamedSpace: Bool, rename: @escaping (UUID) -> Void,
                        editTheme: (() -> Void)?, newFolder: (() -> Void)?, toggleHeader: (() -> Void)?) -> SidebarSpaceMenu? {
        guard !privateWindow, let activeSpaceID else { return nil }
        return dock(spaces: spaces, spaceID: activeSpaceID, activeSpaceID: activeSpaceID, creatingSpace: creatingSpace,
                    showOnSingleUnnamedSpace: showOnSingleUnnamedSpace, rename: rename,
                    editTheme: editTheme, newFolder: newFolder, toggleHeader: toggleHeader)
    }
}

@MainActor
class SidebarSpaceMenuSurface: NSView {
    var spaceMenu: (() -> SidebarSpaceMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? { spaceMenu?()?.makeMenu() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        super.mouseDown(with: event)
    }
}

@MainActor
final class SidebarDockItemMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let provide: () -> SidebarSpaceMenu?

    init(_ provide: @escaping () -> SidebarSpaceMenu?) {
        self.provide = provide
        super.init()
        menu.delegate = self
    }

    func install(on button: NSButton) {
        guard let spaceMenu = provide() else {
            button.menu = nil; menu.removeAllItems()
            return
        }
        spaceMenu.populate(menu)
        if button.menu !== menu { button.menu = menu }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let spaceMenu = provide() { spaceMenu.populate(menu) } else { menu.removeAllItems() }
    }
}
