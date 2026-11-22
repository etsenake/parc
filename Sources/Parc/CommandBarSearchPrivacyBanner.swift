import AppKit

struct CommandBarSearchPrivacyPolicy {
    static let dismissedKey = "commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed"
    let defaults: UserDefaults
    var hasBeenExplicitlyDismissed: Bool { defaults.bool(forKey: Self.dismissedKey) }
    func dismiss() { defaults.set(true, forKey: Self.dismissedKey) }
    static func showsInfoAccessory(dismissed: Bool, bannerVisible: Bool, scoped: Bool, offeringSiteSearch: Bool,
                                   hasResults: Bool, sidebarSession: Bool) -> Bool {
        !dismissed && !bannerVisible && !scoped && !offeringSiteSearch && hasResults && !sidebarSession
    }
}

final class CommandBarPrivacyInfoButton: PointingHandButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        imagePosition = .imageOnly
        refusesFirstResponder = true
        contentTintColor = CommandBarPalette.accessoryForeground
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 8
        self.shadow = shadow
        setAccessibilityLabel("Search suggestions privacy")
        setAccessibilityHelp("Shows how search suggestions use your search engine.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

final class CommandBarSearchPrivacyBanner: NSView {
    static let titleColor = CommandBarPalette.either(NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1),
                                                     NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1))
    static let iconColor = CommandBarPalette.either(NSColor(srgbRed: 0.523, green: 0.523, blue: 0.523, alpha: 1),
                                                    NSColor(srgbRed: 0.494, green: 0.494, blue: 0.494, alpha: 1))
    static let regularHeight: CGFloat = 60
    static let condensedHeight: CGFloat = 133
    static let leadingInset: CGFloat = 16
    static let trailingInset: CGFloat = 10
    static let contentSpacing: CGFloat = 14
    static let buttonSpacing: CGFloat = 10

    var onSearchSettings: (() -> Void)?
    var onDismiss: (() -> Void)?

    let icon = NSImageView()
    let title = NSTextField(labelWithString: "We talk to your search engine to help us suggest results.")
    let settingsButton = CommandBarPrivacyButton(title: "Search Settings…")
    let dismissButton = CommandBarPrivacyButton(title: "Dismiss")

    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        icon.contentTintColor = Self.iconColor
        icon.setAccessibilityElement(false)
        title.font = .boldSystemFont(ofSize: 13)
        title.textColor = Self.titleColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        settingsButton.target = self; settingsButton.action = #selector(searchSettings)
        dismissButton.target = self; dismissButton.action = #selector(dismiss)
        dismissButton.setAccessibilityHelp("Permanently hides this notice.")
        for view in [icon, title, settingsButton, dismissButton] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Search suggestions privacy")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func searchSettings() { onSearchSettings?() }
    @objc private func dismiss() { onDismiss?() }

    private var regularContentWidth: CGFloat {
        Self.leadingInset + 16 + Self.contentSpacing + title.singleLineWidth + Self.contentSpacing
            + settingsButton.intrinsicContentSize.width + Self.buttonSpacing
            + dismissButton.intrinsicContentSize.width + Self.trailingInset
    }
    func isCondensed(forWidth width: CGFloat) -> Bool { width < regularContentWidth }
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        isCondensed(forWidth: width) ? Self.condensedHeight : Self.regularHeight
    }

    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        let iconSize = NSSize(width: 16, height: 16)
        let settingsSize = settingsButton.intrinsicContentSize
        let dismissSize = dismissButton.intrinsicContentSize
        let textX = Self.leadingInset + iconSize.width + Self.contentSpacing
        let titleHeight = ceil(title.intrinsicContentSize.height)
        if isCondensed(forWidth: width) {
            let textWidth = max(0, width - textX - Self.trailingInset)
            title.maximumNumberOfLines = 2; title.lineBreakMode = .byWordWrapping
            let wrapped = ceil(title.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 200)).height ?? titleHeight)
            let buttonsHeight = CommandBarPrivacyButton.bodyHeight
            let block = wrapped + Self.contentSpacing + buttonsHeight
            let top = max(0, (height - block) / 2)
            title.frame = NSRect(x: textX, y: top, width: textWidth, height: wrapped)
            icon.frame = NSRect(origin: NSPoint(x: Self.leadingInset, y: top + (titleHeight - iconSize.height) / 2), size: iconSize)
            let buttonY = top + wrapped + Self.contentSpacing
            settingsButton.frame = NSRect(origin: NSPoint(x: Self.leadingInset, y: buttonY), size: settingsSize)
            dismissButton.frame = NSRect(origin: NSPoint(x: settingsButton.frame.maxX + Self.buttonSpacing, y: buttonY), size: dismissSize)
            return
        }
        title.maximumNumberOfLines = 1; title.lineBreakMode = .byTruncatingTail
        let buttonY = (height - CommandBarPrivacyButton.bodyHeight) / 2
        dismissButton.frame = NSRect(x: width - Self.trailingInset - dismissSize.width, y: buttonY,
                                     width: dismissSize.width, height: dismissSize.height)
        settingsButton.frame = NSRect(x: dismissButton.frame.minX - Self.buttonSpacing - settingsSize.width, y: buttonY,
                                      width: settingsSize.width, height: settingsSize.height)
        icon.frame = NSRect(origin: NSPoint(x: Self.leadingInset, y: (height - iconSize.height) / 2), size: iconSize)
        title.frame = NSRect(x: textX, y: (height - titleHeight) / 2,
                             width: max(0, settingsButton.frame.minX - Self.contentSpacing - textX), height: titleHeight)
    }
}

final class CommandBarPrivacyButton: PointingHandButton {
    static let bodyHeight: CGFloat = 36
    private var hovered = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        font = ParcDialogStyle.buttonFont
        refusesFirstResponder = true
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    private var body: NSRect { NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: Self.bodyHeight) }
    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: ParcDialogStyle.buttonFont])
        return NSSize(width: ceil(text.width) + 24 + 1, height: Self.bodyHeight + 3)
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hovered = false }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var focusRingMaskBounds: NSRect { body }
    override func drawFocusRingMask() { ParcDialogStyle.continuousRect(body, radius: 6).fill() }
    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true
        ParcDialogStyle.neutralShadow.setFill()
        ParcDialogStyle.continuousRect(body.offsetBy(dx: 0, dy: 2), radius: 6).fill()
        let shape = ParcDialogStyle.continuousRect(body, radius: 6)
        (pressed ? ParcDialogStyle.neutralPressed : hovered ? ParcDialogStyle.neutralHovered : ParcDialogStyle.neutralFace).setFill()
        shape.fill()
        ParcDialogStyle.neutralBorder.setStroke(); shape.lineWidth = 1; shape.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: ParcDialogStyle.buttonFont, .foregroundColor: ParcDialogStyle.neutralForeground]
        let label = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: body.minX + 12, y: body.midY - label.height / 2), withAttributes: attributes)
    }
}
