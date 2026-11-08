import AppKit
import QuartzCore

/// An unsaved, original native page. The BrowserWindowController owns the
/// parent relation; neither this view nor promotion reconstructs a navigation.
@MainActor
final class PeekController: NSObject, PCBrowserViewDelegate {
    let identity = UUID()
    let parentTabID: UUID
    let sourceSpaceID: UUID
    let parentPage: PCNativePage
    let page: PCNativePage
    let browser: PCBrowserView
    let view = PeekHostView()
    private let failure = PageFailureView()
    /// A navigation failure or renderer crash covers the page.
    var showsFailure: Bool { failure.presentation != nil }
    private var swipeMonitor: Any?
    private var reduceMotionObserver: NSObjectProtocol?
    private let dismissConfirmation = PeekDismissalConfirmation()
    private var closeFocusReturn: PeekFocusReturn?
    private var finished = false
    private(set) var closePending = false
    /// Last Peek-visible presentation fingerprint applied by `refresh` /
    /// `publishPresentationIfChanged`. Identical title/URL/loading/capture/
    /// crash/favicon/chrome ticks are a true no-op.
    private var lastPresentedFingerprint: String?
    ///
    ///
    private(set) var dismissedURL: URL?
    /// That dismissal's back/forward entries, captured before the page closes.
    private(set) var dismissedNavigationState: NSObject?
    var onClose: (() -> Void)?
    /// The page refused a dismissal's close (its leave-page dialog).
    var onCloseRefused: (() -> Void)?
    var onPromote: ((Bool) -> Void)?
    var onUpdate: (() -> Void)?
    var onMediaChange: (() -> Void)?
    var onContextImage: ((PCNativeContextImage) -> Void)?
    var canInteract: (() -> Bool)?
    var canSplit: (() -> Bool)?
    var canExpand: (() -> Bool)?

    init(page: PCNativePage, parent: PCNativePage, parentTabID: UUID, sourceSpaceID: UUID) {
        self.page = page; parentPage = parent; self.parentTabID = parentTabID; self.sourceSpaceID = sourceSpaceID
        browser = PCBrowserView(frame: .zero, adoptingNativePage: page)
        super.init()
        browser.delegate = self
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
            // BrowserWindow.cancelOperation -> MainMenuAction.exit -> Exit(7),
            // distinct from a renderer Escape carrying its confirmation Bool.
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

    ///
    ///
    /// shows every control and awaiting confirmation leaves them ordinary.
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
        } else {
            removeSwipeMonitor()
            clearDismissConfirmation()
            closeFocusReturn?.cancel()
            view.settleMotion()
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
        // Existing native window-action admission also excludes a reserved
        // security surface even when it is not an attached AppKit sheet.
        return canPrepareExit && PCNativeBrowserApplication.canUseWindowUndo(in: window)
    }

    func rendererEscape(prefersConfirmation: Bool) {
        guard canHandleEscape else { return }
        requestDismiss(.escape(prefersConfirmation: prefersConfirmation))
    }

    func requestDismiss(_ mechanism: Dismissal) {
        guard !finished, !closePending, canInteract?() == true,
              let window = view.window, window.attachedSheet == nil else { return }
        //
        // phone.down.fill/Hang up configurations, keyed by the real dismissal
        // reason. Keep this confirmation in the modal controls, not a sheet.
        let mediaInput = browser.captureState.map { $0.camera || $0.microphone } ?? false
        if let reason = dismissConfirmation.request(mechanism, mediaInput: mediaInput, onExpiry: { [weak self] in
                // The original host's reset emits didFailToConfirmDismissal.
                // Return to the base control without closing or stealing focus.
                self?.view.confirmationTitle = nil
                self?.onUpdate?()
            }) {
            let mediaConfirmation = reason == .mediaInput
            view.confirmationTitle = mediaConfirmation ? "Hang up" : "Close"
            NSAccessibility.post(element: view, notification: .announcementRequested,
                userInfo: [.announcement: mediaConfirmation ? "Choose Hang up to close this Peek." : "Press Escape again or choose Close to close this Peek.",
                           .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            onUpdate?()
            return
        }
        closeAfterConfirmation()
    }

    private func clearDismissConfirmation() {
        dismissConfirmation.cancel()
        view.confirmationTitle = nil
    }

    /// The window closes this Peek while its parent isn't shown (Redo of
    /// Close Peek): the same page close and dismissal record as a user
    /// dismissal, without controls to confirm in or focus to return.
    func closeWhileHidden() {
        guard !finished, !closePending, view.isHidden, !page.isClosed else { return }
        closeConfirmed()
    }

    private func closeAfterConfirmation() {
        guard !finished, !closePending, canInteract?() == true, !page.isClosed else { return }
        clearDismissConfirmation()
        closeFocusReturn = PeekFocusReturn(source: view)
        closeConfirmed()
    }

    private func closeConfirmed() {
        closePending = true; dismissedURL = browser.url
        dismissedNavigationState = page.responds(to: #selector(PCNativePage.captureNavigationState))
            ? page.captureNavigationState() : nil
        refresh()
        browser.requestClose { [weak self] result in
            guard let self, !self.finished else { return }
            self.closePending = false
            if result == .closed { self.onClose?() }
            else {
                self.dismissedURL = nil; self.dismissedNavigationState = nil
                let focusReturn = self.takeFocusReturn()
                self.publishPresentationIfChanged()
                self.restoreFocusAfterRefusal(focusReturn)
                self.onCloseRefused?()
            }
        }
        // Owners observe the dismissal start and a refused close: the Favorite
        //
        if closePending { onUpdate?() }
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
            // Refusal keeps the actual control or renderer editor if it still
            // owns focus. It must not reset selection/composition to page root.
            guard window.firstResponder !== original, let original = original as? NSView,
                  original.window === window, !original.isHiddenOrHasHiddenAncestor else { return }
            if original === page.nativeView || original.isDescendant(of: page.nativeView) {
                focus()
            } else if original === view || original.isDescendant(of: view) {
                _ = window.makeFirstResponder(original)
            }
        }
    }

    /// Applies Peek chrome from the live browser/page. Returns false when the
    /// Peek-visible presentation fingerprint already matches the last apply —
    /// a true no-op that must not fan into the window `onUpdate` bridge.
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

    /// Refresh + window notify only when Peek-visible bits changed. Dismissal
    /// confirmation / modal-phase `onUpdate` paths stay ungated.
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

    /// After actual close, or after the same wrapper was transferred to a saved
    /// pane. This is presentation teardown, never a second page-close route.
    func finish() {
        guard !finished else { return }
        finished = true
        closeFocusReturn?.cancel(); closeFocusReturn = nil
        removeSwipeMonitor()
        if let reduceMotionObserver { NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver) }
        reduceMotionObserver = nil
        clearDismissConfirmation()
        view.onNativeCancel = nil
        view.loadingIndicator.reset()
        view.settleMotion(); view.removeFromSuperview()
        if browser.delegate === self { browser.delegate = nil }
        failure.pageView = nil
        onClose = nil; onCloseRefused = nil; onPromote = nil; onUpdate = nil; onMediaChange = nil; onContextImage = nil; canInteract = nil; canSplit = nil; canExpand = nil
    }

    private func installSwipeMonitor() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self, !self.view.isHidden, event.window === self.view.window,
                      self.canInteract?() == true, self.view.window?.attachedSheet == nil,
                      self.contains(event), event.deltaX > 0,
                      abs(event.deltaX) > abs(event.deltaY) else { return false }
                // Only completed AppKit swipe remains a shell input adaptation.
                // Renderer Escape is delivered by the exact native ACK owner.
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
    /// Peek's own chrome shows no media; the window's Mini Player does.
    func browserViewDidChangeMedia(_ view: PCBrowserView) { if view === browser { onMediaChange?() } }
    /// The Peek bar alone, as the window repaints a pane's.
    func browserViewDidChangePageColor(_ view: PCBrowserView) {
        guard view === browser, !self.view.browserToolbar.isHidden else { return }
        self.view.browserToolbar.showPageColor(of: page, failing: showsFailure)
    }
    func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) { refresh(); focus() }
    /// A loaded icon arrives only as a favicon-only change; the owner's
    /// Favorite tile badge shows this Peek's live favicon (BR-03).
    func browserViewDidChangeFavicon(_ view: PCBrowserView) { publishPresentationIfChanged() }
    /// The engine learned a FairPlay site for Safari's identity (docs/fairplay-identity.md).
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
    ///
    ///
    private(set) var toastContentRect = NSRect.zero
    var onNativeCancel: (() -> Bool)?
    override func cancelOperation(_ sender: Any?) {
        if onNativeCancel?() != true { super.cancelOperation(sender) }
    }
    /// The host takes first responder for Escape only and is no key view
    /// (WindowKeyViewLoop `passesThrough`), so no link leads on from it. Tab
    /// and Shift-Tab from the host enter the window loop where it crosses into
    /// the Peek: its first key view here, or its last going backward, keeping
    /// AppKit's selection direction for the page's renderer.
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
    ///
    ///
    let loadingIndicator = PageLoadingIndicator()
    private let chrome = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let controls = NSStackView()
    private let closeButton = ActionButton("", symbol: "xmark")
    private let expandButton = ActionButton("", symbol: "arrow.up.left.and.arrow.down.right")
    private var closeWidth: NSLayoutConstraint?
    var confirmationTitle: String? {
        didSet {
            let previous = closeButton.layer?.presentation()?.bounds ?? closeButton.layer?.bounds
            closeButton.title = confirmationTitle ?? ""
            closeButton.imagePosition = confirmationTitle == nil ? .imageOnly : .imageLeading
            closeButton.image = NSImage(systemSymbolName: confirmationTitle == "Hang up" ? "phone.down.fill" : "xmark", accessibilityDescription: nil)
            closeButton.setAccessibilityLabel(confirmationTitle ?? "Close Peek")
            needsLayout = true
            layoutSubtreeIfNeeded(); controls.layoutSubtreeIfNeeded()
            guard oldValue != confirmationTitle, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                  let previous, let layer = closeButton.layer else { return }
            // Recovered control-state spring, distinct from modal presentation.
            let animation = CASpringAnimation(keyPath: "bounds")
            let frequency = 2 * Double.pi / 0.25
            animation.mass = 1; animation.stiffness = frequency * frequency
            animation.damping = 2 * 0.8 * frequency
            animation.fromValue = NSValue(rect: previous); animation.toValue = NSValue(rect: layer.bounds)
            animation.duration = animation.settlingDuration
            layer.add(animation, forKey: "parc.peek.confirmation")
        }
    }
    private let splitButton = ActionButton("", symbol: "rectangle.split.2x1")
    var onClose: (() -> Void)?
    var onExpand: (() -> Void)?
    var onSplit: (() -> Void)?
    var onBackground: (() -> Void)?
    var onLayout: (() -> Void)?
    var title = "Peek" { didSet { titleLabel.stringValue = title; setAccessibilityLabel("Peek: " + title) } }
    var isBusy = false { didSet { closeButton.isEnabled = !isBusy; expandButton.isEnabled = canExpand && !isBusy } }
    var canExpand = false { didSet { expandButton.isEnabled = canExpand && !isBusy } }
    var canSplit = false { didSet { splitButton.isEnabled = canSplit } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        content.wantsLayer = true
        content.layer?.cornerRadius = 12; content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        chrome.material = .popover; chrome.blendingMode = .withinWindow; chrome.state = .active
        chrome.wantsLayer = true; chrome.layer?.cornerRadius = 12
        chrome.shadow = NSShadow(); chrome.shadow?.shadowBlurRadius = 18
        chrome.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.22)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor; titleLabel.lineBreakMode = .byTruncatingTail
        controls.orientation = .vertical; controls.spacing = 7; controls.alignment = .leading
        // ModalV2KeyBindings: close carries archiveTab's live binding and
        //
        // same original page and current window destination.
        for (button, name, id) in [(closeButton, "Close Peek", "closeTab:"), (expandButton, "Open Peek as Tab", "openInCurrentSpace:"),
                                   (splitButton, "Add Peek to Split View", nil)] as [(NSButton, String, String?)] {
            LiveShortcutToolTip.set(button, name, commandID: id); button.setAccessibilityLabel(name)
            button.focusRingType = .default
            button.contentTintColor = .labelColor; button.wantsLayer = true
            button.layer?.cornerRadius = 16; button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
            controls.addArrangedSubview(button)
            let width = button.widthAnchor.constraint(equalToConstant: 32); width.isActive = true
            if button === closeButton { closeWidth = width }
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }
        closeButton.actionBlock = { [weak self] in self?.onClose?() }
        expandButton.actionBlock = { [weak self] in self?.onExpand?() }
        splitButton.actionBlock = { [weak self] in self?.onSplit?() }
        addSubview(chrome); addSubview(content); addSubview(controls); addSubview(titleLabel); addSubview(loadingIndicator)
        developerToolbar.isHidden = true; addSubview(developerToolbar)
        browserToolbar.isHidden = true; addSubview(browserToolbar)
        setAccessibilityRole(.group); setAccessibilityLabel("Peek")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        //
        // content-width ratio and 12-point vertical inset. Clamp adapts tiny
        // Parc windows; the title band and 12-point radius remain adaptations.
        let width = min(max(0, bounds.width - 80), bounds.width * 0.8)
        let card = NSRect(x: (bounds.width - width) / 2, y: 12, width: width, height: max(0, bounds.height - 24))
        chrome.frame = card
        //
        // card and in the inset above it, backing-aligned.
        let loaderWidth = min(PageLoadingIndicator.size.width, width), loaderHeight = PageLoadingIndicator.size.height
        loadingIndicator.frame = backingAlignedRect(NSRect(x: card.midX - loaderWidth / 2, y: (card.minY - loaderHeight) / 2,
                                                           width: loaderWidth, height: loaderHeight), options: .alignAllEdgesNearest)
        toastContentRect = NSRect(x: card.minX, y: card.minY + 30, width: width, height: max(0, card.height - 30))
        titleLabel.frame = NSRect(x: card.minX + 12, y: card.minY + 6, width: max(0, width - 24), height: 18)
        let developerHeight: CGFloat = developerToolbar.isHidden ? 0 : DeveloperToolbarLayout.height
        developerToolbar.frame = NSRect(x: card.minX, y: card.minY + 30, width: width, height: developerHeight)
        let toolbarHeight: CGFloat = browserToolbar.isHidden ? 0 : BrowserToolbarView.height
        browserToolbar.frame = NSRect(x: card.minX, y: card.minY + 30, width: width, height: toolbarHeight)
        let stripHeight = max(developerHeight, toolbarHeight)
        content.frame = NSRect(x: card.minX, y: card.minY + 30 + stripHeight, width: width, height: max(0, card.height - 30 - stripHeight))
        let controlsWidth: CGFloat = confirmationTitle == nil ? 32 : min(110, max(32, card.minX - 10))
        closeWidth?.constant = controlsWidth
        controls.frame = NSRect(x: max(2, card.minX - controlsWidth - 8), y: card.minY + 6, width: controlsWidth, height: 110)
        onLayout?()
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !chrome.frame.contains(point) && !controls.frame.contains(point) { onBackground?() }
    }
    func animatePresentation() {
        settleMotion()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        //
        //
        // ease-out, from 0 as the host appears. It never resizes Chromium per frame.
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0; opacity.toValue = 1; opacity.duration = 0.3
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(opacity, forKey: "parc.peek.opacity")
    }
    func settleMotion() {
        layer?.removeAnimation(forKey: "parc.peek.opacity")
        closeButton.layer?.removeAnimation(forKey: "parc.peek.confirmation")
    }
}

extension PeekHostView: PArcToastAnchoring {}
