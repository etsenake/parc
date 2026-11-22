import AppKit
import ParcCore
import ParcEngine
import ParcKit
import ParcNotes
import ParcEasels
import ParcCommandBar
import ParcSidebar

@MainActor
final class TabPeekSlot {
    var current: TabPeekPresentation?
    var queued: (tabID: UUID, replacing: UUID, parentTabID: UUID)?
    var leaving: [TabPeekPresentation] = []
}

@MainActor
enum TabPeekDocument {
    case note(NotePageViewController)
    case easel(EaselEditorViewController)

    var view: NSView {
        switch self {
        case .note(let editor): return editor.view
        case .easel(let editor): return editor.view
        }
    }

    func focus() {
        switch self {
        case .note(let editor): editor.focusContent()
        case .easel(let editor): editor.focusContent()
        }
    }

    func adopt(_ palette: ThemeChromePalette) {
        switch self {
        case .note(let editor):
            if editor.isViewLoaded, editor.view.appearance != palette.contentAppearance {
                editor.inheritSpaceContentAppearance(palette.contentAppearance)
            }
            editor.spaceFocus = palette.focus
        case .easel(let editor):
            (editor.view as? EaselDocumentView)?.inheritSpaceContentAppearance(palette.contentAppearance)
        }
    }

    func handleUnhandledEscape(_ handler: (() -> Bool)?) {
        guard case .note(let editor) = self, editor.isViewLoaded else { return }
        editor.editor.onUnhandledEscape = handler
    }

    func isSame(as other: TabPeekDocument?) -> Bool {
        switch (self, other) {
        case (.note(let a), .note(let b)?): return a === b
        case (.easel(let a), .easel(let b)?): return a === b
        default: return false
        }
    }
}

@MainActor
enum TabPeekContent {
    case page(PCBrowserView)
    case document(TabPeekDocument)
}

@MainActor
final class TabPeekPresentation {
    var session: TabPeekSession
    let content: TabPeekContent
    let parentTabID: UUID
    weak var parentPage: PCNativePage?
    let relay = TabPeekRelay()
    var controller: PeekCard?
    var entryFocus: PeekFocusReturn?
    var loadTimeout: DispatchWorkItem?
    var exitTimer: Timer?

    init(session: TabPeekSession, content: TabPeekContent, parentTabID: UUID, parentPage: PCNativePage) {
        self.session = session; self.content = content
        self.parentTabID = parentTabID; self.parentPage = parentPage
    }

    var tabID: UUID { session.tabID }
    var browser: PCBrowserView? { if case .page(let browser) = content { return browser }; return nil }
    var document: TabPeekDocument? { if case .document(let document) = content { return document }; return nil }
    var shownController: PeekCard? { session.holdsPage ? controller : nil }
    var pageController: PeekController? { controller as? PeekController }
    var documentController: DocumentPeekController? { controller as? DocumentPeekController }
}

@MainActor
final class TabPeekRelay: NSObject, PCBrowserViewDelegate {
    weak var tab: BrowserWindowController?
    weak var peek: PeekController?
    var onPage: (() -> Void)?
    var onFailure: (() -> Void)?

    private func notePage(_ view: PCBrowserView) {
        guard let page = view.nativePage, !page.isClosed, let onPage else { return }
        self.onPage = nil
        DispatchQueue.main.async { onPage() }
    }

    func browserViewDidChangeFavicon(_ view: PCBrowserView) {
        tab?.browserViewDidChangeFavicon(view); peek?.browserViewDidChangeFavicon(view)
    }
    func browserViewDidPresentFrame(_ view: PCBrowserView) { tab?.browserViewDidPresentFrame(view) }
    func browserView(_ view: PCBrowserView, addContextImageToEasel image: PCNativeContextImage) {
        if let peek { peek.browserView(view, addContextImageToEasel: image) } else { tab?.browserView(view, addContextImageToEasel: image) }
    }
    func browserView(_ view: PCBrowserView, openLinkInSplitView url: URL) { tab?.browserView(view, openLinkInSplitView: url) }
    func browserViewCanOpenLinkInSplitView(_ view: PCBrowserView) -> Bool { tab?.browserViewCanOpenLinkInSplitView(view) ?? false }
    func browserView(_ view: PCBrowserView, didChangeCaptureState state: PCNativeCaptureState?) {
        tab?.browserView(view, didChangeCaptureState: state); peek?.browserView(view, didChangeCaptureState: state); notePage(view)
    }
    func browserView(_ view: PCBrowserView, didChangeTitle title: String) {
        tab?.browserView(view, didChangeTitle: title); peek?.browserView(view, didChangeTitle: title); notePage(view)
    }
    func browserView(_ view: PCBrowserView, didChangeURL url: URL) {
        tab?.browserView(view, didChangeURL: url); peek?.browserView(view, didChangeURL: url); notePage(view)
    }
    func browserView(_ view: PCBrowserView, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        tab?.browserView(view, didChangeLoading: loading, canGoBack: canGoBack, canGoForward: canGoForward)
        peek?.browserView(view, didChangeLoading: loading, canGoBack: canGoBack, canGoForward: canGoForward)
        notePage(view)
    }
    func browserView(_ view: PCBrowserView, didChangeRendererCrash crash: PCNativeRendererCrash?) {
        tab?.browserView(view, didChangeRendererCrash: crash); peek?.browserView(view, didChangeRendererCrash: crash)
    }
    func browserViewDidChangePageColor(_ view: PCBrowserView) {
        tab?.browserViewDidChangePageColor(view); peek?.browserViewDidChangePageColor(view)
    }
    func browserViewDidChangeMedia(_ view: PCBrowserView) {
        tab?.browserViewDidChangeMedia(view); peek?.browserViewDidChangeMedia(view)
    }
    func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) {
        if let peek { peek.browserView(view, requestFocusForRendererCrash: crash) }
        else { tab?.browserView(view, requestFocusForRendererCrash: crash) }
    }
    func browserViewDidRequestClose(_ view: PCBrowserView) {
        tab?.browserViewDidRequestClose(view); peek?.browserViewDidRequestClose(view)
    }
    func browserView(_ view: PCBrowserView, didFailWithError error: Error) {
        tab?.browserView(view, didFailWithError: error); peek?.browserView(view, didFailWithError: error)
        if view.nativePage == nil, let onFailure { self.onFailure = nil; onPage = nil; onFailure() }
    }
    func browserView(_ view: PCBrowserView, didLearnSafariIdentityForSite site: String,
                     profilePath: String, offTheRecord: Bool) {
        tab?.browserView(view, didLearnSafariIdentityForSite: site, profilePath: profilePath, offTheRecord: offTheRecord)
    }
}

extension BrowserWindowController {
    var tabPeek: TabPeekPresentation? { tabPeeks.current }

    func presentedPeek(for page: PCNativePage) -> PeekController? {
        if let peek = peeks[page.identifier] { return peek }
        guard let controller = tabPeeks.current?.shownController as? PeekController, controller.page === page else { return nil }
        return controller
    }

    var presentedPeeks: [PeekController] {
        Array(peeks.values) + [tabPeeks.current?.shownController as? PeekController].compactMap { $0 }
    }

    func tabPeekHolds(_ page: PCNativePage) -> Bool {
        guard let current = tabPeeks.current, let browser = current.browser else { return false }
        return browser.nativePage === page && current.session.phase != .finished
    }

    var peekedDocumentTabID: UUID? {
        guard let current = tabPeeks.current, current.document != nil, current.session.phase == .shown,
              let controller = current.documentController, activePeek === controller, !controller.isLeaving else { return nil }
        return current.tabID
    }

    func documentTakesInput(_ id: UUID) -> Bool {
        (currentTabID == id && activePeek == nil) || peekedDocumentTabID == id
    }

    var documentInputTabID: UUID? {
        if let id = peekedDocumentTabID { return id }
        guard activePeek == nil, let id = currentTabID, renderedPaneIDs.contains(id) else { return nil }
        return id
    }

    private func peekDocument(_ id: UUID) -> TabPeekDocument? {
        guard let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              let address = InternalPage(urlString: tab.url) else { return nil }
        if address.noteURL != nil, let note = noteEditors[id], note.profileID == tab.profileID, note.editor.isViewLoaded,
           address == .note(note.url) || address == InternalPage(urlString: note.originalTab.url) {
            return .note(note.editor)
        }
        if let easelID = address.easelID, let easel = easelEditors[id], easel.documentID == easelID,
           easel.profileID == tab.profileID, easel.editor.isViewLoaded {
            return .easel(easel.editor)
        }
        return nil
    }

    private func peekDocumentFailed(_ id: UUID) -> Bool {
        noteFailures[id] != nil || easelFailures[id] != nil
    }

    private func documentKey(_ id: UUID) -> String { "document:" + id.uuidString }

    func tabPeekCandidate(_ id: UUID) -> TabPeekCandidate? {
        guard let binding = nativeBinding, let tab = store.state.tab(id, where: { $0.archivedAt == nil }) else { return nil }
        var candidate = TabPeekCandidate(tabID: id)
        let profilePath = store.independentEngineProfilePath(for: activeProfileID)
        let parentID = currentTabID
        let parent = parentID.flatMap { browsers[$0]?.nativePage }
        candidate.windowAdmits = windowAdmitsPeek(binding) && presentation.isReady && !windowClosePending
        if let parentID, let parent {
            candidate.parentCanHost = parentID != id && !parent.isClosed
                && PCNativeBrowserApplication.owner(of: parent) === binding
                && parent.profilePath == profilePath && browsers[parentID]?.window === window
                && store.state.tab(parentID, where: { $0.archivedAt == nil })?.profileID == activeProfileID
                && switcherCanUse(parentID)
        } else {
            candidate.parentCanHost = false
        }
        candidate.inActiveSpace = (tab.spaceID == activeSpaceID || tab.kind == .favorite) && visibleTabs.contains { $0.id == id }
        candidate.profileMatches = tab.profileID == activeProfileID
            && store.independentEngineProfilePath(for: tab.profileID) == profilePath
        candidate.onScreen = selectedTabIDs.contains(id) || renderedPaneIDs.contains(id)
            || presentation.displayedTabIDs.contains(id) || pendingNativeSelection?.tabID == id
        candidate.busy = closingTabIDs.contains(id) || modelRetirementIDs.contains(id) || transferringTabIDs.contains(id)
            || resolvingTransfers.contains(id) || store.retiringTabIDs.contains(id) || transferRecoveries[id] != nil
            || pendingSearchNavigations[id] != nil || nativeFullscreenTabID == id
        if let address = InternalPage(urlString: tab.url) {
            let document = address.noteURL != nil || address.easelID != nil
            candidate.content = document && !isPrivateBrowsing && !isPopupWindow
                && !store.isProfileRemovalPending(tab.profileID) ? .document : .unsupported
        } else {
            candidate.content = InternalPage.isInternal(tab.url) || noteEditors[id] != nil || easelEditors[id] != nil
                ? .unsupported : .web
        }
        if ownership.canUse(id, owner: presentationID) {
            candidate.holder = ownership.isClaimed(id) ? .here : .nobody
        } else {
            candidate.holder = .elsewhere(movable: canMovePageHere(id))
        }
        if candidate.content == .document {
            if peekDocument(id) != nil { candidate.page = .live(documentKey(id)) }
            else { candidate.page = peekDocumentFailed(id) ? .failed : .unloaded(loadable: true) }
        } else if let browser = browsers[id] {
            if let page = browser.nativePage {
                candidate.page = page.isClosed ? .closed : failures[id] != nil ? .failed : .live(page.identifier)
            } else {
                candidate.page = failures[id] != nil ? .failed : .creating
            }
        } else {
            candidate.page = .unloaded(loadable: URL(string: tab.url) != nil && !rendersBlank(tab))
        }
        if let current = tabPeeks.current, current.session.phase != .finished {
            candidate.shown = .tab(current.tabID, canClose: current.session.phase == .loading
                || current.shownController?.canRequestExit == true)
        } else if let peek = activePeek {
            candidate.shown = .peek(canClose: peek.canRequestExit)
        }
        return candidate
    }

    func offersTabInPeek(_ id: UUID) -> Bool {
        tabPeekCandidate(id).map(TabPeekAdmission.offers) ?? false
    }

    @discardableResult
    func openTabInPeek(_ id: UUID, afterMove: Bool = false) -> Bool {
        guard let candidate = tabPeekCandidate(id), case .success(let plan) = TabPeekAdmission.plan(candidate) else { return false }
        switch plan {
        case .alreadyShown:
            tabPeeks.current?.shownController?.focus()
            return true
        case .moveHere:
            guard !afterMove else { return false }
            return movePagesHere([id][...]) { [weak self] in self?.openTabInPeek(id, afterMove: true) ?? false }
        case .replaceShown:
            if let current = tabPeeks.current, current.session.phase == .loading {
                abandonTabPeek(current)
                return openTabInPeek(id, afterMove: afterMove)
            }
            guard let shown = activePeek, let parent = currentTabID else { return false }
            let identity = shown.identity
            if tabPeeks.queued?.replacing != identity {
                let refused = shown.onCloseRefused, update = shown.onUpdate
                shown.onCloseRefused = { [weak self] in
                    refused?()
                    if self?.tabPeeks.queued?.replacing == identity { self?.tabPeeks.queued = nil }
                }
                shown.onUpdate = { [weak self, weak shown] in
                    update?()
                    if shown?.modalPhase == .presented, self?.tabPeeks.queued?.replacing == identity { self?.tabPeeks.queued = nil }
                }
            }
            tabPeeks.queued = (id, identity, parent)
            if shown.modalPhase == .presented { shown.requestDismiss(.closeButton) }
            guard activePeek !== shown || shown.modalPhase != .presented else { tabPeeks.queued = nil; return false }
            return true
        case .present, .load:
            if candidate.content == .document { return beginDocumentPeek(id) }
            return beginTabPeek(id, plan: plan)
        }
    }

    private func beginTabPeek(_ id: UUID, plan: TabPeekPlan) -> Bool {
        guard let session = TabPeekSession(tabID: id, plan: plan), let parentID = currentTabID,
              let parentPage = browsers[parentID]?.nativePage,
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }) else { return false }
        let browser: PCBrowserView
        switch plan {
        case .present:
            guard let existing = browsers[id] else { return false }
            browser = existing
        default:
            guard browsers[id] == nil, URL(string: tab.url) != nil, ownership.claim(id, owner: presentationID) else { return false }
            browser = PCBrowserView(frame: pageHost.bounds, profilePath: store.independentEngineProfilePath(for: tab.profileID))
        }
        let held = TabPeekPresentation(session: session, content: .page(browser), parentTabID: parentID, parentPage: parentPage)
        held.relay.tab = self
        held.entryFocus = PeekFocusReturn(source: pageHost)
        tabPeeks.current = held
        sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        applyTabPeek(session.opening, held)
        return tabPeeks.current === held
    }

    private func beginDocumentPeek(_ id: UUID) -> Bool {
        guard let parentID = currentTabID, let parentPage = browsers[parentID]?.nativePage,
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }) else { return false }
        if peekDocument(id) == nil {
            guard ownership.claim(id, owner: presentationID) else { return false }
            showInternalPage(tab, in: tabPeekPane(tab))
        }
        guard let document = peekDocument(id),
              let session = TabPeekSession(tabID: id, plan: .present(documentKey(id))) else { return false }
        let held = TabPeekPresentation(session: session, content: .document(document), parentTabID: parentID, parentPage: parentPage)
        held.entryFocus = PeekFocusReturn(source: pageHost)
        tabPeeks.current = held
        sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        applyTabPeek(session.opening, held)
        return tabPeeks.current === held
    }

    private func tabPeekPane(_ tab: BrowserTab) -> BrowserPane {
        if let pane = panes[tab.id] { return pane }
        let pane = makePane(tab)
        pane.frame = pageHost.bounds
        panes[tab.id] = pane
        parkedPages.addSubview(pane)
        pane.layoutSubtreeIfNeeded()
        return pane
    }

    private func createTabPeekPage(_ held: TabPeekPresentation) -> Bool {
        let id = held.tabID
        guard let browser = held.browser, browsers[id] == nil, let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              let url = URL(string: tab.url) else { return false }
        let pane = tabPeekPane(tab)
        browser.frame = pane.contentBounds
        held.relay.onPage = { [weak self, weak held] in
            guard let self, let held else { return }
            self.tabPeekPageArrived(held)
        }
        held.relay.onFailure = { [weak self, weak held] in
            guard let self, let held else { return }
            self.abandonTabPeek(held)
        }
        browser.delegate = held.relay
        browsers[id] = browser; browserProfiles[id] = tab.profileID; liveTabModels[id] = tab
        pane.browser = browser; pane.showBrowser()
        requestedURLs[id] = tab.url
        let restored = store.closedPageHistory.takeRestored(id) as? NSObject ?? launchHistory(for: tab)
        if let restored, browser.restoreNavigationState(restored, url: url) {} else { browser.loadURL(url) }
        let timeout = DispatchWorkItem { [weak self, weak held] in
            guard let self, let held, held.session.phase == .loading else { return }
            self.abandonTabPeek(held)
        }
        held.loadTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        attachOwnedPages()
        return true
    }

    private func tabPeekPageArrived(_ held: TabPeekPresentation) {
        guard tabPeeks.current === held, held.session.phase == .loading else { return }
        held.loadTimeout?.cancel(); held.loadTimeout = nil
        held.relay.onFailure = nil
        guard let page = held.browser?.nativePage, !page.isClosed,
              TabPeekHold.resolve(tabPeekFacts(held, displayed: nil)) == .keep else {
            abandonTabPeek(held); return
        }
        applyTabPeek(held.session.pageReady(page.identifier), held)
    }

    private func abandonTabPeek(_ held: TabPeekPresentation) {
        held.loadTimeout?.cancel(); held.loadTimeout = nil
        held.relay.onPage = nil; held.relay.onFailure = nil
        _ = held.session.resolve(.putBack)
        if let browser = held.browser, browser.delegate === held.relay, browsers[held.tabID] === browser {
            browser.delegate = self
        }
        if tabPeeks.current === held { tabPeeks.current = nil }
    }

    private func tabPeekFacts(_ held: TabPeekPresentation, displayed: [UUID]?) -> TabPeekHoldFacts {
        let id = held.tabID, parent = held.parentTabID, loading = held.session.phase == .loading
        var facts = TabPeekHoldFacts()
        let tab = store.state.tab(id, where: { $0.archivedAt == nil })
        let contentUsable: Bool
        switch held.content {
        case .page(let browser):
            let pageOpen = browser.nativePage.map { !$0.isClosed } ?? loading
            facts.pageInCard = loading || (browsers[id] === browser && pageOpen
                && held.controller.map { browser.isDescendant(of: $0.view) } == true)
            contentUsable = browsers[id] === browser && pageOpen
        case .document(let document):
            let current = document.isSame(as: peekDocument(id))
            facts.pageInCard = current && held.documentController?.holdsDocument == true
            contentUsable = current && !modelRetirementIDs.contains(id) && !closingTabIDs.contains(id)
        }
        facts.windowOpen = !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
        facts.tabUsable = contentUsable && tab?.profileID == activeProfileID
            && (tab?.spaceID == activeSpaceID || tab?.kind == .favorite)
            && switcherCanUse(id) && !resolvingTransfers.contains(id) && nativeFullscreenTabID != id
        facts.tabDisplayed = (displayed ?? presentation.displayedTabIDs).contains(id)
        if let parentPage = held.parentPage {
            facts.parentCurrent = currentTabID == parent && !parentPage.isClosed
                && browsers[parent]?.nativePage === parentPage
                && !closingTabIDs.contains(parent) && !transferringTabIDs.contains(parent)
                && !modelRetirementIDs.contains(parent) && !peekRetirementParents.contains(parent)
        } else {
            facts.parentCurrent = false
        }
        return facts
    }

    func reconcileTabPeek(displaying displayed: [UUID]? = nil) {
        if let current = tabPeeks.current {
            switch current.session.phase {
            case .loading:
                if TabPeekHold.resolve(tabPeekFacts(current, displayed: displayed)) != .keep { abandonTabPeek(current) }
            case .shown:
                let facts = tabPeekFacts(current, displayed: displayed)
                applyTabPeek(current.session.resolve(TabPeekHold.resolve(facts)), current)
                if tabPeeks.current === current, let controller = current.controller {
                    placePeek(controller)
                    controller.view.adoptWindowTheme(rootView)
                    current.document?.adopt(rootView.palette)
                    _ = controller.refresh()
                }
            case .promoting, .finished:
                break
            }
        }
        reconcileQueuedTabPeek()
    }

    private func reconcileQueuedTabPeek() {
        guard let queued = tabPeeks.queued else { return }
        guard currentTabID == queued.parentTabID else { tabPeeks.queued = nil; return }
        let old: PeekCard? = peeks.values.first { $0.identity == queued.replacing }
            ?? tabPeeks.current?.controller.flatMap { $0.identity == queued.replacing ? $0 : nil }
        if let old {
            if old.modalPhase == .presented { tabPeeks.queued = nil }
            return
        }
        tabPeeks.queued = nil
        guard currentTabID == queued.parentTabID, activePeek == nil, tabPeeks.current == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentTabID == queued.parentTabID else { return }
            self.openTabInPeek(queued.tabID)
        }
    }

    func retireTabPeeks() {
        tabPeeks.queued = nil
        for held in tabPeeks.leaving + [tabPeeks.current].compactMap({ $0 }) { finishTabPeek(held) }
        tabPeeks.current = nil; tabPeeks.leaving.removeAll()
    }

    private func applyTabPeek(_ effects: [TabPeekSession.Effect], _ held: TabPeekPresentation) {
        for effect in effects {
            switch effect {
            case .createPage:
                if !createTabPeekPage(held) { abandonTabPeek(held); return }
            case .presentPage(let id):
                switch held.content {
                case .page(let browser):
                    guard browser.nativePage?.identifier == id, presentTabPeekCard(held) else {
                        abandonTabPeek(held); return
                    }
                case .document:
                    guard id == documentKey(held.tabID), presentDocumentPeekCard(held) else {
                        abandonTabPeek(held); return
                    }
                }
            case .returnPage(let id):
                switch held.content {
                case .page(let browser):
                    if browser.nativePage?.identifier == id { _ = handTabPageBack(held) }
                case .document:
                    if id == documentKey(held.tabID) { _ = handDocumentBack(held) }
                }
            case .exit:
                playTabPeekExit(held)
            case .finish:
                finishTabPeek(held)
            }
        }
    }

    private func presentTabPeekCard(_ held: TabPeekPresentation) -> Bool {
        let id = held.tabID
        guard let binding = nativeBinding, let browser = held.browser, let page = browser.nativePage, !page.isClosed,
              let parentPage = held.parentPage, !parentPage.isClosed, browsers[id] === browser,
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }) else { return false }
        let pane = tabPeekPane(tab)
        binding.pageWillDetach(page)
        if pane.browser === browser { pane.browser = nil } else { browser.removeFromSuperview() }
        let controller = PeekController(page: page, parent: parentPage, parentTabID: held.parentTabID,
                                        sourceSpaceID: activeSpaceID, holding: browser)
        held.relay.peek = controller
        browser.delegate = held.relay
        browser.isHidden = false
        wirePeekPresentation(controller)
        peekLayer.addSubview(controller.view, positioned: .above, relativeTo: nil)
        placePeek(controller); controller.view.layoutSubtreeIfNeeded()
        guard binding.pageDidAttach(page, container: browser) else {
            controller.handBackBrowser()
            pane.browser = browser
            browser.delegate = self
            held.relay.peek = nil
            controller.finish()
            if binding.pageDidAttach(page, container: browser) { attachedPageIDs.insert(page.identifier) }
            refreshPagePresentation(id)
            return false
        }
        attachedPageIDs.insert(page.identifier)
        held.controller = controller
        wireTabPeek(controller, held)
        controller.setVisible(true)
        revealTabPeekCard(controller, held) { !page.isClosed }
        return true
    }

    private func presentDocumentPeekCard(_ held: TabPeekPresentation) -> Bool {
        let id = held.tabID
        guard let document = held.document, document.isSame(as: peekDocument(id)),
              let parentPage = held.parentPage, !parentPage.isClosed,
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }) else { return false }
        let pane = tabPeekPane(tab)
        pane.clearNativeContent()
        document.adopt(rootView.palette)
        let controller = DocumentPeekController(document: document.view, parent: parentPage, parentTabID: held.parentTabID,
            sourceSpaceID: activeSpaceID, title: { [weak self] in
                guard let tab = self?.store.state.tab(id) else { return "" }
                return tab.customTitle.flatMap { $0.isEmpty ? nil : $0 } ?? tab.title
            }, focus: { document.focus() })
        wirePeekPresentation(controller)
        peekLayer.addSubview(controller.view, positioned: .above, relativeTo: nil)
        placePeek(controller); controller.view.layoutSubtreeIfNeeded()
        held.controller = controller
        wireTabPeek(controller, held)
        document.handleUnhandledEscape { [weak controller] in
            guard let controller, controller.canHandleEscape else { return false }
            controller.requestDismiss(.exit)
            return true
        }
        controller.setVisible(true)
        revealTabPeekCard(controller, held) { document.isSame(as: self.peekDocument(id)) }
        windowKeyViews.relink()
        return true
    }

    private func revealTabPeekCard(_ controller: PeekCard, _ held: TabPeekPresentation, contentLive: @escaping () -> Bool) {
        let entryFocus = held.entryFocus
        held.entryFocus = nil
        DispatchQueue.main.async { [weak self, weak controller, weak held] in
            guard let self, let controller, let held, self.tabPeeks.current === held,
                  held.shownController === controller, contentLive() else { return }
            self.placePeek(controller); controller.view.layoutSubtreeIfNeeded()
            controller.view.animatePresentation()
            self.nativeBinding?.synchronizeSelectionAndLayout()
            if let window = self.window {
                entryFocus?.perform(in: window, ownerIsAvailable: {
                    self.activePeek === controller && controller.canInteract?() == true
                        && PCNativeBrowserApplication.canUseWindowUndo(in: window)
                }) { _ in controller.focus() }
            }
        }
        updateNavigation(); refreshLivePageChromeOrRender()
    }

    private func wireTabPeek(_ controller: PeekCard, _ held: TabPeekPresentation) {
        let heldID = held.tabID, parent = held.parentTabID
        let contentLive: () -> Bool
        switch held.content {
        case .page:
            guard let pageController = controller as? PeekController, let binding = nativeBinding else { return }
            let page = pageController.page
            contentLive = { [weak self, weak pageController, weak binding] in
                guard let self, let pageController, let binding else { return false }
                return !page.isClosed && PCNativeBrowserApplication.owner(of: page) === binding
                    && pageController.browser.window === self.window && binding.window === self.window
            }
            controller.onClose = { [weak self, weak held] in
                guard let self, let held, page.isClosed else { return }
                self.applyTabPeek(held.session.pageClosed(), held)
            }
            controller.onMediaChange = { [weak self] in self?.scheduleMediaRefresh() }
            controller.onContextImage = { [weak self, weak pageController] image in
                guard let self, let pageController else { return }
                self.browserView(pageController.browser, addContextImageToEasel: image)
            }
        case .document(let document):
            contentLive = { [weak self, weak controller] in
                guard let self, let controller = controller as? DocumentPeekController else { return false }
                return controller.holdsDocument && document.isSame(as: self.peekDocument(heldID))
                    && controller.view.window === self.window
            }
        }
        controller.canInteract = { [weak self, weak controller, weak held] in
            guard let self, let controller, let held else { return false }
            return self.tabPeeks.current === held && held.shownController === controller
                && self.activePeek === controller && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.closingTabIDs.contains(parent) && !self.closingTabIDs.contains(heldID)
                && !self.transferringTabIDs.contains(parent) && !self.transferringTabIDs.contains(heldID)
                && contentLive()
        }
        controller.canExpand = { [weak self, weak controller] in
            guard let self, let controller, controller.canInteract?() == true else { return false }
            return self.switcherCanUse(heldID) && self.visibleTabs.contains { $0.id == heldID }
        }
        controller.canSplit = { [weak self, weak controller] in
            guard let self, let controller else { return false }
            return self.tabPeekSplitRefusal(controller, tabID: heldID, parentID: parent) == nil
        }
        controller.splitToolTip = { [weak self, weak controller] in
            guard let self, let controller else { return nil }
            return self.tabPeekSplitRefusal(controller, tabID: heldID, parentID: parent)?.toolTip
        }
        controller.onReturn = { [weak self, weak held, weak controller] in
            guard let self, let held, let controller, held.session.phase == .shown else { return }
            let effects = held.session.returnRequested()
            guard !effects.isEmpty else { controller.refuseClose(); return }
            let focusReturn = controller.takeFocusReturn()
            self.applyTabPeek(effects, held)
            self.returnFocusAfterTabPeek(focusReturn, to: held)
        }
        controller.onPromote = { [weak self] split in self?.promoteTabPeek(split: split) }
        controller.onUpdate = { [weak self] in self?.refreshLivePageChromeOrRender() }
    }

    private func tabPeekSplitRefusal(_ controller: PeekCard, tabID: UUID, parentID: UUID) -> TabPeekSplitRefusal? {
        var facts = TabPeekSplitFacts()
        facts.peekInteractive = controller.canInteract?() == true
        facts.tabUsable = switcherCanUse(tabID) && visibleTabs.contains { $0.id == tabID }
        facts.parentSelected = selectedTabIDs.contains(parentID)
        facts.panes = selectedTabIDs.count
        facts.windowReady = !isPopupWindow && presentation.isReady && nativeFullscreenTabID == nil && libraryView == nil
            && transferringTabIDs.isEmpty && (selectedTabIDs.count == 1 || activeSplitLayout != nil)
        return TabPeekSplit.refusal(facts)
    }

    func promoteTabPeek(split: Bool) {
        guard let held = tabPeeks.current, let controller = held.shownController,
              controller.canRequestExit, controller.canExpand?() == true, !split || controller.canSplit?() == true else { return }
        let id = held.tabID
        let focusReturn = PeekFocusReturn(source: controller.view)
        let selected = split ? openTabInSplitView(id) : selectTab(id)
        guard selected, held.session.phase != .shown else { focusReturn?.cancel(); return }
        guard let window else { focusReturn?.cancel(); return }
        let available = {
            self.activePeek == nil && self.commandBar == nil
                && !self.closingTabIDs.contains(id) && !self.modelRetirementIDs.contains(id)
                && !self.store.retiringTabIDs.contains(id) && !self.transferringTabIDs.contains(id)
                && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && PCNativeBrowserApplication.canUseWindowUndo(in: window)
        }
        switch held.content {
        case .page:
            guard let page = (controller as? PeekController)?.page, let binding = nativeBinding else { focusReturn?.cancel(); return }
            focusReturn?.perform(in: window, ownerIsAvailable: {
                self.nativeBinding === binding && self.currentBrowser?.nativePage === page && available()
            }) { _ in _ = binding.requestFocus(for: page) }
        case .document(let document):
            focusReturn?.perform(in: window, ownerIsAvailable: {
                self.currentTabID == id && document.isSame(as: self.peekDocument(id)) && available()
            }) { _ in document.focus() }
        }
    }

    @discardableResult
    private func handTabPageBack(_ held: TabPeekPresentation) -> Bool {
        let id = held.tabID
        guard let browser = held.browser else { return false }
        held.relay.peek = nil
        held.pageController?.handBackBrowser()
        guard browsers[id] === browser, let page = browser.nativePage, !page.isClosed else {
            if browser.delegate === held.relay { browser.delegate = browsers[id] === browser ? self : nil }
            return false
        }
        let binding = nativeBinding
        binding?.pageWillDetach(page)
        browser.delegate = self
        guard let pane = panes[id] ?? store.state.tab(id).map(tabPeekPane) else {
            browser.removeFromSuperview()
            attachedPageIDs.remove(page.identifier)
            return false
        }
        pane.browser = browser
        if binding?.pageDidAttach(page, container: browser) == true { attachedPageIDs.insert(page.identifier) }
        else { attachedPageIDs.remove(page.identifier) }
        refreshPagePresentation(id)
        return true
    }

    @discardableResult
    private func handDocumentBack(_ held: TabPeekPresentation) -> Bool {
        let id = held.tabID
        guard let document = held.document else { return false }
        document.handleUnhandledEscape(nil)
        let card = held.documentController
        guard document.isSame(as: peekDocument(id)), let pane = panes[id] ?? store.state.tab(id).map(tabPeekPane) else {
            card?.releaseDocument()
            return false
        }
        switch document {
        case .note(let editor): pane.showNote(editor)
        case .easel(let editor): pane.showNativeContent(editor.view)
        }
        windowKeyViews.relink()
        return true
    }

    private func playTabPeekExit(_ held: TabPeekPresentation) {
        guard let controller = held.controller else {
            applyTabPeek(held.session.exitFinished(), held); return
        }
        let duration = controller.playHandoffExit()
        held.exitTimer?.invalidate()
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self, weak held] _ in
            MainActor.assumeIsolated {
                guard let self, let held else { return }
                self.applyTabPeek(held.session.exitFinished(), held)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        held.exitTimer = timer
        if tabPeeks.current === held { tabPeeks.current = nil; scheduleTabPeekCleanup() }
        tabPeeks.leaving.append(held)
    }

    private func finishTabPeek(_ held: TabPeekPresentation) {
        held.loadTimeout?.cancel(); held.loadTimeout = nil
        held.exitTimer?.invalidate(); held.exitTimer = nil
        held.relay.peek = nil; held.relay.onPage = nil; held.relay.onFailure = nil
        held.document?.handleUnhandledEscape(nil)
        if let browser = held.browser, browser.delegate === held.relay {
            browser.delegate = browsers[held.tabID] === browser ? self : nil
        }
        held.controller?.finish()
        tabPeeks.leaving.removeAll { $0 === held }
        if tabPeeks.current === held { tabPeeks.current = nil; scheduleTabPeekCleanup() }
    }

    private func scheduleTabPeekCleanup() {
        guard !isClosing, !wholeWindowClose else { return }
        if rendering {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isClosing, !self.wholeWindowClose else { return }
                self.updateNavigation(); self.requestNativeSelection(); self.refreshLivePageChromeOrRender()
                self.reconcileQueuedTabPeek()
            }
        } else {
            updateNavigation(); requestNativeSelection(); refreshLivePageChromeOrRender()
            reconcileQueuedTabPeek()
        }
    }

    private func returnFocusAfterTabPeek(_ focusReturn: PeekFocusReturn?, to held: TabPeekPresentation) {
        guard let window, let binding = nativeBinding, let parentPage = held.parentPage else { focusReturn?.cancel(); return }
        let parent = held.parentTabID
        focusReturn?.perform(in: window, ownerIsAvailable: {
            self.currentTabID == parent && self.activePeek == nil
                && self.browsers[parent]?.nativePage === parentPage
                && self.nativeBinding === binding && self.commandBar == nil
                && !self.closingTabIDs.contains(parent) && !self.modelRetirementIDs.contains(parent)
                && !self.peekRetirementParents.contains(parent) && !self.store.retiringTabIDs.contains(parent)
                && !self.transferringTabIDs.contains(parent)
                && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && PCNativeBrowserApplication.canUseWindowUndo(in: window)
        }) { _ in _ = binding.requestFocus(for: parentPage) }
    }

    func settleTabPeek(before id: UUID) {
        guard let current = tabPeeks.current, current.tabID == id || current.parentTabID == id else { return }
        if current.session.phase == .loading { abandonTabPeek(current); return }
        applyTabPeek(current.session.resolve(.putBack), current)
    }

    func handleTabPeekSelection(_ page: PCNativePage, browser: PCNativeBrowserWindow) -> Bool {
        guard let current = tabPeeks.current, let held = current.browser, held.nativePage === page else { return false }
        if let controller = current.shownController, !page.isClosed {
            guard !applyingNativeSelection, !isClosing, !wholeWindowClose else { return true }
            if currentTabID != current.parentTabID {
                applyingNativeSelection = true
                _ = selectTab(current.parentTabID)
                applyingNativeSelection = false
            }
            layoutPeeks(); controller.focus()
            return true
        }
        if current.session.phase == .loading { browser.synchronizeSelectionAndLayout(); return true }
        return false
    }

    func promoteTabPeekForFullscreen(_ page: PCNativePage) -> Bool {
        guard let current = tabPeeks.current, let controller = current.shownController as? PeekController, controller.page === page,
              activePeek === controller else { return false }
        promoteTabPeek(split: false)
        return current.session.phase != .shown
    }
}
