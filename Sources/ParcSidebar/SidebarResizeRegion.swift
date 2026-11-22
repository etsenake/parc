import AppKit
import Combine
import ParcCore
import QuartzCore
import ParcKit

@MainActor
package final class SidebarResizeRegionView: NSView, ResizeHandleView {
    static let width: CGFloat = 8
    package static func frame(trailing edge: NSRect, in container: NSRect) -> NSRect {
        NSRect(x: edge.maxX - width / 2, y: container.minY + 11, width: width, height: max(0, container.height - 22))
    }

    package weak var referenceView: NSView?
    package var onPan: ((NSGestureRecognizer.State, CGFloat, CGFloat) -> Void)?
    package var onDoubleClick: (() -> Void)?
    var performHaptic: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    var delay: (TimeInterval) -> AnyPublisher<Void, Never> = { seconds in
        Just(()).delay(for: .seconds(seconds), scheduler: DispatchQueue.main).eraseToAnyPublisher()
    }
    var runFadeOut: (_ animations: () -> Void, _ completion: @escaping () -> Void) -> Void = { animations, completion in
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        animations()
        CATransaction.commit()
    }
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    package var color = NSColor.clear { didSet { if color != oldValue { needsDisplay = true } } }
    package var isResizing = false {
        didSet {
            guard isResizing != oldValue else { return }
            if isResizing {
                fadeGeneration &+= 1
                indicatorLayer.removeAllAnimations(); indicatorLayer.isHidden = false
            } else if !isHovered { fadeOut() }
        }
    }
    @Published private(set) var isHovered = false
    let indicatorLayer = CAShapeLayer()
    private(set) lazy var panGestureRecognizer = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private(set) lazy var doubleClickGestureRecognizer: NSClickGestureRecognizer = {
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        recognizer.numberOfClicksRequired = 2
        return recognizer
    }()
    private var trackingArea: NSTrackingArea?
    private var hoverSubscription: AnyCancellable?
    private var windowObservers: [NSObjectProtocol] = []
    private var fadeGeneration: UInt64 = 0
    private var dragging = false
    private weak var cursorWindow: NSWindow?
    private var lastTranslation: CGFloat = 0

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.masksToBounds = false
        indicatorLayer.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "hidden": NSNull(),
                                  "opacity": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull()]
        indicatorLayer.isHidden = true; indicatorLayer.opacity = 0.5
        layer?.addSublayer(indicatorLayer)
        addGestureRecognizer(panGestureRecognizer)
        addGestureRecognizer(doubleClickGestureRecognizer)
        hoverSubscription = $isHovered.removeDuplicates().dropFirst()
            .filter { [weak self] _ in self?.isResizing == false }
            .map { [weak self] hovered -> AnyPublisher<Bool, Never> in
                guard hovered else { return Just(false).eraseToAnyPublisher() }
                return (self?.delay(0.25) ?? Empty().eraseToAnyPublisher()).map { true }.eraseToAnyPublisher()
            }
            .switchToLatest()
            .filter { [weak self] _ in self?.isResizing == false }
            .sink { [weak self] visible in if visible { self?.fadeIn() } else { self?.fadeOut() } }
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }

    package override var mouseDownCanMoveWindow: Bool { false }
    package override var wantsUpdateLayer: Bool { true }
    package override func updateLayer() {
        layer?.masksToBounds = false
        if indicatorLayer.superlayer !== layer { layer?.addSublayer(indicatorLayer) }
        indicatorLayer.fillColor = color.cgColor; indicatorLayer.strokeColor = color.cgColor
    }
    package override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
    package override func layout() {
        super.layout()
        let height = max(0, bounds.height - 8)
        indicatorLayer.frame = CGRect(x: 0, y: 0, width: 3, height: height)
        indicatorLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        indicatorLayer.position = CGPoint(x: 0, y: bounds.midY)
        let radius = min(1.5, height / 2)
        indicatorLayer.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 3, height: height),
                                     cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    package override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        indicatorLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
    package override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate,
                                                         .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); trackingArea = area
    }
    package override func mouseEntered(with event: NSEvent) { isHovered = isUnobstructed(atWindowPoint: event.locationInWindow) }
    package override func mouseMoved(with event: NSEvent) { isHovered = isUnobstructed(atWindowPoint: event.locationInWindow) }
    package override func mouseExited(with event: NSEvent) { isHovered = false }
    package override func cursorUpdate(with event: NSEvent) {
        guard let window, isUnobstructed(atWindowPoint: window.mouseLocationOutsideOfEventStream) else {
            super.cursorUpdate(with: event); return
        }
        NSCursor.resizeLeftRight.set()
    }
    func isUnobstructed(atWindowPoint point: NSPoint) -> Bool {
        guard let window, !isHiddenOrHasHiddenAncestor else { return false }
        let screenPoint = window.convertPoint(toScreen: point)
        for child in window.childWindows ?? [] where child.isVisible && !child.ignoresMouseEvents
            && child.frame.contains(screenPoint) {
            if let content = child.contentView, content.hitTest(
                content.superview?.convert(child.convertPoint(fromScreen: screenPoint), from: nil)
                    ?? child.convertPoint(fromScreen: screenPoint)) != nil { return false }
        }
        guard let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point) else { return false }
        return hit === self || hit.isDescendant(of: self)
    }

    package override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelInteraction() }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        if let newWindow {
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelInteraction() }
                })
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    package override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        indicatorLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
    package override var isHidden: Bool { didSet { if isHidden { cancelInteraction() } } }

    package func cancelInteraction() {
        isHovered = false
        guard dragging else { return }
        panGestureRecognizer.isEnabled = false; panGestureRecognizer.isEnabled = true
        if dragging { finishDrag(.cancelled, translation: lastTranslation, velocity: 0) }
    }
    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        let reference = referenceView ?? self
        let translation = recognizer.translation(in: reference).x
        let velocity = recognizer.velocity(in: reference).x
        switch recognizer.state {
        case .began:
            if dragging { finishDrag(.cancelled, translation: lastTranslation, velocity: 0) }
            dragging = true; lastTranslation = translation
            cursorWindow = window; window?.disableCursorRects()
            NSCursor.resizeLeftRight.set()
            onPan?(.began, translation, velocity)
        case .changed:
            guard dragging else { return }
            lastTranslation = translation
            NSCursor.resizeLeftRight.set()
            onPan?(.changed, translation, velocity)
        case .ended, .cancelled, .failed:
            guard dragging else { return }
            finishDrag(recognizer.state, translation: translation, velocity: velocity)
        default: break
        }
    }
    private func finishDrag(_ state: NSGestureRecognizer.State, translation: CGFloat, velocity: CGFloat) {
        let window = cursorWindow
        dragging = false; cursorWindow = nil
        onPan?(state, translation, velocity)
        window?.enableCursorRects()
    }
    @objc private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, window != nil, !isHiddenOrHasHiddenAncestor else { return }
        onDoubleClick?()
    }

    package func present(_ events: [SidebarResizeGesture.Event]) {
        for event in events {
            switch event {
            case .snapEngaged: pulseSnap(); performHaptic()
            case .snapReleased(let haptic): if haptic { performHaptic() }
            case .previewHiddenChanged, .breakpointChanged: break
            }
        }
    }
    func pulseSnap() {
        fadeGeneration &+= 1
        indicatorLayer.removeAllAnimations(); indicatorLayer.isHidden = false
        guard !reducesMotion() else { return }
        let pulse = CABasicAnimation(keyPath: "transform.scale.x")
        pulse.fromValue = 1; pulse.toValue = 1.7; pulse.duration = 0.08; pulse.autoreverses = true
        pulse.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        pulse.fillMode = .forwards
        indicatorLayer.add(pulse, forKey: "transform.scale.x")
    }
    private func fadeIn() {
        fadeGeneration &+= 1
        indicatorLayer.isHidden = false; indicatorLayer.opacity = 0.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 0.5; fade.duration = 0.2; fade.fillMode = .forwards
        indicatorLayer.add(fade, forKey: "opacity")
    }
    private func fadeOut() {
        fadeGeneration &+= 1
        let generation = fadeGeneration
        runFadeOut({
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.5; fade.toValue = 0; fade.duration = 0.2
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
            indicatorLayer.add(fade, forKey: "opacity")
        }, { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fadeGeneration == generation else { return }
                self.indicatorLayer.removeAnimation(forKey: "opacity")
                self.indicatorLayer.isHidden = true; self.indicatorLayer.opacity = 0.5
            }
        })
    }
}
