import AppKit
import ParcCore

@MainActor
final class EaselViewportMover {
    private var timer: Timer?
    private weak var scroll: NSScrollView?

    func move(_ scroll: NSScrollView, to plan: EaselViewportFocus.Plan, animated: Bool = true) {
        cancel()
        let clip = scroll.contentView
        let startZoom = Double(scroll.magnification)
        let startCenter = NSPoint(x: clip.bounds.midX, y: clip.bounds.midY)
        let target = NSPoint(x: plan.center.x, y: plan.center.y)
        guard animated, scroll.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            Self.apply(scroll, zoom: plan.magnification, center: target)
            return
        }
        self.scroll = scroll
        let began = CACurrentMediaTime()
        let duration = EaselZoom.animationDuration
        let endZoom = plan.magnification
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                guard let scroll = self.scroll, scroll.window != nil else { self.cancel(); return }
                let progress = min(1, (CACurrentMediaTime() - began) / duration)
                let eased = EaselZoom.eased(progress)
                let zoom = EaselZoom.interpolated(from: startZoom, to: endZoom, progress: eased)
                let center = NSPoint(x: startCenter.x + (target.x - startCenter.x) * eased,
                                     y: startCenter.y + (target.y - startCenter.y) * eased)
                Self.apply(scroll, zoom: zoom, center: center)
                if progress >= 1 { self.cancel() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    static func apply(_ scroll: NSScrollView, zoom: Double, center: NSPoint) {
        let clamped = min(max(CGFloat(zoom), scroll.minMagnification), scroll.maxMagnification)
        if abs(scroll.magnification - clamped) > 0.0001 { scroll.magnification = clamped }
        let clip = scroll.contentView
        let size = clip.bounds.size
        let bounds = clip.constrainBoundsRect(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                                     width: size.width, height: size.height))
        clip.setBoundsOrigin(bounds.origin)
        scroll.reflectScrolledClipView(clip)
    }

    static func plan(for target: NSRect, in scroll: NSScrollView, mode: EaselViewportFocus.Mode, topInset: CGFloat = 0) -> EaselViewportFocus.Plan? {
        let clip = scroll.contentView.bounds
        let zoom = Double(scroll.magnification)
        let inset = Double(topInset) / max(zoom, 0.01)
        let visible = EaselRect(x: clip.minX, y: clip.minY + inset, width: clip.width, height: max(1, clip.height - inset))
        guard var plan = EaselViewportFocus.plan(target: EaselRect(x: target.minX, y: target.minY, width: target.width, height: target.height),
                                                 visible: visible, magnification: zoom, minimum: Double(scroll.minMagnification),
                                                 maximum: Double(scroll.maxMagnification), mode: mode) else { return nil }
        plan.center.y -= Double(topInset) / 2 / max(plan.magnification, 0.01)
        return plan
    }
}
