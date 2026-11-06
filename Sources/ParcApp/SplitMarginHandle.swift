import AppKit

///
/// pane's trailing `SplitViewDraggerHandleView`.
///
/// - Its grip shows while the handle's `ViewState.isHandleVisible`
///
///
///
///   reports as 2, false for the last ID of the split's `windowContentIDs`
///   and false in a stacked arrangement, so only a page that is not in a
///   split (an empty `windowContentIDs`) laid out side by side keeps it.
///   The grip is the ordinary two-by-24 grip centred on the handle
///
///
///   gives this last handle the draggable region (0, midY − 22, width, 44)
///
///
///
///
/// - Nothing drags it: the split controller's `gestureRecognizerShouldBegin`
///
///
///   begins inside the band, but its handler returns without a trailing pane
///
///   is empty) and the margin keeps its existing behaviour.
@MainActor
final class SplitMarginHandleView: NSView {
    ///
    static let regionHeight: CGFloat = 44
    /// The window's part of `isHandleVisible`: it shows exactly one page that
    /// is not in a split, has the page margin, and no draft or expanded split.
    var windowAllows = false { didSet { if windowAllows != oldValue { refresh() } } }
    /// The split's part: one arranged page and no incoming reserved pane.
    var splitAllows = false { didSet { if splitAllows != oldValue { refresh() } } }
    var isShown: Bool { windowAllows && splitAllows && !bounds.isEmpty }
    private(set) var isHovered = false
    private let grip = CALayer()
    private var trackingArea: NSTrackingArea?
    private var resignObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        grip.name = "Split margin grip"; grip.cornerRadius = 1
        grip.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        layer?.addSublayer(grip)
        setAccessibilityElement(false)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The handle's draggable region, empty while the grip is hidden.
    var region: NSRect {
        guard isShown else { return .zero }
        return NSRect(x: 0, y: bounds.midY - Self.regionHeight / 2, width: bounds.width, height: Self.regionHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refresh()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let window {
            // The tracking area is active in the key window only.
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setHovered(false, animated: false) }
            }
        }
        refresh()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor(animated: false)
    }

    private func refresh() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        grip.frame = NSRect(x: bounds.midX - 1, y: bounds.midY - 12, width: 2, height: 24)
        grip.isHidden = !isShown
        CATransaction.commit()
        if !isShown { isHovered = false }
        updateColor(animated: false)
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let band = region
        if !band.isEmpty { addCursorRect(band, cursor: .resizeLeftRight) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = nil
        let band = region
        guard !band.isEmpty else { return }
        //
        let area = NSTrackingArea(rect: band, options: [.mouseEnteredAndExited, .activeInKeyWindow, .enabledDuringMouseDrag],
                                  owner: self, userInfo: nil)
        addTrackingArea(area); trackingArea = area
        if let window, window.isKeyWindow {
            setHovered(band.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)), animated: false)
        } else { setHovered(false, animated: false) }
    }
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === trackingArea, isShown, window?.isKeyWindow == true else { return }
        setHovered(true, animated: true)
    }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === trackingArea else { return }
        setHovered(false, animated: true)
    }

    private func setHovered(_ hovered: Bool, animated: Bool) {
        let next = hovered && isShown
        guard next != isHovered else { return }
        isHovered = next
        updateColor(animated: animated)
    }

    /// DragHint (idle) and DragHintHighlighted (hover): black in light and
    /// white in dark appearance at 0.2 and 0.5, with the handle's 0.16-second
    ///
    private func updateColor(animated: Bool) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0,
                            alpha: isHovered ? 0.5 : 0.2).cgColor
        let previous = grip.presentation()?.backgroundColor ?? grip.backgroundColor
        let changed = grip.backgroundColor != color
        CATransaction.begin(); CATransaction.setDisableActions(true)
        grip.backgroundColor = color
        CATransaction.commit()
        if changed, animated, let previous {
            let transition = CABasicAnimation(keyPath: "backgroundColor")
            transition.fromValue = previous; transition.toValue = color; transition.duration = 0.16
            grip.add(transition, forKey: "Split margin grip hover")
        } else if !animated { grip.removeAnimation(forKey: "Split margin grip hover") }
    }
}
