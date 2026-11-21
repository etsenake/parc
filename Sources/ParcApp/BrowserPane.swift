import AppKit
import ParcEngine

final class PendingArrival {
    var ran = false
    private let abandoned: () -> Void
    init(abandoned: @escaping () -> Void) { self.abandoned = abandoned }
    deinit {
        guard !ran else { return }
        DispatchQueue.main.async(execute: abandoned)
    }
}

final class BrowserPane: NSView {
    let content = LayoutView()
    private(set) var loadedDeveloperToolbar: DeveloperToolbarView?
    var developerToolbar: DeveloperToolbarView {
        if let loadedDeveloperToolbar { return loadedDeveloperToolbar }
        let toolbar = DeveloperToolbarView()
        toolbar.isHidden = true
        addSubview(toolbar, positioned: .below, relativeTo: browserToolbar)
        loadedDeveloperToolbar = toolbar
        return toolbar
    }
    let browserToolbar = BrowserToolbarView()
    let windowGrabber = WebpageWindowGrabber()
    let debuggerWarning = DebuggerWarningStrip()
    private let controlVisibility = PaneControlVisibility()
    let splitHighlight = SplitPaneHighlight()
    var controlsFocused = true { didSet { needsLayout = true } }
    var controlsObstructed = false {
        didSet {
            guard oldValue != controlsObstructed else { return }
            browserToolbar.setObstructedByModal(controlsObstructed, animated: true); needsLayout = true
        }
    }
    func trackSplitMenu(_ body: () -> Void) { controlVisibility.trackMenu(body) }
    let error = PageFailureView()
    private var nativeContent: NSView?
    private(set) var showsBlank = false
    private(set) var showsNoteCanvas = false
    private(set) var showsTopBar = false
    private var noteCanvasContentAppearance: NSAppearance?
    private var noteCanvasFocus: NSColor?
    private weak var noteController: NotePageViewController?
    private var showsNoteController: Bool {
        guard let noteController, noteController.isViewLoaded else { return false }
        return nativeContent === noteController.view
    }
    var onContentBackingChange: (() -> Void)?
    private var pageBacking: NSColor?
    var contentBacking: NSColor { showsNoteCanvas ? .clear : (surface == .page ? pageBacking : nil) ?? .white }
    var heldOverSwitch = false {
        didSet {
            guard heldOverSwitch != oldValue else { return }
            HeldPaneLayout.apply(heldOverSwitch, to: self)
        }
    }
    var passesInput = false
    override func hitTest(_ point: NSPoint) -> NSView? { heldOverSwitch || passesInput ? nil : super.hitTest(point) }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        heldOverSwitch = false; passesInput = false; alphaValue = 1; super.viewWillMove(toSuperview: newSuperview)
    }
    func showPageBacking(of page: PCNativePage?) {
        let color = page.flatMap { page -> NSColor? in
            guard !page.isClosed, page.responds(to: #selector(getter: PCNativePage.pageBackgroundColor)) else { return nil }
            return PaneTopBarColor.fill(from: page.pageBackgroundColor)
        }
        guard color != pageBacking else { return }
        pageBacking = color
        applyContentBacking()
    }
    private func applyContentBacking() {
        let color = contentBacking.cgColor
        guard content.layer?.backgroundColor != color else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.layer?.backgroundColor = color
        CATransaction.commit()
        onContentBackingChange?()
    }
    let contentResize = PageContentResizer()
    var browser: PCBrowserView? { didSet { oldValue?.removeFromSuperview(); error.pageView = browser; if let browser { content.addSubview(browser); contentResize.place(browser, in: content) } } }
    private var surface = PaneSurface.page {
        didSet {
            guard surface != oldValue else { return }
            applyContentBacking()
            guard !browserToolbar.isHidden else { return }
            browserToolbar.showPageColor(of: livePage?.nativePage, failing: showsFailure)
        }
    }
    var livePage: PCBrowserView? {
        guard let browser, surface.usesPageBar(pageLive: browser.nativePage.map { !$0.isClosed } == true) else { return nil }
        return browser
    }
    var showsFailure: Bool { surface == .failure }
    var showsLocalContent: Bool { surface == .local }
    var onReload: (() -> Void)? { didSet { error.onReload = onReload } }
    var onRetryRenderer: ((RendererCrashPresentation) -> Void)? { didSet { error.onRetryRenderer = onRetryRenderer } }
    var onRendererPresented: ((RendererCrashPresentation) -> Bool)? { didSet { error.onRendererPresented = onRendererPresented } }
    var rendererPresentation: RendererCrashPresentation? {
        if case .renderer(let crash) = error.presentation { return crash }
        return nil
    }
    var rendererFailureOwnsFocus: Bool { rendererPresentation != nil && error.ownsFirstResponder }
    func focusRendererFailure(_ crash: RendererCrashPresentation) { error.focusRendererAction(crash) }
    var contentBounds: NSRect { content.bounds }
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; content.wantsLayer = true; content.layer?.backgroundColor = NSColor.white.cgColor
        splitHighlight.attach(to: self)
        addSubview(content); addSubview(windowGrabber); addSubview(debuggerWarning)
        browserToolbar.isHidden = true; addSubview(browserToolbar)
        content.addSubview(error); error.isHidden = true
        controlVisibility.onChange = { [weak self] revealed, duration in
            self?.browserToolbar.setControlsRevealed(revealed, duration: duration)
        }
        content.onLayout = { [weak self] in
            guard let self else { return }
            self.error.frame = self.content.bounds
            if let browser = self.browser { self.contentResize.place(browser, in: self.content) }
            self.nativeContent?.frame = self.content.bounds
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let developerHeight: CGFloat = loadedDeveloperToolbar?.isHidden == false ? DeveloperToolbarLayout.height : 0
        let toolbarHeight: CGFloat = browserToolbar.isHidden ? 0 : BrowserToolbarView.height
        let headerHeight = max(developerHeight, toolbarHeight)
        if showsTopBar != !browserToolbar.isHidden { showsTopBar = !browserToolbar.isHidden; onContentBackingChange?() }
        browserToolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: toolbarHeight)
        loadedDeveloperToolbar?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: developerHeight)
        let warningHeight = debuggerWarning.height
        debuggerWarning.frame = NSRect(x: 0, y: headerHeight, width: bounds.width, height: warningHeight)
        let pageTop = headerHeight + warningHeight
        let nextContent = NSRect(x: 0, y: pageTop, width: bounds.width, height: bounds.height - pageTop)
        let contentMoved = content.frame != nextContent
        content.frame = nextContent
        if contentMoved { content.needsLayout = true }
        if PaneContentHostedLayoutFlush.shouldLayoutContent(
            frameChanged: contentMoved, needsLayout: content.needsLayout
        ) {
            content.layout()
        }
        for child in content.subviews
            where PaneContentHostedLayoutFlush.shouldLayoutChild(needsLayout: child.needsLayout) {
            child.layoutSubtreeIfNeeded()
        }
        windowGrabber.frame = WebpageWindowDragState.region(in: bounds, topStripHeight: pageTop)
        let bar = headerHeight == PaneTopBarLayout.height ? NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight) : nil
        controlVisibility.update(host: self, bar: bar, focused: controlsFocused, obstructed: controlsObstructed)
        splitHighlight.layout(bounds: bounds, cornerRadius: layer?.cornerRadius ?? 0)
    }
    override func viewDidHide() { super.viewDidHide(); controlVisibility.invalidate() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        controlVisibility.invalidate(); super.viewWillMove(toWindow: newWindow)
    }
    func showNativeContent(_ view: NSView) {
        hidePlaceholder()
        if nativeContent !== view {
            clearNativeContent()
            nativeContent = view
            content.addSubview(view)
            view.autoresizingMask = [.width, .height]
        }
        view.frame = content.bounds; view.isHidden = false
        error.clear(); browser?.isHidden = true; showsBlank = false
        surface = .local
        setNoteCanvasBacking(showsNoteController || view is EaselDocumentView)
        applyNoteCanvasTheme()
    }
    func showNote(_ controller: NotePageViewController) {
        noteController = controller
        showNativeContent(controller.view)
    }
    func inheritNoteCanvasTheme(_ appearance: NSAppearance?, focus: NSColor?) {
        noteCanvasContentAppearance = appearance
        noteCanvasFocus = focus
        applyNoteCanvasTheme()
    }
    private func applyNoteCanvasTheme() {
        if showsNoteController, let noteController {
            noteController.inheritSpaceContentAppearance(noteCanvasContentAppearance)
            noteController.spaceFocus = noteCanvasFocus
        } else if let easel = nativeContent as? EaselDocumentView {
            easel.inheritSpaceContentAppearance(noteCanvasContentAppearance)
        }
    }
    private func setNoteCanvasBacking(_ visible: Bool) {
        guard showsNoteCanvas != visible else { return }
        showsNoteCanvas = visible
        content.layer?.backgroundColor = contentBacking.cgColor
        applyNoteCanvasTheme()
        onContentBackingChange?()
    }
    func clearNativeContent() { nativeContent?.removeFromSuperview(); nativeContent = nil; setNoteCanvasBacking(false) }
    func showBlank() { hidePlaceholder(); error.clear(); browser?.isHidden = true; nativeContent?.isHidden = true; showsBlank = true; surface = .local; setNoteCanvasBacking(false) }
    func showBrowser() {
        hidePlaceholder(); error.clear(); browser?.isHidden = false; nativeContent?.isHidden = true; showsBlank = false; surface = .page; setNoteCanvasBacking(false)
        showPageBacking(of: browser?.nativePage)
    }
    func showError(_ message: String) { hidePlaceholder(); error.showNavigationFailure(message); browser?.isHidden = true; nativeContent?.isHidden = true; showsBlank = false; surface = .failure; setNoteCanvasBacking(false) }
    var placeholder: PagePlaceholderView?
    private var placeholderSnapshot: CGImage?
    private(set) var showsPlaceholder = false
    func showPlaceholder(_ snapshot: CGImage?, title: String, onClick: @escaping () -> Void) {
        let view = placeholder ?? PagePlaceholderView(frame: content.bounds)
        if view.superview !== content || content.subviews.last !== view { content.addSubview(view) }
        placeholder = view
        view.autoresizingMask = [.width, .height]; view.frame = content.bounds; view.isHidden = false
        view.onClick = onClick; view.setAccessibilityLabel(title)
        error.clear(); browser?.isHidden = true; nativeContent?.isHidden = true; showsBlank = false
        surface = .local; setNoteCanvasBacking(false)
        if snapshot !== placeholderSnapshot || !showsPlaceholder {
            view.show(snapshot)
            placeholderSnapshot = snapshot
        }
        guard !showsPlaceholder else { return }
        showsPlaceholder = true
        if let layer { PagePlaceholderDim.apply(true, to: layer, animated: window != nil) }
        onContentBackingChange?()
    }
    private func hidePlaceholder() {
        guard showsPlaceholder else { return }
        showsPlaceholder = false
        placeholder?.removeFromSuperview(); placeholder = nil; placeholderSnapshot = nil
        if let layer { PagePlaceholderDim.apply(false, to: layer, animated: window != nil) }
        onContentBackingChange?()
    }
    func showRendererFailure(_ crash: RendererCrashPresentation) {
        hidePlaceholder()
        error.showRendererFailure(crash)
        browser?.isHidden = true; nativeContent?.isHidden = true; showsBlank = false
        surface = .failure
        setNoteCanvasBacking(false)
    }
}

extension BrowserPane: SplitLayoutFollowing {
    func followSplitLayout(from previous: CGRect, animation: CAAnimation) { splitHighlight.followLayout(from: previous, animation: animation) }
    func cancelSplitLayoutFollow() { splitHighlight.cancelFollow() }
}
