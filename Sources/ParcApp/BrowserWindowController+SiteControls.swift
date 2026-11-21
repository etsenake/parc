import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func preparePopupSiteControls(requireExtensions: Bool, from anchor: NSView? = nil) -> (() -> Bool)? {
        guard isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              let window, window.isKeyWindow, windowCommandSecurityAvailable,
              let browser = currentBrowser, browser.window === window, let page = browser.nativePage, !page.isClosed,
              let binding = nativeBinding else { return nil }
        if requireExtensions && (!binding.responds(to: #selector(PCNativeBrowserWindow.hasEnabledExtensions(for:)))
            || !binding.hasEnabledExtensions(for: page)) { return nil }
        let revision = browser.readerRevision, profileID = activeProfileID, spaceID = activeSpaceID
        var used = false
        return { [weak self, weak window, weak browser, weak page, weak binding, weak anchor] in
            guard !used, let self, let window, let browser, let page, let binding,
                  self.presentation.isReady, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.window === window, window.isKeyWindow, self.windowCommandSecurityAvailable,
                  self.activeProfileID == profileID, self.activeSpaceID == spaceID,
                  self.nativeBinding === binding, self.currentBrowser === browser, browser.window === window,
                  browser.nativePage === page, browser.readerRevision == revision, !page.isClosed else { return false }
            if requireExtensions && (!binding.responds(to: #selector(PCNativeBrowserWindow.hasEnabledExtensions(for:)))
                || !binding.hasEnabledExtensions(for: page)) { return false }
            used = true
            self.showSiteControlCenter(from: anchor ?? self.popupChrome.pageControlsAnchor)
            return true
        }
    }

    func showSiteControlCenter(from sourceAnchor: NSView? = nil, picker: Bool = false) {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              let initialWindow = window, initialWindow.isKeyWindow, windowCommandSecurityAvailable else { return }
        extensionActionGeneration = UUID()
        if let open = siteControlCenter, open.isShown {
            if picker && open.model.focusedExtension == nil && !open.model.extensions.isEmpty { open.beginPicker(); return }
            dismissSiteControlCenter(); return
        }
        guard let browser = currentBrowser, let page = browser.nativePage, !page.isClosed else {
            dismissSiteControlCenter()
            if !picker, window === initialWindow, initialWindow.isKeyWindow, windowCommandSecurityAvailable { showPageMenu() }
            return
        }
        let revision = browser.readerRevision, profileID = activeProfileID, spaceID = activeSpaceID
        dismissSiteControlCenter()
        guard let originalWindow = window, originalWindow === initialWindow,
              presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              originalWindow.isKeyWindow, windowCommandSecurityAvailable,
              activeProfileID == profileID, activeSpaceID == spaceID, currentBrowser === browser,
              browser.nativePage === page, !page.isClosed, browser.readerRevision == revision,
              siteControlCenter == nil else { return }
        let controller = SiteControlCenterController(model: SiteControlCenterModel())
        let canShow: () -> Bool = { [weak self, weak controller, weak originalWindow, weak browser, weak page] in
            guard let self, let controller, let originalWindow, let browser, let page,
                  self.siteControlCenter === controller, self.window === originalWindow,
                  self.presentation.isReady, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  originalWindow.isKeyWindow, self.windowCommandSecurityAvailable,
                  self.activeProfileID == profileID, self.activeSpaceID == spaceID,
                  self.currentBrowser === browser, browser.window === originalWindow,
                  browser.nativePage === page, !page.isClosed, browser.readerRevision == revision else { return false }
            return true
        }
        siteControlCenter = controller
        extensionControlsPage = page
        siteControlCenterRevision = browser.readerRevision
        siteControlCenterOwner = (spaceID, profileID)
        updateSiteControlCenter(controller, page: page, items: extensionControlItems())
        wireSiteControlCenter(controller, browser: browser, page: page)
        controller.onClose = { [weak self, weak controller, weak page] in
            guard let self, let controller, self.siteControlCenter === controller else { return }
            self.siteControlCenterDismissal.track(controller)
            self.siteControlCenter = nil; self.extensionControlsPage = nil
            self.siteControlCenterItems = [:]; self.siteControlCenterPermissions = []
            self.siteControlCenterPermissionTargets = [:]; self.siteControlCenterRevision = nil
            self.siteControlCenterOwner = nil; self.siteControlCenterPageTools = []
            self.sidebar.setAddressPopover(controller, open: false)
            if page?.responds(to: #selector(PCNativePage.closeSiteControls)) == true { page?.closeSiteControls() }
            self.refreshSidebarPointerIfKey()
        }
        controller.onDetach = { [weak self, weak controller] in
            guard let self, let controller, self.siteControlCenter === controller else { return }
            self.sidebar.setAddressPopover(controller, open: false)
        }
        if browser.hasPageInfo, page.responds(to: #selector(PCNativePage.openSiteControls(handler:))) {
            _ = page.openSiteControls { [weak self, weak controller, weak page] rows in
                guard let self, let controller, let page, self.siteControlCenter === controller else { return }
                guard let rows else { self.dismissSiteControlCenter(); return }
                self.siteControlCenterPermissions = rows
                self.updateSiteControlCenter(controller, page: page, items: nil)
            }
        }
        if let anchor = sourceAnchor ?? (isPopupWindow ? popupChrome.pageControlsAnchor : sidebar.isPresented ? sidebar.pageControlsAnchor : nil) {
            let pill = sourceAnchor == nil && !isPopupWindow
            if anchor === sidebar.pageControlsAnchor { sidebar.setAddressPopover(controller, open: true) }
            controller.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY,
                            after: pill ? .milliseconds(anchor.isHiddenOrHasHiddenAncestor ? 100 : 10) : nil,
                            expectedWindow: originalWindow, when: canShow)
        } else {
            let page = hiddenSidebarAnchor
            controller.show(relativeTo: page.rect, of: page.view, preferredEdge: page.view.isFlipped ? .maxY : .minY,
                            expectedWindow: originalWindow, when: canShow)
        }
        if picker { controller.beginPicker() }
    }

    func dismissSiteControlCenter(then action: (() -> Void)? = nil) {
        siteControlCenterDismissal.close(siteControlCenter, then: action)
    }
    func dismissSiteControlCenter(when valid: @escaping () -> Bool, then action: @escaping () -> Void) {
        siteControlCenterDismissal.close(siteControlCenter, when: valid, then: action)
    }

    func updateSiteControlCenter(_ controller: SiteControlCenterController, page: PCNativePage,
                                         items: [ExtensionControlItem]?) {
        let model = controller.model
        let canCopy = canCopyCurrentURL
        model.canCopy = canCopy
        model.canShare = canSharePage
        model.captureAvailable = privateCaptureContextIsValid
        if window?.isKeyWindow == true {
            model.canCapture = canCapturePage
            siteControlCenterPageTools = Set([PCNativePageTool.developerTools, .clearCacheAndRefresh,
                                              .clearCookiesAndRefresh].filter(canPerformPageTool))
        }
        controller.theme = rootView.theme
        updateSiteControlCenterShortcuts()
        if let items {
            siteControlCenterItems = Dictionary(items.map { ($0.identifier, $0) }) { $1 }
            let extensions = items.map {
                SiteControlCenterModel.Extension(id: $0.identifier, name: $0.name, tooltip: $0.tooltip,
                    accessibilityLabel: $0.accessibilityLabel, icon: $0.pinnedArtwork?.image ?? $0.image,
                    isPinned: $0.pinnedIndex != nil, canChangePin: $0.canChangePin,
                    badge: $0.pinnedArtwork?.badge, badgeText: $0.badgeText)
            }
            if model.extensions != extensions { model.extensions = extensions }
            if let focused = model.focusedExtension, !extensions.contains(where: { $0.id == focused }) {
                model.focusedExtension = extensions.first?.id
            }
        }
        let internalPage = ["chrome", "parc"].contains(page.url?.scheme?.lowercased() ?? "parc")
        model.isSecure = internalPage ? nil : page.developerModeSecure
        let settings = siteControlCenterSettings(page: page)
        if model.settings != settings { model.settings = settings }
        model.updateBlocked(blockedContent(for: page))
    }

    func updateSiteControlCenterShortcuts() {
        guard let model = siteControlCenter?.model else { return }
        let shortcuts = KeyboardShortcuts.shared
        model.shortcuts = Dictionary(uniqueKeysWithValues: SiteControlCenterModel.Button.allCases.compactMap { button in
            button.commandID.map { (button, shortcuts.activeShortcut(for: $0)?.display ?? "") }
        })
    }

    func shortcutTooltipDiscoveryFingerprint() -> String {
        let shortcuts = KeyboardShortcuts.shared
        return ShortcutTooltipDiscoverySkip.fingerprint(
            copyURLTooltip: LiveShortcutToolTip.text("Copy URL", commandID: "copyCurrentURL:"),
            copyURLShortcut: shortcuts.activeShortcut(for: "copyCurrentURL:")?.display ?? "",
            captureShortcut: shortcuts.activeShortcut(for: "capturePage:")?.display ?? "",
            captureVisiblePageShortcut: shortcuts.activeShortcut(for: "captureVisiblePage:")?.display ?? "",
            captureFullPageShortcut: shortcuts.activeShortcut(for: "captureFullPage:")?.display ?? ""
        )
    }

    private func siteControlCenterSettings(page: PCNativePage) -> [SiteControlCenterModel.Setting] {
        typealias Setting = SiteControlCenterModel.Setting
        var rows: [Setting] = []
        let host = page.developerModeSiteHost
        let secure = page.developerModeHost != nil && page.developerModeSecure
        if secure, let url = currentBrowser?.url, SidebarRecentDomain.matching(url) != nil {
            let enabled = SidebarPreviewPreference.recentPages.isEnabled
            rows.append(Setting(id: "preview", symbol: "filemenu.and.cursorarrow", symbolSize: 14, symbolWeight: .bold,
                                title: "Preview", subtitle: enabled ? "Enabled" : "Disabled", isOn: enabled, isEnabled: true))
        }
        if let host, !isPrivateBrowsing, !DeveloperModePreferences.shared.loadError {
            let enabled = DeveloperModePreferences.shared.isEnabled(host: host)
            rows.append(Setting(id: "developerMode", symbol: "hammer.fill", symbolSize: 13, symbolWeight: .medium,
                                title: "Developer Mode", subtitle: enabled ? "On" : "Off", isOn: enabled,
                                isEnabled: siteControlCenterPageTools.contains(.developerTools)))
        }
        siteControlCenterPermissionTargets = [:]
        guard secure else { return rows }
        let systemSettings = page.responds(to: #selector(PCNativePage.openSiteControlsSystemSettings(_:revision:)))
        for row in SitePermissionRow.ordered(siteControlCenterPermissions) {
            siteControlCenterPermissionTargets[row.id] = (row.index, row.revision)
            let accessory = systemSettings && row.systemSettings
                ? Setting.Accessory(title: SitePermissionRow.systemSettingsTitle, help: row.systemSettingsHelp)
                : nil
            rows.append(Setting(id: row.id, symbol: "gearshape.fill", symbolSize: 13,
                                symbolWeight: .medium, title: row.title,
                                subtitle: accessory == nil ? (row.allowed ? "Allowed" : "Blocked") : row.subtitle,
                                isOn: row.allowed, isEnabled: row.changeable,
                                accessibilityValue: accessory == nil ? nil : row.accessibilityValue, accessory: accessory))
        }
        return rows
    }

    private func wireSiteControlCenter(_ controller: SiteControlCenterController, browser: PCBrowserView, page: PCNativePage) {
        let model = controller.model
        let revision = browser.readerRevision
        let profileID = activeProfileID, spaceID = activeSpaceID, parent = window
        let current: () -> Bool = { [weak self, weak browser, weak page, weak parent] in
            guard let self, let browser, let page, let parent,
                  !self.isClosing, !self.wholeWindowClose, !page.isClosed else { return false }
            return self.window === parent && browser.window === parent
                && self.activeProfileID == profileID && self.activeSpaceID == spaceID
                && self.currentBrowser === browser && browser.nativePage === page && browser.readerRevision == revision
        }
        let currentPresentation: () -> Bool = { [weak self, weak controller] in
            guard current(), let self, let controller else { return false }
            return self.siteControlCenter === controller
        }
        model.onButton = { [weak self, weak controller] button in
            guard currentPresentation(), let self, let controller else { return }
            switch button {
            case .share:
                guard let url = self.sharePageTarget?.url, let (rect, view) = controller.rect(for: .share) else { return }
                NSSharingServicePicker(items: [url]).show(relativeTo: rect, of: view, preferredEdge: .minY)
            case .copyURL: self.dismissSiteControlCenter { [weak self] in self?.copyCurrentURL() }
            case .capture: self.dismissSiteControlCenter(when: current) { [weak self] in self?.capturePage(.region) }
            case .captureFullPage: self.dismissSiteControlCenter(when: current) { [weak self] in self?.capturePage(.fullPage) }
            case .captureVisiblePage: self.dismissSiteControlCenter(when: current) { [weak self] in self?.capturePage(.viewport) }
            }
        }
        model.onExtension = { [weak self, weak controller] id in
            guard currentPresentation(), let self else { return }
            self.siteControlCenterItems[id]?.execute(controller?.anchorView)
        }
        controller.preparePickerSelection = { [weak self, weak controller] in
            guard currentPresentation(), let self else { return nil }
            let items = self.siteControlCenterItems
            return { [weak anchor = controller?.anchorView] id in items[id]?.execute(anchor) }
        }
        model.onExtensionContextMenu = { [weak self, weak controller] id in
            guard currentPresentation(), let self, let tile = controller?.tile(for: id) else { return }
            self.siteControlCenterItems[id]?.showContextMenu(tile)
        }
        model.onExtensionPin = { [weak self] id in
            guard currentPresentation(), let self, let item = self.siteControlCenterItems[id], item.canChangePin else { return }
            item.setPinned(item.pinnedIndex == nil)
        }
        let afterDismissal: () -> Bool = { [weak self, weak parent] in
            guard current(), let self, let parent, parent.isKeyWindow else { return false }
            return self.windowCommandSecurityAvailable
        }
        let openExtensionDestination: (String) -> Void = { [weak self] address in
            guard let self, afterDismissal(), let url = URL(string: address) else { return }
            self.openAddress(url)
        }
        model.onManageExtensions = { [weak self] in
            guard currentPresentation(), let self else { return }
            self.dismissSiteControlCenter(when: afterDismissal) { openExtensionDestination("parc://extensions/") }
        }
        model.onAddExtension = { [weak self] in
            guard currentPresentation(), let self else { return }
            self.dismissSiteControlCenter(when: afterDismissal) { openExtensionDestination("https://chromewebstore.google.com/category/extensions") }
        }
        model.onSetting = { [weak self, weak controller, weak page] id in
            guard currentPresentation(), let self, let controller, let page else { return }
            self.toggleSiteControlCenterSetting(id, page: page, afterDismissal: afterDismissal)
            if currentPresentation() { self.updateSiteControlCenter(controller, page: page, items: nil) }
        }
        model.onSettingAccessory = { [weak self, weak page] id in
            guard currentPresentation(), let self, let page,
                  let (index, revision) = self.siteControlCenterPermissionTargets[id],
                  page.responds(to: #selector(PCNativePage.openSiteControlsSystemSettings(_:revision:))) else { return }
            _ = page.openSiteControlsSystemSettings(index, revision: revision)
        }
        model.onSiteSettings = { [weak self] in
            guard currentPresentation(), let self else { return }
            self.dismissSiteControlCenter { [weak self] in self?.openSiteControlCenterSiteSettings() }
        }
        model.onSecurity = { [weak self, weak browser, weak page] in
            guard currentPresentation(), let self, let browser, let page else { return }
            if page.responds(to: #selector(PCNativePage.showCertificate)) {
                guard page.canShowCertificate else { return }
                self.dismissSiteControlCenter(when: afterDismissal) { [weak page] in _ = page?.showCertificate() }
                return
            }
            let anchor: NSView = self.isPopupWindow ? self.popupChrome.pageControlsAnchor :
                self.sidebar.isPresented ? self.sidebar.pageControlsAnchor : browser
            self.dismissSiteControlCenter { [weak self, weak browser, weak anchor] in
                guard let self, let browser, self.currentBrowser === browser, browser.canShowSiteInfo else { return }
                self.showSiteInfo(browser, from: self.selectedBrowserToolbar?.siteControlCenterAnchor ?? anchor ?? browser)
            }
        }
        model.onMore = { [weak self] in
            guard currentPresentation(), let self else { return }
            self.siteControlCenterMoreMenu(current: currentPresentation, afterDismissal: afterDismissal,
                                           openExtensionDestination: openExtensionDestination)
                .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        wireBlockedContent(controller, page: page, current: currentPresentation, afterDismissal: afterDismissal)
    }

    private func toggleSiteControlCenterSetting(_ id: String, page: PCNativePage, afterDismissal: @escaping () -> Bool) {
        switch id {
        case "preview":
            SidebarPreviewPreference.recentPages.isEnabled.toggle()
        case "developerMode":
            dismissSiteControlCenter(when: afterDismissal) { [weak self, weak page] in
                guard let self, let page, let host = page.developerModeSiteHost, !self.isPrivateBrowsing,
                      self.canPerformPageTool(.developerTools),
                      let browser = self.currentBrowser, browser.nativePage === page else { return }
                self.setDeveloperMode(!DeveloperModePreferences.shared.isEnabled(host: host), host: host, browser: browser, page: page)
            }
        default:
            guard let (index, revision) = siteControlCenterPermissionTargets[id],
                  page.responds(to: #selector(PCNativePage.toggleSiteControlsPermission(_:revision:))) else { return }
            _ = page.toggleSiteControlsPermission(index, revision: revision)
        }
    }

    private func siteControlCenterMoreMenu(current: @escaping () -> Bool,
                                           afterDismissal: @escaping () -> Bool,
                                           openExtensionDestination: @escaping (String) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let close: (@escaping () -> Void) -> Void = { [weak self] action in
            guard let self, current() else { return }
            self.dismissSiteControlCenter(when: afterDismissal, then: action)
        }
        for (title, tool) in [("Clear Cache", PCNativePageTool.clearCacheAndRefresh), ("Clear Cookies", .clearCookiesAndRefresh)] {
            let item = MenuAction.item(title) { [weak self] in
                close { self?.performPageTool(tool) }
            }
            item.isEnabled = siteControlCenterPageTools.contains(tool)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Manage Extensions…") {
            close { openExtensionDestination("parc://extensions/") }
        })
        menu.addItem(MenuAction.item("Add Extension…") {
            close { openExtensionDestination("https://chromewebstore.google.com/category/extensions") }
        })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("All Site Settings…") { [weak self] in
            close { self?.openSiteControlCenterSiteSettings() }
        })
        return menu
    }

    private func openSiteControlCenterSiteSettings() {
        guard let url = currentBrowser?.url, let scheme = url.scheme, let host = url.host,
              ["http", "https"].contains(scheme.lowercased()) else { openAddress(URL(string: "parc://settings/content")!); return }
        let origin = scheme + "://" + host + (url.port.map { ":\($0)" } ?? "")
        var components = URLComponents(string: "parc://settings/content/siteDetails")
        components?.queryItems = [URLQueryItem(name: "site", value: origin)]
        openAddress(components?.url ?? URL(string: "parc://settings/content")!)
    }

    func openExtensionPicker() {
        guard presentation.isReady, !isClosing, !wholeWindowClose, commandBar == nil else { return }
        showSiteControlCenter(from: selectedBrowserToolbar?.siteControlCenterAnchor,
                              picker: NSEvent.modifierFlags.contains(.command))
    }
    var canOpenExtensionPicker: Bool {
        presentation.isReady && !isClosing && !wholeWindowClose && commandBar == nil
            && currentBrowser?.nativePage.map { !$0.isClosed } == true && !extensionControlItems().isEmpty
    }

    func showPageMenu(from sourceAnchor: NSView? = nil) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if isPopupWindow {
            let openControls = preparePopupSiteControls(requireExtensions: false)
            let item = MenuAction.item("Site Control Center…") { _ = openControls?() }
            item.isEnabled = openControls != nil
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if let binding = nativeBinding, let page = currentBrowser?.nativePage,
           let action = binding.openAppAction(for: page) {
            menu.addItem(MenuAction.item(action.title) { [weak self, weak binding, weak page] in
                guard let self, let binding, let page, !self.isClosing,
                      self.nativeBinding === binding, self.currentBrowser?.nativePage === page else { return }
                _ = binding.executeOpenAppAction(action, for: page)
            })
            menu.addItem(.separator())
        }
        if let browser = currentBrowser {
            let revision = browser.readerRevision
            let info = MenuAction.item("Site Settings and Security…") { [weak self, weak browser] in
                guard let self, let browser, self.presentation.isReady,
                      !self.isClosing, !self.wholeWindowClose,
                      self.currentBrowser === browser, browser.readerRevision == revision,
                      browser.canShowSiteInfo else { return }
                let anchor: NSView = self.isPopupWindow ? self.popupChrome.pageControlsAnchor :
                    self.sidebar.isPresented ? self.sidebar.pageControlsAnchor : browser
                self.showSiteInfo(browser, from: anchor)
            }
            info.isEnabled = presentation.isReady && !isClosing && !wholeWindowClose && browser.canShowSiteInfo
            menu.addItem(info)
        }
        let paymentItems = paymentMenuItems()
        paymentItems.forEach { menu.addItem($0) }
        if !paymentItems.isEmpty { menu.addItem(.separator()) }
        if let peek = activePeek {
            let expand = MenuAction.item("Open Peek as Tab") { [weak self, weak peek] in
                guard let self, let peek, self.activePeek === peek else { return }; self.promotePeek(peek, split: false)
            }
            expand.isEnabled = !peek.closePending
            menu.addItem(expand)
            let split = MenuAction.item("Add Peek to Split View") { [weak self, weak peek] in
                guard let self, let peek, self.activePeek === peek else { return }; self.promotePeek(peek, split: true)
            }
            split.isEnabled = peek.canSplit?() == true; menu.addItem(split)
            menu.addItem(MenuAction.item("Close Peek") { [weak peek] in peek?.requestDismiss(.closeButton) })
        } else if !isPopupWindow {
            let add = MenuAction.item("Add Split View") { [weak self] in self?.toggleSplit() }
            add.isEnabled = splitCommandIsAvailable(.add(.addAfter)) && splitInsertion == nil
            menu.addItem(add)
        }
        if activePeek == nil, let layout = activeSplitLayout {
            let directions = NSMenu(title: "Split Layout")
            for (title, orientation) in [("Side by Side", SplitOrientation.horizontal), ("Stacked", SplitOrientation.vertical)] {
                let item = splitMenuItem(title, command: .orientation(orientation))
                item.state = layout.orientation == orientation ? .on : .off
                directions.addItem(item)
            }
            let layoutItem = NSMenuItem(title: "Split Layout", action: nil, keyEquivalent: "")
            layoutItem.submenu = directions; menu.addItem(layoutItem)
            menu.addItem(splitMenuItem("Expand Current Split", command: .expand))
            menu.addItem(splitMenuItem("Separate Page from Split View", command: .separate))
            menu.addItem(splitMenuItem("Close this Split Pane", command: .close))
            menu.addItem(.separator())
        }
        menu.addItem(MenuAction.item("Find in page…") { [weak self] in self?.findInPage() })
        let copyBrowser = currentBrowser
        let copyRevision = copyBrowser?.readerRevision
        let copy = MenuAction.item("Copy URL") { [weak self, weak copyBrowser] in
            guard let self, let copyBrowser, self.currentBrowser === copyBrowser,
                  copyBrowser.readerRevision == copyRevision else { return }
            self.copyCurrentURL()
        }
        copy.isEnabled = canCopyCurrentURL; menu.addItem(copy)
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Zoom in") { [weak self] in self?.zoomIn() })
        menu.addItem(MenuAction.item("Zoom out") { [weak self] in self?.zoomOut() })
        menu.addItem(MenuAction.item("Actual size") { [weak self] in self?.actualSize() })
        menu.addItem(.separator())
        addReaderMenuItems(to: menu)
        menu.addItem(captureMenuItem("Capture Portion…", mode: .region))
        menu.addItem(captureMenuItem("Capture Visible Area", mode: .viewport))
        menu.addItem(captureMenuItem("Capture Full Page", mode: .fullPage))
        menu.addItem(pageToolItem("Print…", tool: .print))
        menu.addItem(pageToolItem("Save Page As…", tool: .save))
        menu.addItem(pageToolItem("Cast", tool: .cast))
        menu.addItem(pageToolItem("View Source", tool: .viewSource))
        menu.addItem(.separator())
        menu.addItem(pageToolItem("Clear Cache and Refresh", tool: .clearCacheAndRefresh))
        menu.addItem(pageToolItem("Clear Cookies and Refresh", tool: .clearCookiesAndRefresh))
        menu.addItem(pageToolItem("Clear Browsing Data…", tool: .clearBrowsingData))
        menu.addItem(.separator())
        menu.addItem(pageToolItem("Developer Tools", tool: .developerTools))
        menu.addItem(pageToolItem("Inspect Elements", tool: .inspectElements))
        menu.addItem(pageToolItem("JavaScript Console", tool: .javaScriptConsole))
        menu.addItem(pageToolItem("Network Inspector", tool: .networkInspector))
        let developer = NSMenuItem(title: developerModeTitle, action: nil, keyEquivalent: "")
        let developerRequest = makeDeveloperModeRequest()
        developer.representedObject = developerRequest
        developer.target = self; developer.action = #selector(toggleDeveloperModeMenuItem(_:))
        developer.isEnabled = developerRequest != nil
        menu.addItem(developer)
        if isPopupWindow {
            menu.addItem(MenuAction.item("Downloads") { [weak self] in self?.showDownloads() })
        }
        menu.addItem(MenuAction.item("Settings…") { [weak self] in self?.showSettings() })
        if sourceAnchor == nil, !isPopupWindow, !sidebar.isPresented {
            let page = hiddenSidebarAnchor
            menu.popUp(positioning: nil, at: page.menuPoint, in: page.view); return
        }
        let anchor: NSView = sourceAnchor ?? (isPopupWindow ? popupChrome.pageControlsAnchor : sidebar)
        let point = sourceAnchor != nil || isPopupWindow ? NSPoint(x: 0, y: anchor.bounds.height) : NSPoint(x: sidebar.bounds.width - 35, y: 80)
        menu.popUp(positioning: nil, at: point, in: anchor)
    }

    var isCreatingSpace: Bool { spaceCreation != nil }
    func createSpace() {
        if let session = spaceCreation { session.view.focusName(); return }
        guard !isPrivateBrowsing, !isPopupWindow, !store.isEphemeral else { return }
        window?.makeKeyAndOrderFront(nil)
        let press = NewSpaceBlockerWait.press(peek: newSpaceBlockingPeekState, waitActive: newSpaceWaitActive)
        guard press != .bringForward else { return }
        if press == .dismissAndWait, presentation.isReady { dismissForNewSpaceForm() }
        newSpaceWait &+= 1
        newSpaceWaitActive = true
        presentNewSpaceForm(attemptsLeft: 40, wait: newSpaceWait)
    }
}
