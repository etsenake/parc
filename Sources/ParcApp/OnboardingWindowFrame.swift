import AppKit
import QuartzCore

extension OnboardingWindowFrameLayout {
    static func crankPalette(theme: SpaceTheme, dark: Bool) -> WindowFrameCrankPalette {
        guard let primary = theme.primaryColor, theme.isValid else {
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            return WindowFrameCrankPalette(accent: accent, deep: accent.blended(withFraction: 0.35, of: .black) ?? accent,
                                           cap: NSColor(white: dark ? 0.32 : 0.78, alpha: 1), dark: dark)
        }
        let base = ThemeRenderMath.nativeColor(primary)
        let rgb = base.usingColorSpace(.sRGB) ?? base
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let accent = NSColor(hue: hue, saturation: max(0.55, saturation), brightness: dark ? 0.92 : 0.78, alpha: 1)
        let deep = NSColor(hue: hue, saturation: max(0.4, saturation * 0.9), brightness: dark ? 0.55 : 0.62, alpha: 1)
        let cap = NSColor(hue: hue, saturation: min(0.6, max(0.25, saturation)),
                          brightness: dark ? 0.5 : max(0.7, brightness), alpha: 1)
        return WindowFrameCrankPalette(accent: accent, deep: deep, cap: cap, dark: dark)
    }
}

final class OnboardingWindowFramePageCard: NSView {
    private var bars: [CALayer] = []
    var dark = false { didSet { if dark != oldValue { updateColors() } } }
    var thickness = CGFloat(WindowFrameThickness.standard) { didSet { if thickness != oldValue { needsLayout = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        for _ in OnboardingWindowFrameLayout.placeholderBars(in: .zero) {
            let bar = CALayer()
            bar.cornerCurve = .continuous
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        setAccessibilityElement(false)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let radius = WindowFrameThickness.cornerRadius(for: thickness)
        layer?.cornerRadius = radius
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        for (bar, rect) in zip(bars, OnboardingWindowFrameLayout.placeholderBars(in: bounds.size)) {
            bar.frame = rect
            bar.cornerRadius = min(rect.height / 2, 8)
        }
        CATransaction.commit()
    }

    private func updateColors() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.backgroundColor = (dark ? NSColor(white: 0.15, alpha: 1) : NSColor.white).cgColor
        let ink = dark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.07)
        bars.forEach { $0.backgroundColor = ink.cgColor }
        CATransaction.commit()
    }

    func shudder() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = OnboardingWindowFrameLayout.shudderValues
        shake.keyTimes = OnboardingWindowFrameLayout.shudderKeyTimes
        shake.duration = OnboardingWindowFrameLayout.shudderDuration
        shake.isAdditive = true
        layer?.add(shake, forKey: "windowFrameShudder")
    }
}

@MainActor
final class OnboardingWindowFrameStep: NSView {
    let copy = NSView()
    private let windowShadow = NSView()
    private let surface = NSView()
    private let themeSurface = ThemeRendererView(frame: .zero)
    let pageCard = OnboardingWindowFramePageCard(frame: .zero)
    private(set) var crank: WindowFrameCrankView?
    private(set) var value = WindowFrameThickness.standard
    private(set) var shown = CGFloat(WindowFrameThickness.standard)
    private var restoreValue = WindowFrameThickness.standard
    private var wantsCrank = false
    private var crankScheduled = false
    private var palette = OnboardingWindowFrameLayout.crankPalette(theme: SpaceTheme(), dark: false)
    var reduceMotion = false
    var onCommit: ((Int) -> Void)?
    var onCrankChange: (() -> Void)?
    var onKept: (() -> Void)?
    var keyboardView: NSView? { crank }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        windowShadow.wantsLayer = true
        windowShadow.layer?.shadowColor = NSColor.black.cgColor
        windowShadow.layer?.shadowOpacity = 0.3
        windowShadow.layer?.shadowRadius = 12
        windowShadow.layer?.shadowOffset = CGSize(width: 0, height: -6)
        surface.wantsLayer = true
        surface.layer?.cornerRadius = WindowFrameThickness.windowCornerRadius
        surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true
        themeSurface.drawsMaterial = false
        surface.addSubview(themeSurface)
        surface.addSubview(pageCard)
        copy.addSubview(windowShadow)
        copy.addSubview(surface)
        addSubview(copy)
        for view in [windowShadow, surface, themeSurface] as [NSView] { view.setAccessibilityElement(false) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private(set) var startValue = WindowFrameThickness.standard

    func begin(value start: Int) {
        let settled = WindowFrameThickness.clamped(start)
        value = settled; restoreValue = settled; startValue = settled
        follow(CGFloat(settled))
        wantsCrank = true
        scheduleCrank()
    }

    func end() {
        wantsCrank = false
        removeCrank()
    }

    func apply(theme: SpaceTheme, appearance: NSAppearance, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        let chrome = ThemeChromePalette(theme: theme, appearance: appearance)
        let name: NSAppearance.Name = chrome.isDark ? .darkAqua : .aqua
        if copy.appearance?.name != name { copy.appearance = NSAppearance(named: name) }
        themeSurface.appearance = appearance
        themeSurface.theme = theme
        pageCard.dark = chrome.isDark
        (copy.appearance ?? appearance).performAsCurrentDrawingAppearance {
            surface.layer?.backgroundColor = chrome.background.cgColor
        }
        palette = OnboardingWindowFrameLayout.crankPalette(theme: theme, dark: chrome.isDark)
        if crank?.palette != palette { crank?.palette = palette }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { removeCrank() } else { scheduleCrank() }
    }

    override func layout() {
        super.layout()
        copy.frame = OnboardingWindowFrameLayout.copyFrame(in: bounds)
        let bounds = copy.bounds
        windowShadow.frame = bounds
        surface.frame = bounds
        themeSurface.frame = surface.bounds
        let radius = WindowFrameThickness.windowCornerRadius
        CATransaction.begin(); CATransaction.setDisableActions(true)
        windowShadow.layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.commit()
        placePageCard()
        crank?.frame = OnboardingWindowFrameLayout.crankFrame(in: surface.bounds, side: WindowFrameCrankView.side,
                                                              flipped: surface.isFlipped)
    }

    private func follow(_ thickness: CGFloat) {
        shown = OnboardingWindowFrameLayout.shownThickness(thickness)
        placePageCard()
    }

    private func placePageCard() {
        let card = OnboardingWindowFrameLayout.pageCard(in: surface.bounds, thickness: shown)
        pageCard.thickness = shown
        if pageCard.frame != card { pageCard.frame = card }
        pageCard.layoutSubtreeIfNeeded()
    }

    private func scheduleCrank() {
        guard wantsCrank, crank == nil, window != nil, !crankScheduled else { return }
        crankScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.crankScheduled = false
            self.presentCrank()
        }
    }

    private func presentCrank(takingFocus: Bool = true) {
        guard wantsCrank, crank == nil, window != nil else { return }
        superview?.layoutSubtreeIfNeeded()
        let crank = WindowFrameCrankView(value: value, palette: palette)
        crank.onPreview = { [weak self] thickness in self?.follow(thickness) }
        crank.onEvent = { [weak self] event in
            guard let self, case .end = event, !self.reduceMotion else { return }
            self.pageCard.shudder()
        }
        crank.onFinish = { [weak self, weak crank] commit, settled in
            guard let self, let crank, self.crank === crank else { crank?.removeFromSuperview(); return }
            self.discard(crank)
            let kept = commit ? WindowFrameThickness.clamped(settled) : self.restoreValue
            self.value = kept
            self.follow(CGFloat(kept))
            if commit { self.restoreValue = kept; self.onCommit?(kept) }
            self.presentCrank(takingFocus: !commit)
            if commit { self.onKept?() }
        }
        surface.addSubview(crank, positioned: .above, relativeTo: nil)
        crank.frame = OnboardingWindowFrameLayout.crankFrame(in: surface.bounds, side: WindowFrameCrankView.side,
                                                             flipped: surface.isFlipped)
        self.crank = crank
        crank.present(takingFocus: takingFocus)
        if takingFocus { onCrankChange?() }
    }

    var chosenValue: Int { WindowFrameThickness.nearest(shown) }

    private func discard(_ crank: WindowFrameCrankView) {
        crank.onPreview = nil
        crank.onEvent = nil
        crank.onFinish = nil
        crank.removeFromSuperview()
        if self.crank === crank { self.crank = nil }
    }

    private func removeCrank() {
        guard let crank else { return }
        discard(crank)
        follow(CGFloat(value))
    }
}
