import AppKit

/// The browser-choice page's backdrop. A browser's page is a Space theme drawn
///
///
/// strip; a new choice springs the strip's position to that page and the
/// backdrop mixes the two pages either side of it (`transitioning(from:to:
///
/// the mix is. The first choice, and leaving the page, fade the backdrop on the
/// same spring over the page's own fill.
@MainActor
final class BrowserImportBackdrop: NSView {
    enum Page: Equatable { case theme(SpaceTheme), sunset }
    private let renderer = ThemeRendererView()
    private let sunset = BrowserImportSunset()
    ///
    private var position = SidebarSpring(response: SidebarSpacePagingModel.springResponse, damping: 1)
    private var visibility = SidebarSpring(response: SidebarSpacePagingModel.springResponse, damping: 1)
    private var pages: [Page] = []
    private var page: Int?
    private var timer: Timer?
    /// The page that holds most of the mix, nil while the page's own fill does:
    /// text takes its contrast.
    private(set) var dominant: Page? {
        didSet { if dominant != oldValue { onDominantChange?(dominant) } }
    }
    var onDominantChange: ((Page?) -> Void)?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for view in [renderer, sunset] as [NSView] {
            view.autoresizingMask = [.width, .height]; view.frame = bounds; view.alphaValue = 0
            addSubview(view)
        }
        renderer.drawsMaterial = false
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// One page per browser in order, and the chosen browser's index.
    func show(_ next: [Page], selected: Int?) {
        guard next != pages || selected != page else { return }
        let animate = window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let now = CACurrentMediaTime()
        let hidden = visibility.value(at: now) < 0.01
        // Leaving the page keeps the last pages so the backdrop fades out.
        if !next.isEmpty || selected != nil { pages = next }
        page = selected
        if let selected {
            if hidden || !animate { position.place(CGFloat(selected)) } else { position.retarget(CGFloat(selected), now: now) }
        }
        if animate { visibility.retarget(selected == nil ? 0 : 1, now: now) } else { visibility.place(selected == nil ? 0 : 1) }
        guard animate else { settle(); return }
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        tick()
    }

    /// Places the strip and fade directly, for a still frame of the motion.
    func showFrame(position value: CGFloat, visibility shown: CGFloat) {
        position.place(value); visibility.place(shown); apply(value, shown)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        guard !position.isSettled(at: now) || !visibility.isSettled(at: now) else { settle(); return }
        apply(position.value(at: now), visibility.value(at: now))
    }

    private func settle() {
        timer?.invalidate(); timer = nil
        if let page { position.place(CGFloat(page)) }
        visibility.place(page == nil ? 0 : 1)
        apply(position.value(at: CACurrentMediaTime()), page == nil ? 0 : 1)
    }

    private func apply(_ value: CGFloat, _ visible: CGFloat) {
        let shown = min(1, max(0, visible))
        guard !pages.isEmpty else {
            renderer.alphaValue = 0; sunset.alphaValue = 0; dominant = nil; return
        }
        let clamped = min(CGFloat(pages.count - 1), max(0, value))
        let lower = Int(clamped.rounded(.down)), upper = Int(clamped.rounded(.up))
        let progress = clamped - CGFloat(lower)
        // The renderer mixes two themes itself; the sunset crossfades with one.
        switch (pages[lower], pages[upper]) {
        case let (.theme(from), .theme(to)):
            renderer.theme = from
            renderer.pagingTransition = lower == upper ? nil : ThemePagingTransition(from: from, theme: to, progress: progress)
            renderer.alphaValue = shown; sunset.alphaValue = 0
        case let (.sunset, .theme(theme)):
            renderer.theme = theme; renderer.pagingTransition = nil
            renderer.alphaValue = shown * progress; sunset.alphaValue = shown * (1 - progress)
        case let (.theme(theme), .sunset):
            renderer.theme = theme; renderer.pagingTransition = nil
            renderer.alphaValue = shown * (1 - progress); sunset.alphaValue = shown * progress
        case (.sunset, .sunset):
            renderer.alphaValue = 0; sunset.alphaValue = shown
        }
        let held = pages[progress < 0.5 ? lower : upper]
        dominant = shown < 0.5 || held == .theme(SpaceTheme()) ? nil : held
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { settle() }
    }
}

///
/// pink and red on the right, solid across the top and fading into the page
/// below, with the theme grain over it. Colours are sampled from that dialog.
@MainActor
final class BrowserImportSunset: NSView {
    /// The fraction of the page's height that stays solid, and where the
    /// colour is gone; the dialog's own header is shorter than these pages'.
    static let solid: CGFloat = 0.3, clear: CGFloat = 0.64
    private static let colors: [(CGFloat, UInt32)] = [
        (0, 0x3320B4), (0.11, 0x4B3EC8), (0.21, 0x5954D8), (0.31, 0x786FDF), (0.42, 0x9F75D4),
        (0.52, 0xC86BB5), (0.62, 0xEA6D93), (0.72, 0xF85F72), (1, 0xFD5967),
    ]
    private static let wash = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors.map { stop in
        CGColor(srgbRed: CGFloat(stop.1 >> 16 & 0xff) / 255, green: CGFloat(stop.1 >> 8 & 0xff) / 255,
                blue: CGFloat(stop.1 & 0xff) / 255, alpha: 1)
    } as CFArray, locations: colors.map(\.0))!
    private static let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: [
        CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 0.55, alpha: 1),
        CGColor(gray: 0.15, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray,
        locations: [0, solid, solid + (clear - solid) * 0.4, solid + (clear - solid) * 0.75, clear])!
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.height > 0 else { return }
        let rows = max(1, Int(bounds.height * 2))
        let mask = CGContext(data: nil, width: 1, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        // Bitmap rows run bottom-up; the solid end belongs at the view's top.
        mask.drawLinearGradient(Self.fade, start: CGPoint(x: 0, y: CGFloat(rows)), end: .zero, options: [])
        context.saveGState()
        context.clip(to: bounds, mask: mask.makeImage()!)
        context.drawLinearGradient(Self.wash, start: CGPoint(x: bounds.minX, y: 0), end: CGPoint(x: bounds.maxX, y: 0), options: [])
        if let grain = OnboardingSetupCard.grainTile(.grain) {
            context.setBlendMode(.overlay); context.setAlpha(0.6)
            context.draw(grain, in: CGRect(origin: .zero, size: OnboardingSetupLayout.grainTileSize), byTiling: true)
        }
        context.restoreGState()
    }
}
