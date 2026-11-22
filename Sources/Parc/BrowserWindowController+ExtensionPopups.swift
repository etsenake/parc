import AppKit
import ParcSidebar

extension BrowserWindowController {
    @objc(parcExtensionPopupOriginForExtension:popup:size:)
    func extensionPopupOrigin(forExtension identifier: String, popup: NSWindow, size: NSSize) -> NSValue? {
        guard let window, !isClosing, size.width.isFinite, size.height.isFinite else { return nil }
        let anchor = extensionPopupAnchor(for: identifier, popup: popup)
        trackExtensionPopupActivity(popup, control: anchor?.control)
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

    @objc(parcExtensionPopup:forExtension:didChangePhase:)
    func extensionPopup(_ popup: NSWindow, forExtension identifier: String, didChangePhase phase: Int) {
        switch ExtensionPopupLifecycle(rawValue: phase) {
        case .revealed?: showExtensionPopupActivity(extensionPopupActivity.reveal(popup: popup))
        case .closing?, .closed?: endExtensionPopupActivity(popup)
        case nil: break
        }
    }

    private func trackExtensionPopupActivity(_ popup: NSWindow, control: NSView?) {
        let fresh = !extensionPopupActivity.tracks(popup)
        let lit = control.flatMap { showsExtensionPopupActivity($0) ? $0 : nil }
        showExtensionPopupActivity(extensionPopupActivity.place(popup: popup, control: lit))
        guard fresh, extensionPopupActivity.tracks(popup) else { return }
        extensionPopupCloseObserver.map(NotificationCenter.default.removeObserver)
        extensionPopupCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: popup, queue: nil
        ) { [weak self, weak popup] _ in
            MainActor.assumeIsolated { if let popup { self?.endExtensionPopupActivity(popup) } }
        }
    }

    private func endExtensionPopupActivity(_ popup: NSWindow) {
        guard extensionPopupActivity.tracks(popup) else { return }
        extensionPopupCloseObserver.map(NotificationCenter.default.removeObserver)
        extensionPopupCloseObserver = nil
        showExtensionPopupActivity(extensionPopupActivity.end(popup: popup))
    }

    private func showExtensionPopupActivity(_ changes: [ExtensionPopupActivityChange]) {
        for change in changes {
            guard let control = change.control as? any ExtensionPopupActivityDrawing else { continue }
            extensionPopupIndicator(for: control).show(change.phase)
        }
    }

    private func extensionPopupIndicator(for control: any ExtensionPopupActivityDrawing) -> ExtensionPopupActivityIndicator {
        if let indicator = extensionPopupIndicators.first(where: { $0.view === control }) { return indicator }
        extensionPopupIndicators.removeAll { $0.view == nil || $0.isIdle }
        let indicator = ExtensionPopupActivityIndicator(view: control)
        extensionPopupIndicators.append(indicator)
        return indicator
    }

    private func showsExtensionPopupActivity(_ control: NSView) -> Bool {
        guard control is any ExtensionPopupActivityDrawing else { return false }
        if control is ExtensionActionButton { return true }
        let toolbars = [activePeek?.view.browserToolbar] + panes.values.map { $0.browserToolbar }
        let chrome = popupChrome.pageControlsAnchor
        let siteControls = [sidebar.pageControlsAnchor, chrome === popupChrome.addressAnchor ? nil : chrome]
            + toolbars.map { $0?.siteControlCenterAnchor }
        return siteControls.contains { $0 === control }
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
