import AppKit

// Document Picture-in-Picture (`documentPictureInPicture.requestWindow`, as
// Google Meet uses) opens its page in a Chromium browser of the PiP type. The
//
//
// (PictureInPictureFrame) with a 48 pt bar holding Back to Tab and Close above
//
// resize requests and its closing.
@MainActor
final class PictureInPictureWindowController: NSWindowController, NSWindowDelegate,
                                              PCNativeBrowserWindowClient, PCNativePageObserver {
    var onClose: (() -> Void)?
    private let profilePath: String
    private let root = PictureInPictureFrameView()
    private let container = PictureInPictureContainerView()
    private let sidePanel = NSView()
    private let topBar = DocumentPictureInPictureTopBar()
    private let motion: PictureInPictureMotion
    private var binding: PCNativeBrowserWindow?
    private var page: PCNativePage?
    private var closePending = false
    private var closeApproved = false
    private var closed = false
    private var synchronizing = false

    init(request: PCNativeWindowRequest) throws {
        profilePath = request.profilePath
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if request.canResize { style.insert(.resizable) }
        let window = PictureInPicturePanel(contentRect: NSRect(x: 0, y: 0, width: 480,
                                                               height: DocumentPictureInPictureLayout.windowHeight(forPage: 270)),
                                           styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.tabbingMode = .disallowed
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Registration requires the side-panel container inside this window;
        // as the Developer Tools window does, it stays hidden beside the page.
        root.frame = NSRect(origin: .zero, size: window.frame.size)
        container.frame = DocumentPictureInPictureLayout.pageFrame(in: root.bounds)
        container.autoresizingMask = [.width, .height]
        sidePanel.isHidden = true
        topBar.frame = DocumentPictureInPictureLayout.topBarFrame(in: root.bounds)
        topBar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(container)
        root.addSubview(sidePanel)
        root.addSubview(topBar)
        window.contentView = root
        motion = PictureInPictureMotion(window: window)
        super.init(window: window)
        window.delegate = self
        // Chromium attaches the page after it has the container.
        container.onAttach = { [weak self] in self?.presentIfReady() }
        topBar.onReturnToTab = { [weak self] in self?.returnToTab() }
        topBar.onClose = { [weak self] in self?.requestUserClose() }
        topBar.motion = motion
        if request.canResize {
            topBar.onToggleMaximize = { [weak self] in self?.motion.toggleLargest() }
            root.addGestureRecognizer(NSMagnificationGestureRecognizer(
                target: motion, action: #selector(PictureInPictureMotion.magnify(_:))))
        }
        // Chromium sizes the page it asked for; the bar sits above it.
        let screen = request.source?.window?.screen ?? NSScreen.main
        var frame = window.frame
        if request.initialFrame.width > 0 { frame.size.width = request.initialFrame.width }
        if request.initialFrame.height > 0 {
            frame.size.height = DocumentPictureInPictureLayout.windowHeight(forPage: request.initialFrame.height)
        }
        if request.canResize { updateSizeLimits(on: screen) }
        frame.size.width = min(max(frame.width, window.minSize.width), window.maxSize.width)
        frame.size.height = min(max(frame.height, window.minSize.height), window.maxSize.height)
        if request.initialOriginSpecified {
            frame.origin = NSPoint(x: request.initialFrame.minX, y: request.initialFrame.maxY - frame.height)
        } else if let area = screen?.visibleFrame {
            frame.origin = NSPoint(x: area.maxX - frame.width - 16, y: area.minY + 16)
        }
        window.setFrame(PictureInPictureFrame.constrain(frame, to: screen), display: false)
        do {
            binding = try PCNativeBrowserApplication.register(self)
            if request.isOffTheRecord { try binding?.adoptPrivateContext(request: request) }
        } catch {
            window.delegate = nil
            window.close()
            throw error
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func nativeBrowserWindow() -> NSWindow { window! }
    func selectedNativePage() -> PCNativePage? { page?.isClosed == false ? page : nil }
    func visibleNativePages() -> [PCNativePage] {
        guard let page, !page.isClosed, window?.isVisible == true else { return [] }
        return [page]
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, containerFor incoming: PCNativePage,
                       disposition: PCNativePageDisposition) -> NSView? {
        guard browser === binding, !closed, !closePending, !closeApproved,
              !incoming.isClosed, incoming.profilePath == profilePath,
              let window, container.window === window,
              PCNativeBrowserApplication.owner(of: incoming) === browser else { return nil }
        if let page { return page === incoming ? container : nil }
        guard incoming.observer == nil || incoming.observer === self else { return nil }
        page = incoming
        incoming.observer = self
        updateTitle()
        return container
    }

    private func pageIsAttached() -> Bool {
        guard !closed, !closePending, !closeApproved, let page, !page.isClosed, let binding, let window,
              PCNativeBrowserApplication.owner(of: page) === binding,
              page.nativeView.window === window, page.nativeView.isDescendant(of: container) else { return false }
        return true
    }

    /// Shown without focus; the panel becomes key only when clicked.
    private func presentIfReady() {
        guard pageIsAttached(), let window else { return }
        topBar.showsReturnToTab = binding?.canReturnPictureInPictureToOpener ?? false
        if !window.isVisible { window.orderFront(nil) }
        synchronizeLayout(selectPage: true)
    }

    private func updateTitle() {
        guard let page, !page.isClosed else { return }
        window?.title = page.title.isEmpty ? (page.url?.host ?? "Picture in Picture") : page.title
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, didSelect incoming: PCNativePage) {
        guard browser === binding, page === incoming else { return }
        presentIfReady()
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, didClose incoming: PCNativePage) {
        guard browser === binding, page === incoming else { return }
        releasePage(incoming)
    }
    func nativePageDidClose(_ incoming: PCNativePage) {
        guard page === incoming else { return }
        releasePage(incoming)
    }
    func nativePageDidChange(_ incoming: PCNativePage) {
        guard page === incoming, !closed else { return }
        updateTitle()
        synchronizeLayout()
        if window?.isVisible != true { presentIfReady() }
    }
    func nativePage(_ incoming: PCNativePage, didFailWithError error: Error) {
        guard page === incoming else { return }
        NSLog("Parc Picture in Picture page: %@", error.localizedDescription)
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, didFailWithError error: Error) {
        guard browser === binding else { return }
        NSLog("Parc Picture in Picture window: %@", error.localizedDescription)
    }
    private func releasePage(_ incoming: PCNativePage) {
        if incoming.observer === self { incoming.observer = nil }
        page = nil
    }

    // Chromium releases the shell only after its last Browser unregisters.
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

    /// The panel has no close button, so ⌘W and the close control ask here.
    func requestUserClose() {
        guard let window, windowShouldClose(window) else { return }
        window.close()
    }

    private func returnToTab() {
        guard !closed, !closePending, !closeApproved, let binding else { return }
        if !binding.returnPictureInPictureToOpener() { requestUserClose() }
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
        // A click on Close or Back to Tab closes the panel under the pointer.
        topBar.endHover()
        if let page { releasePage(page) }
        container.onAttach = nil
        motion.stop()
        window?.delegate = nil
        binding = nil
        let completion = onClose
        onClose = nil
        completion?()
    }
    func windowDidBecomeKey(_ notification: Notification) { synchronizeLayout(selectPage: true) }
    func windowDidChangeOcclusionState(_ notification: Notification) { synchronizeLayout() }
    func windowDidResize(_ notification: Notification) {
        synchronizeLayout()
        if window?.inLiveResize == false { window?.invalidateShadow() }
    }
    func windowWillStartLiveResize(_ notification: Notification) { motion.stop() }
    func windowDidEndLiveResize(_ notification: Notification) { window?.invalidateShadow() }
    func windowDidChangeScreen(_ notification: Notification) {
        guard let window, window.styleMask.contains(.resizable) else { return }
        updateSizeLimits(on: window.screen)
    }

    ///
    /// and grows to MovableWindow's screen-relative maximum, at any aspect.
    private func updateSizeLimits(on screen: NSScreen?) {
        guard let window else { return }
        let minimum = DocumentPictureInPictureLayout.minimumSize
        window.minSize = minimum
        window.maxSize = PictureInPictureFrame.maximumSize(on: screen, minimum: minimum)
    }

    private func synchronizeLayout(selectPage: Bool = false) {
        guard !closed, !synchronizing else { return }
        synchronizing = true
        defer { synchronizing = false }
        if selectPage { binding?.synchronizeSelectionAndLayout() } else { binding?.synchronizeLayout() }
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, rotateFocusForward forward: Bool) -> Bool {
        guard browser === binding, let window else { return false }
        let before = window.firstResponder
        if forward { window.selectNextKeyView(nil) } else { window.selectPreviousKeyView(nil) }
        return window.firstResponder !== before
    }

    // A PiP window has no address bar, tab search, Profiles, bookmarks or side panel.
    func nativeBrowserFocusAddress(_ browser: PCNativeBrowserWindow) {}
    func nativeBrowserShowTabSearch(_ browser: PCNativeBrowserWindow) {}
    func nativeBrowserCloseTabSearch(_ browser: PCNativeBrowserWindow) {}
    func nativeBrowserShowProfiles(_ browser: PCNativeBrowserWindow) {}
    func nativeBrowser(_ browser: PCNativeBrowserWindow, bookmarkURL url: URL) {}
    func nativeBrowserSidePanelContainer(_ browser: PCNativeBrowserWindow) -> NSView { sidePanel }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, setSidePanelVisible visible: Bool) -> Bool { !visible }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, setTabFullscreenPage incoming: PCNativePage?) -> Bool {
        guard browser === binding, !closed, !closePending else { return false }
        return incoming == nil || incoming === page
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, capabilityUnavailable capability: String) {
        guard browser === binding else { return }
        NSLog("Parc Picture in Picture: %@", capability)
    }
}

// Chromium shows PiP with makeKeyAndOrderFront, also when auto-PiP opens it
// while another app is frontmost; a non-activating panel would then take that
// app's typing. It becomes key only once clicked, and clicking it never
// activates Parc, so leaving and returning to Parc drive auto-PiP as for video.
@MainActor
private final class PictureInPicturePanel: NSPanel {
    private var clicked = false
    override var canBecomeKey: Bool { clicked }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: clicked = true
        default: break
        }
        super.sendEvent(event)
    }
    override func resignKey() {
        super.resignKey()
        clicked = false
    }
}

//
// the top 48 pt; the page fills the rest and runs a point under the bar and
// past the other three edges, so the frame's border, not a seam, meets it.
enum DocumentPictureInPictureLayout {
    static let topBarHeight: CGFloat = 48
    static let minimumSize = NSSize(width: 284, height: 246)
    static func topBarFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.minX, y: bounds.maxY - topBarHeight, width: bounds.width, height: topBarHeight)
    }
    static func pageFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.minX - 1, y: bounds.minY - 1, width: bounds.width + 2,
               height: max(0, bounds.height - topBarHeight + 2))
    }
    /// The window height that gives the page `height` points.
    static func windowHeight(forPage height: CGFloat) -> CGFloat { height + topBarHeight - 2 }
}

@MainActor
private final class PictureInPictureFrameView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        PictureInPictureFrame.style(layer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// DocumentPiPTopBarView: an opaque bar (DocumentPiPTopBarBackgroundColor)
// whose bottom hairline (DocumentPiPHairlineColor) covers the page's top
// point, Back to Tab 10 pt from the leading edge and Close 16 pt from the
//
// MovableWindow does; a double-click there toggles its largest size unless
// the system's title-bar double-click is set to do nothing or minimize
// (handleTopBarDoubleClick; a PiP has no Dock tile).
@MainActor
private final class DocumentPictureInPictureTopBar: NSView {
    private static let backInset: CGFloat = 10
    private static let closeInset: CGFloat = 16
    private static let background = NSColor(srgbRed: 0.129, green: 0.129, blue: 0.137, alpha: 1)
    private static let hairlineColor = NSColor(white: 1, alpha: 0.2)
    var onReturnToTab: (() -> Void)?
    var onClose: (() -> Void)?
    var onToggleMaximize: (() -> Void)?
    weak var motion: PictureInPictureMotion?
    var showsReturnToTab = true {
        didSet { back.isHidden = !showsReturnToTab }
    }
    private let back = PictureInPictureBackToTabButton()
    private let close = PictureInPictureCloseButton()
    private let hairline = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Self.background.cgColor
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Self.hairlineColor.cgColor
        back.perform = { [weak self] in self?.onReturnToTab?() }
        close.perform = { [weak self] in self?.onClose?() }
        addSubview(hairline)
        addSubview(back)
        addSubview(close)
        layoutControls()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutControls()
    }
    func endHover() {
        back.setHovering(false)
        close.setHovering(false)
    }
    private func layoutControls() {
        let pill = back.fittingSize
        back.frame = NSRect(x: Self.backInset, y: ((bounds.height - pill.height) / 2).rounded(),
                            width: pill.width, height: pill.height)
        //
        close.side = bounds.width < 400 ? 16 : 18
        close.frame = NSRect(x: bounds.width - Self.closeInset - close.side,
                             y: ((bounds.height - close.side) / 2).rounded(),
                             width: close.side, height: close.side)
        hairline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if let onToggleMaximize, Self.doubleClickZooms { onToggleMaximize() }
        } else {
            motion?.beginDrag(with: event)
        }
    }
    override func mouseDragged(with event: NSEvent) { motion?.drag(with: event) }
    override func mouseUp(with event: NSEvent) { motion?.endDrag(with: event) }
    // System Settings › Desktop & Dock › "Double-click a window's title bar to".
    private static var doubleClickZooms: Bool {
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        return action != "None" && action != "Minimize"
    }
}

// A bar control under the pointer: full opacity instead of 92.5%, 70% while
//
// and BackToTabButtonStyle). The panel is rarely key, so hover is tracked
// always and the cursor set on entering and leaving, also behind another
// app, rather than left to cursor rects, which apply only in the key window.
@MainActor
private class PictureInPictureBarControl: NSButton {
    static let easing = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
    var perform: (() -> Void)?
    private var tracking: NSTrackingArea?
    private(set) var hovering = false

    init(label: String) {
        super.init(frame: .zero)
        isBordered = false
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(activate)
        wantsLayer = true
        alphaValue = 0.925
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func activate() { perform?() }
    // The first click on an unfocused panel must press the control, not only focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }
    override func mouseDown(with event: NSEvent) {
        // The button tracks the press inside super until the mouse goes up.
        alphaValue = 0.7
        super.mouseDown(with: event)
        alphaValue = hovering ? 1 : 0.925
    }
    // Hidden or removed under the pointer, no exit comes.
    override func viewDidHide() {
        super.viewDidHide()
        setHovering(false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { setHovering(false) }
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != self.hovering else { return }
        self.hovering = hovering
        PCPictureInPicturePointAtControl(hovering)
        alphaValue = hovering ? 1 : 0.925
        hoverChanged()
    }
    func hoverChanged() {}

    func animate(_ keyPath: String, to value: Any, on layer: CALayer) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        animation.toValue = value
        animation.duration = 0.3
        animation.timingFunction = Self.easing
        layer.add(animation, forKey: keyPath)
        layer.setValue(value, forKeyPath: keyPath)
    }
}

// Back to Tab: the up-left arrow alone in a 26 pt circle, as the video PiP's;
// the circle fills white at 33% under the pointer (BackToTabButtonStyle
//
@MainActor
private final class PictureInPictureBackToTabButton: PictureInPictureBarControl {
    private static let side: CGFloat = 26

    init() {
        super.init(label: "Back to Tab")
        image = NSImage(systemSymbolName: "arrow.up.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
        imagePosition = .imageOnly
        contentTintColor = .white
        layer?.cornerRadius = Self.side / 2
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.side) }
    override func hoverChanged() {
        guard let layer else { return }
        animate("backgroundColor", to: NSColor(white: 1, alpha: hovering ? 0.33 : 0).cgColor, on: layer)
    }
}

// Close: a bare bold cross, growing to 110% about its centre under the
//
@MainActor
private final class PictureInPictureCloseButton: PictureInPictureBarControl {
    var side: CGFloat = 18 {
        didSet { if side != oldValue { updateImage() } }
    }

    init() {
        super.init(label: "Close")
        imagePosition = .imageOnly
        contentTintColor = .white
        updateImage()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateImage() {
        image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: side, weight: .bold))
    }
    override func hoverChanged() {
        guard let layer else { return }
        // AppKit anchors a view's layer at its origin; scale about the centre.
        let scale: CGFloat = hovering ? 1.1 : 1
        let dx = bounds.width * (0.5 - layer.anchorPoint.x)
        let dy = bounds.height * (0.5 - layer.anchorPoint.y)
        let transform = CATransform3DTranslate(
            CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), scale, scale, 1), -dx, -dy, 0)
        animate("transform", to: NSValue(caTransform3D: transform), on: layer)
    }
}

@MainActor
private final class PictureInPictureContainerView: NSView {
    var onAttach: (() -> Void)?
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        DispatchQueue.main.async { [weak self] in self?.onAttach?() }
    }
}
