import AppKit

extension BrowserWindowController {
    @objc(parcExtensionPopupOriginForExtension:popup:size:)
    func extensionPopupOrigin(forExtension identifier: String, popup: NSWindow, size: NSSize) -> NSValue? {
        guard let window, !isClosing, size.width.isFinite, size.height.isFinite else { return nil }
        let anchor = extensionPopupAnchor(for: identifier, popup: popup)
        extensionPopupAtSidebar = anchor?.bar === sidebar.addressBarAnchor
        if extensionPopupAtSidebar {
            followExtensionPopupsForAddressHold()
            holdAddressButtonsForLoadingExtensionPopups()
        }
        let control: CGRect, bar: CGRect
        if let anchor {
            control = screenFrame(of: anchor.control, in: window)
            bar = screenFrame(of: anchor.bar, in: window)
        } else {
            control = ExtensionPopupPlacement.pageAnchor(extensionPopupPage.map { screenFrame(of: $0, in: window) } ?? window.frame)
            bar = control
        }
        let screen = SiteControlCenterPlacement.screen(at: CGPoint(x: control.midX, y: control.midY)) ?? window.screen?.visibleFrame
        return NSValue(point: ExtensionPopupPlacement.origin(size: size, control: control, bar: bar,
                                                             window: window.frame, screen: screen))
    }

    private func extensionPopupAnchor(for identifier: String, popup: NSWindow) -> (control: NSView, bar: NSView)? {
        let pinned = { (toolbar: ExtensionToolbarView) in toolbar.button(for: identifier) }
        let sidebarArea = ExtensionPopupArea(owner: sidebar, bar: sidebar.addressBarAnchor,
                                             controls: [pinned(sidebar.extensionToolbar), sidebar.pageControlsAnchor])
        let toolbarArea = { (toolbar: BrowserToolbarView) in
            ExtensionPopupArea(owner: toolbar, bar: toolbar,
                               controls: [pinned(toolbar.extensionToolbar), toolbar.siteControlCenterAnchor])
        }
        let chromeArea = ExtensionPopupArea(owner: popupChrome, bar: popupChrome, controls: [popupChrome.pageControlsAnchor])
        let toolbars = ([activePeek?.view.browserToolbar] + panes.values.map { $0.browserToolbar }).compactMap { $0 }
        let owners = (sidebar.isPresented ? [sidebarArea] : []) + toolbars.map(toolbarArea) + [chromeArea]
        var defaults = extensionPopupsAnchorToSidebar ? [sidebarArea] : []
        if let toolbar = selectedBrowserToolbar { defaults.append(toolbarArea(toolbar)) }
        if isPopupWindow { defaults.append(chromeArea) }
        return ExtensionPopupPlacement.anchor(clicked: extensionPopupSource?.control(for: identifier, popup: popup),
                                              owners: owners, defaults: defaults, shows: showsExtensionPopupAnchor)
    }

    private var extensionPopupPage: NSView? {
        if let peek = activePeek, peek.view.content.window === window { return peek.view.content }
        if let id = currentTabID, let pane = panes[id], pane.window === window { return pane }
        return nil
    }

    private func showsExtensionPopupAnchor(_ view: NSView) -> Bool {
        view.window === window && !view.isHiddenOrHasHiddenAncestor
    }

    private func screenFrame(of view: NSView, in window: NSWindow) -> CGRect {
        window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}
