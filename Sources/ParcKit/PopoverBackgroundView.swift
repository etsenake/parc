import AppKit

package final class PopoverBackgroundView: NSView {
    let translucency = NSVisualEffectView()
    package let wash = NSView()
    let outerBorder = CALayer()
    let innerBorder = CALayer()
    package var flatFill = false { didSet { if flatFill != oldValue { needsDisplay = true; needsLayout = true } } }
    package var cornerRadius: CGFloat = 12 { didSet { needsDisplay = true; needsLayout = true } }
    package var onLayout: (() -> Void)?
    package var onAppearanceChange: (() -> Void)?
    package override var isFlipped: Bool { true }

    package init(blending: NSVisualEffectView.BlendingMode) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        translucency.material = .popover
        translucency.state = .followsWindowActiveState
        translucency.blendingMode = blending
        translucency.isEmphasized = false
        translucency.wantsLayer = true
        translucency.setAccessibilityElement(false)
        addSubview(translucency, positioned: .below, relativeTo: nil)
        wash.wantsLayer = true; wash.setAccessibilityElement(false)
        addSubview(wash, positioned: .above, relativeTo: translucency)
        for ring in [outerBorder, innerBorder] {
            ring.cornerCurve = .continuous
            ring.zPosition = 10
            layer?.addSublayer(ring)
        }
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override func layout() {
        super.layout()
        translucency.frame = bounds; wash.frame = bounds
        applyGeometry()
        onLayout?()
    }
    package override var wantsUpdateLayer: Bool { true }
    package override func updateLayer() {
        applyGeometry()
        effectiveAppearance.performAsCurrentDrawingAppearance { applyColors() }
    }
    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true; onAppearanceChange?()
    }
    package override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties(); needsDisplay = true; needsLayout = true
    }

    private var hairline: CGFloat { 1 / max(1, window?.backingScaleFactor ?? 1) }

    private func applyGeometry() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let radius = cornerRadius
        for view in [self, translucency, wash] as [NSView] {
            view.layer?.cornerRadius = radius; view.layer?.cornerCurve = .continuous
        }
        translucency.layer?.masksToBounds = true; wash.layer?.masksToBounds = true
        outerBorder.frame = bounds; outerBorder.cornerRadius = radius
        outerBorder.borderWidth = flatFill ? 0 : hairline
        let pixel = outerBorder.borderWidth
        innerBorder.frame = bounds.insetBy(dx: pixel, dy: pixel)
        innerBorder.cornerRadius = max(0, radius - pixel)
        innerBorder.borderWidth = flatFill ? 0 : 1
        CATransaction.commit()
    }

    private func applyColors() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if flatFill {
            translucency.isHidden = true; wash.isHidden = true
            layer?.backgroundColor = (dark
                ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.1)
                : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: 0.05)).cgColor
        } else {
            translucency.isHidden = false; wash.isHidden = false
            layer?.backgroundColor = nil
            wash.layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.065, green: 0.065, blue: 0.065, alpha: 0.7)
                                         : NSColor.white.withAlphaComponent(0.7)).cgColor
            outerBorder.borderColor = NSColor.black.withAlphaComponent(dark ? 0.9 : 0.34).cgColor
            innerBorder.borderColor = dark ? NSColor.white.withAlphaComponent(0.23).cgColor : NSColor.clear.cgColor
        }
        CATransaction.commit()
    }
}
