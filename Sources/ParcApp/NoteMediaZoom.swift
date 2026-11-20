import AppKit

@MainActor
final class NoteMediaZoomOverlay: NSView {
    private let backdrop = CALayer()
    private let picture = CALayer()
    private var image: NoteMediaImage
    private let source: URL?
    private var originRect: NSRect
    private weak var previousResponder: NSResponder?
    private var pinch: CGFloat = 0
    private var closing = false
    private var onClose: (() -> Void)?
    private static let margin: CGFloat = 36

    private init(image: NoteMediaImage, source: URL?, origin: NSRect) {
        self.image = image
        self.source = source
        originRect = origin
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        backdrop.opacity = 0
        picture.contentsGravity = .resizeAspect
        picture.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        picture.cornerCurve = .continuous
        picture.cornerRadius = NoteMediaStyle.imageRadius
        picture.masksToBounds = true
        picture.minificationFilter = .trilinear
        layer?.addSublayer(backdrop)
        layer?.addSublayer(picture)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Zoomed image")
        setAccessibilityHelp("Click or press Escape to close.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @discardableResult
    static func present(image: NoteMediaImage, source: URL?, from rect: NSRect, of view: NSView,
                        in canvas: NotePageCanvasView, onClose: (() -> Void)? = nil) -> NoteMediaZoomOverlay {
        let host = canvas.overlayView
        let visible = canvas.visibleRect.isEmpty ? canvas.bounds : canvas.visibleRect
        let frame = host.convert(visible, from: canvas)
        let overlay = NoteMediaZoomOverlay(image: image, source: source, origin: .zero)
        overlay.frame = frame
        overlay.originRect = overlay.convert(rect, from: view)
        overlay.onClose = onClose
        host.addSubview(overlay)
        overlay.open()
        return overlay
    }

    private func open() {
        previousResponder = window?.firstResponder
        window?.makeFirstResponder(self)
        refreshColors()
        let scale = window?.backingScaleFactor ?? 2
        NoteMediaMotion.instant {
            backdrop.frame = bounds
            picture.contents = image.first
            picture.contentsScale = scale
            picture.bounds = CGRect(origin: .zero, size: originRect.size)
            picture.position = CGPoint(x: originRect.midX, y: originRect.midY)
        }
        startAnimating()
        let target = fittedRect()
        animate(to: target, spring: .settle)
        fadeBackdrop(visible: true)
        upgradeResolution(for: target)
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    private func fittedRect() -> NSRect {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        guard area.width > 0, area.height > 0 else { return bounds }
        let natural = image.pointSize.width > 0 ? image.pointSize : CGSize(width: image.first.width, height: image.first.height)
        let fit = min(area.width / natural.width, area.height / natural.height)
        let current = originRect.width / max(1, natural.width)
        let ratio = max(min(fit, 2), min(current, fit))
        let size = CGSize(width: (natural.width * ratio).rounded(), height: (natural.height * ratio).rounded())
        return NSRect(x: (bounds.midX - size.width / 2).rounded(), y: (bounds.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }

    private func animate(to rect: NSRect, spring: NoteSpring, completion: (() -> Void)? = nil) {
        let fromBounds = picture.presentation()?.bounds ?? picture.bounds
        let fromPosition = picture.presentation()?.position ?? picture.position
        let toBounds = CGRect(origin: .zero, size: rect.size)
        let toPosition = CGPoint(x: rect.midX, y: rect.midY)
        NoteMediaMotion.instant {
            picture.bounds = toBounds
            picture.position = toPosition
        }
        guard !NoteAnimation.reduceMotion else {
            picture.removeAnimation(forKey: "zoom.bounds")
            picture.removeAnimation(forKey: "zoom.position")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = closing ? 1 : 0
            fade.toValue = closing ? 0 : 1
            fade.duration = 0.15
            NoteMediaMotion.instant { picture.opacity = closing ? 0 : 1 }
            CATransaction.begin()
            CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion?() } }
            picture.add(fade, forKey: "zoom.fade")
            CATransaction.commit()
            return
        }
        let bounds = NoteAnimation.spring("bounds", spring, from: NSValue(rect: fromBounds), to: NSValue(rect: toBounds))
        let position = NoteAnimation.spring("position", spring, from: NSValue(point: fromPosition), to: NSValue(point: toPosition))
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion?() } }
        picture.add(bounds, forKey: "zoom.bounds")
        picture.add(position, forKey: "zoom.position")
        CATransaction.commit()
    }

    private func fadeBackdrop(visible: Bool) {
        let from = backdrop.presentation()?.opacity ?? backdrop.opacity
        let to: Float = visible ? 1 : 0
        NoteMediaMotion.instant { backdrop.opacity = to }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = visible ? 0.2 : 0.15
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        backdrop.add(fade, forKey: "zoom.backdrop")
    }

    private func upgradeResolution(for rect: NSRect) {
        guard let source else { return }
        let pixels = NoteMediaImageLoader.pixels(for: rect.size, scale: window?.backingScaleFactor ?? 2)
        guard pixels > image.decodedPixels else { return }
        NoteMediaImageLoader.shared.load(source, pixels: pixels) { [weak self] result in
            guard let self, !self.closing, case .success(let sharper) = result else { return }
            self.image = sharper
            NoteMediaMotion.instant { self.picture.contents = sharper.first }
            self.startAnimating()
        }
    }

    private func startAnimating() {
        picture.removeAnimation(forKey: "zoom.frames")
        guard image.isAnimated, !NoteAnimation.reduceMotion else { return }
        picture.add(NoteImageFrames.animation(for: image), forKey: "zoom.frames")
    }

    func close() {
        guard !closing else { return }
        closing = true
        if window?.firstResponder === self { window?.makeFirstResponder(previousResponder) }
        fadeBackdrop(visible: false)
        animate(to: originRect, spring: .reorder) { [weak self] in
            self?.removeFromSuperview()
        }
        onClose?()
        onClose = nil
    }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant { backdrop.frame = bounds }
        guard !closing, picture.animation(forKey: "zoom.bounds") == nil else { return }
        let target = fittedRect()
        NoteMediaMotion.instant {
            picture.bounds = CGRect(origin: .zero, size: target.size)
            picture.position = CGPoint(x: target.midX, y: target.midY)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        NoteMediaMotion.instant { backdrop.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.backdrop, in: self) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) { close() }
    override func rightMouseDown(with event: NSEvent) { close() }
    override func scrollWheel(with event: NSEvent) {}

    override func magnify(with event: NSEvent) {
        if event.phase == .began { pinch = 0 }
        pinch += event.magnification
        if pinch < -0.08 { close() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.charactersIgnoringModifiers == " " { close(); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { close() }

    override func accessibilityPerformCancel() -> Bool {
        close()
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, !closing { closing = true; onClose?(); onClose = nil }
    }
}
