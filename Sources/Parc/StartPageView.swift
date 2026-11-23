import AppKit
import ParcCore
import ParcKit
import ParcSidebar

struct StartPageLayout: Equatable {
    static let markSize = CGSize(width: 65, height: 96)
    static let markSpacing: CGFloat = 24
    static let maximumBarWidth: CGFloat = 765
    static let sideGutter: CGFloat = 40
    static let pairCenter: CGFloat = 0.45
    static let defaultBarRestHeight: CGFloat = 64

    var mark: CGRect
    var commandBarSlot: CGRect
    var windowButtons: CGRect?
    var sidebarButton: CGRect?

    init(size: CGSize, barRestHeight: CGFloat, markSize: CGSize = StartPageLayout.markSize, chromeOrigin: CGPoint?, showsWindowButtons: Bool,
         toolbarWidth: CGFloat? = nil, showsNavigation: Bool = false) {
        let width = max(0, size.width), height = max(0, size.height)
        let markSize = markSize.width > 0 && markSize.height > 0 ? markSize : Self.markSize
        let barWidth = max(0, min(Self.maximumBarWidth, width - 2 * Self.sideGutter))
        let pair = markSize.height + Self.markSpacing + max(0, barRestHeight)
        let top = max(0, (height * Self.pairCenter - pair / 2).rounded())
        let barTop = top + markSize.height + Self.markSpacing
        mark = CGRect(x: ((width - markSize.width) / 2).rounded(), y: top, width: markSize.width, height: markSize.height)
        commandBarSlot = CGRect(x: ((width - barWidth) / 2).rounded(), y: barTop, width: barWidth, height: max(0, height - barTop))
        guard let origin = chromeOrigin else {
            windowButtons = nil; sidebarButton = nil
            return
        }
        let bar = SidebarChromeLayout.toolbar(width: toolbarWidth.map { max(0, $0) } ?? width,
                                              windowButtons: showsWindowButtons ? WindowStandardButtons.stackSize : nil,
                                              showsNavigation: showsNavigation)
        windowButtons = bar.windowButtons?.offsetBy(dx: origin.x, dy: origin.y)
        sidebarButton = bar.toggle?.offsetBy(dx: origin.x, dy: origin.y)
    }
}

@MainActor
final class StartPageView: NSView {
    static let accessibilityTitle = "Start page"
    static let sidebarButtonTitle = "Show sidebar"

    let commandBarSlot: NSView = StartPageCommandBarSlot()
    let mark = StartPageMarkView()
    let privateMark: StartPagePrivateMarkView
    let paper = StartPagePaperView()
    let windowButtons = WindowStandardButtons()
    let markEffects = StartPagePassthroughView()
    let sidebarButton = ActionButton(StartPageView.sidebarButtonTitle, symbol: "sidebar.left")
    var theme = SpaceTheme() { didSet { if theme != oldValue { applyTheme() } } }
    var incognito = false {
        didSet {
            guard incognito != oldValue else { return }
            paper.incognito = incognito; mark.incognito = incognito
            refreshMarks()
            applyPalette()
        }
    }
    weak var coordinateSpace: NSView? {
        didSet {
            guard coordinateSpace !== oldValue else { return }
            mark.coordinateSpace = coordinateSpace
            needsLayout = true
        }
    }
    var pagingTransition: ThemePagingTransition? {
        didSet {
            guard pagingTransition != oldValue else { return }
            paper.pagingTransition = pagingTransition
            mark.pagingTransition = pagingTransition
        }
    }
    var showsWindowChrome = false { didSet { if showsWindowChrome != oldValue { refreshChrome() } } }
    var showsWindowButtons = true { didSet { if showsWindowButtons != oldValue { refreshChrome() } } }
    var barRestHeight = StartPageLayout.defaultBarRestHeight { didSet { if barRestHeight != oldValue { needsLayout = true } } }
    var sidebarToolbarWidth: CGFloat? { didSet { if sidebarToolbarWidth != oldValue { needsLayout = true } } }
    var sidebarShowsNavigation = false { didSet { if sidebarShowsNavigation != oldValue { needsLayout = true } } }
    var onToggleSidebar: (() -> Void)?
    var isDeparting = false
    private var sidebarGlyphPointSize: CGFloat = 0
    override var isFlipped: Bool { true }

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, privateMark: StartPagePrivateMarkView())
    }

    init(frame frameRect: NSRect, privateMark: StartPagePrivateMarkView) {
        self.privateMark = privateMark
        super.init(frame: frameRect)
        wantsLayer = true
        for view in [paper, mark, privateMark, commandBarSlot, windowButtons, sidebarButton, markEffects] { addSubview(view) }
        mark.effectsHost = markEffects
        sidebarButton.imagePosition = .imageOnly
        sidebarButton.translucentFace = TranslucentButtonFace(view: sidebarButton)
        sidebarButton.focusRingCornerRadius = 5
        sidebarButton.actionBlock = { [weak self] in self?.onToggleSidebar?() }
        sidebarButton.cell?.setAccessibilityLabel(Self.sidebarButtonTitle)
        LiveShortcutToolTip.set(sidebarButton, Self.sidebarButtonTitle, commandID: "toggleSidebar:")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(Self.accessibilityTitle)
        applyTheme()
        refreshChrome()
        refreshMarks()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func invalidateCoordinates() {
        mark.invalidateCoordinates()
        needsLayout = true
    }

    var chromeOrigin: CGPoint {
        guard let space = coordinateSpace, space !== self, isDescendant(of: space) else { return .zero }
        let anchor = SidebarPresentationFrame.floating.rect(width: 0, in: space.bounds)
        return convert(CGPoint(x: anchor.minX, y: space.isFlipped ? anchor.minY : anchor.maxY), from: space)
    }

    override func layout() {
        super.layout()
        if paper.frame != bounds { paper.frame = bounds }
        if markEffects.frame != bounds { markEffects.frame = bounds }
        let frames = StartPageLayout(size: bounds.size, barRestHeight: barRestHeight,
                                     markSize: showsPrivateMark ? StartPagePrivateMarkView.size : mark.intrinsicContentSize,
                                     chromeOrigin: showsWindowChrome ? chromeOrigin : nil, showsWindowButtons: showsWindowButtons,
                                     toolbarWidth: sidebarToolbarWidth, showsNavigation: sidebarShowsNavigation)
        if showsPrivateMark {
            if privateMark.frame != frames.mark { privateMark.frame = frames.mark }
        } else if mark.frame != frames.mark { mark.frame = frames.mark }
        if commandBarSlot.frame != frames.commandBarSlot { commandBarSlot.frame = frames.commandBarSlot }
        if let frame = frames.windowButtons, windowButtons.frame != frame { windowButtons.frame = frame }
        guard let frame = frames.sidebarButton else { return }
        if sidebarButton.frame != frame { sidebarButton.frame = frame }
        let glyph = SidebarChromeLayout.navigationGlyphPointSize(buttonSide: frame.height)
        if sidebarGlyphPointSize != glyph {
            sidebarGlyphPointSize = glyph
            sidebarButton.image = NavigationControlArtwork.symbol("sidebar.left", pointSize: glyph) ?? sidebarButton.image
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isDeparting { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, let superview, hitTest(superview.convert(event.locationInWindow, from: nil)) === self else {
            super.mouseDown(with: event); return
        }
        switch SidebarTablistBackground.press(clickCount: event.clickCount, modifiers: event.modifierFlags) {
        case .passThrough: super.mouseDown(with: event)
        case .waitForRelease: break
        case .dragWindow:
            NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: window)
            window.performDrag(with: event)
        }
    }

    override func accessibilityChildren() -> [Any]? {
        super.accessibilityChildren().map { SidebarAccessibility.headerFirst($0, header: [windowButtons, sidebarButton]) }
    }

    private func applyTheme() {
        paper.theme = theme
        mark.theme = theme
        applyPalette()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    private func applyPalette() {
        let palette = ThemeChromePalette(theme: paper.effectiveTheme, isDark: paper.isDark)
        if sidebarButton.contentTintColor != palette.title { sidebarButton.contentTintColor = palette.title }
    }

    var showsPrivateMark: Bool { incognito && privateMark.hasArtwork }

    private func refreshMarks() {
        let privateShown = showsPrivateMark
        if mark.isHidden != privateShown { mark.isHidden = privateShown }
        if privateMark.isHidden == privateShown { privateMark.isHidden = !privateShown }
        needsLayout = true
    }

    private func refreshChrome() {
        let buttonsHidden = !(showsWindowChrome && showsWindowButtons)
        if windowButtons.isHidden != buttonsHidden { windowButtons.isHidden = buttonsHidden }
        if sidebarButton.isHidden == showsWindowChrome { sidebarButton.isHidden = !showsWindowChrome }
        needsLayout = true
    }
}

@MainActor
private final class StartPageCommandBarSlot: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

final class StartPagePassthroughView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}
