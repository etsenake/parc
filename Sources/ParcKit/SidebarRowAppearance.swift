import AppKit

package struct SidebarRowAppearance: Equatable {
    package var current = false
    var contentVisible = false
    package var multiSelected = false
    package var hovered = false
    package var highlighted = false
    package var dimmed = false
    package var keyDragged = false
    package var splitChild = false
    package var splitGroupSelected = false
    package init(current: Bool = false, contentVisible: Bool = false, multiSelected: Bool = false, hovered: Bool = false, highlighted: Bool = false, dimmed: Bool = false, keyDragged: Bool = false, splitChild: Bool = false, splitGroupSelected: Bool = false) {
        self.current = current
        self.contentVisible = contentVisible
        self.multiSelected = multiSelected
        self.hovered = hovered
        self.highlighted = highlighted
        self.dimmed = dimmed
        self.keyDragged = keyDragged
        self.splitChild = splitChild
        self.splitGroupSelected = splitGroupSelected
    }

    package enum Fill: Equatable { case current, contentVisible, multiSelected, hovered, splitChild }

    var fill: Fill? {
        if splitChild { return splitGroupSelected ? .splitChild : nil }
        if current || keyDragged { return .current }
        if contentVisible { return .contentVisible }
        if multiSelected { return .multiSelected }
        return hovered ? .hovered : nil
    }

    var showsShadow: Bool { current && !splitChild }

    package var splitsResetRegions: Bool { fill == nil && !highlighted }
    package var resetRegionCorners: CACornerMask {
        splitsResetRegions ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
    }

    package static let cornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 1
    static let shadowOffset = CGSize(width: 0, height: -1)
    static let dimmedOpacity: Float = 0.5
    package static let ringWidth: CGFloat = 2
    static let iconSlotSize: CGFloat = 24
    package static let iconSize: CGFloat = 16
    static let iconSlotInset: CGFloat = 6
    static let titleInset: CGFloat = 36
    package static let titleTextPadding: CGFloat = 2
    package static let titleFontSize: CGFloat = 14
    static let slashSize = NSSize(width: 4, height: 15)
    package static let slashLineWidth: CGFloat = 2
    static let resetTitleInset = iconSlotInset + iconSlotSize + slashSize.width + 4
    package static let closeSize: CGFloat = 24
    package static let closeTrailingInset: CGFloat = 6
    static let idleTitleTrailingInset: CGFloat = 10
    package static let titleCloseSpacing: CGFloat = 2
    package static let resetSubtitle = "Back to Pinned URL"
    package static let separateSubtitle = "Separate From Pinned Tab"
    package static let subtitleTextAlpha: CGFloat = 0.5
    package static let subtitleLift: CGFloat = 7
    package static let subtitleDuration: CFTimeInterval = 0.1
    package static let subtitleFontSize: CGFloat = 11

    static let splitChildHeight: CGFloat = 28
    static let splitChildInset: CGFloat = 2
    static let splitChildCloseInset = (splitChildHeight - closeSize) / 2
    static let splitChildCloseGap: CGFloat = 2
    static let splitChildIconTitleSpacing: CGFloat = 6
    static let splitChildMinimumTitleWidth: CGFloat = 20
    static let splitChildIndicatorSize: CGFloat = 8 + 2 * 3
    static let splitChildCornerRadius: CGFloat = 8

    package struct SplitChildLayout: Equatable {
        package var cell: NSRect
        package var indicator: NSRect?
        package var iconSlot: NSRect
        package var close: NSRect
        package var showsClose: Bool
        package var title: NSRect?
    }

    package static func splitChildLayout(in bounds: NSRect, titleHeight: CGFloat, recording: Bool,
                                 closeAvailable: Bool, groupHovered: Bool) -> SplitChildLayout {
        let width = bounds.width
        let cell = NSRect(x: 0, y: ((bounds.height - splitChildHeight) / 2).rounded(.down), width: width, height: splitChildHeight)
        func centered(_ height: CGFloat) -> CGFloat { cell.minY + ((cell.height - height) / 2).rounded(.down) }
        let roomy = width - 2 * splitChildInset > iconSlotSize
        var x = splitChildInset
        var indicator: NSRect?
        if roomy, recording, iconSlotSize + splitChildIndicatorSize + 2 * splitChildInset <= width {
            indicator = NSRect(x: x, y: centered(splitChildIndicatorSize),
                               width: splitChildIndicatorSize, height: splitChildIndicatorSize)
            x += splitChildIndicatorSize
        }
        let slot = roomy ? NSRect(x: x, y: centered(iconSlotSize), width: iconSlotSize, height: iconSlotSize)
                         : NSRect(x: 0, y: centered(iconSlotSize), width: width, height: iconSlotSize)
        let close = NSRect(x: width - closeSize - splitChildCloseInset, y: centered(closeSize), width: closeSize, height: closeSize)
        let showsClose = roomy && closeAvailable && groupHovered && close.minX + splitChildCloseGap >= slot.maxX
        let titleX = slot.maxX + splitChildIconTitleSpacing
        let titleWidth = width - titleX - (showsClose ? width - close.minX + splitChildCloseGap : splitChildInset)
        let title = roomy && titleWidth > splitChildMinimumTitleWidth
            ? NSRect(x: titleX, y: centered(titleHeight), width: titleWidth, height: titleHeight) : nil
        return SplitChildLayout(cell: cell, indicator: indicator, iconSlot: slot, close: close, showsClose: showsClose, title: title)
    }

    func cornerRadius(in bounds: NSRect) -> CGFloat {
        splitChild ? min(bounds.width / 2, Self.splitChildCornerRadius) : Self.cornerRadius
    }

    package static func iconSlotFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: iconSlotInset, y: ((bounds.height - iconSlotSize) / 2).rounded(.down),
               width: iconSlotSize, height: iconSlotSize)
    }

    package static func iconFrame(in bounds: NSRect) -> NSRect {
        let slot = iconSlotFrame(in: bounds)
        return NSRect(x: slot.minX + (iconSlotSize - iconSize) / 2,
                      y: ((bounds.height - iconSize) / 2).rounded(.down), width: iconSize, height: iconSize)
    }

    package static func slashFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: iconSlotFrame(in: bounds).maxX, y: ((bounds.height - slashSize.height) / 2).rounded(.down),
               width: slashSize.width, height: slashSize.height)
    }

    package static func resetRegionFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: 0, y: 0, width: slashFrame(in: bounds).minX, height: bounds.height)
    }

    package static func closeFrame(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.width - closeTrailingInset - closeSize, y: ((bounds.height - closeSize) / 2).rounded(.down),
               width: closeSize, height: closeSize)
    }

    package static func titleTrailingEdge(in bounds: NSRect, closeVisible: Bool) -> CGFloat {
        closeVisible ? closeFrame(in: bounds).minX - titleCloseSpacing : bounds.width - idleTitleTrailingInset
    }

    package static func titleLabelSpan(resettable: Bool, trailing: CGFloat) -> (minX: CGFloat, width: CGFloat) {
        let minX = (resettable ? resetTitleInset : titleInset) - titleTextPadding
        return (minX, max(0, trailing + titleTextPadding - minX))
    }

    package static func color(_ fill: Fill, dark: Bool) -> NSColor {
        switch fill {
        case .current:
            return dark ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.2)
                        : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
        case .contentVisible:
            return dark ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.15)
                        : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.7)
        case .multiSelected:
            return dark ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.1)
                        : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.1)
        case .hovered:
            return dark ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.1)
                        : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: 0.05)
        case .splitChild:
            return dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07)
                        : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.07)
        }
    }

    static func shadowColor(dark: Bool) -> NSColor {
        dark ? .clear : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.2)
    }

    package static func controlFill(pressed: Bool, dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: pressed ? 0.103 : 0.077)
             : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: pressed ? 0.09 : 0.071)
    }

    package static func regionFill(pressed: Bool, dark: Bool) -> NSColor {
        guard pressed else { return color(.hovered, dark: dark) }
        return dark ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.065)
                    : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: 0.065)
    }

    package static func slashColor(dark: Bool) -> NSColor {
        dark ? NSColor(displayP3Red: 1, green: 1, blue: 1, alpha: 0.3)
             : NSColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.3)
    }
}

package final class SidebarRowBackgroundView: NSView {
    package var appearanceState = SidebarRowAppearance() { didSet { if appearanceState != oldValue { invalidateLayers() } } }
    package var dark = false { didSet { if dark != oldValue { invalidateLayers() } } }
    package var ringColor: NSColor = .labelColor { didSet { if ringColor != oldValue { invalidateLayers() } } }
    let fillLayer = CALayer()
    let ringLayer = CALayer()
    private(set) var paintedBounds: NSRect?

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = false
        layer?.masksToBounds = false
        layer?.allowsGroupOpacity = false
        setAccessibilityElement(false)
    }
    package convenience init() { self.init(frame: .zero) }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var wantsUpdateLayer: Bool { true }
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }
    package override func layout() {
        super.layout()
        if paintedBounds != bounds { invalidateLayers() }
    }

    private func invalidateLayers() {
        needsDisplay = true
        if layer != nil { updateLayer() }
    }

    package override func updateLayer() {
        guard let layer else { return }
        let state = appearanceState
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if fillLayer.superlayer !== layer { layer.addSublayer(fillLayer) }
        if ringLayer.superlayer !== layer { layer.addSublayer(ringLayer) }
        layer.backgroundColor = nil
        layer.masksToBounds = false
        layer.allowsGroupOpacity = false
        let corner = state.cornerRadius(in: bounds)
        for sublayer in [fillLayer, ringLayer] {
            sublayer.frame = layer.bounds
            sublayer.cornerRadius = corner
            sublayer.cornerCurve = .continuous
        }
        fillLayer.backgroundColor = state.fill.map { SidebarRowAppearance.color($0, dark: dark).cgColor }
        fillLayer.masksToBounds = false
        fillLayer.opacity = state.dimmed ? SidebarRowAppearance.dimmedOpacity : 1
        fillLayer.shadowColor = state.showsShadow ? SidebarRowAppearance.shadowColor(dark: dark).cgColor : NSColor.clear.cgColor
        fillLayer.shadowOpacity = 1
        fillLayer.shadowRadius = SidebarRowAppearance.shadowRadius
        fillLayer.shadowOffset = SidebarRowAppearance.shadowOffset
        let radius = max(0, min(corner, bounds.width / 2, bounds.height / 2))
        fillLayer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ringLayer.isHidden = !state.highlighted
        ringLayer.borderWidth = SidebarRowAppearance.ringWidth
        ringLayer.borderColor = ringColor.cgColor(in: effectiveAppearance)
        paintedBounds = bounds
    }
}
