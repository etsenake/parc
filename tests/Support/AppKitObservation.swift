import AppKit
import ObjectiveC
import QuartzCore

// Test-process observers for production behaviour that has no public readout:
// per-frame sources, redraw requests, layer geometry writes, the system
// settings AppKit components read (Reduce Motion, standard defaults), the
// global input state (modifier flags, pressed buttons), the event, cursor and
// window drag hit testing consults, and the dragging sessions views begin.
// Each exchanges a Foundation, AppKit or Core Animation method implementation
// inside the test executable only.

private func exchange(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
    guard let originalMethod = class_getInstanceMethod(type, original),
          let replacementMethod = class_getInstanceMethod(type, replacement) else {
        preconditionFailure("missing \(original) or \(replacement) on \(type)")
    }
    method_exchangeImplementations(originalMethod, replacementMethod)
}

/// A repeating timer added to a run loop, or a display link created for a view.
@MainActor final class FrameSource {
    let timer: Timer?
    let link: AnyObject?
    private let target: NSObject?
    private let selector: Selector?
    fileprivate var invalidated = false
    fileprivate init(timer: Timer) { self.timer = timer; link = nil; target = nil; selector = nil }
    fileprivate init(link: AnyObject, target: NSObject?, selector: Selector) {
        timer = nil; self.link = link; self.target = target; self.selector = selector
    }
    /// Still scheduled: a valid timer, or a display link nobody has invalidated.
    var isLive: Bool { timer?.isValid ?? !invalidated }
    /// Delivers one frame callback now. Display links never fire for a view
    /// outside an on-screen window, so checks deliver their frames this way.
    func fire() {
        if let timer { if timer.isValid { timer.fire() }; return }
        guard !invalidated, let link, let target, let selector else { return }
        _ = target.perform(selector, with: link)
    }
}

@MainActor enum FrameSources {
    private static var installed = false
    fileprivate static var recorded: [FrameSource] = []
    static func install() {
        guard !installed else { return }
        installed = true
        exchange(RunLoop.self, NSSelectorFromString("addTimer:forMode:"), #selector(RunLoop.observed_add(_:forMode:)))
        if #available(macOS 14.0, *) {
            exchange(NSView.self, #selector(NSView.displayLink(target:selector:)),
                     #selector(NSView.observed_displayLink(target:selector:)))
            // NSView vends a private CADisplayLink subclass with its own invalidate.
            let probe = NSView().displayLink(target: NSNull(), selector: #selector(NSObject.description))
            exchange(object_getClass(probe)!, #selector(CADisplayLink.invalidate),
                     #selector(CADisplayLink.observed_invalidate))
            probe.invalidate()
            recorded.removeAll()
        }
    }
    /// Frame sources scheduled while `body` runs.
    static func scheduled(during body: () -> Void) -> [FrameSource] {
        precondition(installed, "FrameSources.install() first")
        let start = recorded.count
        body()
        return Array(recorded[start...])
    }
    fileprivate static func record(_ timer: Timer) {
        guard !recorded.contains(where: { $0.timer === timer }) else { return }
        recorded.append(FrameSource(timer: timer))
    }
}

extension RunLoop {
    @objc dynamic func observed_add(_ timer: Timer, forMode mode: RunLoop.Mode) {
        if Thread.isMainThread { MainActor.assumeIsolated { FrameSources.record(timer) } }
        observed_add(timer, forMode: mode)
    }
}

extension NSView {
    @available(macOS 14.0, *)
    @objc dynamic func observed_displayLink(target: Any, selector: Selector) -> CADisplayLink {
        let link = observed_displayLink(target: target, selector: selector)
        FrameSources.recorded.append(FrameSource(link: link, target: target as? NSObject, selector: selector))
        return link
    }
}

@available(macOS 14.0, *)
extension CADisplayLink {
    @objc dynamic func observed_invalidate() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { for source in FrameSources.recorded where source.link === self { source.invalidated = true } }
        }
        observed_invalidate()
    }
}

/// `needsDisplay = true` requests per view.
@MainActor enum Redraws {
    private static var installed = false
    fileprivate static var counts: [ObjectIdentifier: Int] = [:]
    static func install() {
        guard !installed else { return }
        installed = true
        exchange(NSView.self, #selector(setter: NSView.needsDisplay), #selector(NSView.observed_setNeedsDisplay(_:)))
    }
    static func count(_ view: NSView) -> Int {
        precondition(installed, "Redraws.install() first")
        return counts[ObjectIdentifier(view), default: 0]
    }
}

extension NSView {
    @objc dynamic nonisolated func observed_setNeedsDisplay(_ flag: Bool) {
        if flag, Thread.isMainThread {
            MainActor.assumeIsolated { Redraws.counts[ObjectIdentifier(self), default: 0] += 1 }
        }
        observed_setNeedsDisplay(flag)
    }
}

/// One setter call on a layer, or a view frame assignment.
struct GeometryWrite {
    let object: AnyObject
    let key: String
}

@MainActor enum GeometryWrites {
    private static var installed = false
    fileprivate static var log: [GeometryWrite]?
    static func install() {
        guard !installed else { return }
        installed = true
        exchange(CALayer.self, #selector(setter: CALayer.frame), #selector(CALayer.observed_setFrame(_:)))
        exchange(CALayer.self, #selector(setter: CALayer.bounds), #selector(CALayer.observed_setBounds(_:)))
        exchange(CALayer.self, #selector(setter: CALayer.position), #selector(CALayer.observed_setPosition(_:)))
        exchange(CALayer.self, #selector(setter: CALayer.transform), #selector(CALayer.observed_setTransform(_:)))
        exchange(CALayer.self, #selector(setter: CALayer.opacity), #selector(CALayer.observed_setOpacity(_:)))
        exchange(CALayer.self, #selector(setter: CALayer.cornerRadius), #selector(CALayer.observed_setCornerRadius(_:)))
        exchange(CALayer.self, #selector(setter: CALayer.maskedCorners), #selector(CALayer.observed_setMaskedCorners(_:)))
        exchange(CALayer.self, #selector(setter: CALayer.shadowPath), #selector(CALayer.observed_setShadowPath(_:)))
        exchange(CAShapeLayer.self, #selector(setter: CAShapeLayer.path), #selector(CAShapeLayer.observed_setPath(_:)))
        exchange(CAShapeLayer.self, #selector(setter: CAShapeLayer.strokeStart), #selector(CAShapeLayer.observed_setStrokeStart(_:)))
        exchange(CAShapeLayer.self, #selector(setter: CAShapeLayer.strokeEnd), #selector(CAShapeLayer.observed_setStrokeEnd(_:)))
        exchange(NSView.self, #selector(setter: NSView.frame), #selector(NSView.observed_setFrame(_:)))
    }
    /// Every write made while `body` runs, in order.
    static func during(_ body: () -> Void) -> [GeometryWrite] {
        precondition(installed, "GeometryWrites.install() first")
        log = []
        body()
        defer { log = nil }
        return log ?? []
    }
    /// Writes to `view`'s own sublayers, excluding any view's backing layer.
    static func layerWrites(by view: NSView, during body: () -> Void) -> [GeometryWrite] {
        during(body).filter { write in
            guard let layer = write.object as? CALayer, !(layer.delegate is NSView) else { return false }
            return owner(of: layer) === view
        }
    }
    /// The view whose backing layer is `layer` or its nearest ancestor.
    static func owner(of layer: CALayer) -> NSView? {
        var current: CALayer? = layer
        while let candidate = current {
            if let view = candidate.delegate as? NSView { return view }
            current = candidate.superlayer
        }
        return nil
    }
    fileprivate nonisolated static func note(_ object: AnyObject, _ key: String) {
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { log?.append(GeometryWrite(object: object, key: key)) }
    }
}

extension CALayer {
    @objc dynamic func observed_setFrame(_ value: CGRect) { GeometryWrites.note(self, "frame"); observed_setFrame(value) }
    @objc dynamic func observed_setBounds(_ value: CGRect) { GeometryWrites.note(self, "bounds"); observed_setBounds(value) }
    @objc dynamic func observed_setPosition(_ value: CGPoint) { GeometryWrites.note(self, "position"); observed_setPosition(value) }
    @objc dynamic func observed_setTransform(_ value: CATransform3D) { GeometryWrites.note(self, "transform"); observed_setTransform(value) }
    @objc dynamic func observed_setOpacity(_ value: Float) { GeometryWrites.note(self, "opacity"); observed_setOpacity(value) }
    @objc dynamic func observed_setCornerRadius(_ value: CGFloat) { GeometryWrites.note(self, "cornerRadius"); observed_setCornerRadius(value) }
    @objc dynamic func observed_setMaskedCorners(_ value: CACornerMask) {
        GeometryWrites.note(self, "maskedCorners"); observed_setMaskedCorners(value)
    }
    @objc dynamic func observed_setShadowPath(_ value: CGPath?) { GeometryWrites.note(self, "shadowPath"); observed_setShadowPath(value) }
}

extension CAShapeLayer {
    @objc dynamic func observed_setPath(_ value: CGPath?) { GeometryWrites.note(self, "path"); observed_setPath(value) }
    @objc dynamic func observed_setStrokeStart(_ value: CGFloat) { GeometryWrites.note(self, "strokeStart"); observed_setStrokeStart(value) }
    @objc dynamic func observed_setStrokeEnd(_ value: CGFloat) { GeometryWrites.note(self, "strokeEnd"); observed_setStrokeEnd(value) }
}

extension NSView {
    @objc dynamic nonisolated func observed_setFrame(_ value: NSRect) { GeometryWrites.note(self, "frame"); observed_setFrame(value) }
}

/// Values for the system settings production code reads directly. `nil`
/// passes through to the real setting.
enum SystemOverrides {
    nonisolated(unsafe) static var reduceMotion: Bool?
    nonisolated(unsafe) static var standardDefaults: UserDefaults?
    nonisolated(unsafe) private static var installed = false
    static func install() {
        guard !installed else { return }
        installed = true
        exchange(NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion),
                 #selector(getter: NSWorkspace.observed_reduceMotion))
        guard let standard = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard)),
              let replacement = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.observed_standard)) else {
            preconditionFailure("missing +[NSUserDefaults standardUserDefaults]")
        }
        method_exchangeImplementations(standard, replacement)
    }
}

extension NSWorkspace {
    @objc dynamic var observed_reduceMotion: Bool { SystemOverrides.reduceMotion ?? self.observed_reduceMotion }
}

extension UserDefaults {
    @objc dynamic class var observed_standard: UserDefaults { SystemOverrides.standardDefaults ?? self.observed_standard }
}

/// The global input state NSEvent's class getters report, so a check does not
/// see a person using the machine. `nil` passes through to the real state.
enum InputOverrides {
    nonisolated(unsafe) static var modifierFlags: NSEvent.ModifierFlags?
    nonisolated(unsafe) static var pressedMouseButtons: Int?
    nonisolated(unsafe) private static var installed = false
    static func install() {
        guard !installed else { return }
        installed = true
        for (original, replacement) in [("modifierFlags", #selector(getter: NSEvent.observed_modifierFlags)),
                                        ("pressedMouseButtons", #selector(getter: NSEvent.observed_pressedMouseButtons))] {
            guard let originalMethod = class_getClassMethod(NSEvent.self, NSSelectorFromString(original)),
                  let replacementMethod = class_getClassMethod(NSEvent.self, replacement) else {
                preconditionFailure("missing +[NSEvent \(original)]")
            }
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }
}

extension NSEvent {
    @objc dynamic class var observed_modifierFlags: NSEvent.ModifierFlags {
        InputOverrides.modifierFlags ?? self.observed_modifierFlags
    }
    @objc dynamic class var observed_pressedMouseButtons: Int {
        InputOverrides.pressedMouseButtons ?? self.observed_pressedMouseButtons
    }
}

/// The event NSApplication reports dispatching, the cursor NSCursor reports
/// showing, and window drags, for views that consult them while hit testing.
/// `nil` passes through to AppKit.
enum DispatchOverrides {
    nonisolated(unsafe) static var currentEvent: NSEvent?
    nonisolated(unsafe) static var cursor: NSCursor?
    /// `NSCursor.current` reads answered from `cursor`.
    nonisolated(unsafe) static var cursorReads = 0
    /// Receives `NSWindow.performDrag(with:)` in place of AppKit's drag loop.
    nonisolated(unsafe) static var windowDrag: ((NSWindow, NSEvent) -> Void)?
    nonisolated(unsafe) private static var installed = false
    static func install() {
        guard !installed else { return }
        installed = true
        exchange(NSApplication.self, #selector(getter: NSApplication.currentEvent),
                 #selector(getter: NSApplication.observed_currentEvent))
        exchange(NSWindow.self, #selector(NSWindow.performDrag(with:)), #selector(NSWindow.observed_performDrag(with:)))
        guard let current = class_getClassMethod(NSCursor.self, #selector(getter: NSCursor.current)),
              let replacement = class_getClassMethod(NSCursor.self, #selector(getter: NSCursor.observed_current)) else {
            preconditionFailure("missing +[NSCursor currentCursor]")
        }
        method_exchangeImplementations(current, replacement)
    }
}

extension NSApplication {
    @objc dynamic nonisolated var observed_currentEvent: NSEvent? { DispatchOverrides.currentEvent ?? self.observed_currentEvent }
}

extension NSCursor {
    @objc dynamic nonisolated class var observed_current: NSCursor {
        guard let cursor = DispatchOverrides.cursor else { return self.observed_current }
        DispatchOverrides.cursorReads += 1
        return cursor
    }
}

extension NSWindow {
    @objc dynamic nonisolated func observed_performDrag(with event: NSEvent) {
        guard let windowDrag = DispatchOverrides.windowDrag else { return observed_performDrag(with: event) }
        windowDrag(self, event)
    }
}

/// One `beginDraggingSession(with:event:source:)` call.
struct DraggingStart {
    let view: NSView
    let items: [NSDraggingItem]
    let source: NSDraggingSource
}

/// Dragging sessions views begin, recorded in place of AppKit's drag loop.
@MainActor enum DraggingSessions {
    private static var installed = false
    fileprivate static var log: [DraggingStart]?
    static func install() {
        guard !installed else { return }
        installed = true
        exchange(NSView.self, #selector(NSView.beginDraggingSession(with:event:source:)),
                 #selector(NSView.observed_beginDraggingSession(with:event:source:)))
    }
    /// Sessions begun while `body` runs. None of them reaches AppKit; outside
    /// `body` AppKit begins sessions as usual.
    static func begun(during body: () -> Void) -> [DraggingStart] {
        precondition(installed, "DraggingSessions.install() first")
        log = []
        defer { log = nil }
        body()
        return log ?? []
    }
}

extension NSView {
    /// Recording returns no session: AppKit never starts one. AppKit declares
    /// the result non-null, so this nil is safe only because the production
    /// callers under test discard it.
    @objc dynamic func observed_beginDraggingSession(with items: [NSDraggingItem], event: NSEvent,
                                                     source: NSDraggingSource) -> NSDraggingSession? {
        guard DraggingSessions.log != nil else { return observed_beginDraggingSession(with: items, event: event, source: source) }
        DraggingSessions.log?.append(DraggingStart(view: self, items: items, source: source))
        return nil
    }
}
