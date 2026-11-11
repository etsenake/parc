import AppKit

struct CaptureLensMotion {
    static let throttle = 0.09
    private var origin = DownloadArrivalSpring()
    private var size = DownloadArrivalSpring()
    private var pending: CGRect?
    private var lastTargetTime = -Double.infinity
    private var lastTickTime: Double?
    private(set) var rect: CGRect?

    mutating func target(_ rect: CGRect?, at time: Double, animated: Bool) {
        guard let rect else { clear(); return }
        guard animated, self.rect != nil else { settle(rect, at: time); return }
        if time - lastTargetTime >= Self.throttle { apply(rect, at: time) }
        else { pending = rect }
    }
    mutating func tick(at time: Double) {
        if let pending, time - lastTargetTime >= Self.throttle { apply(pending, at: time) }
        guard rect != nil else { return }
        let dt = max(0, min(time - (lastTickTime ?? time), 0.1))
        lastTickTime = time
        origin.tick(dt); size.tick(dt)
        rect = CGRect(x: origin.value.x, y: origin.value.y,
                      width: max(0, size.value.x), height: max(0, size.value.y))
        if !isAnimating {
            settle(CGRect(x: origin.toValue.x, y: origin.toValue.y,
                          width: max(0, size.toValue.x), height: max(0, size.toValue.y)), at: time)
        }
    }
    var isAnimating: Bool { pending != nil || !origin.hasResolved || !size.hasResolved }
    mutating func settle(at time: Double) {
        guard rect != nil else { return }
        settle(pending ?? CGRect(x: origin.toValue.x, y: origin.toValue.y,
            width: size.toValue.x, height: size.toValue.y), at: time)
    }
    private mutating func apply(_ rect: CGRect, at time: Double) {
        pending = nil; lastTargetTime = time
        origin.toValue = SIMD2(rect.minX, rect.minY); size.toValue = SIMD2(rect.width, rect.height)
    }
    private mutating func settle(_ rect: CGRect, at time: Double) {
        pending = nil; self.rect = rect; lastTickTime = time; lastTargetTime = time
        origin = DownloadArrivalSpring(initialValue: SIMD2(rect.minX, rect.minY))
        size = DownloadArrivalSpring(initialValue: SIMD2(rect.width, rect.height))
        origin.configure(response: 0.35, dampingRatio: 0.87)
        size.configure(response: 0.35, dampingRatio: 0.87)
    }
    mutating func clear() {
        self = CaptureLensMotion()
    }
}

@MainActor enum CaptureMotion {
    static func reveal(_ layer: CALayer?, reduceMotion: Bool) {
        guard let layer else { return }
        layer.removeAnimation(forKey: "captureReveal")
        guard !reduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0; animation.toValue = 1; animation.duration = 1
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        layer.add(animation, forKey: "captureReveal")
    }
    static func blendPortrait(_ view: NSImageView, previous: NSImage?) {
        settleImageBlend(view)
        guard let previous, view.image != nil, view.window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let overlay = CaptureBlendImageView(frame: view.bounds)
        overlay.image = previous; overlay.imageScaling = view.imageScaling
        overlay.identifier = NSUserInterfaceItemIdentifier("captureImageBlend")
        overlay.autoresizingMask = [.width, .height]; overlay.wantsLayer = true
        overlay.setAccessibilityElement(false); overlay.setAccessibilityHidden(true)
        view.addSubview(overlay)
        guard let layer = overlay.layer else { overlay.removeFromSuperview(); return }
        let spring = CASpringAnimation(keyPath: "opacity")
        spring.mass = 1; spring.stiffness = pow(2 * .pi / 0.5, 2)
        spring.damping = 4 * .pi * 0.7 / 0.5; spring.duration = spring.settlingDuration
        spring.fromValue = 1; spring.toValue = 0
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak overlay] in MainActor.assumeIsolated { overlay?.removeFromSuperview() } }
        CATransaction.setDisableActions(true); layer.opacity = 0
        layer.add(spring, forKey: "portraitBlend"); CATransaction.commit()
    }
    static func settleImageBlend(_ view: NSImageView) {
        for subview in view.subviews where subview.identifier?.rawValue == "captureImageBlend" {
            subview.layer?.removeAllAnimations(); subview.removeFromSuperview()
        }
    }
    static func announce(_ message: String, from element: NSAccessibilityElementProtocol) {
        NSAccessibility.post(element: element, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

@MainActor final class CaptureFocusReturn {
    private weak var window: NSWindow?
    private weak var target: NSView?
    private weak var expectedResponder: NSResponder?
    private weak var expectedEditorOwner: AnyObject?
    private let valid: () -> Bool
    private var observer: NSObjectProtocol?
    private var selection: NSRange?
    private var consumed = false
    init(window: NSWindow, target: NSView, valid: @escaping () -> Bool) {
        self.window = window; self.target = target; self.valid = valid
        expectedResponder = window.firstResponder
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
            expectedEditorOwner = editor.delegate as AnyObject?
        }
        if let field = target as? NSTextField, let editor = field.currentEditor() as? NSTextView {
            selection = editor.selectedRange()
        }
    }
    func restore() {
        guard !consumed, valid(), let window, let target, target.window === window, !target.isHiddenOrHasHiddenAncestor,
              window.attachedSheet == nil,
              window.firstResponder === expectedResponder || window.firstResponder === target || window.firstResponder == nil else { cancel(); return }
        if let editor = expectedResponder as? NSTextView, editor.isFieldEditor,
           editor.delegate as AnyObject? !== expectedEditorOwner { cancel(); return }
        guard window.isKeyWindow else {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.restore() } }
            return
        }
        cancel()
        if window.makeFirstResponder(target), let field = target as? NSTextField,
           let editor = field.currentEditor() as? NSTextView, let selection {
            let length = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, length), length: min(selection.length, max(0, length - selection.location))))
        }
    }
    func cancel() { consumed = true; if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}

@MainActor private final class CaptureBlendImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
