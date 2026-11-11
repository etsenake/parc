import AppKit
import SwiftUI

enum OnboardingBookmarkPalette {
    static let stroke = NSColor(srgbRed: 0.192, green: 0.220, blue: 0.988, alpha: 1)
}

struct OnboardingBookmarkFolderIcon: NSViewRepresentable {
    let expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> OnboardingBookmarkFolderView {
        let view = OnboardingBookmarkFolderView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        view.setExpanded(expanded, animated: false)
        return view
    }

    func updateNSView(_ view: OnboardingBookmarkFolderView, context: Context) {
        view.setExpanded(expanded, animated: !reduceMotion && !context.transaction.disablesAnimations)
    }
}

@MainActor
final class OnboardingBookmarkFolderView: NSView {
    private let back = CAShapeLayer()
    private let backShade = CAGradientLayer()
    private let backShadeMask = CAShapeLayer()
    private let frontContainer = CALayer()
    private let front = CAShapeLayer()
    private let frontShade = CAGradientLayer()
    private(set) var expanded = false
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.masksToBounds = false
        layer?.addSublayer(back)
        back.addSublayer(backShade)
        backShade.mask = backShadeMask
        layer?.addSublayer(frontContainer)
        frontContainer.addSublayer(front)
        front.addSublayer(frontShade)
        back.fillColor = NSColor(srgbRed: 0.753, green: 0.757, blue: 0.957, alpha: 1).cgColor
        front.fillColor = NSColor(srgbRed: 0.941, green: 0.941, blue: 0.937, alpha: 1).cgColor
        let stroke = OnboardingBookmarkPalette.stroke.cgColor
        back.strokeColor = stroke; front.strokeColor = stroke
        frontShade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.15).cgColor]
        frontShade.locations = [0, 1]
        frontShade.startPoint = CGPoint(x: 0.1, y: 0); frontShade.endPoint = CGPoint(x: 0.9, y: 1)
        backShade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.36).cgColor]
        backShade.locations = [0, 1]
        backShade.startPoint = .zero; backShade.endPoint = CGPoint(x: 0.6, y: 1)
        applyState(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let scale = max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        let width = bounds.width, height = bounds.height
        guard width > 0, height > 0 else { return }
        let radius = (width / 7).rounded()
        let lineWidth = (1.25 * scale).rounded() / scale
        let top = ((height * 0.25).rounded() * scale).rounded() / scale
        let shoulder = floor(top / 1.5)
        let tabX = (width * 0.42 * scale).rounded() / scale
        let shoulderX = (width * 0.58 * scale).rounded() / scale
        let path = CGMutablePath()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: tabX, y: 0))
        path.addLine(to: CGPoint(x: shoulderX, y: shoulder))
        path.addLine(to: CGPoint(x: width - radius, y: shoulder))
        path.addArc(center: CGPoint(x: width - radius, y: shoulder + radius), radius: radius,
                    startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: width, y: height - radius))
        path.addArc(center: CGPoint(x: width - radius, y: height - radius), radius: radius,
                    startAngle: 0, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: radius, y: height))
        path.addArc(center: CGPoint(x: radius, y: height - radius), radius: radius,
                    startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addArc(center: CGPoint(x: radius, y: radius), radius: radius,
                    startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
        path.closeSubpath()

        CATransaction.begin(); CATransaction.setDisableActions(true)
        for plane in [back, frontContainer] {
            plane.anchorPoint = CGPoint(x: 0, y: 1)
            plane.position = CGPoint(x: bounds.minX, y: bounds.maxY)
        }
        back.bounds = CGRect(origin: .zero, size: bounds.size)
        back.path = path; back.lineWidth = lineWidth
        backShade.frame = back.bounds; backShadeMask.frame = back.bounds; backShadeMask.path = path
        frontContainer.bounds = CGRect(x: 0, y: 0, width: width, height: height - top)
        front.frame = frontContainer.bounds; front.lineWidth = lineWidth
        front.path = CGPath(roundedRect: front.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        frontShade.frame = front.bounds; frontShade.cornerRadius = radius
        for item in [back, backShade, backShadeMask, frontContainer, front, frontShade] { item.contentsScale = scale }
        CATransaction.commit()
    }

    func setExpanded(_ value: Bool, animated: Bool) {
        guard expanded != value else { return }
        expanded = value; applyState(animated: animated)
    }

    private func applyState(animated: Bool) {
        var base = CATransform3DIdentity
        base.m34 = -1 / 350
        if expanded {
            base = CATransform3DTranslate(base, 3, 0, 0)
            base = CATransform3DRotate(base, 32 * .pi / 180, 0, 1, 0)
        }
        CATransaction.begin(); CATransaction.setDisableActions(!animated)
        back.transform = CATransform3DRotate(base, expanded ? 28 * .pi / 180 : 0, 1, 0, 0)
        frontContainer.transform = CATransform3DRotate(base, expanded ? -30 * .pi / 180 : 0, 1, 0, 0)
        frontShade.opacity = expanded ? 1 : 0
        backShade.opacity = expanded ? 1 : 0.2
        CATransaction.commit()
    }
}
