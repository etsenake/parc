import AppKit

@MainActor
final class AutoArchiveEducationView: NSView, NSTextViewDelegate {
    var onDismiss: (() -> Void)?
    var onSettings: (() -> Void)?
    private let title = NSTextField(wrappingLabelWithString: "We cleaned up!")
    private let message = AutoArchiveEducationLinkView()
    private let dismiss = PointingHandButton(title: "Got it", target: nil, action: nil)
    private var palette: ThemeChromePalette?
    private var interactionEnabled = true
    private let messageText = "Parc archives tabs that you haven’t used in the past 12 hours. You can adjust this in Settings."
    private var titleHeight: CGFloat { ceil(title.font?.boundingRectForFont.height ?? 16) }
    override var isFlipped: Bool { true }
    var keyViewControls: [NSView] { [message, dismiss] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 1
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        title.maximumNumberOfLines = 0
        message.drawsBackground = false
        message.isEditable = false; message.isSelectable = true
        message.textContainerInset = .zero
        message.textContainer?.lineFragmentPadding = 0
        message.textContainer?.widthTracksTextView = true
        message.isHorizontallyResizable = false
        message.isVerticallyResizable = false
        message.delegate = self
        message.onActivate = { [weak self] in self?.activateSettings() }
        message.setAccessibilityLabel("Auto-archive information. Settings")
        message.setAccessibilityHelp("Open Settings to adjust automatic archiving.")
        dismiss.isBordered = false
        dismiss.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .light)
        dismiss.target = self; dismiss.action = #selector(dismissPressed)
        dismiss.wantsLayer = true
        dismiss.layer?.cornerRadius = 12; dismiss.layer?.cornerCurve = .continuous
        [title, message, dismiss].forEach(addSubview)
        setAccessibilityElement(false)
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyPalette(_ palette: ThemeChromePalette) {
        self.palette = palette
        refreshColors()
    }

    func setInteractionEnabled(_ enabled: Bool) {
        interactionEnabled = enabled
        message.interactionEnabled = enabled
        message.isSelectable = enabled
        dismiss.isEnabled = enabled
    }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - 24)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        let height = (messageText as NSString).boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .paragraphStyle: paragraph]).height
        return 24 + titleHeight + 12 + ceil(height) + 12 + 32 + 12
    }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 12, y: 12, width: max(1, bounds.width - 24), height: titleHeight)
        let messageY = title.frame.maxY + 24
        let buttonHeight: CGFloat = 32
        dismiss.frame = NSRect(x: 12, y: bounds.height - 12 - buttonHeight,
                               width: max(1, bounds.width - 24), height: buttonHeight)
        message.frame = NSRect(x: 12, y: messageY, width: max(1, bounds.width - 24),
                               height: max(1, dismiss.frame.minY - 12 - messageY))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dark = palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let header = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState(); header.addClip()
        (dark ? NSColor.white.withAlphaComponent(0.05) : NSColor.black.withAlphaComponent(0.08)).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: titleHeight + 24).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func refreshColors() {
        let dark = palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        layer?.backgroundColor = (palette?.backgroundExtra ?? .windowBackgroundColor).cgColor(in: palette?.contentAppearance ?? effectiveAppearance)
        title.textColor = (dark ? NSColor.white : .black).withAlphaComponent(0.8)
        let bodyColor = NSColor(named: "ForegroundSecondary") ?? .secondaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                        .foregroundColor: bodyColor]
        let text = NSMutableAttributedString(string: messageText, attributes: attributes)
        let linkRange = (messageText as NSString).range(of: "Settings")
        text.addAttribute(.link, value: URL(string: "parc-auto-archive://settings")!, range: linkRange)
        message.textStorage?.setAttributedString(text)
        message.linkTextAttributes = [.foregroundColor: palette?.foregroundPrimary ?? NSColor.linkColor,
                                      .underlineStyle: NSUnderlineStyle.single.rawValue]
        dismiss.contentTintColor = palette?.foregroundPrimary ?? .labelColor
        dismiss.attributedTitle = NSAttributedString(string: "Got it", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .light),
            .foregroundColor: dark ? NSColor.white : NSColor.black
        ])
        dismiss.layer?.backgroundColor = (palette?.focus ?? .controlBackgroundColor).cgColor(in: palette?.contentAppearance ?? effectiveAppearance)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        activateSettings(); return true
    }
    private func activateSettings() {
        guard interactionEnabled, window?.isKeyWindow == true, !isHiddenOrHasHiddenAncestor else { return }
        onSettings?()
    }
    @objc private func dismissPressed() {
        guard interactionEnabled, window?.isKeyWindow == true, !isHiddenOrHasHiddenAncestor else { return }
        onDismiss?()
    }
}

@MainActor
private final class AutoArchiveEducationLinkView: NSTextView {
    var interactionEnabled = true
    var onActivate: (() -> Void)?
    override var acceptsFirstResponder: Bool { interactionEnabled }
    override func keyDown(with event: NSEvent) {
        if interactionEnabled, !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            super.keyDown(with: event); return
        }
        if interactionEnabled, event.keyCode == 36 || event.keyCode == 49 || event.keyCode == 76 {
            onActivate?(); return
        }
        super.keyDown(with: event)
    }
}
