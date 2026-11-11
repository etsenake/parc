import AppKit

@MainActor
final class DevToolsWindowController: NSWindowController, NSWindowDelegate,
                                      PCNativeBrowserWindowClient, PCNativePageObserver {
    var onClose: (() -> Void)?
    private let profilePath: String
    private weak var sourceClient: (any PCNativeBrowserWindowClient)?
    private weak var sourceBinding: PCNativeBrowserWindow?
    private let root = DevToolsRootView(frame: NSRect(origin: .zero,
                                                      size: DevToolsWindowGeometry.emptyRestoreFallbackSize))
    private var binding: PCNativeBrowserWindow?
    private var page: PCNativePage?
    private var closePending = false
    private var closeApproved = false
    private var closed = false
    private var synchronizing = false
    private var fullscreenSidePanelVisibility: Bool?

    init(profilePath: String, source: PCNativeBrowserWindow?, request: PCNativeWindowRequest? = nil) throws {
        self.profilePath = profilePath
        sourceBinding = source
        sourceClient = source?.client
        let window = NSWindow(contentRect: .zero,
                              styleMask: DevToolsWindowGeometry.styleMask,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        DevToolsWindowGeometry.applyChrome(to: window)
        super.init(window: window)
        window.delegate = self
        let autosave = DevToolsWindowGeometry.frameAutosaveName(
            bundleIdentifier: Bundle.main.bundleIdentifier)
        windowFrameAutosaveName = autosave
        DevToolsWindowGeometry.restoreFrame(window, using: autosave)
        root.onGeometryChanged = { [weak self] in
            self?.synchronizeLayout()
        }
        root.onLayout = { [weak self] in
            self?.showToolsWindowIfHidden()
        }
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        do {
            binding = try PCNativeBrowserApplication.register(self)
            if let request, request.isOffTheRecord { try binding?.adoptPrivateContext(request: request) }
        }
        catch {
            window.delegate = nil
            window.close()
            throw error
        }
        root.layoutSubtreeIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var canToggleClosed: Bool {
        guard !closed, !closePending, !closeApproved,
              let window, window === NSApp.keyWindow, window.isVisible,
              window.attachedSheet == nil, let binding, let page, !page.isClosed,
              page.nativeView.window === window,
              PCNativeBrowserApplication.owner(of: page) === binding else { return false }
        return true
    }

    func toggleClosed(_ sender: Any?) {
        guard canToggleClosed else { return }
        window?.performClose(sender)
    }

    func nativeBrowserWindow() -> NSWindow { window! }
    func selectedNativePage() -> PCNativePage? { page?.isClosed == false ? page : nil }
    func visibleNativePages() -> [PCNativePage] {
        guard let page, !page.isClosed, window?.isVisible == true,
              !root.pageContainer.isHiddenOrHasHiddenAncestor else { return [] }
        return [page]
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, containerFor incoming: PCNativePage,
                       disposition: PCNativePageDisposition) -> NSView? {
        guard browser === binding, !closed, !closePending, !closeApproved,
              !incoming.isClosed, incoming.profilePath == profilePath,
              let window, root.pageContainer.window === window,
              PCNativeBrowserApplication.owner(of: incoming) === browser else { return nil }
        if let page { return page === incoming ? root.pageContainer : nil }
        guard incoming.observer == nil || incoming.observer === self else { return nil }
        page = incoming
        incoming.observer = self
        presentToolsIfReady()
        return root.pageContainer
    }

    private func toolsPageIsAttached() -> Bool {
        guard !closed, !closePending, !closeApproved,
              let page, !page.isClosed, let binding, let window,
              PCNativeBrowserApplication.owner(of: page) === binding,
              page.nativeView.window === window,
              page.nativeView.isDescendant(of: root.pageContainer) else { return false }
        return true
    }

    private func showToolsWindowIfHidden() {
        guard toolsPageIsAttached(), let window, !window.isVisible else { return }
        presentToolsIfReady()
    }

    private func presentToolsIfReady() {
        guard toolsPageIsAttached(), let page, let window else { return }
        if !window.isVisible {
            showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        }
        synchronizeLayout(selectPage: true)
        guard toolsPageIsAttached(), page.nativeView.window === window,
              window.attachedSheet == nil else { return }
        window.makeFirstResponder(page.nativeView)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, didClose incoming: PCNativePage) {
        guard browser === binding, page === incoming else { return }
        releasePage(incoming)
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, didSelect incoming: PCNativePage) {
        guard browser === binding, page === incoming, !closed, !closePending, !closeApproved,
              !incoming.isClosed, incoming.observer === self,
              incoming.profilePath == profilePath,
              PCNativeBrowserApplication.owner(of: incoming) === browser,
              let window, browser.window === window,
              incoming.nativeView.window === window,
              incoming.nativeView.isDescendant(of: root.pageContainer) else { return }
        presentToolsIfReady()
    }
    func nativePageDidClose(_ incoming: PCNativePage) {
        guard page === incoming else { return }
        releasePage(incoming)
    }
    func nativePageDidChange(_ incoming: PCNativePage) {
        guard page === incoming, !closed else { return }
        synchronizeLayout()
        showToolsWindowIfHidden()
    }
    func nativePage(_ incoming: PCNativePage, didFailWithError error: Error) {
        guard page === incoming else { return }
        report(error.localizedDescription)
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, didFailWithError error: Error) {
        guard browser === binding else { return }
        report(error.localizedDescription)
    }
    private func releasePage(_ incoming: PCNativePage) {
        if incoming.observer === self { incoming.observer = nil }
        page = nil
    }

    @objc func nativeBrowserDidReleaseLastBrowser(_ browser: PCNativeBrowserWindow) {
        guard browser === binding, !closed else { return }
        closeApproved = true
        closePending = false
        finishShellClose()
    }

    @objc func nativeBrowserCreationReservationDidAbort(_ browser: PCNativeBrowserWindow) {
        guard browser === binding, !closed, page == nil else { return }
        closeApproved = true
        closePending = false
        finishShellClose()
    }

    private func finishShellClose() {
        guard closeApproved, !closed else { return }
        if let page { releasePage(page) }
        window?.close()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window, !closed else { return false }
        if closeApproved { return true }
        guard !closePending, let binding else { return false }
        closePending = true
        binding.requestClose { [weak self] allowed in
            guard let self, !self.closed else { return }
            self.closePending = false
            if allowed {
                self.closeApproved = true
                self.finishShellClose()
            }
        }
        return false
    }
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window, !closed else { return }
        closed = true
        if let page { releasePage(page) }
        root.onGeometryChanged = nil
        root.onLayout = nil
        window?.delegate = nil
        binding = nil
        let completion = onClose
        onClose = nil
        completion?()
    }
    func windowDidBecomeKey(_ notification: Notification) { synchronizeLayout(selectPage: true) }
    func windowDidChangeOcclusionState(_ notification: Notification) { synchronizeLayout() }
    func windowDidResize(_ notification: Notification) { synchronizeLayout() }
    private func synchronizeLayout(selectPage: Bool = false) {
        guard !closed, !synchronizing else { return }
        synchronizing = true
        defer { synchronizing = false }
        if selectPage { binding?.synchronizeSelectionAndLayout() }
        else { binding?.synchronizeLayout() }
    }

    func nativeBrowserFocusAddress(_ browser: PCNativeBrowserWindow) {
        withSource(browser) { client, source in client.nativeBrowserFocusAddress(source) }
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, rotateFocusForward forward: Bool) -> Bool {
        guard browser === binding, let window else { return false }
        let before = window.firstResponder
        if forward { window.selectNextKeyView(nil) } else { window.selectPreviousKeyView(nil) }
        return window.firstResponder !== before
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, setTabFullscreenPage incoming: PCNativePage?) -> Bool {
        guard browser === binding, !closed, !closePending else { return false }
        guard incoming == nil || incoming === page else { return false }
        if incoming != nil {
            if fullscreenSidePanelVisibility == nil { fullscreenSidePanelVisibility = root.sidePanelVisible }
            root.sidePanelVisible = false
        } else if let previous = fullscreenSidePanelVisibility {
            root.sidePanelVisible = previous
            fullscreenSidePanelVisibility = nil
        }
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        return true
    }
    func nativeBrowserShowTabSearch(_ browser: PCNativeBrowserWindow) {
        withSource(browser) { client, source in client.nativeBrowserShowTabSearch(source) }
    }
    func nativeBrowserCloseTabSearch(_ browser: PCNativeBrowserWindow) {
        withSource(browser) { client, source in client.nativeBrowserCloseTabSearch(source) }
    }
    func nativeBrowserShowProfiles(_ browser: PCNativeBrowserWindow) {
        withSource(browser) { client, source in client.nativeBrowserShowProfiles(source) }
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, bookmarkURL url: URL) {
        withSource(browser) { client, source in client.nativeBrowser(source, bookmarkURL: url) }
    }
    func nativeBrowserSidePanelContainer(_ browser: PCNativeBrowserWindow) -> NSView { root.sidePanel }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, setSidePanelVisible visible: Bool) -> Bool {
        guard browser === binding, !closed, !closePending,
              fullscreenSidePanelVisibility == nil || !visible else { return false }
        root.sidePanelVisible = visible
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        return root.sidePanel.window === window && root.sidePanel.isHidden == !visible
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, capabilityUnavailable capability: String) {
        guard browser === binding else { return }
        report(capability)
    }
    private func withSource(_ browser: PCNativeBrowserWindow,
                            perform: (any PCNativeBrowserWindowClient, PCNativeBrowserWindow) -> Void) {
        guard browser === binding, !closed else { return }
        guard let sourceBinding, let client = sourceClient, sourceBinding.client === client else {
            report("This Developer Tools window no longer has its originating browser window.")
            return
        }
        perform(client, sourceBinding)
    }
    private func report(_ message: String) {
        NSLog("Parc Developer Tools: %@", message)
        root.errorLabel.stringValue = message
        root.errorLabel.isHidden = false
        root.needsLayout = true
    }
}

@MainActor
private final class DevToolsRootView: NSView {
    let pageContainer = NSView()
    let sidePanel = NSView()
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    var sidePanelVisible = false
    var onLayout: (() -> Void)?
    var onGeometryChanged: (() -> Void)?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        addSubview(pageContainer)
        addSubview(sidePanel)
        sidePanel.isHidden = true
        errorLabel.isHidden = true
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.font = .systemFont(ofSize: 12)
        addSubview(errorLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let plan = DevToolsRootLayoutSkip.plan(
            bounds: bounds,
            sidePanelVisible: sidePanelVisible,
            errorHidden: errorLabel.isHidden)
        let matched = DevToolsRootLayoutSkip.surfacesAlreadyMatch(
            plan,
            sidePanelFrame: sidePanel.frame,
            sidePanelHidden: sidePanel.isHidden,
            pageContainerFrame: pageContainer.frame,
            errorLabelFrame: errorLabel.frame)
        if !matched {
            sidePanel.frame = plan.sidePanelFrame
            sidePanel.isHidden = plan.sidePanelHidden
            pageContainer.frame = plan.pageContainerFrame
            errorLabel.frame = plan.errorLabelFrame
            onGeometryChanged?()
        }
        onLayout?()
    }
}
