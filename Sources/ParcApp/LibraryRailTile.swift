import AppKit
import QuartzCore

enum LibraryRailLayout {
    static let width: CGFloat = 112
    static let tileHeight: CGFloat = 80
    static func tiles(count: Int, height: CGFloat) -> [NSRect] {
        guard count > 0 else { return [] }
        let top: CGFloat = 48, bottom = max(top, height - 8 - 28 - 20)
        let slot = min(100, (bottom - top) / CGFloat(count))
        let tile = min(tileHeight, slot)
        let start = top + (bottom - top - slot * CGFloat(count)) / 2
        return (0..<count).map { index in
            NSRect(x: 8, y: start + CGFloat(index) * slot + (slot - tile) / 2, width: width - 15, height: tile)
        }
    }
    static func back(height: CGFloat) -> NSRect { NSRect(x: 8, y: max(0, height - 37), width: 30, height: 28) }
}

@MainActor
final class LibraryRailTile: PointingHandButton {
    static let iconSize: CGFloat = 28
    static let progressSize: CGFloat = 24
    nonisolated static let cornerRadius: CGFloat = 12
    nonisolated static let pressedInset: CGFloat = 2
    nonisolated static let pressResponse = 0.18, pressDamping = 0.8
    nonisolated static func fillOpacity(selected: Bool, hovered: Bool) -> CGFloat { selected ? 0.1 : hovered ? 0.05 : 0 }
    nonisolated static func fill(opacity: CGFloat) -> NSColor {
        NSColor.labelColor.withAlphaComponent(NSColor.labelColor.alphaComponent * opacity)
    }
    nonisolated static func artOpacity(selected: Bool) -> CGFloat { selected ? 1 : 0.7 }
    private final class Cell: NSButtonCell {
        override var nextState: Int { state.rawValue }
    }
    override class var cellClass: AnyClass? {
        get { Cell.self }
        set {}
    }
    var actionBlock: (() -> Void)?
    var iconColors: (primary: NSColor, secondary: NSColor)? { didSet { art.needsDisplay = true } }
    var showsLabel = true {
        didSet {
            guard showsLabel != oldValue else { return }
            needsLayout = true; art.needsDisplay = true
            parcTooltip = showsLabel ? nil : TooltipConfiguration(title)
        }
    }
    let progress: DownloadActivityBadge?
    fileprivate private(set) var showsProgress = false
    private let animationName: LibraryRailAnimation.Name
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private let fill = NSView()
    private let art = LibraryRailTileArt()
    private var hovered = false { didSet { if hovered != oldValue { refreshFill() } } }
    private var pressed = false { didSet { if pressed != oldValue { refreshFill(animated: true) } } }
    private var tracking: NSTrackingArea?
    private var playback: (timer: Timer, start: CFTimeInterval, from: Double, end: Double)?
    private var parkedFrame: Double?

    init(_ title: String, animation: LibraryRailAnimation.Name, hasProgressBadge: Bool = false) {
        animationName = animation
        progress = hasProgressBadge ? DownloadActivityBadge(frame: .zero) : nil
        super.init(frame: .zero)
        self.title = title
        isBordered = false; bezelStyle = .regularSquare; setButtonType(.momentaryChange)
        target = self; action = #selector(invoke)
        focusRingType = .exterior
        setAccessibilityLabel(title)
        setAccessibilityRole(.radioButton)
        wantsLayer = true
        fill.wantsLayer = true
        fill.layer?.cornerRadius = Self.cornerRadius; fill.layer?.cornerCurve = .continuous
        addSubview(fill); addSubview(art)
        art.tile = self
        if let progress {
            art.addSubview(progress)
            progress.onChange = { [weak self] activity in
                guard let self, self.showsProgress != (activity != nil) else { return }
                self.showsProgress = activity != nil
                self.needsLayout = true; self.art.needsDisplay = true
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var state: NSControl.StateValue {
        didSet {
            guard state != oldValue else { return }
            setAccessibilitySelected(state == .on)
            NSAccessibility.post(element: self, notification: .valueChanged)
            refreshFill(); art.needsDisplay = true
            if state == .on { playSelection() }
        }
    }
    var animation: LibraryRailAnimation? { LibraryRailAnimation.named(animationName) }
    fileprivate var currentFrame: Double {
        guard let animation else { return 0 }
        guard let playback else { return parkedFrame ?? animation.startFrame }
        return min(playback.end, playback.from + (CACurrentMediaTime() - playback.start) * animation.frameRate)
    }
    private func playSelection() {
        guard window != nil, !reduceMotion, let animation,
              let from = animation.frame(forMarker: "hover-start"),
              let end = animation.frame(forMarker: "selection-end") else { return }
        finishPlayback()
        let duration = max(0, end - from) / animation.frameRate
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.playback?.timer === timer else { return timer.invalidate() }
                if CACurrentMediaTime() - start >= duration { self.finishPlayback() }
                self.art.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playback = (timer, start, from, end)
    }
    private func finishPlayback() {
        guard let playback else { return }
        playback.timer.invalidate(); self.playback = nil
        parkedFrame = playback.end
        art.needsDisplay = true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishPlayback(); hovered = false; pressed = false }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        art.frame = bounds
        progress?.frame = slot().icon
        refreshFill()
    }
    fileprivate func label(color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .bold),
                                                              .foregroundColor: color, .paragraphStyle: paragraph])
    }
    fileprivate func slot() -> (icon: NSRect, label: NSRect) {
        let size = showsProgress ? Self.progressSize : Self.iconSize
        let labelWidth: CGFloat = 80, gap: CGFloat = 4
        let labelHeight = showsLabel ? ceil(label(color: .labelColor).boundingRect(with: CGSize(width: labelWidth, height: 200),
                                                                                   options: [.usesLineFragmentOrigin]).height) : 0
        let top = showsLabel ? (bounds.height - size - gap - labelHeight) / 2 : (bounds.height - size) / 2
        return (NSRect(x: (bounds.width - size) / 2, y: top, width: size, height: size),
                NSRect(x: (bounds.width - labelWidth) / 2, y: top + size + gap, width: labelWidth, height: labelHeight))
    }
    private func refreshFill(animated: Bool = false) {
        guard let layer = fill.layer else { return }
        let from = layer.presentation() ?? layer
        let (fromBounds, fromPosition) = (from.bounds, from.position)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let inset = pressed ? Self.pressedInset : 0
        fill.frame = bounds.insetBy(dx: inset, dy: inset)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = Self.fill(opacity: Self.fillOpacity(selected: state == .on, hovered: hovered)).cgColor
        }
        CATransaction.commit()
        guard animated, window != nil, !reduceMotion else { return }
        for (key, value, target) in [("bounds", NSValue(rect: fromBounds), NSValue(rect: layer.bounds)),
                                     ("position", NSValue(point: fromPosition), NSValue(point: layer.position))] {
            let spring = CASpringAnimation(keyPath: key)
            spring.mass = 1; spring.stiffness = pow(2 * Double.pi / Self.pressResponse, 2)
            spring.damping = 4 * Double.pi * Self.pressDamping / Self.pressResponse
            spring.duration = spring.settlingDuration
            spring.fromValue = value; spring.toValue = target
            layer.add(spring, forKey: key)
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFill(); art.needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        tracking = next; addTrackingArea(next)
    }
    override func mouseEntered(with event: NSEvent) { hovered = isEnabled }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func viewDidHide() { super.viewDidHide(); hovered = false }
    override func mouseDown(with event: NSEvent) {
        pressed = isEnabled
        super.mouseDown(with: event)
        pressed = false
    }
    override func draw(_ dirtyRect: NSRect) {}
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
    }
    @objc private func invoke() { actionBlock?() }
}

@MainActor
private final class LibraryRailTileArt: NSView {
    weak var tile: LibraryRailTile?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let tile, let context = NSGraphicsContext.current?.cgContext else { return }
        let selected = tile.state == .on
        let dark = WindowStandardButtons.isDark(effectiveAppearance)
        let slot = tile.slot()
        if !tile.showsProgress, let animation = tile.animation {
            let colors = tile.iconColors ?? (dark ? .white : .black, dark ? .black : .white)
            context.saveGState(); context.setAlpha(LibraryRailTile.artOpacity(selected: selected))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            animation.draw(in: context, rect: slot.icon,
                           frame: tile.currentFrame, primary: colors.primary.cgColor, secondary: colors.secondary.cgColor)
            context.endTransparencyLayer(); context.restoreGState()
        }
        guard tile.showsLabel else { return }
        let color = NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0,
                            alpha: selected ? (dark ? 0.92 : 0.85) : (dark ? 0.592 : 0.565))
        tile.label(color: color).draw(with: slot.label, options: [.usesLineFragmentOrigin])
    }
}
