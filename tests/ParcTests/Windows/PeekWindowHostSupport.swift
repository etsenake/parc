import AppKit
import QuartzCore
import Testing
@testable import Parc

enum PeekWindowHostSupport {
    static let window = CGRect(x: 0, y: 0, width: 1280, height: 800)
    static let sidebarWidth: CGFloat = 228

    static func page(thickness t: CGFloat, docked: Bool = true) -> CGRect {
        let left = docked ? sidebarWidth : t
        return CGRect(x: left, y: t, width: window.width - left - t, height: window.height - 2 * t)
    }

    static func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    static func transform(_ value: Any?) -> CATransform3D? { (value as? NSValue)?.caTransform3DValue }

    static func centreOffset(of transform: CATransform3D, width: CGFloat) -> CGFloat {
        transform.m41 + transform.m11 * width / 2 - width / 2
    }

    static func midway(_ from: CATransform3D, _ to: CATransform3D, _ fraction: CGFloat) -> CATransform3D {
        var result = to
        result.m41 = from.m41 + (to.m41 - from.m41) * fraction
        result.m42 = from.m42 + (to.m42 - from.m42) * fraction
        return result
    }

    static let narrow = CGRect(x: 0, y: 0, width: 1042, height: 780)
    static let wide = CGRect(x: 0, y: 0, width: 1042 + 228, height: 780)
    static var scale: CGFloat { PeekWindowLayout(bounds: window, page: wide, stepsBack: true).scale }

    @MainActor static func pageView() -> (NSView, CALayer) {
        let view = NSView(frame: wide)
        view.wantsLayer = true
        return (view, view.layer!)
    }

    @MainActor static func slidingPage(from start: CGRect, slide: CABasicAnimation) -> (NSView, CALayer) {
        let (view, layer) = pageView()
        slide.fromValue = NSValue(rect: start)
        slide.isRemovedOnCompletion = false
        layer.add(slide, forKey: PeekStepBack.slideKey)
        return (view, layer)
    }

    static var finalStep: CATransform3D { PeekWindowLayout.stepTransform(bounds: wide, anchor: .zero, scale: scale) }
}
