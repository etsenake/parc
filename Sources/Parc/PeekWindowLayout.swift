import AppKit
import QuartzCore

struct PeekWindowLayout: Equatable {
    static let cardInset: CGFloat = 12
    static let controlGap: CGFloat = 13
    static let controlSize: CGFloat = 32
    static let controlTopInset: CGFloat = 7
    static let controlSpacing: CGFloat = 9
    static let controlCount = 3
    static let stepBack: CGFloat = 9

    enum Region: Equatable { case card, controls, page, frame }

    var bounds: CGRect
    var page: CGRect
    var stepsBack: Bool

    var card: CGRect {
        let reserved = 2 * (Self.controlGap + Self.controlSize + 8)
        let width = max(0, min(page.width * 0.8, page.width - reserved)).rounded(.down)
        return CGRect(x: page.minX + ((page.width - width) / 2).rounded(.down), y: bounds.minY + Self.cardInset,
                      width: width, height: max(0, bounds.height - 2 * Self.cardInset))
    }

    var scale: CGFloat {
        guard stepsBack, page.width > 4 * Self.stepBack, page.height > 4 * Self.stepBack else { return 1 }
        return (page.width - 2 * Self.stepBack) / page.width
    }

    func scale(progress: CGFloat) -> CGFloat {
        1 - min(1, max(0, progress)) * (1 - scale)
    }

    func steppedPage(progress: CGFloat = 1) -> CGRect {
        let factor = scale(progress: progress)
        let width = page.width * factor, height = page.height * factor
        return CGRect(x: page.midX - width / 2, y: page.midY - height / 2, width: width, height: height)
    }

    func controls(closeWidth: CGFloat) -> CGRect {
        let x = card.maxX + Self.controlGap
        let width = max(Self.controlSize, min(closeWidth, page.maxX - x - 4))
        let count = CGFloat(Self.controlCount)
        return CGRect(x: x, y: card.minY + Self.controlTopInset, width: width,
                      height: count * Self.controlSize + (count - 1) * Self.controlSpacing)
    }

    func region(at point: CGPoint, controls: CGRect) -> Region {
        if controls.contains(point) { return .controls }
        if card.contains(point) { return .card }
        if steppedPage().contains(point) { return .page }
        return .frame
    }

    static func stepTransform(bounds: CGRect, anchor: CGPoint, scale: CGFloat) -> CATransform3D {
        guard scale != 1 else { return CATransform3DIdentity }
        let x = (0.5 - anchor.x) * bounds.width, y = (0.5 - anchor.y) * bounds.height
        let centered = CATransform3DScale(CATransform3DMakeTranslation(x, y, 0), scale, scale, 1)
        return CATransform3DTranslate(centered, -x, -y, 0)
    }

    static func pageAcceptsHit(at point: CGPoint, in bounds: CGRect, scale: CGFloat) -> Bool {
        guard scale < 1 else { return true }
        let width = bounds.width * scale, height = bounds.height * scale
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height).contains(point)
    }
}

@MainActor
final class PeekLayerView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor
class PeekHitView: NSView {
    var hitLayout = PeekWindowLayout(bounds: .zero, page: .zero, stepsBack: false)
    var hitControls = CGRect.zero
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview else { return nil }
        switch hitLayout.region(at: convert(point, from: superview), controls: hitControls) {
        case .frame: return nil
        case .page: return self
        case .card, .controls: return routedHit(super.hitTest(point) ?? self)
        }
    }

    func routedHit(_ hit: NSView) -> NSView { hit }

    func claims(_ point: NSPoint) -> Bool {
        !isHidden && hitLayout.region(at: point, controls: hitControls) != .frame
    }
}
