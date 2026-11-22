import AppKit
import Combine
import ParcCore
import ParcEngine
import ParcKit
import ParcNotes
import ParcLibrary
import ParcCommandBar
import ParcSettings
import ParcOnboarding

extension BrowserWindowController {
    func preparePopupCopyURL() -> (() -> Bool)? {
        guard isPopupWindow, commandBar == nil, canCopyCurrentURL,
              let window, let browser = currentBrowser, browser.window === window,
              let page = browser.nativePage, !page.isClosed, let url = browser.url else { return nil }
        let revision = browser.readerRevision
        var used = false
        return { [weak self, weak window, weak browser, weak page] in
            guard !used, let self, let window, let browser, let page,
                  self.window === window, browser.window === window,
                  self.currentBrowser === browser, self.selectedNativePage() === page,
                  browser.readerRevision == revision, browser.url == url, !page.isClosed, self.commandBar == nil,
                  self.canCopyCurrentURL else { return false }
            used = true
            self.copyPageLink(as: .plain)
            return true
        }
    }
    var canCopyCurrentURLAsMarkdown: Bool {
        commandBar == nil && currentURLForCopy != nil &&
            selectedNativePage()?.canCopyLink(as: .markdown) == true
    }
    var canCopyCurrentURLAsQuote: Bool {
        commandBar == nil && currentURLForCopy != nil &&
            selectedNativePage()?.canCopyLink(as: .quote) == true
    }
    func copyCurrentURL() {
        guard let url = currentURLForCopy else { return }
        if commandBar == nil, let page = selectedNativePage() {
            guard page.canCopyLink(as: .plain) else { return }
            copyPageLink(as: .plain)
        } else {
            copyLinkOperation = UUID()
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(url, forType: .string) { showToast(.copiedCurrentURL(URL(string: url))) }
        }
    }
    func copyCurrentURLAsMarkdown() {
        guard canCopyCurrentURLAsMarkdown else { return }
        copyPageLink(as: .markdown)
    }
    func copyCurrentURLAsQuote() {
        guard canCopyCurrentURLAsQuote else { return }
        copyPageLink(as: .quote)
    }
    var sharePageTarget: (browser: PCBrowserView, url: URL)? {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              libraryView == nil, window?.attachedSheet == nil,
              let browser = currentBrowser, browser.window === window, !browser.isHiddenOrHasHiddenAncestor,
              let page = browser.nativePage, !page.isClosed,
              let url = browser.url, !url.absoluteString.isEmpty else { return nil }
        return (browser, url)
    }
    var canSharePage: Bool { sharePageTarget != nil }
    func sharePage() {
        guard let (browser, url) = sharePageTarget else { return }
        let bounds = browser.bounds
        let top = browser.isFlipped ? bounds.minY : bounds.maxY - 1
        NSSharingServicePicker(items: [url]).show(
            relativeTo: NSRect(x: bounds.minX, y: top, width: bounds.width, height: 1),
            of: browser, preferredEdge: browser.isFlipped ? .maxY : .minY)
    }
    private func copyPageLink(as format: PCNativeLinkCopyFormat) {
        guard let page = selectedNativePage(), page.canCopyLink(as: format) else { return }
        performLinkCopy(page: page, format: format) { completion in
            page.copyLink(as: format, completion: completion)
        }
    }
    func copySharedQuote(_ selection: PCNativeSharedQuoteSelection, page: PCNativePage) {
        performLinkCopy(page: page, format: .quote) { completion in
            selection.copy(completion: completion)
        }
    }
    private func performLinkCopy(page: PCNativePage, format: PCNativeLinkCopyFormat,
                                 start: (@escaping @Sendable (PCNativeLinkCopyResult) -> Void) -> Void) {
        let operation = UUID(); copyLinkOperation = operation
        start { [weak self, weak page] result in
            MainActor.assumeIsolated {
                guard let self, let page, self.copyLinkOperation == operation,
                      self.selectedNativePage() === page, !page.isClosed,
                      !self.isClosing, !self.wholeWindowClose else { return }
                switch result {
                case .copied:
                    let url = self.copiedLink(page: self.currentBrowser?.url)
                    self.showToast(format == .quote ? .copiedQuoteLink(url) : .copiedCurrentURL(url))
                case .unavailable:
                    self.showToast(.standard(format == .quote ? "Couldn’t create a link to this selection" : "This page’s link is unavailable"))
                case .blocked: self.showToast(.standard("Copying this link is restricted"))
                case .cancelled: break
                @unknown default: break
                }
            }
        }
    }
    func copiedLink(page url: URL?) -> URL? {
        guard let scheme = url?.scheme?.lowercased(),
              let copied = NSPasteboard.general.string(forType: .string).flatMap({ URL(string: $0) }),
              copied.scheme?.lowercased() == scheme else { return url }
        return copied
    }
    func showImportFailures() { importNotices.showNext() }

    func showImportFailuresWhenIdle() { importNotices.showNextWhenIdle() }

    func makeImportNotices() -> ParcToastQueue {
        let queue = ParcToastQueue(presenter: toasts, next: { Self.nextImportNotice() }, present: { [weak self] item in
            self?.showToast(item.content, at: .window, onRetry: item.onRetry)
        })
        queue.canShow = { [weak self] in
            guard let self else { return false }
            return self.presentation.isReady && !self.isClosing && !self.isPrivateBrowsing && !self.isPopupWindow
        }
        queue.isFront = { [weak self] in NSApp.isActive && self?.window?.isKeyWindow == true }
        return queue
    }

    private static func nextImportNotice() -> ParcToastQueue.Item? {
        if let outcome = ImportedBrowserDataFailures.take() {
            return .init(content: outcome == .failed ? .importFailed : .importPartial,
                         restore: { ImportedBrowserDataFailures.restore(outcome) })
        }
        guard let notice = ImportedExtensionFailures.take() else { return nil }
        func failed(_ change: ImportedExtensionFailures.Failure.Change) -> [ParcToastContent.FailedExtension] {
            notice.failures.filter { $0.change == change }.map {
                .init(name: $0.name, profile: $0.profile, reason: $0.reason.map(Self.explained))
            }
        }
        return .init(content: .extensionsNotApplied(added: failed(.add), removed: failed(.removal), retry: notice.canRetry),
                     onRetry: notice.canRetry ? { notice.retry() } : nil, restore: { ImportedExtensionFailures.restore(notice) })
    }

    private static func explained(_ reason: ImportedExtensionFailures.Failure.Reason) -> ParcToastContent.FailedExtension.Reason {
        switch reason {
        case .administrator: return .administrator
        case .otherApp: return .otherApp
        case .parentalApproval: return .parentalApproval
        case .blocklisted: return .blocklisted
        }
    }

    @discardableResult
    func showToast(_ content: ParcToastContent, at location: ToastLocation = .content(nil),
                   onTap: (() -> Void)? = nil, onRetry: (() -> Void)? = nil,
                   onRetire: (() -> Void)? = nil) -> ParcToastPresentation? {
        guard let window, !isClosing, !wholeWindowClose else { return nil }
        let anchor: NSView?
        switch location {
        case .window: anchor = nil
        case .content(let id):
            anchor = id.flatMap { panes[$0] } ?? activePeek.flatMap { $0.view.isHidden ? nil : $0.view }
                ?? currentTabID.flatMap { panes[$0] }
        }
        let toast = toasts.show(content, in: window, over: anchor, theme: rootView.theme, onTap: onTap, onRetry: onRetry,
                                onRetire: onRetire)
        if toast != nil { retireShortcutHint() }
        return toast
    }

    private var essentialsCopyRoute: EssentialsCopyRoute {
        EssentialsCopyRoute(hasURL: currentURLForCopy != nil, commandBarOpen: commandBar != nil,
                            hasNativePage: selectedNativePage() != nil)
    }
    func showEssentialShortcuts() {
        guard presentation.isReady, !isClosing, !wholeWindowClose else { return }
        if shortcutEssentials == nil {
            let controller = ShortcutEssentialsWindow(shortcuts: .shared)
            controller.onViewAll = { [weak self] in
                guard let self, !self.isClosing, !self.wholeWindowClose else { return }
                self.showSettings(pane: .shortcuts)
            }
            let originalWindow = window
            controller.isOwnerAvailable = { [weak self, weak originalWindow] in
                guard let self, let originalWindow, self.window === originalWindow else { return false }
                return self.presentation.isReady && !self.isClosing && !self.wholeWindowClose
                    && !self.windowClosePending && self.windowCommandSecurityAvailable
            }
            controller.canPerformCommand = { [weak self, weak controller] id in
                guard let self else { return false }
                guard id == "copyCurrentURL:" else { return true }
                switch self.essentialsCopyRoute {
                case .unavailable: return false
                case .currentURL: return self.canCopyCurrentURL
                case .commandWindow:
                    guard let page = self.selectedNativePage(), let binding = self.nativeBinding,
                          let commandWindow = controller?.window else { return false }
                    return page.canCopyURL(fromCommandWindow: commandWindow, browser: binding)
                }
            }
            controller.onEscape = { [weak self, weak controller] in
                guard controller?.isOwnerAvailable?() == true else { return }
                self?.commandBar?.dismiss()
            }
            controller.onCommand = { [weak self, weak controller, weak originalWindow] id, event in
                guard let self, let originalWindow, controller?.isOwnerAvailable?() == true else { return }
                let previousEvent = self.shortcutInvocationEvent
                self.shortcutInvocationEvent = event
                defer { self.shortcutInvocationEvent = previousEvent }
                if id != "copyCurrentURL:" { originalWindow.makeKeyAndOrderFront(nil) }
                switch id {
                case "newTab:": self.newTab()
                case "cycleToNextRecentTab:": self.cycleRecentTab(forward: true)
                case "copyCurrentURL:":
                    switch self.essentialsCopyRoute {
                    case .unavailable: break
                    case .currentURL: self.copyCurrentURL()
                    case .commandWindow:
                        guard let page = self.selectedNativePage(), let binding = self.nativeBinding,
                              let commandWindow = controller?.window else { break }
                        self.performLinkCopy(page: page, format: .plain) { completion in
                            page.copyURL(fromCommandWindow: commandWindow, browser: binding, completion: completion)
                        }
                    }
                case "split:": self.toggleSplit()
                default: break
                }
            }
            shortcutEssentials = controller
        }
        shortcutEssentials?.show(relativeTo: window)
    }
    func prepareSettingsForTermination() -> Bool {
        settings?.prepareForTermination() ?? true
    }
    func closePreparedSettingsForTermination() -> Bool {
        let wasVisible = settings?.window?.isVisible == true
        guard settings?.attemptClose() ?? true else { return false }
        restoreSettingsAfterCancelledTermination = wasVisible
        return true
    }
    func showSettings(pane: SettingsWindow.Pane? = nil, shortcutID: String? = nil, contextSpaceID: UUID? = nil) {
        guard !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved else { return }
        if isPrivateBrowsing { onRequestApplicationSettings?(pane, shortcutID); return }
        let spaceID = contextSpaceID ?? activeSpaceID
        if settings?.contextSpaceID != spaceID {
            guard settings?.window?.attachedSheet == nil else { return }
            if let settings, !settings.attemptClose() { return }
            settings = nil
        }
        if settings == nil {
            settings = SettingsWindow(store: store, spaceID: spaceID, actions: AppDelegate.settingsActions)
            settings?.onSheetEnded = { [weak self] in self?.retryPendingSettingsClose() }
            settings?.onProfileSettingsPage = { [weak self] spaceID, profileID, page in
                guard let self, let settings = self.settings else { return false }
                return self.showProfileSettingsPage(page, spaceID: spaceID, profileID: profileID, from: settings)
            }
            settings?.onMoreSettings = { [weak self] spaceID, profileID in
                guard let self, let settings = self.settings else { return false }
                return self.showAdvancedSettings(spaceID: spaceID, profileID: profileID, from: settings)
            }
            settings?.onDeleteSpace = { [weak self] spaceID in
                guard let self, let sheetWindow = self.settings?.window else { return false }
                return self.deleteSpace(spaceID, confirmingIn: sheetWindow)
            }
        }
        if shortcutID != nil, settings?.window?.attachedSheet != nil { return }
        settings?.refresh()
        if let shortcutID { guard settings?.showShortcut(shortcutID) == true else { return } }
        else if let pane { settings?.showPane(pane) }
        settings?.showWindow(nil); settings?.window?.makeKeyAndOrderFront(nil)
    }

    func showPasswordManager() {
        guard let space = store.state.spaces.first(where: { $0.id == activeSpaceID }) else { return }
        showPasswordManager(spaceID: space.id, profileID: space.profileID)
    }

    func showAdvancedSettings(spaceID: UUID, profileID: UUID, from settings: SettingsWindow) -> Bool {
        guard !isPrivateBrowsing, settings.permitsPage(in: store, spaceID: spaceID, profileID: profileID),
              let window, window.attachedSheet == nil, !window.isMiniaturized,
              presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, transferringTabIDs.isEmpty,
              resolvingTransfers.isEmpty, transferRecoveries.isEmpty,
              !store.isProfileRemovalPending(profileID),
              store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return false }
        window.makeKeyAndOrderFront(nil)
        guard spaceCommandsAvailable else { return false }
        closeLibrary(restoreFocus: false)
        selectSpace(spaceID)
        guard activeSpaceID == spaceID, activeProfileID == profileID else { return false }
        let existing = store.state.tabs.first { tab in
            guard tab.spaceID == spaceID, tab.profileID == profileID, tab.archivedAt == nil,
                  ownership.canUse(tab.id, owner: presentationID),
                  let url = URL(string: tab.url) else { return false }
            return BrowserInternalURL.isWebUI(url) && url.host == "settings"
        }
        if let existing {
            guard selectTab(existing.id) else { return false }
        } else {
            var createdID: UUID?
            let creation = creationProvenance(activeTabID: currentTabID)
            performWindowCommand {
                let id = store.open("parc://settings/", creation: creation)
                presentation.recordCreation(id, state: store.state)
                store.updateTab(id, title: "Settings")
                createdID = id
            }
            guard let createdID, selectedTabIDs.contains(createdID),
                  store.state.containsTab(createdID, where: { $0.spaceID == spaceID && $0.profileID == profileID }) else { return false }
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func showProfileSettingsPage(_ page: ProfileSettingsPage, spaceID: UUID, profileID: UUID,
                                 from settings: SettingsWindow) -> Bool {
        guard !isPrivateBrowsing, settings.permitsProfilePage(in: store, spaceID: spaceID, profileID: profileID),
              let window, window.attachedSheet == nil, !window.isMiniaturized,
              presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, transferringTabIDs.isEmpty,
              resolvingTransfers.isEmpty, transferRecoveries.isEmpty,
              !store.isProfileRemovalPending(profileID),
              store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return false }
        window.makeKeyAndOrderFront(nil)
        guard spaceCommandsAvailable else { return false }
        closeLibrary(restoreFocus: false)
        selectSpace(spaceID)
        guard activeSpaceID == spaceID, activeProfileID == profileID else { return false }
        if let existing = store.state.tabs.first(where: {
            $0.spaceID == spaceID && $0.profileID == profileID && $0.archivedAt == nil
                && ownership.canUse($0.id, owner: presentationID) && page.canReuse($0.url)
        }) {
            guard selectTab(existing.id) else { return false }
        } else {
            var createdID: UUID?
            let creation = creationProvenance(activeTabID: currentTabID)
            performWindowCommand {
                let id = store.open(page.address, creation: creation)
                presentation.recordCreation(id, state: store.state)
                store.updateTab(id, title: page.title)
                createdID = id
            }
            guard let createdID, selectedTabIDs.contains(createdID),
                  store.state.containsTab(createdID, where: { $0.spaceID == spaceID && $0.profileID == profileID }) else { return false }
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    @discardableResult
    func showPasswordManager(spaceID: UUID, profileID: UUID) -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty,
              store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return false }
        let destination = "parc://password-manager/passwords"
        selectSpace(spaceID)
        guard activeSpaceID == spaceID, activeProfileID == profileID else { return false }
        let existing = store.state.tabs.first { tab in
            guard tab.spaceID == spaceID, tab.profileID == profileID, tab.archivedAt == nil,
                  ownership.canUse(tab.id, owner: presentationID),
                  let url = URL(string: tab.url) else { return false }
            return BrowserInternalURL.isWebUI(url) && url.host == "password-manager"
        }
        if let existing {
            guard selectTab(existing.id) else { return false }
            window?.makeKeyAndOrderFront(nil)
            return true
        }
        var createdID: UUID?
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            let id = store.open(destination, creation: creation)
            presentation.recordCreation(id, state: store.state)
            createdID = id
            store.updateTab(id, title: "Password Manager")
        }
        window?.makeKeyAndOrderFront(nil)
        guard let createdID else { return false }
        return selectedTabIDs.contains(createdID) && store.state.containsTab(createdID, where: { $0.spaceID == spaceID && $0.profileID == profileID })
    }
    var canChangePageZoom: Bool {
        PageZoomAvailability.canChange(
            windowReady: presentation.isReady,
            closing: isClosing || wholeWindowClose,
            hasOriginalPage: currentBrowser != nil && (activePeek?.identity ?? currentTabID) != nil
        )
    }
    func zoomIn() { changeZoom(1) }
    func zoomOut() { changeZoom(-1) }
    func actualSize() { changeZoom(0) }
    private func changeZoom(_ direction: Int) {
        guard canChangePageZoom, let id = activePeek?.identity ?? currentTabID, let browser = currentBrowser else { return }
        if browser.zoomPage(direction) {
            if browser.nativePage != nil { showZoomToast(browser.pageZoomLevel) }
            return
        }
        let level = direction == 0 ? 0 : min(5, max(-5, (zoomLevels[id] ?? 0) + 0.5 * Double(direction)))
        zoomLevels[id] = level; browser.setZoomLevel(level); showZoomToast(level)
    }
    private func showZoomToast(_ level: Double) {
        showToast(.zoom(percent: Int((pow(1.2, level) * 100).rounded())))
    }
    func setupFindBar() {
        findHost.isHidden = true; findField.delegate = self
        findHost.onPrevious = { [weak self] in self?.performFind(forward: false, next: true) }
        findHost.onNext = { [weak self] in self?.performFind(forward: true, next: true) }
        findHost.onClose = { [weak self] in self?.dismissFind() }
        menuObservers.append(NotificationCenter.default.addObserver(
            forName: PCNativePage.findResultDidChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let page = notification.object as? PCNativePage,
                      self.visibleFind?.owner === page else { return }
                self.reconcileFind()
            }
        })
    }
    func layoutFindBar() {
        guard !findHost.isHidden, let state = visibleFind, isCurrentFind(state),
              libraryView == nil, nativeFullscreenTabID == nil,
              let page = state.owner else { return }
        findHost.place(over: page.nativeView, in: rootView, window: window)
    }
    private var canOwnFind: Bool {
        ownsSpaceCommandFocus && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && currentTabID.map { !closingTabIDs.contains($0) && !modelRetirementIDs.contains($0) } != false
            && window?.attachedSheet == nil && pageCapture == nil && tabSwitcher == nil
            && spaceCreation == nil && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
    }
    private func findState(for page: PCNativePage) -> BrowserFindState<PCNativePage> {
        if let state = findStates[page.identifier], state.matches(page, revision: page.readerRevision) { return state }
        let state = BrowserFindState(owner: page, revision: page.readerRevision)
        findStates[page.identifier] = state; return state
    }
    func isCurrentFind(_ state: BrowserFindState<PCNativePage>) -> Bool {
        guard let page = state.owner, !page.isClosed else { return false }
        return state.matches(selectedNativePage(), revision: page.readerRevision)
    }
    func reconcileFind() {
        if FindReconcileSkip.shouldSkip(isPresented: visibleFind != nil) { return }
        findStates = findStates.filter { _, state in
            guard let page = state.owner else { return false }
            return !page.isClosed && page.readerRevision == state.revision
        }
        if let visibleFind, !isCurrentFind(visibleFind) || libraryView != nil { dismissFind(restoreFocus: false) }
        guard let state = visibleFind, let page = state.owner else { return }
        let result = page.findResult
        let presentation = PageFindResultPresentation.resolve(query: state.query, revision: state.revision,
            resultQuery: result?.query, resultRevision: result?.documentRevision,
            matches: result?.numberOfMatches, ordinal: result?.activeMatchOrdinal)
        findHost.update(result: presentation, available: canOwnFind && isCurrentFind(state))
        layoutFindBar()
    }
    private func noteFindCommand(_ action: BrowserFindAction, id: UUID, editor: NotePageViewController, window: NSWindow,
                                 prepare: @escaping () -> Void) -> BrowserFindCommand {
        let profileID = activeProfileID
        return BrowserFindCommand(action: action, window: window, available: { [weak self, weak editor] in
            guard let self, let editor, editor.isViewLoaded, self.canOwnFind,
                  let note = self.noteEditors[id], note.editor === editor,
                  (self.activePeek == nil && self.renderedPaneIDs.contains(id)) || self.peekedDocumentTabID == id,
                  note.profileID == profileID, self.activeProfileID == profileID,
                  self.switcherCanUse(id),
                  let tab = self.store.state.tab(id, where: { $0.profileID == profileID }),
                  InternalPage(urlString: tab.url) == .note(editor.file.url),
                  editor.canPerform(action) else { return false }
            if let current = window.firstResponder as? NSView, current.isDescendant(of: editor.view) { return true }
            return self.currentTabID == id || self.peekedDocumentTabID == id
        }, prepare: prepare, execute: { [weak self, weak editor] in
            guard let editor, editor.isViewLoaded else { return }
            if action == .show || action == .replace { self?.dismissFind(restoreFocus: false) }
            _ = editor.perform(action)
        })
    }
    private func focusedNoteEmbedPage(in window: NSWindow) -> PCNativePage? {
        guard libraryView == nil, let id = documentInputTabID,
              let note = noteEditors[id], note.profileID == activeProfileID,
              let page = NoteEmbeddedPages.pool(for: note.editor)?.selectedPage, selectedNativePage() === page,
              let responder = window.firstResponder as? NSView else { return nil }
        if responder === page.nativeView || responder.isDescendant(of: page.nativeView) { return page }
        guard let state = visibleFind, state.owner === page, isCurrentFind(state), !findHost.isHidden,
              responder.isDescendant(of: findHost) else { return nil }
        return page
    }
    func prepareFindMenuItem(_ item: NSMenuItem, action: BrowserFindAction, preservingTarget: Bool = false) -> Bool {
        if preservingTarget, let command = item.representedObject as? BrowserFindCommand {
            return command.action == action && command.isAvailable
        }
        item.representedObject = nil
        guard canOwnFind, let window else { return false }
        let prepare: () -> Void = { [weak self] in self?.commandBar?.dismiss() }
        let command: BrowserFindCommand
        let noteEmbedHasFocus = focusedNoteEmbedPage(in: window) != nil
        if !noteEmbedHasFocus, let responder = window.firstResponder as? NSView,
           let entry = noteEditors.first(where: { $0.value.editor.isViewLoaded
               && responder.isDescendant(of: $0.value.editor.view) }),
           (activePeek == nil && renderedPaneIDs.contains(entry.key)) || peekedDocumentTabID == entry.key,
           entry.value.profileID == activeProfileID {
            command = noteFindCommand(action, id: entry.key, editor: entry.value.editor, window: window, prepare: prepare)
        } else if action == .show, let libraryView {
            command = BrowserFindCommand(action: action, window: window, available: { [weak self, weak libraryView] in
                self?.canOwnFind == true && libraryView != nil && self?.libraryView === libraryView
            }, prepare: prepare, execute: { [weak self, weak libraryView] in
                self?.dismissFind(restoreFocus: false); libraryView?.focusSearch()
            })
        } else if !noteEmbedHasFocus, libraryView == nil, let id = documentInputTabID,
                  let note = noteEditors[id], note.profileID == activeProfileID, note.editor.isViewLoaded {
            command = noteFindCommand(action, id: id, editor: note.editor, window: window, prepare: prepare)
        } else if action.isNativeTextOnly {
            return false
        } else {
            guard libraryView == nil, let page = selectedNativePage(), page.canFindInPage else { return false }
            let state = findState(for: page)
            command = BrowserFindCommand(action: action, window: window, available: { [weak self, weak page] in
                guard let self, let page, self.canOwnFind, self.libraryView == nil,
                      self.isCurrentFind(state), page.canFindInPage else { return false }
                switch action {
                case .show: return true
                case .next, .previous: return !state.query.isEmpty
                case .useSelection: return !page.selectionForFind.isEmpty
                case .jumpToSelection, .replace: return false
                }
            }, prepare: prepare, execute: { [weak self, weak page] in
                guard let self, let page, self.isCurrentFind(state) else { return }
                switch action {
                case .show:
                    self.visibleFind = state
                    if self.findField.stringValue != state.query { self.findField.stringValue = state.query }
                    self.rootView.addSubview(self.findHost, positioned: .above, relativeTo: nil)
                    self.findHost.isHidden = false; self.layoutChrome(); self.reconcileFind()
                    self.window?.makeFirstResponder(self.findField); self.findField.selectText(nil)
                case .next, .previous:
                    page.findText(state.query, forward: action == .next, findNext: true)
                case .useSelection:
                    let selection = page.selectionForFind
                    guard !selection.isEmpty else { return }
                    state.query = selection
                    if self.visibleFind === state { self.findField.stringValue = selection }
                    page.findText(selection, forward: true, findNext: false); self.reconcileFind()
                case .jumpToSelection, .replace: return
                }
            })
        }
        item.representedObject = command; return command.isAvailable
    }
    func findInPage() {
        let item = NSMenuItem(title: "Find…", action: nil, keyEquivalent: "")
        guard prepareFindMenuItem(item, action: .show) else { return }
        _ = (item.representedObject as? BrowserFindCommand)?.perform()
    }
    func dismissFind(restoreFocus: Bool = true) {
        let state = visibleFind; visibleFind = nil
        let mayRestore = state.map(isCurrentFind) ?? false
        findHost.isHidden = true; state?.owner?.stopFinding(); layoutChrome()
        if restoreFocus, mayRestore, window?.isKeyWindow == true, commandBar == nil {
            if let page = state?.owner { _ = nativeBinding?.requestFocus(for: page) }
        }
    }
    func performFind(forward: Bool, next: Bool) {
        guard let state = visibleFind, isCurrentFind(state), let page = state.owner,
              page.canFindInPage, window?.isKeyWindow == true,
              (findField.currentEditor() as? NSTextInputClient)?.hasMarkedText() != true else { return }
        state.query = findField.stringValue
        if state.query.isEmpty { page.stopFinding() }
        else { page.findText(state.query, forward: forward, findNext: next) }
        reconcileFind()
    }
}
