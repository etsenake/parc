import AppKit
import ParcCore
import QuartzCore
import ParcKit

final class FavoritesEmptyStateView: NSView {
    static let title = "Drag to add Favorites"
    static let subtitle = "Favorites keep your most used sites and apps close"
    static let dismissLabel = "Dismiss"
    static let dismissIdentifier = "sidebarFavoritesEmptyStateDismissButton"
    static let hideTitle = "Hide"

    private var onDismiss: (() -> Void)?
    private(set) var isDraggingOver = false { didSet { if isDraggingOver != oldValue { applyStyle(animated: true) } } }

    private let card = CALayer()
    private let innerBorder = CAGradientLayer()
    private let innerBorderShape = CAShapeLayer()
    private let outerBorder = CAShapeLayer()
    private let icon = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let dismissButton = DismissButton()
    private var colors = Colors(isDark: false, title: .labelColor, maxContrast: .black, minContrast: .white,
                                backgroundExtra: .controlBackgroundColor)

    private struct Colors {
        var isDark: Bool
        var title, maxContrast, minContrast, backgroundExtra: NSColor
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        card.cornerRadius = 12; card.cornerCurve = .continuous
        innerBorderShape.fillColor = nil; innerBorderShape.strokeColor = NSColor.black.cgColor; innerBorderShape.lineWidth = 1
        innerBorder.mask = innerBorderShape; innerBorder.opacity = 0.3
        outerBorder.fillColor = nil; outerBorder.lineWidth = 1; outerBorder.lineJoin = .round
        for sublayer in [card, innerBorder, outerBorder] { layer?.addSublayer(sublayer) }

        icon.imageScaling = .scaleNone
        let centred = NSMutableParagraphStyle(); centred.alignment = .center
        titleLabel.attributedStringValue = NSAttributedString(string: Self.title, attributes: [
            .paragraphStyle: centred, .font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        subtitleLabel.attributedStringValue = NSAttributedString(string: Self.subtitle, attributes: [
            .paragraphStyle: centred, .kern: -0.2, .font: NSFont.systemFont(ofSize: 12, weight: .regular)])
        for label in [titleLabel, subtitleLabel] {
            label.cell?.lineBreakMode = .byWordWrapping; label.isSelectable = false; label.drawsBackground = false
        }

        let mark = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        dismissButton.image = mark; dismissButton.imagePosition = .imageOnly
        dismissButton.isBordered = false; dismissButton.bezelStyle = .regularSquare
        dismissButton.target = self; dismissButton.action = #selector(dismiss)
        dismissButton.setAccessibilityLabel(Self.dismissLabel)
        dismissButton.setAccessibilityIdentifier(Self.dismissIdentifier)
        for view in [icon, titleLabel, subtitleLabel, dismissButton] as [NSView] { addSubview(view) }
        applyStyle(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyPalette(isDark: Bool, title: NSColor, maxContrast: NSColor, minContrast: NSColor, backgroundExtra: NSColor) {
        colors = Colors(isDark: isDark, title: title, maxContrast: maxContrast, minContrast: minContrast, backgroundExtra: backgroundExtra)
        applyStyle(animated: false)
    }

    func update(favorites: Int, profileID: UUID?, settings: BrowserSettings, privateWindow: Bool,
                dismiss: @escaping (UUID) -> Void) {
        onDismiss = profileID.map { profile in { dismiss(profile) } }
        isHidden = !(profileID.map { SidebarChromeLayout.showsAppTrayEmptyState(
            favorites: favorites, dismissed: settings.favoritesEmptyStateDismissed(for: $0), privateWindow: privateWindow) } ?? false)
    }

    func trayHeight(gridHeight: CGFloat, width: CGFloat) -> CGFloat {
        SidebarChromeLayout.appTrayHeight(gridHeight: gridHeight, emptyState: isHidden ? nil : fittingHeight(width: width))
    }

    @discardableResult func showsDrop(_ over: Bool) -> Bool {
        isDraggingOver = over && !isHidden
        return isDraggingOver
    }

    func fittingHeight(width: CGFloat) -> CGFloat {
        let sizes = measure(width: width)
        return SidebarChromeLayout.AppTrayEmptyState.height(icon: sizes.icon, title: sizes.title, subtitle: sizes.subtitle)
    }

    override func layout() {
        super.layout()
        let sizes = measure(width: bounds.width)
        let frames = SidebarChromeLayout.AppTrayEmptyState.frames(width: bounds.width, height: bounds.height,
                                                                   icon: sizes.icon, title: sizes.title, subtitle: sizes.subtitle)
        icon.frame = frames.icon; titleLabel.frame = frames.title; subtitleLabel.frame = frames.subtitle
        dismissButton.frame = frames.close
        CATransaction.begin(); CATransaction.setDisableActions(true)
        card.frame = frames.card
        innerBorder.frame = frames.card
        innerBorderShape.path = CGPath(roundedRect: CGRect(origin: .zero, size: frames.card.size).insetBy(dx: 0.5, dy: 0.5),
                                       cornerWidth: 11.5, cornerHeight: 11.5, transform: nil)
        outerBorder.path = CGPath(roundedRect: frames.card.insetBy(dx: -0.5, dy: -0.5), cornerWidth: 12.5, cornerHeight: 12.5, transform: nil)
        let top: CGFloat = innerBorder.contentsAreFlipped() ? 0 : 1
        innerBorder.startPoint = CGPoint(x: 0.5, y: top); innerBorder.endPoint = CGPoint(x: 0.5, y: 1 - top)
        CATransaction.commit()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let hide = NSMenuItem(title: Self.hideTitle, action: #selector(dismiss), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }

    @objc private func dismiss() { onDismiss?() }

    private func measure(width: CGFloat) -> (icon: CGSize, title: CGSize, subtitle: CGSize) {
        let textWidth = SidebarChromeLayout.AppTrayEmptyState.textWidth(trayWidth: width)
        func size(_ label: NSTextField) -> CGSize {
            let cell = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)) ?? .zero
            return CGSize(width: min(textWidth, ceil(cell.width)), height: ceil(cell.height))
        }
        return (icon.image?.size ?? .zero, size(titleLabel), size(subtitleLabel))
    }

    private func applyStyle(animated: Bool) {
        let dragging = isDraggingOver
        let animates = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let tint = colors.isDark ? colors.minContrast : colors.backgroundExtra
        icon.image = NSImage(systemSymbolName: "star.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                .applying(.init(paletteColors: [colors.maxContrast.withAlphaComponent(dragging ? 0.5 : 1),
                                                colors.minContrast.withAlphaComponent(dragging ? 0.3 : 0.5)])))
        titleLabel.textColor = colors.title; subtitleLabel.textColor = colors.title
        dismissButton.contentTintColor = colors.title.withAlphaComponent(0.7)
        let easeOut = CAMediaTimingFunction(name: .easeOut)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animates ? 0.18 : 0
            context.timingFunction = easeOut
            (animates ? titleLabel.animator() : titleLabel).alphaValue = dragging ? 0.5 : 1
            (animates ? subtitleLabel.animator() : subtitleLabel).alphaValue = dragging ? 0.3 : 0.7
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animates)
        CATransaction.setAnimationDuration(0.18); CATransaction.setAnimationTimingFunction(easeOut)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            card.backgroundColor = colors.backgroundExtra.withAlphaComponent(dragging ? 0.3 : 0.15).cgColor
            innerBorder.colors = [tint.withAlphaComponent(0.2).cgColor, tint.withAlphaComponent(0.8).cgColor]
        }
        outerBorder.strokeColor = colors.maxContrast.withAlphaComponent(0.3).cgColor
        outerBorder.lineDashPattern = dragging ? nil : [5]
        CATransaction.commit()
    }
}

private final class DismissButton: PointingHandButton {
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(ovalIn: bounds).fill() }
}
