import AppKit
import QuartzCore

@MainActor
final class PeekController: NSObject, PCBrowserViewDelegate {
    let identity = UUID()
    let parentTabID: UUID
    let sourceSpaceID: UUID
    let parentPage: PCNativePage
    let page: PCNativePage
    let browser: PCBrowserView
    let returnsPage: Bool
    let view = PeekHostView()
    private let failure = PageFailureView()
    var showsFailure: Bool { failure.presentation != nil }
    private var swipeMonitor: Any?
    private var reduceMotionObserver: NSObjectProtocol?
    private let dismissConfirmation = PeekDismissalConfirmation()
    private var closeFocusReturn: PeekFocusReturn?
    private var closeTransition = PeekCloseTransition()
    private var exitTimer: Timer?
    private var sheetObserver: NSObjectProtocol?
    private var closeInFlight = false
    private var finished = false
    private(set) var closePending = false
    private var lastPresentedFingerprint: String?
    private(set) var dismissedURL: URL?
    private(set) var dismissedNavigationState: NSObject?
    var onClose: (() -> Void)?
    var onCloseRefused: (() -> Void)?
    var onReturn: (() -> Void)?
    var onPromote: ((Bool) -> Void)?
    var onUpdate: (() -> Void)?
    var onMediaChange: (() -> Void)?
    var onContextImage: ((PCNativeContextImage) -> Void)?
    var canInteract: (() -> Bool)?
    var canSplit: (() -> Bool)?
    var canExpand: (() -> Bool)?

    init(page: PCNativePage, parent: PCNativePage, parentTabID: UUID, sourceSpaceID: UUID, holding held: PCBrowserView? = nil) {
        self.page = page; parentPage = parent; self.parentTabID = parentTabID; self.sourceSpaceID = sourceSpaceID
        browser = held ?? PCBrowserView(frame: .zero, adoptingNativePage: page)
        returnsPage = held != nil
        super.init()
        if !returnsPage { browser.delegate = self }
        view.content.addSubview(browser)
        view.content.addSubview(failure)
        failure.pageView = browser
        failure.onReload = { [weak self] in self?.browser.reload() }
        failure.onRetryRenderer = { [weak self] expected in
            guard let self, let crash = self.browser.rendererCrash,
                  expected.identity === crash else { return }
            _ = self.browser.performRendererCrashAction(crash)
        }
        failure.onRendererPresented = { [weak self] expected in
            guard let self, let crash = self.browser.rendererCrash,
                  expected.identity === crash else { return false }
            return self.browser.rendererCrashDidPresent(crash)
        }
        view.onLayout = { [weak self] in
            guard let self else { return }
            self.browser.frame = self.view.content.bounds
            self.failure.frame = self.view.content.bounds
        }
        view.onNativeCancel = { [weak self] in
            guard let self, self.canHandleEscape,
                  let responder = self.view.window?.firstResponder as? NSView,
                  (responder === self.view || responder.isDescendant(of: self.view)),
                  responder !== self.page.nativeView,
                  !responder.isDescendant(of: self.page.nativeView) else { return false }
            self.requestDismiss(.exit)
            return true
        }
        view.onClose = { [weak self] in self?.requestDismiss(.closeButton) }
        view.onExpand = { [weak self] in self?.promote(split: false) }
        view.onSplit = { [weak self] in self?.promote(split: true) }
        view.onBackground = { [weak self] in self?.requestDismiss(.background) }
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.view.settleMotion() } }
        refresh()
    }

    typealias Dismissal = PeekDismissalConfirmation.Dismissal

    enum ModalPhase { case presented, awaitingDismissConfirmation, dismissing }
    var modalPhase: ModalPhase {
        closePending ? .dismissing : dismissConfirmation.reason != nil ? .awaitingDismissConfirmation : .presented
    }

    func setVisible(_ visible: Bool, animate: Bool = false) {
        guard !finished else { return }
        let changed = view.isHidden == visible
        view.isHidden = !visible
        if visible {
            installSwipeMonitor()
            refresh()
            if changed && animate { view.animatePresentation() }
            if view.window?.attachedSheet != nil { apply(closeTransition.sheetBegan(visible: true)) }
        } else {
            removeSwipeMonitor()
            clearDismissConfirmation()
            closeFocusReturn?.cancel()
            view.settleMotion()
            let hidden = closeTransition.hide()
            apply(hidden.filter { $0 != .requestClose })
            if hidden.contains(.requestClose) {
                DispatchQueue.main.async { [weak self] in self?.requestPageClose() }
            }
        }
    }

    func contains(_ event: NSEvent) -> Bool {
        !view.isHidden && event.window === view.window && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }

    var canHandleEscape: Bool { canRequestExit }

    var canPrepareExit: Bool {
        guard let window = view.window else { return false }
        return !finished && !closePending && !view.isHidden && window.attachedSheet == nil && canInteract?() == true
    }
    var canRequestExit: Bool {
        guard let window = view.window else { return false }
        return canPrepareExit && PCNativeBrowserApplication.canUseWindowUndo(in: window)
    }

    func rendererEscape(prefersConfirmation: Bool) {
        guard canHandleEscape else { return }
        requestDismiss(.escape(prefersConfirmation: prefersConfirmation))
    }

    var canSwipeDismiss: Bool {
        guard let window = view.window else { return false }
        return !finished && !closePending && !view.isHidden && window.attachedSheet == nil
            && canInteract?() == true && closeTransition.phase == .resting && view.swipeIsAtRest
    }

    func beginSwipeDismissal() -> Bool {
        guard canSwipeDismiss, closeTransition.beginDrag() else { return false }
        view.beginSwipe()
        return true
    }

    func followSwipeDismissal(_ output: HistorySwipeOutput) {
        apply(closeTransition.drag(output))
    }

    func commitSwipeDismissal() -> Bool {
        guard closeTransition.phase == .dragging else { return false }
        requestDismiss(.swipe)
        if closeTransition.phase == .dragging { apply(closeTransition.springBack()) }
        return true
    }

    private func apply(_ effects: [PeekCloseTransition.Effect]) {
        for effect in effects {
            switch effect {
            case let .follow(fraction): view.followSwipe(fraction)
            case .haptic: NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
            case let .springBack(velocity):
                view.passesInput = false
                view.springBack(velocity: velocity)
            case let .exit(kind, _, velocity, generation):
                view.passesInput = true
                let duration = view.exit(kind, velocity: velocity)
                exitTimer?.invalidate()
                let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.apply(self.closeTransition.exitFinished(generation))
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                exitTimer = timer
            case .requestClose: requestPageClose()
            case .vanish:
                view.passesInput = true
                view.vanish()
            case .reappear:
                view.passesInput = false
                view.reappear()
            case .settle:
                view.passesInput = false
                view.settleSwipe()
            }
        }
    }

    func requestDismiss(_ mechanism: Dismissal) {
        guard !finished, !closePending, canInteract?() == true,
              let window = view.window, window.attachedSheet == nil else { return }
        let mediaInput = browser.captureState.map { $0.camera || $0.microphone } ?? false
        if let reason = dismissConfirmation.request(mechanism, mediaInput: mediaInput, onExpiry: { [weak self] in
                self?.view.confirmationTitle = nil
                self?.onUpdate?()
            }) {
            let hangUp = reason == .mediaInput && !returnsPage
            view.confirmationTitle = hangUp ? "Hang up" : "Close"
            NSAccessibility.post(element: view, notification: .announcementRequested,
                userInfo: [.announcement: hangUp ? "Choose Hang up to close this Peek."
                    : reason == .mediaInput ? "Choose Close to close this Peek." : "Press Escape again or choose Close to close this Peek.",
                           .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            onUpdate?()
            return
        }
        closeAfterConfirmation(exit: mechanism == .swipe ? .slide : .fade)
    }

    private func clearDismissConfirmation() {
        dismissConfirmation.cancel()
        view.confirmationTitle = nil
    }

    func closeWhileHidden() {
        guard !finished, !closePending, view.isHidden, !page.isClosed else { return }
        closeConfirmed()
    }

    private func closeAfterConfirmation(exit: PeekCloseTransition.Exit) {
        guard !finished, !closePending, canInteract?() == true, !page.isClosed else { return }
        clearDismissConfirmation()
        closeFocusReturn = PeekFocusReturn(source: view)
        closeConfirmed(exit: exit)
    }

    private func closeConfirmed(exit: PeekCloseTransition.Exit = .fade) {
        closePending = true; dismissedURL = browser.url
        dismissedNavigationState = page.responds(to: #selector(PCNativePage.captureNavigationState))
            ? page.captureNavigationState() : nil
        refresh()
        observeSheets()
        let effects = closeTransition.close(visible: !view.isHidden && view.window != nil, exit: exit)
        if effects.isEmpty { requestPageClose() } else { apply(effects) }
        if closePending { onUpdate?() }
    }

    private func requestPageClose() {
        exitTimer?.invalidate(); exitTimer = nil
        guard !finished, closePending, !closeInFlight, !page.isClosed else { return }
        if returnsPage {
            if let onReturn { onReturn() } else { refuseClose() }
            return
        }
        closeInFlight = true
        browser.requestClose { [weak self] result in
            guard let self, !self.finished else { return }
            self.closeInFlight = false
            if result == .closed {
                self.closePending = false
                self.stopObservingSheets()
                self.onClose?()
            } else {
                self.dismissedURL = nil; self.dismissedNavigationState = nil
                self.refuseClose()
            }
        }
    }

    func refuseClose() {
        guard !finished, closePending else { return }
        closePending = false
        stopObservingSheets()
        apply(closeTransition.refused(visible: !view.isHidden))
        let focusReturn = takeFocusReturn()
        publishPresentationIfChanged()
        restoreFocusAfterRefusal(focusReturn)
        onCloseRefused?()
    }

    func handBackBrowser() {
        guard returnsPage else { return }
        failure.pageView = nil
    }

    func playHandoffExit() -> TimeInterval {
        guard !finished else { return 0 }
        exitTimer?.invalidate(); exitTimer = nil
        removeSwipeMonitor()
        clearDismissConfirmation()
        view.passesInput = true
        return view.exit(.fade, velocity: 0)
    }

    private func observeSheets() {
        guard sheetObserver == nil, let window = view.window else { return }
        sheetObserver = NotificationCenter.default.addObserver(forName: NSWindow.willBeginSheetNotification, object: window,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.finished else { return }
                self.apply(self.closeTransition.sheetBegan(visible: !self.view.isHidden))
            }
        }
    }

    private func stopObservingSheets() {
        if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) }
        sheetObserver = nil
    }

    func takeFocusReturn() -> PeekFocusReturn? {
        let result = closeFocusReturn ?? PeekFocusReturn(source: view)
        closeFocusReturn = nil
        return result
    }

    private var canFocus: Bool {
        guard !finished, !closePending, !view.isHidden, canInteract?() == true,
              let window = view.window else { return false }
        return PCNativeBrowserApplication.canUseWindowUndo(in: window)
    }

    func focus() {
        guard canFocus else { return }
        if case .renderer(let crash)? = failure.presentation { _ = failure.focusRendererAction(crash) }
        else { _ = PCNativeBrowserApplication.owner(of: page)?.requestFocus(for: page) }
    }

    private func restoreFocusAfterRefusal(_ focusReturn: PeekFocusReturn?) {
        guard let window = view.window else { return }
        focusReturn?.perform(in: window, ownerIsAvailable: { self.canFocus }) { [self] original in
            guard window.firstResponder !== original, let original = original as? NSView,
                  original.window === window, !original.isHiddenOrHasHiddenAncestor else { return }
            if original === page.nativeView || original.isDescendant(of: page.nativeView) {
                focus()
            } else if original === view || original.isDescendant(of: view) {
                _ = window.makeFirstResponder(original)
            }
        }
    }

    @discardableResult
    func refresh() -> Bool {
        guard !finished else { return false }
        let fingerprint = presentationFingerprint()
        if PeekPresentationSkip.shouldSkip(previous: lastPresentedFingerprint, next: fingerprint) {
            return false
        }
        lastPresentedFingerprint = fingerprint
        applyPresentation()
        return true
    }

    private func publishPresentationIfChanged() {
        if refresh() { onUpdate?() }
    }

    private func presentationFingerprint() -> String {
        let capture: String
        if let state = browser.captureState {
            capture = PeekPresentationSkip.captureToken(
                active: state.active, camera: state.camera, microphone: state.microphone,
                tab: state.tab, window: state.window, display: state.display,
                mirrored: state.mirrored, shared: state.shared)
        } else {
            capture = PeekPresentationSkip.captureToken(
                active: false, camera: false, microphone: false, tab: false,
                window: false, display: false, mirrored: false, shared: false)
        }
        let crash: String
        if let rendererCrash = browser.rendererCrash {
            crash = PeekPresentationSkip.crashToken(
                identity: ObjectIdentifier(rendererCrash),
                terminationStatus: Int(rendererCrash.terminationStatus),
                errorCode: Int(rendererCrash.errorCode))
        } else {
            crash = PeekPresentationSkip.crashToken(identity: nil, terminationStatus: 0, errorCode: 0)
        }
        return PeekPresentationSkip.fingerprint(
            title: PeekPresentationSkip.displayTitle(browserTitle: browser.title, urlHost: browser.url?.host),
            url: browser.url?.absoluteString ?? "",
            loading: browser.isLoading,
            canGoBack: browser.canGoBack,
            canGoForward: browser.canGoForward,
            closePending: closePending,
            canExpand: !closePending && canExpand?() == true,
            canSplit: !closePending && canSplit?() == true,
            capture: capture,
            crash: crash,
            favicon: PeekPresentationSkip.faviconToken(page.favicon?.tiffRepresentation))
    }

    private func applyPresentation() {
        view.title = PeekPresentationSkip.displayTitle(browserTitle: browser.title, urlHost: browser.url?.host)
        view.isBusy = closePending
        view.canExpand = !closePending && canExpand?() == true
        view.canSplit = !closePending && canSplit?() == true
        view.loadingIndicator.setLoading(browser.isLoading)
        if let crash = browser.rendererCrash {
            failure.showRendererFailure(RendererCrashPresentation(pageIdentifier: page.identifier,
                identity: crash, terminationStatus: Int(crash.terminationStatus), errorCode: Int(crash.errorCode)))
        } else if browser.isLoading || failure.presentation.map({ if case .renderer = $0 { return true }; return false }) == true {
            failure.clear()
        }
    }

    private func promote(split: Bool) {
        guard canRequestExit, canExpand?() == true, !split || canSplit?() == true else { return }
        onPromote?(split)
    }

    func finish() {
        guard !finished else { return }
        finished = true
        closeFocusReturn?.cancel(); closeFocusReturn = nil
        exitTimer?.invalidate(); exitTimer = nil
        stopObservingSheets()
        apply(closeTransition.finish())
        removeSwipeMonitor()
        if let reduceMotionObserver { NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver) }
        reduceMotionObserver = nil
        clearDismissConfirmation()
        view.onNativeCancel = nil
        view.loadingIndicator.reset()
        view.settleMotion(); view.removeFromSuperview()
        if browser.delegate === self { browser.delegate = nil }
        failure.pageView = nil
        onClose = nil; onCloseRefused = nil; onReturn = nil; onPromote = nil; onUpdate = nil; onMediaChange = nil; onContextImage = nil; canInteract = nil; canSplit = nil; canExpand = nil
    }

    private func installSwipeMonitor() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self, !self.view.isHidden, event.window === self.view.window,
                      self.canInteract?() == true, self.view.window?.attachedSheet == nil,
                      self.contains(event), event.deltaX > 0,
                      abs(event.deltaX) > abs(event.deltaY) else { return false }
                self.requestDismiss(.swipe)
                return true
            }
            return consumed ? nil : event
        }
    }
    private func removeSwipeMonitor() { if let swipeMonitor { NSEvent.removeMonitor(swipeMonitor) }; swipeMonitor = nil }
    func browserView(_ view: PCBrowserView, addContextImageToEasel image: PCNativeContextImage) { onContextImage?(image) }
    func browserViewDidRequestClose(_ view: PCBrowserView) { if view === browser, page.isClosed { onClose?() } }
    func browserView(_ view: PCBrowserView, didChangeTitle title: String) { publishPresentationIfChanged() }
    func browserView(_ view: PCBrowserView, didChangeURL url: URL) { publishPresentationIfChanged() }
    func browserView(_ view: PCBrowserView, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) { publishPresentationIfChanged() }
    func browserView(_ view: PCBrowserView, didChangeCaptureState state: PCNativeCaptureState?) { publishPresentationIfChanged() }
    func browserView(_ view: PCBrowserView, didChangeRendererCrash crash: PCNativeRendererCrash?) { publishPresentationIfChanged() }
    func browserViewDidChangeMedia(_ view: PCBrowserView) { if view === browser { onMediaChange?() } }
    func browserViewDidChangePageColor(_ view: PCBrowserView) {
        guard view === browser, !self.view.browserToolbar.isHidden else { return }
        self.view.browserToolbar.showPageColor(of: page, failing: showsFailure)
    }
    func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) { refresh(); focus() }
    func browserViewDidChangeFavicon(_ view: PCBrowserView) { publishPresentationIfChanged() }
    func browserView(_ view: PCBrowserView, didLearnSafariIdentityForSite site: String,
                     profilePath: String, offTheRecord: Bool) {
        FairPlayIdentityController.shared.didLearn(site, profilePath: profilePath, offTheRecord: offTheRecord)
    }
    func browserView(_ view: PCBrowserView, didFailWithError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled, browser.rendererCrash == nil else { return }
        failure.showNavigationFailure(error.localizedDescription)
        browserViewDidChangePageColor(view)
    }
}

@MainActor
final class PeekHostView: NSView {
    private(set) var toastContentRect = NSRect.zero
    var onNativeCancel: (() -> Bool)?
    override func cancelOperation(_ sender: Any?) {
        if onNativeCancel?() != true { super.cancelOperation(sender) }
    }
    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let window, window.firstResponder === self else { super.keyDown(with: event); return }
        func descendants(of view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants(of: $0) } }
        func outside(_ view: NSView?) -> NSView? {
            view.flatMap { $0.window === window && !$0.isDescendant(of: self) ? $0 : nil }
        }
        let members = descendants(of: self)
        if event.modifierFlags.contains(.shift) {
            if let exit = members.lazy.compactMap({ member in
                outside(member.nextKeyView).flatMap { $0.previousKeyView === member ? $0 : nil }
            }).first { window.selectKeyView(preceding: exit); return }
        } else if let entry = members.lazy.compactMap({ member in
            outside(member.previousKeyView).flatMap { $0.nextKeyView === member ? $0 : nil }
        }).first { window.selectKeyView(following: entry); return }
        super.keyDown(with: event)
    }
    let content = LayoutView()
    let developerToolbar = DeveloperToolbarView()
    let browserToolbar = BrowserToolbarView()
    let loadingIndicator = PageLoadingIndicator()
    private let backdrop = ThemeRendererView()
    private let stage = LayoutView()
    private lazy var swipe = PeekDismissalAnimator(stage: stage, wash: backdrop, restingWash: PeekCardAppearance.backdropOpacity)
    private let cardEdge = LayoutView()
    private let edgeLayer = CALayer()
    private let card = LayoutView()
    private let controls = LayoutView()
    private let closeButton = PeekControlButton(symbol: "xmark")
    private let expandButton = PeekControlButton(symbol: "arrow.up.left.and.arrow.down.right")
    private let splitButton = PeekControlButton(symbol: "square.split.2x1")
    private var controlColors = PeekControlColors(fill: .controlBackgroundColor, accent: .labelColor)
    private var backdropOrigin: NSPoint?
    private static let cornerRadius: CGFloat = 8
    private static let controlSpacing: CGFloat = 9
    private static let controlTopInset: CGFloat = 7
    var palette = ThemeChromePalette(theme: SpaceTheme(), isDark: false) {
        didSet { if palette != oldValue { applyPalette() } }
    }
    var confirmationTitle: String? {
        didSet {
            guard oldValue != confirmationTitle else { return }
            refreshCloseButton()
            closeButton.setAccessibilityLabel(confirmationTitle ?? "Close Peek")
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }
    var onClose: (() -> Void)?
    var onExpand: (() -> Void)?
    var onSplit: (() -> Void)?
    var onBackground: (() -> Void)?
    var onLayout: (() -> Void)?
    var title = "Peek" { didSet { setAccessibilityLabel("Peek: " + title) } }
    var passesInput = false
    var isBusy = false { didSet { closeButton.isEnabled = !isBusy; expandButton.isEnabled = canExpand && !isBusy } }
    var canExpand = false { didSet { expandButton.isEnabled = canExpand && !isBusy } }
    var canSplit = false { didSet { splitButton.isEnabled = canSplit } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        backdrop.alphaValue = PeekCardAppearance.backdropOpacity
        cardEdge.wantsLayer = true
        cardEdge.layer?.addSublayer(edgeLayer)
        card.wantsLayer = true
        card.layer?.cornerRadius = Self.cornerRadius; card.layer?.masksToBounds = true
        for (button, name, id) in [(closeButton, "Close Peek", "closeTab:"), (expandButton, "Open Peek as Tab", "openInCurrentSpace:"),
                                   (splitButton, "Add Peek to Split View", nil)] as [(PeekControlButton, String, String?)] {
            LiveShortcutToolTip.set(button, name, commandID: id, anchor: .trailing)
            button.setAccessibilityLabel(name)
            controls.addSubview(button)
        }
        closeButton.actionBlock = { [weak self] in self?.onClose?() }
        expandButton.actionBlock = { [weak self] in self?.onExpand?() }
        splitButton.actionBlock = { [weak self] in self?.onSplit?() }
        stage.wantsLayer = true
        addSubview(backdrop); addSubview(stage)
        stage.addSubview(cardEdge); stage.addSubview(card); stage.addSubview(controls); stage.addSubview(loadingIndicator)
        card.addSubview(content)
        developerToolbar.isHidden = true; card.addSubview(developerToolbar)
        browserToolbar.isHidden = true; card.addSubview(browserToolbar)
        setAccessibilityRole(.group); setAccessibilityLabel("Peek")
        applyPalette()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func adoptWindowTheme(_ source: ThemeRendererView) {
        if backdrop.coordinateSpace !== source { backdrop.coordinateSpace = source }
        backdrop.incognito = source.incognito
        backdrop.theme = source.theme
        palette = source.palette
    }

    private func applyPalette() {
        loadingIndicator.appearance = palette.contentAppearance
        let appearance = palette.contentAppearance ?? effectiveAppearance
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        card.layer?.backgroundColor = PeekCardAppearance.cardFill(dark: dark).cgColor
        controlColors = PeekControlColors(palette: palette)
        expandButton.setContent(symbol: "arrow.up.left.and.arrow.down.right", text: nil, colors: controlColors)
        splitButton.setContent(symbol: "square.split.2x1", text: nil, colors: controlColors)
        refreshCloseButton()
    }

    private func refreshCloseButton() {
        closeButton.setContent(symbol: confirmationTitle == "Hang up" ? "phone.down.fill" : "xmark", text: confirmationTitle,
                               colors: confirmationTitle == nil ? controlColors : .confirmation)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !passesInput, let hit = super.hitTest(point) else { return nil }
        return hit === cardEdge || hit === stage || hit === backdrop || hit.isDescendant(of: backdrop) ? self : hit
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        stage.frame = bounds
        let origin = convert(bounds.origin, to: nil)
        if backdropOrigin != origin { backdropOrigin = origin; backdrop.invalidateCoordinates() }
        let frame = DeveloperChromeGeometry.peekCard(in: bounds)
        swipe.geometry = PeekDismissalMotion.Geometry(paneWidth: bounds.width, cardMinX: frame.minX)
        swipe.apply()
        card.frame = frame
        cardEdge.frame = frame.insetBy(dx: -0.5, dy: -0.5)
        layoutCardEdge()
        let loaderWidth = min(PageLoadingIndicator.size.width, frame.width), loaderHeight = PageLoadingIndicator.size.height
        loadingIndicator.frame = backingAlignedRect(NSRect(x: frame.midX - loaderWidth / 2, y: (frame.minY - loaderHeight) / 2,
                                                           width: loaderWidth, height: loaderHeight), options: .alignAllEdgesNearest)
        toastContentRect = frame
        let developerHeight: CGFloat = developerToolbar.isHidden ? 0 : DeveloperToolbarLayout.height
        developerToolbar.frame = NSRect(x: 0, y: 0, width: frame.width, height: developerHeight)
        let toolbarHeight: CGFloat = browserToolbar.isHidden ? 0 : BrowserToolbarView.height
        browserToolbar.frame = NSRect(x: 0, y: 0, width: frame.width, height: toolbarHeight)
        let stripHeight = max(developerHeight, toolbarHeight)
        content.frame = NSRect(x: 0, y: stripHeight, width: frame.width, height: max(0, frame.height - stripHeight))
        layoutControls(beside: frame)
        onLayout?()
    }

    private func layoutCardEdge() {
        let radius = Self.cornerRadius
        CATransaction.begin(); CATransaction.setDisableActions(true)
        edgeLayer.frame = cardEdge.bounds
        edgeLayer.cornerRadius = radius
        edgeLayer.backgroundColor = NSColor.white.cgColor
        edgeLayer.borderWidth = PeekCardAppearance.borderWidth
        edgeLayer.borderColor = PeekCardAppearance.borderColor.cgColor
        edgeLayer.shadowColor = NSColor.black.cgColor
        edgeLayer.shadowOpacity = PeekCardAppearance.shadowOpacity
        edgeLayer.shadowRadius = PeekCardAppearance.shadowRadius
        edgeLayer.shadowOffset = CGSize(width: 0, height: edgeLayer.contentsAreFlipped() ? 1 : -1)
        edgeLayer.shadowPath = CGPath(roundedRect: edgeLayer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.commit()
    }

    private func layoutControls(beside card: NSRect) {
        let size = PeekControlButton.diameter
        let x = card.maxX + DeveloperChromeGeometry.peekControlGap
        let closeWidth = min(closeButton.preferredWidth, max(size, bounds.width - x - 4))
        let buttons = [closeButton, expandButton, splitButton]
        controls.frame = NSRect(x: x, y: card.minY + Self.controlTopInset, width: max(size, closeWidth),
                                height: CGFloat(buttons.count) * size + CGFloat(buttons.count - 1) * Self.controlSpacing)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 0, y: CGFloat(index) * (size + Self.controlSpacing),
                                  width: button === closeButton ? closeWidth : size, height: size)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !card.frame.contains(point) && !controls.frame.contains(point) { onBackground?() }
    }
    func animatePresentation() {
        settleMotion()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0; opacity.toValue = 1; opacity.duration = 0.3
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(opacity, forKey: "parc.peek.opacity")
    }
    func settleMotion() {
        layer?.removeAnimation(forKey: "parc.peek.opacity")
        [closeButton, expandButton, splitButton].forEach { $0.settleMotion() }
        swipe.complete()
    }
    var swipeIsAtRest: Bool { swipe.isAtRest }
    func beginSwipe() { swipe.begin() }
    func followSwipe(_ fraction: Double) { swipe.follow(fraction) }
    func springBack(velocity: Double) { swipe.springBack(velocity: velocity) }
    func exit(_ kind: PeekCloseTransition.Exit, velocity: Double) -> TimeInterval { swipe.exit(kind, velocity: velocity) }
    func reappear() { swipe.reappear() }
    func vanish() { swipe.vanish() }
    func settleSwipe() { swipe.settle() }
}

extension PeekHostView: ParcToastAnchoring {}
