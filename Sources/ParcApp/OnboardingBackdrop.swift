import AppKit
import QuartzCore

@MainActor
final class OnboardingBackdrop {
    private weak var parent: NSWindow?
    private var overlay: NSWindow?
    private var surface: NSView?
    private var deadlines: [DispatchWorkItem] = []
    private var screenObserver: NSObjectProtocol?
    private var generation = 0
    private var wantsAnimation = false
    private var completed = false

    func start(behind parent: NSWindow, reduceMotion: Bool) {
        cancel()
        self.parent = parent
        wantsAnimation = !reduceMotion
        completed = reduceMotion
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: parent, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenChanged() }
        }
        screenChanged()
    }

    func welcomeEnded() {
        if overlay == nil { cancel() }
    }

    func cancel() {
        generation += 1
        deadlines.forEach { $0.cancel() }; deadlines.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        removeOverlay()
        parent = nil
        wantsAnimation = false
        completed = true
    }

    private func screenChanged() {
        guard let parent, let screen = parent.screen else { return }
        if let overlay {
            overlay.setFrame(screen.frame, display: true)
        } else if wantsAnimation, !completed, screen === NSScreen.main {
            begin(on: screen, parent: parent)
        }
    }

    private func begin(on screen: NSScreen, parent: NSWindow) {
        wantsAnimation = false
        let overlay = NSWindow(contentRect: screen.frame, styleMask: [.fullSizeContentView],
                               backing: .buffered, defer: true)
        overlay.isReleasedWhenClosed = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.animationBehavior = .none
        overlay.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let surface = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        surface.wantsLayer = true
        surface.autoresizingMask = [.width, .height]
        surface.setAccessibilityElement(false)
        surface.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        overlay.contentView = surface
        self.overlay = overlay; self.surface = surface
        parent.addChildWindow(overlay, ordered: .below)
        if let layer = surface.layer {
            animate(layer, keyPath: "opacity", from: 0, to: 1, duration: 1.5)
        }
        schedule(after: 4) { $0.showGradient() }
        schedule(after: 5) { owner in
            guard let layer = owner.surface?.layer else { return }
            owner.animate(layer, keyPath: "opacity", from: 1, to: 0, duration: 2.5)
        }
        schedule(after: 7.5) { owner in
            owner.removeOverlay()
            owner.completed = true
            if let observer = owner.screenObserver { NotificationCenter.default.removeObserver(observer) }
            owner.screenObserver = nil
        }
    }

    private func showGradient() {
        guard let surface, let layer = surface.layer else { return }
        let height = surface.bounds.height / 2
        let blue = NSColor(srgbRed: 0x31 / 255.0, green: 0x39 / 255.0, blue: 0xFB / 255.0, alpha: 1)
        let gradient = CAGradientLayer()
        gradient.colors = [blue.withAlphaComponent(0).cgColor, blue.withAlphaComponent(0.5).cgColor]
        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.frame = CGRect(x: 0, y: -height, width: surface.bounds.width, height: height)
        layer.addSublayer(gradient)
        let origin = gradient.position.y
        animate(gradient, keyPath: "position.y", from: origin, to: origin + height, duration: 0.4)
        animate(gradient, keyPath: "opacity", from: 1, to: 0, duration: 0.6)
    }

    private func animate(_ layer: CALayer, keyPath: String, from: Double, to: Double, duration: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(to, forKeyPath: keyPath)
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from; animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: keyPath)
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping (OnboardingBackdrop) -> Void) {
        let expected = generation
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected else { return }
            action(self)
        }
        deadlines.append(task)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func removeOverlay() {
        surface?.layer?.removeAllAnimations()
        surface?.layer?.sublayers?.forEach { $0.removeAllAnimations() }
        if let overlay {
            parent?.removeChildWindow(overlay)
            overlay.orderOut(nil)
        }
        surface = nil; overlay = nil
    }
}
