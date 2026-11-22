import AppKit
import ParcKit

@MainActor final class ExtensionSidePanelView: NSView {
    static let headerHeight: CGFloat = PaneTopBarLayout.height
    let content: NSView = ExtensionSidePanelContentView()
    let closeButton = SplitPaneControl(.close)
    private let titleLabel = NSTextField(labelWithString: "Extension")
    var onClose: (() -> Bool)?
    private(set) var headerDisplayInvalidations = 0
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setAccessibilityElement(false)
        LiveShortcutToolTip.set(closeButton, "Close Extension Side Panel")
        closeButton.setAccessibilityLabel("Close Extension Side Panel")
        closeButton.setAccessibilityIdentifier("extension-side-panel-close")
        closeButton.actionBlock = { [weak self] in _ = self?.requestClose() }
        addSubview(content); addSubview(titleLabel); addSubview(closeButton)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Extension Side Panel")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func cancelOperation(_ sender: Any?) {
        if !requestClose() {
            _ = nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender)
        }
    }
    private func requestClose() -> Bool {
        guard !isHiddenOrHasHiddenAncestor, window?.isKeyWindow == true else { return false }
        return onClose?() == true
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width), height = max(0, bounds.height)
        let header = min(Self.headerHeight, height)
        let contentFrame = NSRect(x: 0, y: header, width: width, height: max(0, height - header))
        let size = closeButton.surfaceSize
        let closeHidden = width < size.width + 10 || header < size.height
        let closeFrame = NSRect(x: max(0, width - size.width - 5), y: max(0, (header - size.height) / 2),
                                width: size.width, height: size.height)
        let titleHidden = header < 17 || width < 110
        let titleFrame = NSRect(x: 8, y: max(0, (header - 17) / 2), width: max(0, width - size.width - 23), height: 17)
        var chromeMoved = false
        if content.frame != contentFrame { content.frame = contentFrame; chromeMoved = true }
        if closeButton.isHidden != closeHidden { closeButton.isHidden = closeHidden; chromeMoved = true }
        if closeButton.frame != closeFrame { closeButton.frame = closeFrame; chromeMoved = true }
        if titleLabel.isHidden != titleHidden { titleLabel.isHidden = titleHidden; chromeMoved = true }
        if titleLabel.frame != titleFrame { titleLabel.frame = titleFrame; chromeMoved = true }
        if chromeMoved { invalidateHeaderFill() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateHeaderFill()
    }

    private func invalidateHeaderFill() {
        headerDisplayInvalidations += 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: min(Self.headerHeight, bounds.height)).fill()
    }
}

@MainActor private final class ExtensionSidePanelContentView: NSView {
    override var isFlipped: Bool { true }
}
