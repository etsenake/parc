import AppKit

///
///
/// dock's Space items and the sidebar's own menu (SidebarSpaceMenuSurface):
/// Rename Space…, Edit Theme Color…, New Folder, then
///
/// item without its action is disabled. The builder's first argument is
/// `ContextMenuUtils.SpaceMenuContext` (sidebarContextMenu 0,
/// spaceHeaderContextMenu 1, sidebarDockContextMenu 2, clickableIcon 3; 4 is
/// none); the production owner supplies Change Space Icon… and Profile choices.
///
///
/// services (Share Space…, Live Folders).
@MainActor
struct SidebarSpaceMenu {
    static let renameTitle = "Rename Space…", editThemeTitle = "Edit Theme Color…", newFolderTitle = "New Folder"

    var includesManagement = false
    var changeIcon: (() -> Void)? = nil
    var profiles: [(name: String, selected: Bool, action: (() -> Void)?)] = []
    var delete: (() -> Void)? = nil
    var manage: (() -> Void)? = nil
    var turnIntoFolder: [(name: String, action: (() -> Void)?)] = []
    var rename: (() -> Void)?
    var editTheme: (() -> Void)?
    var newFolder: (() -> Void)?
    /// `SidebarChromeLayout.SpaceHeader.toggleTitle` for the menu's Space, or
    /// nil when the menu offers no header toggle.
    var toggleTitle: String?
    ///
    /// MainMenuAction.onSpaceHeaderVisibilityToggled).
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

    ///
    func populate(_ menu: NSMenu) {
        menu.autoenablesItems = false
        menu.removeAllItems()
        for (title, action) in entries {
            let target = SidebarSpaceMenuTarget(action)
            let item = NSMenuItem(title: title, action: #selector(SidebarSpaceMenuTarget.run), keyEquivalent: "")
            // NSMenuItem holds its target weakly; the represented object keeps it.
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
            if title == Self.editThemeTitle, !profiles.isEmpty {
                let parent = NSMenuItem(title: "Set Profile", action: nil, keyEquivalent: "")
                parent.submenu = profileMenu()
                parent.isEnabled = true; menu.addItem(parent)
            }
        }
    }

    func profileMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        for profile in profiles {
            let target = SidebarSpaceMenuTarget(profile.action)
            let item = NSMenuItem(title: profile.name, action: #selector(SidebarSpaceMenuTarget.run), keyEquivalent: "")
            item.target = target; item.representedObject = target
            item.state = profile.selected ? .on : .off
            item.isEnabled = profile.action != nil; menu.addItem(item)
        }
        return menu
    }

    /// The available items as custom actions, so VoiceOver reaches them
    /// without the pointer.
    var accessibilityActions: [NSAccessibilityCustomAction] {
        (entries + profiles.map { ("Set Profile: " + $0.name, $0.action) } + turnIntoFolder.map { ("Turn into Folder in " + $0.name, $0.action) }).compactMap { title, action in
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
    /// The menu of the dock item for Space `spaceID`. SidebarViewController's
    ///
    /// header toggle allowed (w6 = 1) and the menu's state built for the
    ///
    /// Space, and returns none while the window creates a Space
    /// (SidebarViewController.ViewState.isCreatingNewSpace). Rename Space…
    ///
    /// Color… and New Folder name the item's Space too; Parc's theme editor
    /// and folder prompt act on the active Space, so the other Spaces' items
    /// offer them disabled (Parc adaptation). Nothing selects the Space.
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
    ///
    ///
    ///
    /// builds the Space menu for WindowState.focusedSpaceID with
    /// `.sidebarContextMenu`, the header toggle allowed (w6 = 1) and no rename
    /// closure, and returns none while the window creates a Space
    ///
    /// (WindowStyle other than .standard(.global)) or outside the Spaces layout
    ///
    /// windows, so Space creation and the private window remain. The items are
    /// the active Space's dock item's (`dock`): Rename Space… through Parc's
    ///
    /// editor, the folder prompt and the toggle for that Space.
    static func sidebar(spaces: [BrowserSpace], activeSpaceID: UUID?, creatingSpace: Bool, privateWindow: Bool,
                        showOnSingleUnnamedSpace: Bool, rename: @escaping (UUID) -> Void,
                        editTheme: (() -> Void)?, newFolder: (() -> Void)?, toggleHeader: (() -> Void)?) -> SidebarSpaceMenu? {
        guard !privateWindow, let activeSpaceID else { return nil }
        return dock(spaces: spaces, spaceID: activeSpaceID, activeSpaceID: activeSpaceID, creatingSpace: creatingSpace,
                    showOnSingleUnnamedSpace: showOnSingleUnnamedSpace, rename: rename,
                    editTheme: editTheme, newFolder: newFolder, toggleHeader: toggleHeader)
    }
}

///
///
///
/// rightMouseDown: and any other click to super. A right-click on a view in
/// the sidebar without a menu of its own (the list's empty area below its
/// rows, its bottom inset, the gaps between rows, Clear or New Tab) passes
/// up the responder chain to it, as does that view's Control-click mouseDown
/// [C]; rows, Favorites, the Space header and the dock's Space items keep
/// their own menus. SidebarView is one. It is no accessibility element, as
///
/// through the header's and the dock's menus.
@MainActor
class SidebarSpaceMenuSurface: NSView {
    /// The sidebar's Space menu (SidebarSpaceMenu.sidebar), or none.
    var spaceMenu: (() -> SidebarSpaceMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? { spaceMenu?()?.makeMenu() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        super.mouseDown(with: event)
    }
}

///
///
/// SidebarViewController's provider builds the Space menu for the item's
/// Space (`SidebarSpaceMenu.dock`). Parc installs it as the item button's
/// menu, which AppKit shows on a right-click or Control-click and offers to
/// VoiceOver as Show Menu on the button's exposed cell [C]. The items are
/// rebuilt from `provide` as the menu opens; the button has no menu while
/// `provide` offers none.
@MainActor
final class SidebarDockItemMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let provide: () -> SidebarSpaceMenu?

    init(_ provide: @escaping () -> SidebarSpaceMenu?) {
        self.provide = provide
        super.init()
        menu.delegate = self
    }

    /// Puts the current menu on `button`, or removes it while there is none.
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
