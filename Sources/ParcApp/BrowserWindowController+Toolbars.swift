import AppKit
import Combine

extension BrowserWindowController {
    func applySidebarToolbarOwnership() {
        sidebar.usesContentToolbar = !sidebarShowsAddressBar
        sidebar.navigationInContentToolbar = selectedBrowserToolbar != nil
    }
    func configureBrowserToolbar(_ toolbar: BrowserToolbarView, browser: PCBrowserView?, visible: Bool, failing: Bool, themeBackground: NSColor?, leading: Bool = false, tabID: UUID? = nil) {
        guard visible, !isPopupWindow, libraryView == nil,
              let browser, let page = browser.nativePage, !page.isClosed else {
            if toolbar.ownsFocus, window?.isKeyWindow == true, commandBar == nil,
               let browser, currentBrowser === browser, let page = browser.nativePage, !page.isClosed {
                window?.makeFirstResponder(page.nativeView)
            }
            toolbar.isHidden = true; toolbar.setPageColor(nil, for: nil); toolbar.invalidate(); return
        }
        toolbar.isHidden = false; toolbar.themeBackground = themeBackground
        toolbar.showPageColor(of: page, failing: failing)
        let revision = browser.readerRevision
        let selected = currentBrowser === browser
        let enabled = !isClosing && !wholeWindowClose && !windowClosePending && commandBar == nil
            && window?.isKeyWindow == true
            && window.map { PCNativeBrowserApplication.canPresentTabSwitcher(in: $0) } == true
        toolbar.update(url: browser.url,
            fullURL: BrowserToolbarPreferences.shared.state.showsFullURL,
            enabled: enabled, canBack: page.canShowBackHistory, canForward: page.canShowForwardHistory,
            loading: page.loading, canReload: page.canPerformNavigation(page.loading ? .stop : .reload),
            canCopy: selected ? canCopyCurrentURL : browser.url != nil && page.canCopyLink(as: .plain),
            canShowSiteInfo: true,
            canSplit: activePeek?.canSplit?() ?? true,
            close: activePeek?.browser !== browser && activeSplitLayout != nil,
            showSidebar: leading && sidebarPresentation != .locked,
            insecure: page.responds(to: #selector(getter: PCNativePage.secureContextState))
                && page.secureContextState == .insecure,
            extensionItems: selected ? extensionControlItems() : [])
        toolbar.updateBlockedContent(blockedContent(for: page))
        let original: () -> Bool = { [weak self, weak browser, weak page] in
            guard let self, let browser, let page else { return false }
            return self.activateDeveloperPage(browser, page: page, revision: revision)
        }
        toolbar.onNavigation = { [weak self] kind in
            guard original() else { return nil }; return self?.prepareNavigationInteraction(kind)
        }
        toolbar.onEscape = { [weak self, weak page] in
            guard original(), let page else { return }; self?.window?.makeFirstResponder(page.nativeView)
        }
        toolbar.onTitleMenu = { [weak self, weak browser] in
            guard let self, let browser else { return nil }
            return self.paneTitleMenu(browser: browser, admit: original)
        }
        toolbar.onAction = { [weak self, weak browser, weak page] action, anchor in
            guard let self else { return }
            if action == .closeSplit {
                if let tabID { self.closeClickedSplitPane(tabID) }
                return
            }
            guard original(), let browser, let page else { return }
            switch action {
            case .address: self.focusAddress()
            case .copy: self.copyCurrentURL()
            case .siteInfo, .siteInsecure, .blocked: self.showSiteControlCenter(from: anchor)
            case .pageMenu: self.showPageMenu(from: anchor)
            case .split: self.showDeveloperSplitMenu(from: anchor, browser: browser, page: page, revision: revision)
            case .closeSplit: break
            case .sidebar: self.toggleSidebar()
            }
        }
    }

    func configureDocumentToolbar(_ pane: BrowserPane, tabID: UUID, visible: Bool, leading: Bool) {
        let toolbar = pane.browserToolbar
        guard visible, !isPopupWindow, libraryView == nil,
              let tab = store.state.tab(tabID, where: { $0.archivedAt == nil }) else {
            if toolbar.ownsFocus, window?.isKeyWindow == true, commandBar == nil { focusSelectedLocalContent() }
            toolbar.isHidden = true; toolbar.setPageColor(nil, for: nil); toolbar.invalidate(); return
        }
        toolbar.isHidden = false; toolbar.themeBackground = rootView.palette.background
        toolbar.setPageColor(nil, for: nil)
        let enabled = !isClosing && !wholeWindowClose && !windowClosePending && commandBar == nil
            && window?.isKeyWindow == true
            && window.map { PCNativeBrowserApplication.canPresentTabSwitcher(in: $0) } == true
        toolbar.update(url: nil, documentTitle: tab.title.isEmpty ? "New tab" : tab.title,
            fullURL: false, enabled: enabled, canBack: false, canForward: false, loading: false,
            canReload: false, canCopy: false, canShowSiteInfo: false, canSplit: true,
            close: activeSplitLayout != nil, showSidebar: leading && sidebarPresentation != .locked,
            siteControls: false, extensionItems: [])
        let admit: () -> Bool = { [weak self, weak pane] in
            guard let self, let pane, self.panes[tabID] === pane, self.selectedTabIDs.contains(tabID),
                  pane.livePage == nil, self.activePeek == nil, self.commandBar == nil,
                  self.presentation.isReady, !self.isClosing, let window = self.window, window.isKeyWindow,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
            if self.focusedTabID != tabID { self.focusedTabID = tabID; self.requestNativeSelection(); self.updateNavigation() }
            return self.currentTabID == tabID
        }
        toolbar.onNavigation = { _ in nil }
        toolbar.onEscape = { [weak self] in guard admit() else { return }; self?.focusSelectedLocalContent() }
        toolbar.onTitleMenu = { [weak self] in
            guard let self else { return nil }
            let model = self.store.state.tab(tabID, where: { $0.archivedAt == nil })
            return self.paneTitleMenu(browser: nil, tab: model, admit: admit)
        }
        toolbar.onAction = { [weak self] action, anchor in
            guard let self else { return }
            if action == .closeSplit {
                self.closeClickedSplitPane(tabID)
                return
            }
            guard admit() else { return }
            switch action {
            case .address: self.focusAddress()
            case .split: self.showSplitPaneMenu(tabID, from: anchor)
            case .closeSplit: break
            case .sidebar: self.toggleSidebar()
            case .copy, .siteInfo, .siteInsecure, .pageMenu, .blocked: break
            }
        }
    }

    private func paneTitleMenu(browser: PCBrowserView?, tab: BrowserTab? = nil, admit: @escaping () -> Bool) -> NSMenu? {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              commandBar == nil, libraryView == nil, let window, window.isKeyWindow else { return nil }
        if let peek = activePeek, peek.browser !== browser { return nil }
        let content = PaneMenuContent(livePage: browser?.nativePage.map { !$0.isClosed } == true, tabURL: tab?.url,
                                      localDocument: tab.map { InternalPage.isInternal($0.url) } == true)
        guard content != .none else { return nil }
        let isWeb = content == .web
        let shareURL = browser?.url ?? tab.flatMap { URL(string: $0.url) }
        let menu = NSMenu(); menu.autoenablesItems = false
        func page(_ title: String, enabled: Bool = true, _ perform: @escaping (BrowserWindowController) -> Void) -> NSMenuItem {
            let item = MenuAction.item(title) { [weak self] in
                guard let self, !self.isClosing, admit() else { return }
                perform(self)
            }
            item.isEnabled = enabled; return item
        }
        func preference(_ title: String, enabled: Bool, _ change: @escaping () throws -> Void) -> NSMenuItem {
            let item = MenuAction.item(title) { [weak self] in
                guard let self, self.presentation.isReady, !self.isClosing, !self.wholeWindowClose else { return }
                do { try change() } catch { showError(error) }
            }
            item.isEnabled = enabled; return item
        }
        let copyURL = page("Copy URL", enabled: browser == nil || shareURL != nil) { $0.copyCurrentURL() }
        KeyboardShortcuts.shared.showBinding(on: copyURL, for: "copyCurrentURL:")
        menu.addItem(copyURL)
        if isWeb {
            let canCapture = browser != nil && privateCaptureContextIsValid
            menu.addItem(PaneShareMenu.item(for: shareURL))
            let portion = page("Capture Portion…", enabled: canCapture) { $0.capturePage(.region) }
            KeyboardShortcuts.shared.showBinding(on: portion, for: "capturePage:")
            menu.addItem(portion)
            menu.addItem(page("Capture Visible Area", enabled: canCapture) { $0.capturePage(.viewport) })
            menu.addItem(page("Capture Full Page", enabled: canCapture) { $0.capturePage(.fullPage) })
            menu.addItem(.separator())
            menu.addItem(page("Manage Extensions…") { $0.openAddress(URL(string: "parc://extensions/")!) })
        }
        var section: [NSMenuItem] = []
        let toolbar = BrowserToolbarPreferences.shared
        if isWeb {
            let full = toolbar.state.showsFullURL
            section.append(preference(full ? "Hide Full URL" : "Show Full URL", enabled: !toolbar.loadError) {
                try toolbar.setShowsFullURL(!full)
            })
        }
        if !isPopupWindow, activeSplitLayout == nil {
            let visible = toolbar.state.isVisible
            section.append(preference(visible ? "Hide Toolbar" : "Show as Toolbar", enabled: canToggleToolbar) {
                try toolbar.setVisible(!visible)
            })
        }
        if isWeb {
            let quotes = SharedQuotePreferences.shared, enabled = quotes.state.isEnabled
            section.append(preference(enabled ? "Disable Shared Quotes" : "Enable Shared Quotes", enabled: !quotes.loadError) {
                try quotes.setEnabled(!enabled)
            })
        }
        if !section.isEmpty { menu.addItem(.separator()); section.forEach(menu.addItem) }
        return menu
    }

    func prepareFairPlayIdentityMenuItem(_ item: NSMenuItem) -> Bool {
        item.representedObject = nil
        guard let page = currentBrowser?.nativePage, !page.isClosed, let site = page.fairPlayIdentitySite else { return false }
        let offTheRecord = page.fairPlayIdentityOffTheRecord
        let useChrome: Bool
        switch FairPlayIdentityController.shared.identity(of: site, profilePath: page.profilePath, offTheRecord: offTheRecord) {
        case .safari: useChrome = true
        case .chrome: useChrome = false
        case .undecided: return false
        }
        item.title = useChrome ? "Use Chrome Identity for This Site" : "Use Safari Identity for This Site"
        item.representedObject = FairPlayIdentityMenuRequest(owner: self, page: page, site: site,
                                                             offTheRecord: offTheRecord, useChrome: useChrome)
        return true
    }
    func toggleFairPlayIdentity(from item: NSMenuItem) {
        guard let request = item.representedObject as? FairPlayIdentityMenuRequest, request.owner === self,
              let page = request.page, currentBrowser?.nativePage === page, !page.isClosed,
              page.fairPlayIdentitySite == request.site else { return }
        let identity = FairPlayIdentityController.shared
        if request.useChrome {
            identity.useChromeIdentity(for: request.site, profilePath: request.profilePath, offTheRecord: request.offTheRecord)
        } else {
            identity.useSafariIdentity(for: request.site, profilePath: request.profilePath, offTheRecord: request.offTheRecord)
        }
    }
    var developerModeTitle: String {
        guard let host = currentBrowser?.nativePage?.developerModeSiteHost else { return "Turn on Developer Mode for this site" }
        return DeveloperModePreferences.shared.isEnabled(host: host)
            ? "Turn off Developer Mode for this site" : "Turn on Developer Mode for this site"
    }
    func makeDeveloperModeRequest() -> DeveloperModeMenuRequest? {
        guard !isPrivateBrowsing, !DeveloperModePreferences.shared.loadError, canPerformPageTool(.developerTools),
              let browser = currentBrowser, let page = browser.nativePage,
              let host = page.developerModeSiteHost else { return nil }
        return DeveloperModeMenuRequest(owner: self, browser: browser, page: page, host: host)
    }
    func prepareDeveloperModeMenuItem(_ item: NSMenuItem) -> Bool {
        item.title = developerModeTitle
        item.representedObject = makeDeveloperModeRequest()
        return item.representedObject != nil
    }
    func toggleDeveloperMode(from item: NSMenuItem) {
        guard let request = item.representedObject as? DeveloperModeMenuRequest,
              request.owner === self, let browser = request.browser, currentBrowser === browser,
              browser.nativePage === request.page, browser.readerRevision == request.revision,
              request.page.developerModeSiteHost == request.host, canPerformPageTool(.developerTools) else { return }
        setDeveloperMode(!DeveloperModePreferences.shared.isEnabled(host: request.host), host: request.host,
                         browser: browser, page: request.page)
    }
    @objc func toggleDeveloperModeMenuItem(_ sender: NSMenuItem) { toggleDeveloperMode(from: sender) }

    func setDeveloperMode(_ on: Bool, host: String, browser: PCBrowserView, page: PCNativePage) {
        do {
            try DeveloperModePreferences.shared.setEnabled(on, host: host)
        } catch { showError(error); return }
        refreshDeveloperToolbars()
        guard Self.knowsDeveloperTools(page), on != page.hasDeveloperTools else { return }
        _ = browser.performPageTool(on ? .javaScriptConsole : .developerTools)
    }

    private static func knowsDeveloperTools(_ page: PCNativePage) -> Bool {
        page.responds(to: #selector(getter: PCNativePage.hasDeveloperTools))
    }

    private func toggleDeveloperTools(_ browser: PCBrowserView) {
        guard let page = browser.nativePage, Self.knowsDeveloperTools(page),
              let request = makeDeveloperModeRequest(), request.page === page else {
            _ = browser.performPageTool(.developerTools)
            return
        }
        setDeveloperMode(!page.hasDeveloperTools, host: request.host, browser: browser, page: page)
    }

    func activateDeveloperPage(_ browser: PCBrowserView, page: PCNativePage, revision: UInt) -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              commandBar == nil, libraryView == nil, nativeFullscreenTabID == nil,
              browser.nativePage === page, !page.isClosed, browser.readerRevision == revision,
              let window, browser.window === window, window.isKeyWindow,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
        if let peek = activePeek { return peek.browser === browser && !peek.closePending }
        guard let id = browsers.first(where: { $0.value === browser })?.key,
              selectedTabIDs.contains(id), panes[id]?.browser === browser,
              !closingTabIDs.contains(id), !store.retiringTabIDs.contains(id),
              !transferringTabIDs.contains(id) else { return false }
        if focusedTabID != id {
            focusedTabID = id; requestNativeSelection(); updateNavigation()
        }
        return currentBrowser === browser
    }
    private func configureWebpageDragging(_ pane: BrowserPane, tabID: UUID) {
        guard !WebpageWindowDraggingPreferences.shared.loadError,
              WebpageWindowDraggingPreferences.shared.state.isEnabled,
              selectedTabIDs.contains(tabID), activePeek == nil, nativeFullscreenTabID == nil,
              libraryView == nil, !isPopupWindow, let browser = pane.browser,
              let page = browser.nativePage, !page.isClosed else {
            pane.windowGrabber.configure(owner: nil, revision: 0, isCurrent: nil, eligibility: nil); return
        }
        let revision = browser.readerRevision
        let original: () -> Bool = { [weak self, weak pane, weak browser, weak page] in
            guard let self, let pane, let browser, let page,
                  !WebpageWindowDraggingPreferences.shared.loadError,
                  WebpageWindowDraggingPreferences.shared.state.isEnabled,
                  self.presentation.isReady, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.activePeek == nil, self.pageCapture == nil, self.libraryView == nil,
                  self.commandBar == nil, self.nativeFullscreenTabID == nil,
                  self.selectedTabIDs.contains(tabID), self.panes[tabID] === pane, pane.browser === browser,
                  browser.nativePage === page, !page.isClosed, browser.readerRevision == revision,
                  !browser.isHiddenOrHasHiddenAncestor,
                  !self.closingTabIDs.contains(tabID), !self.store.retiringTabIDs.contains(tabID),
                  !self.transferringTabIDs.contains(tabID),
                  let window = self.window, browser.window === window,
                  window.isVisible, window.isMovable, !window.styleMask.contains(.fullScreen),
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
            return true
        }
        pane.windowGrabber.configure(owner: page, revision: revision, isCurrent: original) { [weak page] event in
            guard original(), WebpageWindowDragState.permitsModifiers(event.modifierFlags), let page,
                  let host = page.nativeView as? PCNativePageHost,
                  let rendererContainer = host.contentView, !rendererContainer.isHiddenOrHasHiddenAncestor,
                  rendererContainer.bounds.contains(rendererContainer.convert(event.locationInWindow, from: nil)) else { return false }
            return true
        }
    }

    func refreshDeveloperToolbars() {
        let modal = activePeek?.modalPhase
        let leading = renderedPaneIDs.first
        var flushedChromeLayout = false
        for (id, pane) in panes {
            let obstructed = modal == .presented
            if pane.controlsObstructed != obstructed { pane.controlsObstructed = obstructed }
            let focused = currentTabID == id || modal == .dismissing
            if pane.controlsFocused != focused { pane.controlsFocused = focused }
            configureWebpageDragging(pane, tabID: id)
            configurePaneDeveloperToolbar(pane,
                visible: selectedTabIDs.contains(id) && activePeek == nil && nativeFullscreenTabID == nil)
            let developerPage = pane.browser?.nativePage?.developerModeSiteHost
                .map { DeveloperModePreferences.shared.isEnabled(host: $0) } == true
            let topBar = selectedTabIDs.contains(id) && paneTopBarDisplayed && !developerPage
            if let browser = pane.livePage {
                configureBrowserToolbar(pane.browserToolbar, browser: browser, visible: topBar, failing: pane.showsFailure,
                                        themeBackground: rootView.palette.background, leading: id == leading, tabID: id)
            } else {
                configureDocumentToolbar(pane, tabID: id, visible: topBar, leading: id == leading)
            }
            let developerHeight: CGFloat = pane.loadedDeveloperToolbar?.isHidden == false ? DeveloperToolbarLayout.height : 0
            let browserHeight: CGFloat = pane.browserToolbar.isHidden ? 0 : BrowserToolbarView.height
            if pane.needsLayout
                || !DeveloperChromeGeometry.paneIsCurrent(
                    bounds: pane.bounds,
                    developerHeight: developerHeight,
                    browserHeight: browserHeight,
                    developerFrame: pane.loadedDeveloperToolbar?.frame
                        ?? NSRect(x: 0, y: 0, width: pane.bounds.width, height: 0),
                    browserFrame: pane.browserToolbar.frame,
                    contentFrame: pane.content.frame) {
                pane.needsLayout = true
                pane.layoutSubtreeIfNeeded()
                flushedChromeLayout = true
            }
        }
        refreshSplitPaneHighlights()
        for peek in peeks.values {
            configureDeveloperToolbar(peek.view.developerToolbar, browser: peek.browser,
                visible: activePeek === peek)
            configureBrowserToolbar(peek.view.browserToolbar, browser: peek.browser,
                visible: PaneTopBarAdmission.peekDisplayed(
                    toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible,
                    isActivePeek: activePeek === peek,
                    developerToolbarHidden: peek.view.developerToolbar.isHidden),
                failing: peek.showsFailure, themeBackground: nil)
            let developerHeight: CGFloat = peek.view.developerToolbar.isHidden ? 0 : DeveloperToolbarLayout.height
            let browserHeight: CGFloat = peek.view.browserToolbar.isHidden ? 0 : BrowserToolbarView.height
            if peek.view.needsLayout
                || !DeveloperChromeGeometry.peekIsCurrent(
                    bounds: peek.view.bounds,
                    developerHeight: developerHeight,
                    browserHeight: browserHeight,
                    developerFrame: peek.view.developerToolbar.frame,
                    browserFrame: peek.view.browserToolbar.frame,
                    contentFrame: peek.view.content.frame) {
                peek.view.needsLayout = true
                peek.view.layoutSubtreeIfNeeded()
                flushedChromeLayout = true
            }
        }
        applySidebarToolbarOwnership()
        if flushedChromeLayout {
            synchronizeNativeLayout()
        }
    }
    func configurePaneDeveloperToolbar(_ pane: BrowserPane, visible: Bool) {
        let shows = visible && libraryView == nil
            && pane.browser?.nativePage?.developerModeSiteHost.map { DeveloperModePreferences.shared.isEnabled(host: $0) } == true
        guard let toolbar = shows ? pane.developerToolbar : pane.loadedDeveloperToolbar else { return }
        configureDeveloperToolbar(toolbar, browser: pane.browser, visible: visible)
    }

    func configureDeveloperToolbar(_ toolbar: DeveloperToolbarView, browser: PCBrowserView?, visible: Bool) {
        guard visible, libraryView == nil, let browser, let page = browser.nativePage,
              let host = page.developerModeSiteHost, DeveloperModePreferences.shared.isEnabled(host: host) else {
            if toolbar.ownsFocus, window?.isKeyWindow == true, commandBar == nil,
               let browser, currentBrowser === browser, let page = browser.nativePage, !page.isClosed {
                toolbar.restoreCommittedAddress(); window?.makeFirstResponder(page.nativeView)
            }
            toolbar.isHidden = true; toolbar.onAction = nil; toolbar.onFocus = nil
            toolbar.onEdit = nil; toolbar.onEscape = nil; return
        }
        toolbar.isHidden = false
        let revision = browser.readerRevision
        let selected = currentBrowser === browser
        let editing = !isClosing && !wholeWindowClose && !windowClosePending
            && commandBar == nil && window?.isKeyWindow == true
            && window.map { PCNativeBrowserApplication.canPresentTabSwitcher(in: $0) } == true
        let enabled = editing && selected && browser.canPerformPageTool(.developerTools)
        toolbar.update(url: browser.url?.absoluteString ?? "", tint: page.developerModeTint,
            editing: editing, enabled: enabled, secure: page.developerModeSecure, siteInfo: browser.canShowSiteInfo,
            copy: selected && canCopyCurrentURL, capture: selected && canCapturePage,
            split: !isPopupWindow && (activePeek?.canSplit?() ?? true))
        let original: () -> Bool = { [weak self, weak browser, weak page] in
            guard let self, let browser, let page else { return false }
            return self.activateDeveloperPage(browser, page: page, revision: revision)
        }
        toolbar.onFocus = original
        toolbar.onEscape = { [weak self, weak page] in
            guard original(), let self, let page else { return }
            self.window?.makeFirstResponder(page.nativeView)
        }
        toolbar.onEdit = { [weak self, weak toolbar] text, selection in
            DispatchQueue.main.async { [weak self, weak toolbar] in
                guard original(), let self, let toolbar else { return }
                toolbar.restoreCommittedAddress()
                self.presentCommandBar(newTab: false, initialEdit: (text, selection))
            }
        }
        toolbar.onAction = { [weak self, weak browser, weak page] action, anchor in
            guard original(), let self, let browser, let page else { return }
            switch action {
            case .siteInfo: if browser.canShowSiteInfo { _ = browser.showSiteInfo(from: anchor) }
            case .copy: self.copyCurrentURL()
            case .portrait: self.capturePage(.portrait)
            case .capture: self.capturePage(.region)
            case .console: self.performPageTool(.javaScriptConsole)
            case .network: self.performPageTool(.networkInspector)
            case .inspect: self.performPageTool(.inspectElements)
            case .extensions: self.showSiteControlCenter(from: anchor)
            case .tools: self.showPageMenu(from: anchor)
            case .split: self.showDeveloperSplitMenu(from: anchor, browser: browser, page: page, revision: revision)
            }
        }
    }
    private func showDeveloperSplitMenu(from anchor: NSView, browser: PCBrowserView, page: PCNativePage, revision: UInt) {
        guard activateDeveloperPage(browser, page: page, revision: revision), !isPopupWindow else { return }
        let menu = NSMenu(); menu.autoenablesItems = false
        if let peek = activePeek {
            let item = MenuAction.item("Add Peek to Split View") { [weak self, weak peek] in
                guard let self, let peek, self.activePeek === peek,
                      self.activateDeveloperPage(browser, page: page, revision: revision) else { return }
                self.promotePeek(peek, split: true)
            }
            item.isEnabled = peek.canSplit?() == true; menu.addItem(item)
        } else if let paneID = currentTabID {
            showSplitPaneMenu(paneID, from: anchor); return
        } else if activeSplitLayout != nil {
            menu.addItem(splitMenuItem("Expand Current Split", command: .expand))
            menu.addItem(splitMenuItem("Separate Page from Split View", command: .separate))
            menu.addItem(splitMenuItem("Close this Split Pane", command: .close))
        } else {
            menu.addItem(MenuAction.item("Add Split View") { [weak self, weak browser, weak page] in
                guard let self, let browser, let page,
                      self.activateDeveloperPage(browser, page: page, revision: revision) else { return }
                self.toggleSplit()
            })
        }
        menu.appearance = anchor.effectiveAppearance
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
    }

    func showDeveloperTools() { performPageTool(.developerTools) }

    func canPerformPageTool(_ tool: PCNativePageTool) -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose,
              let browser = currentBrowser else { return false }
        return browser.canPerformPageTool(tool)
    }

    func performPageTool(_ tool: PCNativePageTool) {
        guard canPerformPageTool(tool), let browser = currentBrowser else { return }
        runPageTool(tool, in: browser)
    }

    private func runPageTool(_ tool: PCNativePageTool, in browser: PCBrowserView) {
        if tool == .developerTools { toggleDeveloperTools(browser); return }
        let opens = browser.nativePage.map { Self.knowsDeveloperTools($0) && !$0.hasDeveloperTools } ?? false
        _ = browser.performPageTool(tool)
        guard opens, [.javaScriptConsole, .networkInspector, .inspectElements].contains(tool),
              let request = makeDeveloperModeRequest(), request.browser === browser,
              !DeveloperModePreferences.shared.isEnabled(host: request.host) else { return }
        do {
            try DeveloperModePreferences.shared.setEnabled(true, host: request.host)
            refreshDeveloperToolbars()
        } catch { showError(error) }
    }

    var canExportEaselImage: Bool { currentEaselEditor?.canExportImage == true }
    func exportEaselImage() { currentEaselEditor?.exportImage() }
    var currentEaselEditor: EaselEditorViewController? {
        guard presentation.isReady, !isClosing, !wholeWindowClose, activePeek == nil, window?.isKeyWindow == true,
              let id = currentTabID, !transferringTabIDs.contains(id), renderedPaneIDs.contains(id) else { return nil }
        return easelEditors[id]?.editor
    }

    var readerActionTitle: String {
        switch currentBrowser?.readerMode ?? .inactive {
        case .distilling: return "Cancel Reader"
        case .viewing, .failedViewer: return "Exit Reader"
        case .unavailable: return "Try Reader Again"
        default: return "Enter Reader"
        }
    }

    func canToggleReaderMode() -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose,
              let browser = currentBrowser else { return false }
        return browser.canToggleReaderMode()
    }

    func prepareReaderMenuItem(_ item: NSMenuItem) -> Bool {
        item.title = readerActionTitle
        item.representedObject = currentBrowser.map { ReaderMenuRequest(owner: self, browser: $0) }
        return canToggleReaderMode()
    }

    func toggleReaderMode(from item: NSMenuItem) {
        guard let request = item.representedObject as? ReaderMenuRequest,
              request.owner === self, let browser = request.browser,
              currentBrowser === browser, browser.readerRevision == request.revision,
              canToggleReaderMode() else { return }
        _ = browser.toggleReaderMode()
    }

    func addReaderMenuItems(to menu: NSMenu) {
        let browser = currentBrowser
        let revision = browser?.readerRevision
        let item = MenuAction.item(readerActionTitle) { [weak self, weak browser] in
            guard let self, let browser, self.currentBrowser === browser,
                  browser.readerRevision == revision, self.canToggleReaderMode() else { return }
            _ = browser.toggleReaderMode()
        }
        item.isEnabled = canToggleReaderMode()
        menu.addItem(item)
        if let message = browser?.readerMessage, !message.isEmpty {
            let detail = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        }
    }

    func prepareScriptPermissionMenuItem(_ item: NSMenuItem, preservingTarget: Bool) -> Bool {
        if preservingTarget {
            guard let request = item.representedObject as? ScriptPermissionMenuRequest,
                  request.owner === self, let page = request.page,
                  currentBrowser?.nativePage === page else { return false }
            item.state = page.appleEventJavaScriptAllowed ? .on : .off
            return page.canToggleAppleEventJavaScript
        }
        guard let page = currentBrowser?.nativePage else {
            item.representedObject = nil; item.state = .off; return false
        }
        item.representedObject = ScriptPermissionMenuRequest(owner: self, page: page)
        item.state = page.appleEventJavaScriptAllowed ? .on : .off
        return page.canToggleAppleEventJavaScript
    }
    func toggleScriptPermission(from item: NSMenuItem) {
        guard let request = item.representedObject as? ScriptPermissionMenuRequest,
              request.owner === self, let page = request.page,
              currentBrowser?.nativePage === page, page.canToggleAppleEventJavaScript else { return }
        _ = page.toggleAppleEventJavaScript()
        item.state = page.appleEventJavaScriptAllowed ? .on : .off
    }

    func preparePageToolMenuItem(_ item: NSMenuItem, tool: PCNativePageTool) -> Bool {
        item.representedObject = currentBrowser.map { PageToolMenuRequest(owner: self, browser: $0, tool: tool) }
        return canPerformPageTool(tool)
    }

    func performPageTool(from item: NSMenuItem) {
        guard let request = item.representedObject as? PageToolMenuRequest,
              request.owner === self, let browser = request.browser,
              currentBrowser === browser, browser.readerRevision == request.revision,
              canPerformPageTool(request.tool) else { return }
        runPageTool(request.tool, in: browser)
    }

    func pageToolItem(_ title: String, tool: PCNativePageTool) -> NSMenuItem {
        let browser = currentBrowser
        let revision = browser?.readerRevision
        let item = MenuAction.item(title) { [weak self, weak browser] in
            guard let self, let browser, self.currentBrowser === browser,
                  browser.readerRevision == revision,
                  self.canPerformPageTool(tool) else { return }
            self.runPageTool(tool, in: browser)
        }
        item.isEnabled = canPerformPageTool(tool)
        if tool == .clearCacheAndRefresh {
            item.toolTip = "Reload this page without using cached resources."
        } else if tool == .clearCookiesAndRefresh {
            item.toolTip = "Clear this site's cookies, storage and cached data, then refresh. This may sign you out."
        }
        return item
    }

    func refreshPaymentControls() {
        sharedQuotes.bind(isClosing || wholeWindowClose ? nil : selectedNativePage(), window: window)
        guard !isClosing, let binding = nativeBinding,
              let page = currentBrowser?.nativePage, !page.isClosed else {
            paymentFeedbackWork?.cancel(); paymentFeedbackWork = nil
            sidebar.updatePaymentEntry(title: nil, symbol: "creditcard", enabled: false, savedLabel: "")
            return
        }
        let actions = binding.paymentActions(for: page)
        let title = actions.count > 1 ? "Payment methods" : actions.first?.title
        let saved = actions.map(\.savedLabel).filter { !$0.isEmpty }.joined(separator: " · ")
        if sidebar.updatePaymentEntry(title: title, symbol: actions.first?.symbolName ?? "creditcard",
                                      enabled: actions.contains { $0.isEnabled }, savedLabel: saved) {
            sidebar.layoutSubtreeIfNeeded()
        }
        guard sidebarPresentation != .hidden, sidebar.isPaymentEntryVisible else { return }
        for action in actions where action.requiresPresentationAcknowledgment {
            _ = binding.paymentFeedbackPresented(action, for: page)
            guard !isClosing, !page.isClosed, nativeBinding === binding,
                  currentBrowser?.nativePage === page, sidebar.isPaymentEntryVisible else { return }
        }
        guard !saved.isEmpty else { return }
        NSAccessibility.post(element: sidebar, notification: .announcementRequested,
                             userInfo: [.announcement: saved, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        for action in actions where !action.savedLabel.isEmpty {
            _ = binding.paymentFeedbackPresented(action, for: page)
        }
        paymentFeedbackWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak binding, weak page] in
            guard let self, let binding, let page,
                  self.nativeBinding === binding, self.currentBrowser?.nativePage === page else { return }
            self.refreshPaymentControls()
        }
        paymentFeedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func performPaymentAction(_ action: PCNativePaymentAction,
                                      binding: PCNativeBrowserWindow, page: PCNativePage) {
        guard nativeBinding === binding, currentBrowser?.nativePage === page,
              !isClosing, !page.isClosed else { return }
        _ = binding.executePaymentAction(action, for: page)
    }

    func paymentMenuItems() -> [NSMenuItem] {
        guard !isClosing, let binding = nativeBinding,
              let page = currentBrowser?.nativePage, !page.isClosed else { return [] }
        return binding.paymentActions(for: page).map { action in
            let item = MenuAction.item(action.title) { [weak self, weak binding, weak page] in
                guard let self, let binding, let page else { return }
                self.performPaymentAction(action, binding: binding, page: page)
            }
            item.isEnabled = action.isEnabled
            return item
        }
    }

    func showPaymentControls(anchor: NSView) {
        guard !isClosing, let binding = nativeBinding,
              let page = currentBrowser?.nativePage, !page.isClosed else { return }
        let actions = binding.paymentActions(for: page)
        if actions.count == 1, let action = actions.first {
            performPaymentAction(action, binding: binding, page: page)
            return
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        paymentMenuItems().forEach { menu.addItem($0) }
        guard !menu.items.isEmpty else { refreshPaymentControls(); return }
        if anchor.isDescendant(of: sidebar), !sidebar.isPresented {
            let page = hiddenSidebarAnchor
            menu.popUp(positioning: nil, at: page.menuPoint, in: page.view)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
        }
    }

    var hiddenSidebarAnchor: (view: NSView, rect: NSRect, menuPoint: NSPoint) {
        let page: NSView = currentBrowser ?? pageHost
        let top = page.isFlipped ? page.bounds.minY : page.bounds.maxY - 1
        return (page, NSRect(x: page.bounds.minX, y: top, width: 1, height: 1),
                NSPoint(x: page.bounds.minX, y: page.isFlipped ? page.bounds.minY : page.bounds.maxY))
    }

    @objc(parcSitePermissionAnchorForPage:)
    func sitePermissionAnchor(forPage page: NSView) -> NSDictionary? {
        guard let current = currentBrowser, page === current || page.isDescendant(of: current) else { return nil }
        let anchor: NSView? = selectedBrowserToolbar?.siteControlCenterAnchor
            ?? (activePeek != nil ? nil : isPopupWindow ? popupChrome.pageControlsAnchor
                : sidebar.isPresented ? sidebar.pageControlsAnchor : nil)
        guard let anchor, anchor.window === window, !anchor.isHiddenOrHasHiddenAncestor else { return nil }
        if anchor === sidebar.pageControlsAnchor { holdAddressButtonsForNextPopover() }
        return ["view": anchor, "rect": NSValue(rect: anchor.bounds),
                "edge": NSNumber(value: NSRectEdge.maxY.rawValue)]
    }
    func holdAddressButtonsForNextPopover() {
        holdAddressButtons(owner: NSObject()) { AddressPopoverRevealHold(onEnd: $0) }
    }
    private func holdAddressButtons(owner: AnyObject, _ hold: (@escaping () -> Void) -> AddressPopoverRevealHold) {
        let id = ObjectIdentifier(owner)
        addressPromptHolds[id] = hold { [weak self] in
            guard let self else { return }
            self.sidebar.setAddressPopover(owner, open: false)
            self.addressPromptHolds[id] = nil
        }
        sidebar.setAddressPopover(owner, open: true)
    }
    var extensionPopupsAnchorToSidebar: Bool { sidebar.isPresented && sidebarShowsAddressBar }
    func followExtensionPopupsForAddressHold() {
        guard extensionPopupKeyObserver == nil, !isClosing else { return }
        extensionPopupKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                                           object: nil, queue: nil) { [weak self] note in
            MainActor.assumeIsolated { self?.holdAddressButtons(forExtensionPopup: note.object as? NSWindow) }
        }
    }
    private func holdAddressButtons(forExtensionPopup popup: NSWindow?) {
        addressPromptHolds.values.forEach { $0.endIfWindowClosed() }
        guard let popup, let window, !isClosing, addressPromptHolds[ObjectIdentifier(popup)] == nil,
              SidebarAddressButtonsReveal.holdsExtensionPopup(popup, of: window, showsPage: popup.contentView is PCNativePageHost,
                                                              atSidebar: extensionPopupAtSidebar && extensionPopupsAnchorToSidebar)
        else { return }
        holdAddressButtons(owner: popup) { [weak window] onEnd in
            AddressPopoverRevealHold(window: popup, isOpen: { SidebarAddressButtonsReveal.extensionPopupOpen($0, of: window) },
                                     onEnd: onEnd)
        }
    }
    func endAddressButtonHolds() {
        extensionPopupKeyObserver.map(NotificationCenter.default.removeObserver)
        extensionPopupKeyObserver = nil
        addressPromptHolds.values.forEach { $0.end() }
    }
    @discardableResult func showSiteInfo(_ browser: PCBrowserView, from anchor: NSView) -> Bool {
        if anchor === sidebar.pageControlsAnchor { holdAddressButtonsForNextPopover() }
        return browser.showSiteInfo(from: anchor)
    }

    func extensionControlItems() -> [ExtensionControlItem] {
        guard !isClosing, let binding = nativeBinding,
              let page = currentBrowser?.nativePage, !page.isClosed else { return [] }
        return extensionControlItems(actions: binding.extensionActions(for: page), binding: binding, page: page)
    }

    func extensionControlItems(actions: [PCNativeExtensionAction],
                                       binding: PCNativeBrowserWindow,
                                       page: PCNativePage) -> [ExtensionControlItem] {
        actions.map { action in
            ExtensionControlItem(identifier: action.identifier, name: action.name,
                tooltip: action.tooltip, accessibilityLabel: action.accessibilityLabel,
                image: action.icon, pinnedIndex: action.pinnedIndex == NSNotFound ? nil : Int(action.pinnedIndex),
                canChangePin: action.canChangePin,
                execute: { [weak self, weak binding, weak page] in
                    guard let self, let binding, let page,
                          self.nativeBinding === binding, self.currentBrowser?.nativePage === page,
                          !self.isClosing, !page.isClosed else { return }
                    self.performExtensionActionAfterDismissingControls {
                        _ = binding.executeExtensionAction(action, for: page)
                    }
                }, showContextMenu: { [weak self, weak binding, weak page] control in
                    guard let self, let binding, let page,
                          self.nativeBinding === binding, self.currentBrowser?.nativePage === page,
                          !self.isClosing, !self.wholeWindowClose, !page.isClosed else { return }
                    self.showExtensionContextMenu(action, binding: binding, page: page, beside: control)
                }, setPinned: { [weak self, weak binding, weak page] pinned in
                    guard let self, let binding, let page,
                          self.nativeBinding === binding, self.currentBrowser?.nativePage === page,
                          !self.isClosing, !page.isClosed else { return }
                    _ = binding.setExtensionAction(action, pinned: pinned, for: page)
                    self.refreshExtensionControls()
                },
                pinnedArtwork: ExtensionPinnedArtwork(
                    unbadged: action.responds(to: #selector(getter: PCNativeExtensionAction.iconWithoutBadge))
                        ? action.iconWithoutBadge : nil,
                    badgeText: action.badgeText, textColor: action.badgeTextColor,
                    backgroundColor: action.badgeBackgroundColor),
                badgeText: action.badgeText)
        }
    }

    private func extensionControlsSignature(page: PCNativePage?,
                                            actions: [PCNativeExtensionAction],
                                            sidebarOwns: Bool,
                                            popupAvailable: Bool?) -> String {
        let pagePart = page.map { "p:\(ObjectIdentifier($0)):\($0.identifier)" } ?? "p:-"
        let avail = popupAvailable.map { $0 ? "1" : "0" } ?? "-"
        var parts: [String] = [
            pagePart,
            "s\(sidebarOwns ? 1 : 0)",
            "a\(avail)",
            "g\(actions.first?.generation ?? 0)",
        ]
        for action in actions {
            let pin = action.pinnedIndex == NSNotFound ? "-" : String(action.pinnedIndex)
            parts.append([
                action.identifier,
                action.name,
                action.tooltip,
                action.accessibilityLabel,
                pin,
                action.isEnabled ? "1" : "0",
                action.canChangePin ? "1" : "0",
            ].joined(separator: "\u{1f}"))
        }
        return parts.joined(separator: ";")
    }

    private func extensionControlsPopupAvailable(binding: PCNativeBrowserWindow?,
                                                 page: PCNativePage?) -> Bool? {
        guard isPopupWindow else { return nil }
        guard let binding, let page, !page.isClosed,
              binding.responds(to: #selector(PCNativeBrowserWindow.hasEnabledExtensions(for:))) else {
            return false
        }
        return binding.hasEnabledExtensions(for: page)
    }

    private func showExtensionContextMenu(_ action: PCNativeExtensionAction, binding: PCNativeBrowserWindow,
                                          page: PCNativePage, beside control: NSView) {
        extensionActionGeneration = UUID()
        guard binding.responds(to: #selector(PCNativeBrowserWindow.showExtensionActionContextMenu(_:for:presenter:))),
              let window = control.window, window.isVisible else {
            _ = binding.showExtensionActionContextMenu(action, for: page)
            return
        }
        let show = { [weak self] (menu: ParcContextMenu) in
            menu.willPerform = { item in self?.extensionMenuWillPerform(item) }
            _ = binding.showExtensionActionContextMenu(action, for: page, presenter: menu)
        }
        if siteControlCenter?.presentExtensionMenu(beside: control, for: action.identifier, show) == true { return }
        let rect = window.convertToScreen(control.convert(control.bounds, to: nil))
        let screen = SiteControlCenterPlacement.screen(at: CGPoint(x: rect.midX, y: rect.midY)) ?? window.screen?.visibleFrame
        let menu = ParcContextMenu(anchor: rect, regions: SiteControlCenterPlacement.regions(window: window.frame, screen: screen),
                                  parent: window, colors: ParcMenuColors(theme: rootView.theme))
        let inSidebar = control.isDescendant(of: sidebar)
        if inSidebar { sidebar.setAddressPopover(menu, open: true) }
        if let center = siteControlCenter { center.keepingOpen { show(menu) } } else { show(menu) }
        if inSidebar { sidebar.setAddressPopover(menu, open: false) }
    }

    private static let extensionSidePanelMenuItem = NSUserInterfaceItemIdentifier("extension-menu:side-panel")

    private func extensionMenuWillPerform(_ item: NSMenuItem) {
        guard item.identifier == Self.extensionSidePanelMenuItem, siteControlCenter != nil else { return }
        dismissSiteControlCenter()
    }

    private func performExtensionActionAfterDismissingControls(_ action: @escaping () -> Void) {
        guard !isClosing, !wholeWindowClose, let window, let binding = nativeBinding,
              let browser = currentBrowser, let page = browser.nativePage, !page.isClosed else { return }
        let generation = UUID()
        extensionActionGeneration = generation
        let revision = browser.readerRevision
        let spaceID = activeSpaceID
        dismissSiteControlCenter { [weak self, weak window, weak binding, weak browser, weak page] in
            guard let self, let window, let binding, let browser, let page,
                  self.extensionActionGeneration == generation, !self.isClosing, !self.wholeWindowClose,
                  self.window === window, window.isKeyWindow, binding.window === window,
                  self.nativeBinding === binding, self.currentBrowser === browser,
                  self.activeSpaceID == spaceID, browser.nativePage === page, !page.isClosed,
                  browser.readerRevision == revision else { return }
            self.extensionActionGeneration = UUID()
            action()
        }
    }

    func refreshExtensionControls() {
        if siteControlCenter != nil && (extensionControlsPage !== currentBrowser?.nativePage
            || currentBrowser?.readerRevision != siteControlCenterRevision
            || siteControlCenterOwner.map { $0.space != activeSpaceID || $0.profile != activeProfileID } ?? false) {
            dismissSiteControlCenter()
        }
        let page: PCNativePage? = {
            guard !isClosing, let page = currentBrowser?.nativePage, !page.isClosed else { return nil }
            return page
        }()
        let binding = nativeBinding
        let sidebarOwns = sidebarShowsAddressBar
        let popupAvailable = extensionControlsPopupAvailable(binding: binding, page: page)
        let actions: [PCNativeExtensionAction]
        if let binding, let page {
            actions = binding.extensionActions(for: page)
        } else {
            actions = []
        }
        let signature = extensionControlsSignature(page: page, actions: actions,
                                                   sidebarOwns: sidebarOwns,
                                                   popupAvailable: popupAvailable)
        if signature == lastExtensionControlsSignature {
            if let siteControlCenter, let sccPage = extensionControlsPage {
                updateSiteControlCenter(siteControlCenter, page: sccPage, items: nil)
            }
            return
        }
        lastExtensionControlsSignature = signature

        let items: [ExtensionControlItem]
        if let binding, let page {
            items = extensionControlItems(actions: actions, binding: binding, page: page)
        } else {
            items = []
        }
        if isPopupWindow {
            popupChrome.updateExtensions(available: popupAvailable ?? false)
        }
        sidebar.extensionToolbar.update(sidebarOwns ? items : [])
        selectedBrowserToolbar?.updateExtensionItems(items)
        if let siteControlCenter, let sccPage = extensionControlsPage {
            updateSiteControlCenter(siteControlCenter, page: sccPage, items: items)
        }
    }
}
