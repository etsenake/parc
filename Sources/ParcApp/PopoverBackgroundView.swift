import AppKit

///
///
///
///
/// draws the shadow.
final class PopoverBackgroundView: NSView {
    ///
    ///
    /// view in the browser window; Parc's is a child panel over it, so it
    /// blends behind the panel to reach the page underneath.
    let translucency = NSVisualEffectView()
    /// The wash sits in its own view over the material.
    let wash = NSView()
    let outerBorder = CALayer()
    let innerBorder = CALayer()
    /// The command bar's inline sidebar variant.
    var sidebarBrowsing = false { didSet { if sidebarBrowsing != oldValue { needsDisplay = true; needsLayout = true } } }
    var cornerRadius: CGFloat = 12 { didSet { needsDisplay = true; needsLayout = true } }
    var onLayout: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    override var isFlipped: Bool { true }

    init(blending: NSVisualEffectView.BlendingMode) {
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
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        translucency.frame = bounds; wash.frame = bounds
        applyGeometry()
        onLayout?()
    }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        applyGeometry()
        effectiveAppearance.performAsCurrentDrawingAppearance { applyColors() }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true; onAppearanceChange?()
    }
    override func viewDidChangeBackingProperties() {
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
        // The outer ring is one device pixel on the edge; the inner ring is a
        // point wide just inside it, its radius reduced by the same pixel
        //
        outerBorder.frame = bounds; outerBorder.cornerRadius = radius
        outerBorder.borderWidth = sidebarBrowsing ? 0 : hairline
        let pixel = outerBorder.borderWidth
        innerBorder.frame = bounds.insetBy(dx: pixel, dy: pixel)
        innerBorder.cornerRadius = max(0, radius - pixel)
        innerBorder.borderWidth = sidebarBrowsing ? 0 : 1
        CATransaction.commit()
    }

    private func applyColors() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if sidebarBrowsing {
            //
            //
            translucency.isHidden = true; wash.isHidden = true
            layer?.backgroundColor = (dark
                ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.1)
                : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: 0.05)).cgColor
        } else {
            translucency.isHidden = false; wash.isHidden = false
            layer?.backgroundColor = nil
            //
            //
            wash.layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.065, green: 0.065, blue: 0.065, alpha: 0.7)
                                         : NSColor.white.withAlphaComponent(0.7)).cgColor
            // `.decorative`: black 0.9 dark / 0.34 light outside, and white
            // 0.23 inside in dark only.
            outerBorder.borderColor = NSColor.black.withAlphaComponent(dark ? 0.9 : 0.34).cgColor
            innerBorder.borderColor = dark ? NSColor.white.withAlphaComponent(0.23).cgColor : NSColor.clear.cgColor
        }
        CATransaction.commit()
    }
}
