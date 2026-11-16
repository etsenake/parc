import AppKit
import Combine

extension BrowserWindowController: BrowserScriptOwner {
    var scriptingID: UUID { presentationID }
    var scriptingIsIncognito: Bool { isPrivateBrowsing }
    var scriptingWindow: NSWindow? { window }
    var scriptingAvailable: Bool {
        guard presentation.isReady, !isClosing, !preparedForRoutedPage,
              scriptingAuthorization?() == true, let nativeBinding else { return false }
        if isPrivateBrowsing {
            return !isPopupWindow && nativeBinding.isPrivateBrowsing && nativeBinding.browsingContextKind == .offTheRecord
        }
        let origin: ScriptWindowOrigin
        if let request = nativeWindowRequest {
            origin = request.isOffTheRecord ? .offTheRecord : request.kind == .browser ? .nativeBrowser : .auxiliary
        } else { origin = .application }
        let context: ScriptWindowContext
        switch nativeBinding.browsingContextKind {
        case .regular: context = .regular
        case .offTheRecord: context = .offTheRecord
        case .mixed: context = .mixed
        case .unavailable: context = .unavailable
        @unknown default: return false
        }
        return scriptWindowHasNormalOwner(origin: origin, context: context)
    }
    var scriptingActiveTabID: UUID? { currentTabID }
    var scriptingActiveSpaceID: UUID { activeSpaceID }
    var scriptingSpaces: [ScriptSpaceRecord] {
        guard scriptingAvailable else { return [] }
        return store.state.spaces.filter { !store.isProfileRemovalPending($0.profileID) }
            .map { ScriptSpaceRecord(id: $0.id, profileID: $0.profileID, title: $0.name) }
    }
    private func scriptingRecord(_ tab: BrowserTab) -> ScriptTabRecord {
        let browser: PCBrowserView? = {
            guard let browser = browsers[tab.id], browserProfiles[tab.id] == tab.profileID,
                  let page = browser.nativePage, !page.isClosed,
                  page.profilePath == store.independentEngineProfilePath(for: tab.profileID),
                  page.observer === browser, let binding = nativeBinding,
                  PCNativeBrowserApplication.owner(of: page) === binding else { return nil }
            return browser
        }()
        let location = tab.kind == .favorite ? "topApp" : tab.kind == .pinned ? "pinned" : "unpinned"
        return ScriptTabRecord(id: tab.id, profileID: tab.profileID,
            title: browser.map { $0.title.isEmpty ? tab.title : $0.title } ?? tab.title,
            url: browser?.url?.absoluteString ?? tab.url,
            loading: browser?.isLoading ?? false, location: location)
    }
    private func scriptingUsable(_ tab: BrowserTab) -> Bool { ownership.canUse(tab.id, owner: presentationID) }
    var scriptingTabs: [ScriptTabRecord] {
        guard scriptingAvailable else { return [] }
        return store.state.scriptListedTabs(where: scriptingUsable).map(scriptingRecord)
    }
    func scriptingTabRecord(_ id: UUID, profile: UUID?) -> ScriptTabRecord? {
        guard scriptingAvailable else { return nil }
        return store.state.scriptListedTab(id, profile: profile, where: scriptingUsable).map(scriptingRecord)
    }
    func scriptingTabs(in space: UUID, profile: UUID) -> [ScriptTabRecord] {
        guard scriptingSpaces.contains(where: { $0.id == space && $0.profileID == profile }) else { return [] }
        return store.state.scriptListedTabs(inSpace: space, profile: profile, where: scriptingUsable).map(scriptingRecord)
    }
    func scriptingTabRecord(_ id: UUID, inSpace space: UUID, profile: UUID) -> ScriptTabRecord? {
        guard scriptingSpaces.contains(where: { $0.id == space && $0.profileID == profile }) else { return nil }
        return store.state.scriptListedTab(id, inSpace: space, profile: profile, where: scriptingUsable).map(scriptingRecord)
    }
    private func scriptingCheck() throws {
        guard scriptingAvailable else { throw BrowserScriptError.missing }
        guard !wholeWindowClose, !windowClosePending, !windowCloseApproved,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty, transferRecoveries.isEmpty,
              window?.attachedSheet == nil, NSApp.modalWindow == nil else { throw BrowserScriptError.busy }
    }
    private func scriptingTab(_ id: UUID, profile: UUID) throws -> BrowserTab {
        try scriptingCheck()
        guard let tab = store.state.tab(id, where: { $0.profileID == profile && $0.archivedAt == nil }),
              !store.isProfileRemovalPending(profile), ownership.canUse(id, owner: presentationID) else { throw BrowserScriptError.missing }
        guard !closingTabIDs.contains(id), !transferringTabIDs.contains(id),
              !modelRetirementIDs.contains(id), !store.retiringTabIDs.contains(id),
              !peekRetirementParents.contains(id) else { throw BrowserScriptError.busy }
        return tab
    }
    private func scriptingBrowser(_ id: UUID, profile: UUID) throws -> PCBrowserView {
        _ = try scriptingTab(id, profile: profile)
        guard let browser = browsers[id], browserProfiles[id] == profile,
              let page = browser.nativePage, !page.isClosed,
              page.profilePath == store.independentEngineProfilePath(for: profile),
              page.observer === browser, let binding = nativeBinding,
              PCNativeBrowserApplication.owner(of: page) === binding else {
            throw BrowserScriptError.unsupported("This tab has no live browser page. Select it before issuing a page command.")
        }
        return browser
    }
    func scriptingPerform(_ action: ScriptTabAction, tab id: UUID, profile: UUID) throws {
        _ = try scriptingTab(id, profile: profile)
        if action == .select {
            guard activePeek == nil else { throw BrowserScriptError.busy }
            commandBar?.dismiss(); navigationHistory?.dismiss(); closeLibrary(restoreFocus: false)
            guard selectTab(id) else { throw BrowserScriptError.busy }
            focusSelectedLocalContent()
            return
        }
        let browser = try scriptingBrowser(id, profile: profile)
        switch action {
        case .back: if browser.canGoBack { browser.goBack() }
        case .forward: if browser.canGoForward { browser.goForward() }
        case .reload: browser.reload()
        case .stop: browser.stop()
        case .select: break
        }
    }
    func scriptingExecuteJavaScript(_ script: String, tab id: UUID, profile: UUID,
        completion: @escaping (Result<String?, Error>) -> Void) throws -> () -> Void {
        let browser = try scriptingBrowser(id, profile: profile)
        guard let page = browser.nativePage else { throw BrowserScriptError.missing }
        let execution = page.executeAppleEventJavaScript(script) { [weak self, weak browser, weak page] result in
            guard let self, let browser, let page,
                  (try? self.scriptingBrowser(id, profile: profile)) === browser,
                  browser.nativePage === page else {
                completion(.failure(BrowserScriptError.missing)); return
            }
            if result.errorNumber != 0 {
                completion(.failure(BrowserScriptError.execution(
                    result.errorMessage ?? "The JavaScript request could not finish.", result.errorNumber)))
            } else { completion(.success(result.json)) }
        }
        return { execution.cancel() }
    }

    func scriptingNavigate(_ url: URL, tab id: UUID, profile: UUID) throws {
        let url = try BrowserScriptError.url(url.absoluteString)
        let browser = try scriptingBrowser(id, profile: profile)
        inputRevisions.removeValue(forKey: id); pendingSearchNavigations.removeValue(forKey: id)
        browser.loadURL(url)
    }
    func scriptingMakeTab(_ url: URL, space: UUID?, profile: UUID?) throws -> ScriptTabRecord {
        try scriptingCheck()
        guard activePeek == nil else { throw BrowserScriptError.busy }
        let destination = space ?? activeSpaceID
        guard let target = scriptingSpaces.first(where: { $0.id == destination && (profile == nil || $0.profileID == profile) }) else {
            throw BrowserScriptError.missing
        }
        let url = try BrowserScriptError.url(url.absoluteString)
        commandBar?.dismiss(); navigationHistory?.dismiss(); closeLibrary(restoreFocus: false)
        if activeSpaceID != destination { selectSpace(destination) }
        guard activeSpaceID == target.id, activeProfileID == target.profileID else { throw BrowserScriptError.busy }
        let id = UUID()
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            store.openResolvedURL(url, id: id, creation: creation)
            presentation.recordCreation(id, state: store.state)
        }
        guard let result = scriptingTabRecord(id, profile: target.profileID) else { throw BrowserScriptError.busy }
        return result
    }
    func scriptingFocus(space: UUID, profile: UUID) throws {
        try scriptingCheck()
        guard activePeek == nil, nativeFullscreenTabID == nil else { throw BrowserScriptError.busy }
        guard scriptingSpaces.contains(where: { $0.id == space && $0.profileID == profile }) else { throw BrowserScriptError.missing }
        commandBar?.dismiss(); navigationHistory?.dismiss(); closeLibrary(restoreFocus: false)
        if activeSpaceID != space { selectSpace(space) }
        guard activeSpaceID == space else { throw BrowserScriptError.busy }
        requestNativeSelection(); focusSelectedLocalContent()
    }
    func scriptingClose(tab: UUID?, profile: UUID?, completion: @escaping (Bool) -> Void) throws {
        try scriptingCheck()
        if let tab, let profile {
            _ = try scriptingTab(tab, profile: profile)
            closeTabsWithReopen([tab], shouldCommit: { [weak self] in
                guard let self, !self.isClosing, !self.wholeWindowClose,
                      self.ownership.canUse(tab, owner: self.presentationID) else { return false }
                return self.store.state.containsTab(tab, where: { $0.profileID == profile && $0.archivedAt == nil })
            }, completion: completion)
        } else {
            guard let window, window.styleMask.contains(.closable), nativeBinding != nil else { throw BrowserScriptError.busy }
            scriptingWindowCloseCompletions.append(completion)
            window.performClose(nil)
        }
    }
    func finishScriptingWindowClose(_ approved: Bool) {
        let callbacks = scriptingWindowCloseCompletions
        scriptingWindowCloseCompletions.removeAll()
        callbacks.forEach { $0(approved) }
    }
}
