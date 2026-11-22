import AppKit
import ParcCore
import ParcEngine
import ParcKit

@MainActor
package final class NoteEmbedSurface: NSView, EmbeddedPageSurface {
    package enum Host: Equatable { case note, easel }

    static let headerHeight: CGFloat = 38
    package let browser: PCBrowserView
    let address: URL
    let liveAddress: URL
    let host: Host
    let captureLayout: EaselCaptureLayout?
    package var positioningAllowed = true {
        didSet {
            guard positioningAllowed != oldValue, captureLayout != nil else { return }
            if !positioningAllowed, positioning != nil { stopPositioning() }
            if positioningAllowed { needsLayout = true }
        }
    }
    package var onLayout: (() -> Void)?
    package var onRetry: (() -> Void)?
    package var onNavigate: ((URL) -> Bool)?
    package var onDone: (() -> Void)?
    package var onOpen: ((URL) -> Void)?
    package var onSnapshot: (() -> Void)?
    package var onFramingFailed: (() -> Void)?
    var onCaption: (() -> Void)? {
        didSet {
            guard captionButton.isHidden != (onCaption == nil) else { return }
            captionButton.isHidden = onCaption == nil
            header.needsLayout = true
        }
    }
    package var interactive = false {
        didSet {
            guard interactive != oldValue else { return }
            if host == .easel {
                if !interactive { closePopovers() }
                if !interactive && framing.revealsPage { positionCapture(force: true) }
                refresh()
                needsLayout = true
                return
            }
            refresh()
            refreshRing(animated: true)
            superview?.refreshCursorIfPointerOwned()
        }
    }
    var selected = false { didSet { if selected != oldValue { refreshRing(animated: true) } } }
    var scrollLatched = false
    var sendsAppReferrer: Bool { captureLayout == nil }
    private let content = NoteEmbedPageClip()
    private let ring = CALayer()
    private let header = EmbeddedPageHeader()
    private let clip = NoteEmbedPageClip()
    private let cover = NSView()
    private let backButton = NoteToolbarButton(icon: .symbol("chevron.left"), label: "Back")
    private let reloadButton = NoteToolbarButton(icon: .symbol("arrow.clockwise"), label: "Reload")
    private let openButton = NoteToolbarButton(icon: .symbol("arrow.up.right.square"), label: "Open in a tab")
    private let moreButton = NoteToolbarButton(icon: .symbol("ellipsis"), label: "More")
    private let doneButton: NoteToolbarButton
    private let captionButton = NoteToolbarButton(icon: .symbol("text.below.photo"), label: "Caption")
    private let snapshotChip = NoteChip(EaselWebItemChrome.backToSnapshotTitle, icon: .symbol("photo"))
    private let fallback: NoteEmbedFallbackView
    private var status: String?
    private var retryTitle = "Retry"
    private var framing = EaselLiveFraming()
    private var positioning: PCNativeLiveCapturePosition?
    private var positionGeneration: UInt64 = 0
    private var positionedWidth: CGFloat = 0
    private var positionedZoom: Double = 0
    private var moreMenu: NotePagePopover?
    private var addressPopover: NotePagePopover?
    private var lastSearch: (query: String, category: EaselWebNavigation.Category)?

    package init(address: URL, profilePath: String, host: Host = .note, captureLayout: EaselCaptureLayout? = nil,
         loadsLinkPreview: Bool = true) {
        self.address = address
        self.host = host
        self.captureLayout = captureLayout
        liveAddress = captureLayout == nil ? NoteEmbedAddress.liveURL(for: address) : address
        browser = PCBrowserView(frame: .zero, profilePath: profilePath)
        fallback = NoteEmbedFallbackView(address: address)
        doneButton = NoteToolbarButton(icon: .symbol("checkmark"), label: host == .note ? "Back to the note" : "Back to the Easel")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        content.wantsLayer = true
        content.layer?.cornerRadius = NoteMediaStyle.cardRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.borderWidth = 1
        content.layer?.masksToBounds = true
        addSubview(content)
        ring.cornerRadius = NoteMediaStyle.cardRadius + 3
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.opacity = 0
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.exposesChildren = { [weak self] in self?.inputAvailable == true }
        content.addSubview(clip)
        clip.addSubview(browser)
        cover.wantsLayer = true
        cover.isHidden = true
        content.addSubview(cover)
        fallback.onOpen = { [weak self] in
            guard let self else { return }
            if self.host == .note { self.onOpen?(self.address) } else { self.openInTab() }
        }
        fallback.onRetry = { [weak self] in self?.onRetry?() }
        content.addSubview(fallback)
        content.addSubview(header)
        backButton.onPress = { [weak self] in self?.navigate(.back) }
        reloadButton.onPress = { [weak self] in self?.reloadOrStop() }
        openButton.onPress = { [weak self] in self?.openInTab() }
        moreButton.onPress = { [weak self] in self?.showMore() }
        doneButton.onPress = { [weak self] in self?.onDone?() }
        doneButton.isHidden = true
        captionButton.onPress = { [weak self] in self?.onCaption?() }
        captionButton.isHidden = true
        snapshotChip.onPress = { [weak self] in self?.onSnapshot?() }
        snapshotChip.setToolTip(EaselWebItemChrome.backToSnapshotHelp)
        switch host {
        case .note:
            header.buttons = [captionButton, backButton, reloadButton, openButton, doneButton]
            layer?.addSublayer(ring)
            setAccessibilityElement(true)
            setAccessibilityRole(.group)
            setAccessibilityLabel("Live page: " + NoteMediaFormat.displayHost(address))
        case .easel:
            fallback.isHidden = true
            fallback.retryChip.acceptsKeyboardFocus = true
            doneButton.acceptsKeyboardFocus = true
            if captureLayout != nil {
                header.buttons = [reloadButton, openButton, moreButton, doneButton]
                header.action = snapshotChip
                header.setBadge("Live", help: EaselWebItemChrome.liveHelp, live: true)
            } else {
                header.buttons = [backButton, reloadButton, openButton, moreButton, doneButton]
            }
            setAccessibilityElement(false)
        }
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self.ring)
            if let layer = self.fallback.layer { NoteAnimation.settle(layer) }
        }
        if loadsLinkPreview {
            header.loadPreview(for: address) { [weak self] preview in
                if let preview { self?.fallback.configure(preview: preview) }
                self?.refresh()
            }
        }
        if host == .note { setStatus("Loading webpage…", retry: false) } else { refresh() }
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var isFlipped: Bool { true }

    package var inputAvailable: Bool {
        interactive && (browser.nativePage?.isClosed != false || browser.nativePage?.embeddedOwnerValid == true)
    }

    package var showsRecovery: Bool { status != nil || browser.nativePage?.rendererCrash != nil }

    package var pageArea: (page: NSRect, visible: NSRect) { (convert(browser.bounds, from: browser), clip.frame) }

    var pageRect: NSRect {
        if host == .easel {
            return NSRect(x: 0, y: Self.headerHeight, width: bounds.width, height: max(1, bounds.height - Self.headerHeight))
        }
        return NSRect(x: 1, y: Self.headerHeight, width: max(1, bounds.width - 2), height: max(1, bounds.height - Self.headerHeight - 1))
    }

    private var documentName: String { host == .note ? "note" : "Easel" }

    package func setStatus(_ text: String?, retry: Bool) {
        if host == .easel {
            if text == nil, captureLayout != nil, !framing.revealsPage { showLiningUp(); return }
            status = text
            fallback.configure(status: text.map(friendly), retryTitle: retry ? retryTitle : nil)
            fallback.isHidden = text == nil
            cover.isHidden = text == nil
            needsLayout = true
            return
        }
        let wasLive = status == nil
        status = text
        fallback.configure(status: text.map(friendly), retryTitle: retry ? retryTitle : nil)
        if text == nil {
            if !wasLive || !fallback.isHidden { hideFallback() }
        } else {
            fallback.layer?.removeAllAnimations()
            fallback.isHidden = false
            fallback.alphaValue = 1
            fallback.layer?.opacity = 1
        }
        refresh()
        needsLayout = true
    }

    private func friendly(_ text: String) -> String { EmbeddedPageStatusText.friendly(text, document: documentName) }

    package func setRetryTitle(_ title: String) {
        retryTitle = title
        guard let status else { return }
        let visible = host == .note || !fallback.retryChip.isHidden
        fallback.configure(status: friendly(status), retryTitle: visible ? title : nil)
    }

    private func hideFallback() {
        guard !fallback.isHidden else { return }
        NoteAnimation.fade(fallback, visible: false, duration: 0.18) { [weak self] in
            guard let self, self.status == nil else { return }
            self.fallback.isHidden = true
        }
    }

    package func refresh() {
        if host == .easel { refreshEasel(); return }
        let page = browser.nativePage
        let live = page?.isClosed == false && page?.embeddedOwnerValid == true
        let title = browser.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = NoteLinkMetadata.shared.cached(address)
        header.setPage(title: live && !title.isEmpty ? title : (preview?.title ?? NoteMediaFormat.displayHost(address)),
                       host: NoteMediaFormat.displayHost(live ? (page?.url ?? address) : address))
        backButton.isEnabled = live && page?.canPerformNavigation(.back) == true
        refreshReload(enabled: live)
        doneButton.isHidden = !interactive
        setAccessibilityValue(page?.url?.absoluteString ?? address.absoluteString)
        header.needsLayout = true
        needsLayout = true
    }

    private func refreshEasel() {
        let page = browser.nativePage
        let interactive = inputAvailable
        let live = page?.isClosed == false && page?.embeddedOwnerValid == true
        let preview = NoteLinkMetadata.shared.cached(address)
        let current = live ? (page?.url ?? address) : address
        let pageTitle = browser.title.trimmingCharacters(in: .whitespacesAndNewlines)
        header.setPage(title: live && !pageTitle.isEmpty ? pageTitle : (preview?.title ?? EaselWebItemChrome.displayHost(address)),
                       host: EaselWebItemChrome.displayHost(current))
        if captureLayout == nil { header.setEaselTooltip("Edit webpage address or search") } else { header.parcTooltip = nil }
        header.onTitle = captureLayout == nil && interactive ? { [weak self] in self?.editAddress() } : nil
        backButton.isEnabled = interactive && page?.canPerformNavigation(.back) == true
        refreshReload(enabled: interactive)
        openButton.isEnabled = true
        moreButton.isEnabled = interactive
        snapshotChip.isEnabled = interactive
        doneButton.isHidden = !interactive
        fallback.retryChip.isEnabled = interactive
        setAccessibilityHidden(!interactive)
        header.needsLayout = true
        window?.invalidateCursorRects(for: header)
    }

    private func refreshReload(enabled: Bool) {
        let page = browser.nativePage
        let loading = browser.isLoading
        reloadButton.content = .icon(.symbol(loading ? "xmark" : "arrow.clockwise"))
        reloadButton.setAccessibilityLabel(loading ? "Stop" : "Reload")
        reloadButton.setToolTip(loading ? "Stop" : "Reload")
        reloadButton.isEnabled = enabled && page?.canPerformNavigation(loading ? .stop : .reload) == true
    }

    package func validateInput() {
        guard host == .easel, !inputAvailable || window == nil else { return }
        closePopovers()
    }

    package func focusRecovery() -> Bool {
        guard host == .easel, interactive, let window else { return false }
        let retryVisible = !fallback.isHidden && !fallback.retryChip.isHidden
        return window.makeFirstResponder(retryVisible ? fallback.retryChip : doneButton)
    }

    package func focusRetry() {
        guard host == .easel, interactive, !fallback.isHidden, !fallback.retryChip.isHidden else { return }
        window?.makeFirstResponder(fallback.retryChip)
    }

    package override func cancelOperation(_ sender: Any?) {
        guard host == .easel else { super.cancelOperation(sender); return }
        if addressPopover?.isOpen == true || moreMenu?.isOpen == true { closePopovers(); return }
        if interactive { onDone?() }
    }

    package override func accessibilityChildren() -> [Any]? {
        host == .easel && !inputAvailable ? [] : super.accessibilityChildren()
    }

    package override func layout() {
        super.layout()
        content.frame = bounds
        NoteMediaMotion.instant { ring.frame = bounds.insetBy(dx: -3, dy: -3) }
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        clip.frame = pageRect
        if let captureLayout {
            let zoom = browser.nativePage?.liveCaptureZoomFactor ?? 1
            let size = EaselCaptureGeometry.displaySize(captureLayout, availableWidth: bounds.width,
                                                        availableHeight: pageRect.height, pageZoom: zoom)
            clip.frame = NSRect(x: (bounds.width - size.width) / 2, y: Self.headerHeight + (pageRect.height - size.height) / 2,
                                width: size.width, height: size.height)
            browser.frame = NSRect(x: 0, y: 0, width: captureLayout.viewport.x * zoom, height: captureLayout.viewport.y * zoom)
            positionCapture()
        } else {
            browser.frame = clip.bounds
        }
        cover.frame = pageRect
        fallback.frame = pageRect
        refreshColors()
        if let addressPopover, addressPopover.isOpen, let anchor = popoverAnchor(addressPopover.panel.superview) {
            addressPopover.reposition(anchor: anchor)
        }
        onLayout?()
    }

    private func refreshColors() {
        let fill = host == .note ? NoteMediaStyle.cardFill : NoteTheme.panelFill
        let stroke = host == .note ? NoteMediaStyle.cardStroke : NoteTheme.panelStroke
        NoteMediaMotion.instant {
            content.layer?.backgroundColor = NoteMediaStyle.cg(fill, in: self)
            content.layer?.borderColor = NoteMediaStyle.cg(stroke, in: self)
            cover.layer?.backgroundColor = NoteMediaStyle.cg(host == .note ? NoteMediaStyle.cardFill : NoteTheme.menuFill, in: self)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
    }

    private func refreshRing(animated: Bool) {
        guard host == .note else { return }
        let target: Float = interactive || selected ? 1 : 0
        if animated { NoteAnimation.fade(ring, to: target, duration: 0.12) }
        else { NoteMediaMotion.instant { ring.opacity = target } }
    }

    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    package override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if host == .easel {
            guard interactive else { return nil }
            if NSApp.currentEvent?.type == .scrollWheel,
               !EaselLiveFraming.admitsPageScrolling(framesCapture: captureLayout != nil), pageRect.contains(local) { return nil }
            return super.hitTest(point)
        }
        if status == nil, pageRect.contains(local) {
            let admits = NSApp.currentEvent?.type == .scrollWheel ? scrollLatched : interactive
            if !admits { return nil }
        }
        return super.hitTest(point)
    }

    func takesPageInput(at windowPoint: NSPoint) -> Bool {
        guard host == .note, !showsRecovery, !isHiddenOrHasHiddenAncestor, let page = browser.nativePage,
              !page.isClosed, page.embeddedOwnerValid else { return false }
        return pageRect.contains(convert(windowPoint, from: nil))
    }

    private func navigate(_ action: PCNativeNavigationAction) {
        guard let page = browser.nativePage, !page.isClosed, page.embeddedOwnerValid, page.canPerformNavigation(action) else { return }
        _ = page.performNavigation(action, inNewTab: false)
    }

    private func reloadOrStop() { navigate(browser.isLoading ? .stop : .reload) }

    private func openInTab() {
        guard let current = browser.nativePage?.url, browser.nativePage?.isClosed == false else { onOpen?(address); return }
        let unchanged = current.absoluteString == liveAddress.absoluteString || current.absoluteString == address.absoluteString
        onOpen?(unchanged ? address : current)
    }

    private func popoverHost() -> NSView? { enclosingScrollView?.superview ?? superview }

    private func popoverAnchor(_ host: NSView?) -> NSRect? {
        guard let host else { return nil }
        return host.convert(NSRect(x: 8, y: Self.headerHeight - 4, width: 1, height: 1), from: self)
    }

    private func closePopovers() {
        moreMenu?.close(animated: false)
        addressPopover?.close(animated: false)
    }

    private func editAddress() {
        guard host == .easel, captureLayout == nil, inputAvailable, let page = browser.nativePage, page.embeddedOwnerValid,
              let host = popoverHost(), let anchor = popoverAnchor(host) else { return }
        closePopovers()
        let editor = EmbeddedPageAddressEditor(text: lastSearch?.query ?? page.url?.absoluteString ?? address.absoluteString,
                                               category: lastSearch?.category ?? .images)
        let popover = NotePagePopover(content: editor)
        popover.exempt(header)
        editor.onSubmit = { [weak self, weak popover, weak page] url, search in
            guard let self, let page, self.inputAvailable, self.browser.nativePage === page,
                  self.onNavigate?(url) == true else { return false }
            self.lastSearch = search
            popover?.close()
            return true
        }
        editor.onCancel = { [weak popover] in popover?.close() }
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.addressPopover === popover else { return }
            self.addressPopover = nil
            if self.inputAvailable, let page = self.browser.nativePage, let window = self.window, window.attachedSheet == nil {
                window.makeFirstResponder(page.nativeView)
            }
        }
        addressPopover = popover
        popover.present(in: host, anchor: anchor, edge: .below, alignment: .leading)
        editor.focus()
    }

    private func showMore() {
        guard host == .easel, inputAvailable, let host = popoverHost() else { return }
        if moreMenu?.isOpen == true { moreMenu?.close(); return }
        closePopovers()
        let page = browser.nativePage
        var items: [NoteMenuList.Item] = []
        if captureLayout == nil {
            items.append(.init(id: "forward", title: "Forward", icon: .symbol("chevron.right"),
                               isEnabled: page?.canPerformNavigation(.forward) == true))
            items.append(.init(id: "address", title: "Edit Address or Search…", icon: .symbol("magnifyingglass"),
                               isEnabled: page?.canPerformNavigation(.reload) == true))
        } else {
            items.append(.init(id: "snapshot", title: "Back to Snapshot", icon: .symbol("photo")))
        }
        items.append(.init(id: "open", title: "Open in a Tab", icon: .symbol("arrow.up.right.square")))
        items.append(.init(id: "site", title: "Site Information", icon: .symbol("info.circle"),
                           isEnabled: browser.canShowSiteInfo, separatorBefore: true))
        let list = NoteMenuList(items: items)
        list.minimumWidth = 220
        list.setAccessibilityLabel("Webpage")
        let popover = NotePagePopover(content: list)
        popover.exempt(moreButton)
        popover.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        list.onCancel = { [weak popover] in popover?.close() }
        list.onActivate = { [weak self, weak popover] item in
            popover?.close(animated: true)
            guard let self else { return }
            switch item.id {
            case "forward": self.navigate(.forward)
            case "address": self.editAddress()
            case "snapshot": self.onSnapshot?()
            case "open": self.openInTab()
            case "site": _ = self.browser.showSiteInfo(from: self.moreButton)
            default: break
            }
        }
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.moreMenu === popover else { return }
            self.moreMenu = nil
        }
        moreMenu = popover
        let keyboard = NSApp.currentEvent?.type == .keyDown
        list.prepare(origin: keyboard ? .keyboard : .pointer)
        popover.present(in: host, anchor: host.convert(moreButton.bounds, from: moreButton), edge: .below, alignment: .trailing)
        if keyboard { list.moveHighlight(by: 1) }
    }

    package func cancelPositioning() {
        guard captureLayout != nil else { return }
        stopPositioning()
        guard host == .easel else { return }
        framing.pageChanged()
        if status == nil || status == "Positioning live capture…" { showLiningUp() }
    }

    private func stopPositioning() {
        positionGeneration &+= 1
        positioning?.cancel()
        positioning = nil
        positionedWidth = 0
        positionedZoom = 0
    }

    private func showLiningUp() {
        status = "Positioning live capture…"
        fallback.configure(status: friendly("Positioning live capture…"), retryTitle: nil)
        fallback.isHidden = false
        cover.isHidden = false
        needsLayout = true
    }

    private func framed(_ success: Bool) {
        switch framing.positioned(success: success, pageStillLoading: browser.isLoading) {
        case .reveal: setStatus(nil, retry: false)
        case .keepWaiting: showLiningUp()
        case .backToSnapshot:
            setStatus("This page could not align with the captured region.", retry: false)
            onFramingFailed?()
        }
    }

    package func positionCapture(force: Bool = false) {
        guard positioningAllowed, let layout = captureLayout, let page = browser.nativePage, !page.isClosed,
              page.embeddedOwnerValid, window != nil else { return }
        let zoom = page.liveCaptureZoomFactor
        let width = min(clip.bounds.width, clip.bounds.height * layout.region.width / layout.region.height)
        guard width > 0, zoom.isFinite, zoom > 0, force || positionedWidth != width || positionedZoom != zoom else { return }
        stopPositioning()
        positionedWidth = width
        positionedZoom = zoom
        let generation = positionGeneration
        browser.frame = NSRect(x: 0, y: 0, width: layout.viewport.x * zoom, height: layout.viewport.y * zoom)
        if !framing.revealsPage { showLiningUp() }
        positioning = page.positionLiveCapture(NSRect(x: layout.region.x, y: layout.region.y,
            width: layout.region.width, height: layout.region.height),
            scrollOffset: NSPoint(x: layout.scroll.x, y: layout.scroll.y),
            scrollContainers: layout.nativeScrollContainers, displayWidth: width) { [weak self, weak page] success in
                MainActor.assumeIsolated {
                    guard let self, let page, self.positionGeneration == generation,
                          self.browser.nativePage === page, page.embeddedOwnerValid else { return }
                    self.positioning = nil
                    self.framed(success)
                }
            }
        if positioning == nil { framed(false) }
    }
}

@MainActor
private final class NoteEmbedPageClip: NSView {
    var exposesChildren: () -> Bool = { true }
    override var isFlipped: Bool { true }
    override func accessibilityChildren() -> [Any]? { exposesChildren() ? super.accessibilityChildren() : [] }
}

@MainActor
package final class NoteEmbedResizeHandle: NSView {
    package static let size = NSSize(width: 72, height: 14)
    package var onDrag: ((CGFloat) -> Void)?
    package var onEnd: ((CGFloat) -> Void)?
    package var onStep: ((CGFloat) -> Void)?
    private let pill = CALayer()
    private var tracking: NSTrackingArea?
    private var start: NSPoint?
    private var hovered = false

    package override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pill.cornerRadius = 2.5
        pill.cornerCurve = .continuous
        pill.borderWidth = 1
        pill.opacity = 0
        layer?.addSublayer(pill)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Resize live page")
        setAccessibilityHelp("Drag up or down to change the height.")
        addCursorUpdateArea()
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var isFlipped: Bool { true }

    package func setVisible(_ visible: Bool) {
        let target: Float = visible || hovered || start != nil ? 1 : 0
        guard pill.opacity != target else { return }
        NoteAnimation.fade(pill, to: target, duration: NoteAnimation.hoverDuration)
    }

    package override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            pill.frame = NSRect(x: (bounds.width - 36) / 2, y: (bounds.height - 5) / 2, width: 36, height: 5)
            pill.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.handleFill, in: self)
            pill.borderColor = NoteMediaStyle.cg(NoteMediaStyle.handleStroke, in: self)
        }
    }

    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    package override func cursorUpdate(with event: NSEvent) {
        if applyNoteCursor(.resizeUpDown, for: event) { return }
        super.cursorUpdate(with: event)
    }

    package override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    package override func mouseEntered(with event: NSEvent) { refreshHover(at: event.locationInWindow) }
    package override func mouseMoved(with event: NSEvent) { refreshHover(at: event.locationInWindow) }

    private func refreshHover(at windowPoint: NSPoint) {
        let next = NoteFloatingPanel.allowsHover(for: self, at: windowPoint)
        guard next != hovered else { return }
        hovered = next
        setVisible(next)
    }

    package override func mouseExited(with event: NSEvent) { hovered = false; setVisible(false) }
    package override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    package override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow
        setVisible(true)
    }

    package override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        onDrag?(start.y - event.locationInWindow.y)
    }

    package override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        onEnd?(start.y - event.locationInWindow.y)
        setVisible(false)
    }

    package override func accessibilityPerformIncrement() -> Bool { onStep?(40); return true }
    package override func accessibilityPerformDecrement() -> Bool { onStep?(-40); return true }
}
