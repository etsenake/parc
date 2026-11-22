import AppKit
import Testing
@testable import Parc

enum NavigationLoadingTestsSupport {
    @MainActor final class Frames: DisplayFrameDriving {
        private(set) var starts = 0
        private var onFrame: (() -> Bool)?
        var isRunning: Bool { onFrame != nil }
        func start(in view: NSView, onFrame: @escaping () -> Bool) {
            guard !isRunning else { return }
            starts += 1
            self.onFrame = onFrame
        }
        func stop() { onFrame = nil }
        func fire() { if onFrame?() != true { stop() } }
    }

    final class RedrawCountingView: NSView {
        var redraws = 0
        override var needsDisplay: Bool {
            get { super.needsDisplay }
            set {
                if newValue { redraws += 1 }
                super.needsDisplay = newValue
            }
        }
    }

    @MainActor final class GlyphScene {
        let view = RedrawCountingView()
        let frames = Frames()
        var clock: CFTimeInterval = 0
        var reduceMotion = false
        let glyph: ReloadGlyph

        init() {
            _ = NSApplication.shared
            glyph = ReloadGlyph(view: view, pointSize: SidebarChromeLayout.navigationGlyphPointSize, rasterized: true)
            glyph.frames = frames
            glyph.now = { [unowned self] in self.clock }
            glyph.reduceMotion = { [unowned self] in self.reduceMotion }
        }
    }

    @MainActor final class PillScene {
        let pill = PageLoadingIndicator(frame: NSRect(x: 0, y: 0, width: 128, height: 4))
        let frames = Frames()
        var clock: CFTimeInterval = 0
        var onScreen = true
        var reduceMotion = false
        private var loadingStarted: CFTimeInterval = 0
        private(set) var frame = 0
        private static let unpresented = CATransform3DMakeScale(0.5, 0.5, 1)

        init() {
            _ = NSApplication.shared
            pill.frames = frames
            pill.now = { [unowned self] in self.clock }
            pill.isVisibleOnScreen = { [unowned self] _ in self.onScreen }
            pill.reduceMotion = { [unowned self] in self.reduceMotion }
        }

        static func sweeping() -> PillScene {
            let s = PillScene()
            s.startLoading()
            _ = s.sweepFrame()
            return s
        }

        var track: CALayer { pill.layer!.sublayers!.first! }
        var bar: CAShapeLayer { track.sublayers!.last as! CAShapeLayer }

        func startLoading() {
            loadingStarted = clock
            frame = 0
            pill.setLoading(true)
        }

        func deliverFrame() -> Bool {
            frame += 1
            clock = loadingStarted + (Double(frame) - 0.5) / 60
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            track.transform = Self.unpresented
            CATransaction.commit()
            frames.fire()
            return !CATransform3DEqualToTransform(track.transform, Self.unpresented)
        }

        func sweepFrame() -> Int? {
            while bar.opacity == 0, frame < 300 { _ = deliverFrame() }
            return bar.opacity == 0 ? nil : frame
        }

        func settleSkippedTicks() -> Int {
            var skipped = 0
            let limit = frame + 480
            while skipped < 2, frame < limit {
                let empty = bar.strokeStart == 0 && bar.strokeEnd == 0
                let presented = deliverFrame()
                skipped = empty && bar.strokeEnd == 0 && !presented ? skipped + 1 : 0
            }
            return skipped
        }

        func boundsSpring() -> (from: CGFloat, to: CGFloat, spring: CASpringAnimation)? {
            guard let spring = track.animation(forKey: "bounds") as? CASpringAnimation,
                  let from = spring.fromValue as? NSValue, let to = spring.toValue as? NSValue else { return nil }
            return (from.rectValue.width, to.rectValue.width, spring)
        }

        func barSpring() -> CASpringAnimation? { bar.animation(forKey: "opacity") as? CASpringAnimation }

        static func isSweepSpring(_ spring: CASpringAnimation) -> Bool {
            let response = 2 * Double.pi / (spring.stiffness / spring.mass).squareRoot()
            let fraction = spring.damping / (2 * (spring.stiffness * spring.mass).squareRoot())
            return abs(response - 0.8) < 0.0001 && abs(fraction - 0.92) < 0.0001 && spring.duration == spring.settlingDuration
        }
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.0001) -> Bool { abs(a - b) <= e }
}
